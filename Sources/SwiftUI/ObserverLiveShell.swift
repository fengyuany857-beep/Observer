import SwiftUI
import ObserverReadAPI

private enum ObserverEventPollOutcome {
    case unchanged
    case invalidated(ObserverEventInvalidationReason)
    case unavailable(String)
    case deferred
}

@MainActor
public final class ObserverLiveViewModel: ObservableObject {
    @Published public private(set) var envelope: ObserverDataEnvelope?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastErrorCode: String?
    @Published public private(set) var configurationRevision = 0
    @Published public private(set) var credentialStored = false
    @Published public private(set) var baseURLString: String
    @Published public private(set) var projectID: String
    @Published public private(set) var eventCursor: Int?
    @Published public private(set) var lastInvalidationReason: String?
    @Published public private(set) var lastEventPollErrorCode: String?

    private let configurationStore: ObserverRuntimeConfigurationStore
    private var dataSource: RealObserverDataSource?
    private var eventClient: ObserverReadAPIClient?
    private var eventCursorStore = ObserverEventCursorStore()

    private static let eventPollIntervalNanoseconds: UInt64 = 2_000_000_000
    private static let quietPollsBeforeSafetyRefresh = 15
    private static let unavailablePollsBeforeFallbackRefresh = 3

    public init(
        configurationStore: ObserverRuntimeConfigurationStore = ObserverRuntimeConfigurationStore()
    ) {
        self.configurationStore = configurationStore
        let settings = configurationStore.loadSettings()
        self.baseURLString = settings.baseURL.absoluteString
        self.projectID = settings.projectID

        do {
            if let configuration = try configurationStore.makeTransportConfiguration() {
                self.dataSource = RealObserverDataSource(configuration: configuration)
                self.eventClient = try Self.makeEventClient(configuration)
                self.credentialStored = true
            }
        } catch {
            self.lastErrorCode = Self.errorCode(error)
        }
    }

    public var isConfigured: Bool {
        dataSource != nil && credentialStored
    }

    public var connectionLabel: String {
        if let envelope {
            return envelope.snapshot.connectionState.rawValue
        }
        if isRefreshing {
            return "CONNECTING"
        }
        if lastErrorCode != nil {
            return "ERROR"
        }
        return isConfigured ? "IDLE" : "NOT CONFIGURED"
    }

    public func saveConfiguration(
        baseURLString: String,
        projectID: String,
        bearerTokenCandidate: String
    ) throws {
        let settings = try configurationStore.saveSettings(
            baseURLString: baseURLString,
            projectID: projectID
        )

        let trimmedToken = bearerTokenCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            try configurationStore.saveBearerToken(trimmedToken)
        }

        guard let token = try configurationStore.loadBearerToken() else {
            throw ObserverRuntimeConfigurationError.credentialMissing
        }

        let configuration = try ObserverTransportConfiguration(
            baseURL: settings.baseURL,
            bearerToken: token,
            projectID: settings.projectID
        )

