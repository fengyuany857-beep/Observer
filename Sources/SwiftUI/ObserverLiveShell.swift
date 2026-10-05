import SwiftUI

@MainActor
public final class ObserverLiveViewModel: ObservableObject {
    @Published public private(set) var envelope: ObserverDataEnvelope?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastErrorCode: String?
    @Published public private(set) var configurationRevision = 0
    @Published public private(set) var credentialStored = false
    @Published public private(set) var baseURLString: String
    @Published public private(set) var projectID: String

    private let configurationStore: ObserverRuntimeConfigurationStore
    private var dataSource: RealObserverDataSource?

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
        self.credentialStored = true
        self.envelope = nil
        self.lastErrorCode = nil
        self.configurationRevision += 1
    }

    public func forgetCredential() throws {
        try configurationStore.deleteBearerToken()
        credentialStored = false
        dataSource = nil
        envelope = nil
        lastErrorCode = nil
        configurationRevision += 1
    }

    public func refresh() async {
        guard let dataSource else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            envelope = try await dataSource.load()
            lastErrorCode = nil
        } catch {
            lastErrorCode = Self.errorCode(error)
        }
    }

    public func runPollingLoop() async {
        guard isConfigured else { return }
        while !Task.isCancelled {
            await refresh()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }
        }
    }

    private static func errorCode(_ error: Error) -> String {
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