        self.baseURLString = settings.baseURL.absoluteString
        self.projectID = settings.projectID
        self.dataSource = RealObserverDataSource(configuration: configuration)
        self.eventClient = try Self.makeEventClient(configuration)
        self.eventCursorStore.reset()
        self.eventCursor = nil
        self.lastInvalidationReason = nil
        self.lastEventPollErrorCode = nil
        self.credentialStored = true
        self.envelope = nil
        self.lastErrorCode = nil
        self.configurationRevision += 1
    }

    public func forgetCredential() throws {
        try configurationStore.deleteBearerToken()
        credentialStored = false
        dataSource = nil
        eventClient = nil
        eventCursorStore.reset()
        eventCursor = nil
        lastInvalidationReason = nil
        lastEventPollErrorCode = nil
        envelope = nil
        lastErrorCode = nil
        configurationRevision += 1
    }

    @discardableResult
    public func refresh() async -> Bool {
        guard let dataSource else { return false }
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let loaded = try await dataSource.load()
            envelope = loaded

            let isLive = loaded.snapshot.provenance == .live
            if isLive, let metadata = loaded.transportMetadata {
                if eventCursorStore.seed(
                    projectID: projectID,
                    sourceInstanceID: metadata.sourceInstanceID,
                    cursor: metadata.eventCursor
                ) {
                    eventCursor = metadata.eventCursor
                    lastEventPollErrorCode = nil
                } else {
                    eventCursor = nil
                    lastEventPollErrorCode = "EVENT_CURSOR_BASELINE_INVALID"
                }
            } else if isLive {
                eventCursorStore.reset()
                eventCursor = nil
                lastEventPollErrorCode = "EVENT_CURSOR_METADATA_MISSING"
            }

            lastErrorCode = nil
            return isLive
        } catch {
            lastErrorCode = Self.errorCode(error)
            return false
        }
    }

    public func runPollingLoop() async {
        guard isConfigured else { return }

        _ = await refresh()
        var quietPolls = 0
        var unavailablePolls = 0

        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: Self.eventPollIntervalNanoseconds)
            } catch {
                return
            }

            switch await pollEventInvalidation() {
            case .invalidated(let reason):
                lastInvalidationReason = reason.rawValue
                _ = await refresh()
                quietPolls = 0
                unavailablePolls = 0
            case .unchanged:
                quietPolls += 1
                unavailablePolls = 0
                if quietPolls >= Self.quietPollsBeforeSafetyRefresh {
                    _ = await refresh()
                    quietPolls = 0
                }
            case .unavailable:
                unavailablePolls += 1
                if unavailablePolls >= Self.unavailablePollsBeforeFallbackRefresh {
                    _ = await refresh()
                    quietPolls = 0
                    unavailablePolls = 0
                }
            case .deferred:
                continue
            }
        }
    }

    private func pollEventInvalidation() async -> ObserverEventPollOutcome {
        guard !isRefreshing else { return .deferred }
        guard let eventClient else {
            lastEventPollErrorCode = "EVENT_CLIENT_UNAVAILABLE"
            return .unavailable("EVENT_CLIENT_UNAVAILABLE")
        }
        guard let afterID = eventCursorStore.afterID(for: projectID) else {
            lastEventPollErrorCode = "EVENT_CURSOR_UNSEEDED"
            return .unavailable("EVENT_CURSOR_UNSEEDED")
        }

        do {
            let page = try await eventClient.events(
                projectID: projectID,
                afterID: afterID,
                limit: 200
            )
            lastEventPollErrorCode = nil

            switch eventCursorStore.observe(
                projectID: page.projectID,
                sourceInstanceID: page.sourceInstanceID,
                eventCursor: page.eventCursor,
                eventCount: page.events.count
            ) {
            case .unchanged:
                return .unchanged
            case .baselineMissing:
                return .unavailable("EVENT_CURSOR_UNSEEDED")
            case .invalidate(let reason):
                return .invalidated(reason)
            }
        } catch {
            let code = Self.readAPIErrorCode(error)
            lastEventPollErrorCode = code
            return .unavailable(code)
        }
    }

    private static func makeEventClient(
        _ configuration: ObserverTransportConfiguration
    ) throws -> ObserverReadAPIClient {
        let apiConfiguration = try ObserverReadAPIConfiguration(
            baseURL: configuration.baseURL,
            bearerToken: configuration.bearerToken,
            requestTimeout: configuration.requestTimeout
        )
        return ObserverReadAPIClient(configuration: apiConfiguration)
    }

    private static func readAPIErrorCode(_ error: Error) -> String {
        guard let api = error as? ObserverReadAPIError else {
            return "EVENT_POLL_FAILED"
        }
        switch api {
        case .invalidConfiguration(let code): return code
        case .invalidProjectID: return "PROJECT_ID_INVALID"
        case .invalidSessionID: return "SESSION_ID_INVALID"
        case .invalidCursor: return "CURSOR_INVALID"
        case .invalidLimit: return "LIMIT_INVALID"
        case .transportContractMismatch: return "TRANSPORT_CONTRACT_MISMATCH"
        case .authFailed: return "AUTH_FAILED"
        case .forbidden: return "FORBIDDEN"
        case .rateLimited: return "RATE_LIMITED"
        case .httpStatus(let status): return "HTTP_\(status)"
        case .responseContractMismatch: return "BODY_CONTRACT_MISMATCH"
        case .responseScopeMismatch: return "RESPONSE_SCOPE_MISMATCH"
        case .unavailable(let state): return "UNAVAILABLE_\(state)"
        case .unexpectedResponse: return "UNEXPECTED_RESPONSE"
        }
    }

    private static func errorCode(_ error: Error) -> String {
        if error is ObserverReadAPIError {
            return readAPIErrorCode(error)
        }
        guard let transport = error as? ObserverTransportError else {
            if let runtime = error as? ObserverRuntimeConfigurationError {
                switch runtime {
                case .invalidBaseURL: return "CONFIG_URL_INVALID"
                case .invalidProjectID: return "CONFIG_PROJECT_INVALID"
                case .invalidBearerToken: return "CONFIG_TOKEN_INVALID"
                case .credentialMissing: return "CONFIG_TOKEN_MISSING"
                case .keychainFailure: return "KEYCHAIN_UNAVAILABLE"
                }
            }
            return "OBSERVER_UNKNOWN_ERROR"
        }

        switch transport {
        case .invalidConfiguration(let code): return code
        case .invalidResponse: return "INVALID_RESPONSE"
        case .authFailed(let code): return code ?? "AUTH_FAILED"
        case .forbidden(let code): return code ?? "FORBIDDEN"
        case .rateLimited: return "RATE_LIMITED"
        case .httpStatus(let status, let code): return code ?? "HTTP_\(status)"
        case .contractMismatch: return "CONTRACT_MISMATCH"
        case .schemaDecodeFailed: return "SCHEMA_DECODE_FAILED"
        }
    }
}

@MainActor
public struct ObserverLiveRoot: View {
    @StateObject private var model = ObserverLiveViewModel()
    @State private var selectedTab: ObserverRootTab = .overview

    public init() {}

    public var body: some View {
        Group {
            if model.isConfigured {
                ObserverLiveShell(model: model, selectedTab: $selectedTab)
            } else {
                ObserverSetupView(model: model)
            }
        }
        .task(id: model.configurationRevision) {
            await model.runPollingLoop()
        }
    }
}

@MainActor
private struct ObserverLiveShell: View {
    @ObservedObject var model: ObserverLiveViewModel
    @Binding var selectedTab: ObserverRootTab

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                if let envelope = model.envelope {
                    OverviewView(
                        presentation: ObserverProjectionBuilder.makeOverview(envelope.snapshot),
                        detail: preferredDetail(for: envelope)
                    )
                } else {
                    ObserverLivePlaceholder(
                        title: model.connectionLabel,
                        detail: model.lastErrorCode ?? "Waiting for the first live Observer snapshot."
                    )
                }
            }
            .tabItem { Label("Overview", systemImage: "scope") }
            .tag(ObserverRootTab.overview)

            NavigationStack {
                if let envelope = model.envelope {
                    let overview = ObserverProjectionBuilder.makeOverview(envelope.snapshot)
                    RunsView(
                        rows: ObserverProjectionBuilder.makeRunRows(envelope.snapshot),
                        details: details(for: envelope),
                        incident: overview.connectionIncident,
                        cachedNotice: overview.cachedNotice
                    )
                } else {
                    ObserverLivePlaceholder(
                        title: model.connectionLabel,
                        detail: model.lastErrorCode ?? "No live run index has been received yet."
                    )
                }
            }
            .tabItem { Label("Runs", systemImage: "list.bullet.rectangle") }
            .tag(ObserverRootTab.runs)

            NavigationStack {
                ObserverLiveSettingsView(model: model)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(ObserverRootTab.settings)
        }
        .tint(Color.secondary)
        .observerTabBarMinimizeIfAvailable()
    }

    private func details(for envelope: ObserverDataEnvelope) -> [String: RunDetailPresentation] {
        Dictionary(uniqueKeysWithValues: envelope.snapshot.runs.compactMap { run in
            ObserverProjectionBuilder.makeRunDetail(envelope.snapshot, runID: run.runID)
                .map { (run.runID, $0) }
        })
    }

    private func preferredDetail(for envelope: ObserverDataEnvelope) -> RunDetailPresentation? {
        guard let runID = envelope.preferredDetailRunID else { return nil }
        return ObserverProjectionBuilder.makeRunDetail(envelope.snapshot, runID: runID)
    }
}

private struct ObserverLivePlaceholder: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x6) {
            ObserverPageIdentity("OBSERVER", subtitle: "LIVE READ ONLY")
            ObserverDisplayText(title)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            ProgressView()
                .controlSize(.small)
                .opacity(title == "CONNECTING" ? 1 : 0)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ObserverSpacing.x5)
        .padding(.top, ObserverSpacing.x4)
    }
}

@MainActor
private struct ObserverSetupView: View {
    @ObservedObject var model: ObserverLiveViewModel
    @State private var baseURL = ObserverRuntimeConfigurationStore.defaultBaseURLString
    @State private var projectID = ObserverRuntimeConfigurationStore.defaultProjectID
    @State private var token = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ObserverSpacing.x8) {
                    ObserverPageIdentity("CONNECT", subtitle: "OBSERVER READ ONLY")
                    ObserverDisplayText("LIVE SOURCE")

                    VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
                        ObserverMetadataKey("SERVER")
                        TextField("https://host:port", text: $baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.URL)
                            .padding(.vertical, ObserverSpacing.x3)
                        Divider()

                        ObserverMetadataKey("PROJECT")
                        TextField("project-id", text: $projectID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.vertical, ObserverSpacing.x3)
                        Divider()

                        ObserverMetadataKey("READ TOKEN")
                        SecureField("Paste Observer read token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.password)
                            .padding(.vertical, ObserverSpacing.x3)
                        Divider()
                    }

                    if let localError {
                        Text(localError)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Button("SAVE & CONNECT") {
                        do {
                            try model.saveConfiguration(
                                baseURLString: baseURL,
                                projectID: projectID,
                                bearerTokenCandidate: token
                            )
                            token = ""
                            localError = nil
                        } catch {
                            localError = "CONFIGURATION REJECTED"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)

                    Text("The bearer token is stored in iOS Keychain. It is not written to UserDefaults, source code, screenshots, or the repository.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, ObserverSpacing.x5)
                .padding(.top, ObserverSpacing.x6)
                .padding(.bottom, ObserverSpacing.x18)
            }
            .onAppear {
                baseURL = model.baseURLString
                projectID = model.projectID
            }
        }
    }
}

@MainActor
private struct ObserverLiveSettingsView: View {
    @ObservedObject var model: ObserverLiveViewModel
    @State private var baseURL = ""
    @State private var projectID = ""
    @State private var replacementToken = ""
    @State private var localMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ObserverSpacing.x10) {
                ObserverPageIdentity("SETTINGS", subtitle: "LIVE OBSERVER CONFIG")

                settingsGroup(
                    title: "OBSERVER",
                    rows: [
                        ("MODE", "READ ONLY"),
                        ("NETWORK", model.connectionLabel),
                        ("PROJECT", model.projectID),
                        ("CREDENTIAL", model.credentialStored ? "KEYCHAIN STORED" : "MISSING")
                    ]
                )

                VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
                    ObserverMetadataKey("SERVER")
                    TextField("https://host:port", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.vertical, ObserverSpacing.x3)
                    Divider()

                    ObserverMetadataKey("PROJECT")
                    TextField("project-id", text: $projectID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.vertical, ObserverSpacing.x3)
                    Divider()

                    ObserverMetadataKey("REPLACE READ TOKEN")
                    SecureField("Leave blank to keep current token", text: $replacementToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.vertical, ObserverSpacing.x3)
                    Divider()
                }

                if let error = model.lastErrorCode {
                    Text("LAST ERROR  \(error)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let localMessage {
                    Text(localMessage)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("SAVE") {
                        do {
                            try model.saveConfiguration(
                                baseURLString: baseURL,
                                projectID: projectID,
                                bearerTokenCandidate: replacementToken
                            )
                            replacementToken = ""
                            localMessage = "SAVED"
                        } catch {
                            localMessage = "SAVE FAILED"
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("REFRESH NOW") {
                        Task { await model.refresh() }
                    }
                    .buttonStyle(.bordered)
                }

                Button("FORGET LOCAL CREDENTIAL", role: .destructive) {
                    do {
                        try model.forgetCredential()
                        replacementToken = ""
                        localMessage = "LOCAL CREDENTIAL REMOVED"
                    } catch {
                        localMessage = "KEYCHAIN REMOVE FAILED"
                    }
                }
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                    ObserverMetadataKey("BOUNDARY")
                    Text("Read-only Observer transport only. No command plane, approval, retry, restore, deploy, or VPS mutation capability is available to this client.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, ObserverSpacing.x4)
                .overlay(alignment: .top) { Divider() }
            }
            .padding(.horizontal, ObserverSpacing.x5)
            .padding(.top, ObserverSpacing.x4)
            .padding(.bottom, ObserverSpacing.x18)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            baseURL = model.baseURLString
            projectID = model.projectID
        }
    }

    @ViewBuilder
    private func settingsGroup(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ObserverMetadataKey(title)
                .padding(.bottom, ObserverSpacing.x3)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: ObserverSpacing.x4) {
                    Text(row.0)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: ObserverSpacing.x4)
                    Text(row.1)
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, ObserverSpacing.x3)

                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }
}
