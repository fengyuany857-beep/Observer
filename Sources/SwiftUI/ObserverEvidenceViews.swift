import SwiftUI
import ObserverReadAPI

enum ObserverEvidenceMode: Sendable {
    case timeline
    case rawEvents
    case effects

    var title: String {
        switch self {
        case .timeline: "Timeline"
        case .rawEvents: "Raw Events"
        case .effects: "Effects"
        }
    }

    var subtitle: String {
        switch self {
        case .timeline: "SESSION-LINKED EVENT EVIDENCE"
        case .rawEvents: "PROJECT EVENT EVIDENCE"
        case .effects: "PROJECT EFFECT LEDGER"
        }
    }

    var boundaryText: String {
        switch self {
        case .timeline:
            "Events are evidence hints, not canonical run truth. Only events with an exact session_id match are shown here."
        case .rawEvents:
            "Project-scoped event evidence is shown without promoting event payloads or flags into run/session state."
        case .effects:
            "Effect state belongs to the effect ledger. Project effects are not promoted into run/session status or Current Operation."
        }
    }
}

@MainActor
final class ObserverEvidenceViewModel: ObservableObject {
    @Published private(set) var events: [ObserverReadEvent] = []
    @Published private(set) var effects: [ObserverReadEffect] = []
    @Published private(set) var projectID = ""
    @Published private(set) var cursor: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorCode: String?

    let mode: ObserverEvidenceMode
    let runID: String

    init(mode: ObserverEvidenceMode, runID: String) {
        self.mode = mode
        self.runID = runID
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let store = ObserverRuntimeConfigurationStore()
            guard let transport = try store.makeTransportConfiguration() else {
                throw ObserverRuntimeConfigurationError.credentialMissing
            }
            let apiConfiguration = try ObserverReadAPIConfiguration(
                baseURL: transport.baseURL,
                bearerToken: transport.bearerToken,
                requestTimeout: transport.requestTimeout
            )
            let client = ObserverReadAPIClient(configuration: apiConfiguration)
            projectID = transport.projectID

            switch mode {
            case .timeline:
                let page = try await client.events(
                    projectID: transport.projectID,
                    afterID: 0,
                    limit: 200
                )
                cursor = page.eventCursor
                events = page.eventsForSession(runID).sorted { $0.createdAt < $1.createdAt }
                effects = []
            case .rawEvents:
                let page = try await client.events(
                    projectID: transport.projectID,
                    afterID: 0,
                    limit: 200
                )
                cursor = page.eventCursor
                events = page.events.sorted { $0.eventID > $1.eventID }
                effects = []
            case .effects:
                let page = try await client.effects(
                    projectID: transport.projectID,
                    limit: 100
                )
                cursor = nil
                effects = page.effects
                events = []
            }
            errorCode = nil
        } catch {
            errorCode = Self.errorCode(error)
        }
    }

    private static func errorCode(_ error: Error) -> String {
        if let api = error as? ObserverReadAPIError {
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
        if let runtime = error as? ObserverRuntimeConfigurationError {
            switch runtime {
            case .invalidBaseURL: return "CONFIG_URL_INVALID"
            case .invalidProjectID: return "CONFIG_PROJECT_INVALID"
            case .invalidBearerToken: return "CONFIG_TOKEN_INVALID"
            case .credentialMissing: return "CONFIG_TOKEN_MISSING"
            case .keychainFailure: return "KEYCHAIN_UNAVAILABLE"
            }
        }
        return "EVIDENCE_READ_FAILED"
    }
}

struct ObserverEvidenceDestinationView: View {
    @StateObject private var model: ObserverEvidenceViewModel
    let projectName: String

    init(mode: ObserverEvidenceMode, runID: String, projectName: String) {
        _model = StateObject(wrappedValue: ObserverEvidenceViewModel(mode: mode, runID: runID))
        self.projectName = projectName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ObserverSpacing.x6) {
                ObserverPageIdentity(model.mode.title.uppercased(), subtitle: model.mode.subtitle)

                Text(model.mode.boundaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: ObserverSpacing.x1) {
                        ObserverMetadataKey("PROJECT")
                        Text(model.projectID.isEmpty ? projectName : model.projectID)
                            .font(.callout.weight(.medium))
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("REFRESH") {
                        Task { await model.refresh() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isLoading)
                }

                if let cursor = model.cursor {
                    evidenceMetadata(key: "EVENT CURSOR", value: String(cursor))
                }

                if model.isLoading && !model.hasLoaded {
                    ProgressView()
                        .controlSize(.small)
                }

                if let errorCode = model.errorCode {
                    VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                        ObserverMetadataKey("READ ERROR")
                        Text(errorCode)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, ObserverSpacing.x3)
                    .overlay(alignment: .top) { Divider() }
                    .overlay(alignment: .bottom) { Divider() }
                } else {
                    switch model.mode {
                    case .timeline, .rawEvents:
                        eventsBody
                    case .effects:
                        effectsBody
                    }
                }
            }
            .padding(.horizontal, ObserverSpacing.x5)
            .padding(.top, ObserverSpacing.x4)
            .padding(.bottom, ObserverSpacing.x18)
        }
        .navigationTitle(model.mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .task {
            if !model.hasLoaded {
                await model.refresh()
            }
        }
    }

    @ViewBuilder
    private var eventsBody: some View {
        if model.events.isEmpty && model.hasLoaded {
            emptyState("NO MATCHING EVENT EVIDENCE")
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.events) { event in
                    eventRow(event)
                    Divider()
                }
            }
            .overlay(alignment: .top) { Divider() }
        }
    }

    @ViewBuilder
    private var effectsBody: some View {
        if model.effects.isEmpty && model.hasLoaded {
            emptyState("NO PROJECT EFFECTS OBSERVED")
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.effects) { effect in
                    effectRow(effect)
                    Divider()
                }
            }
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func eventRow(_ event: ObserverReadEvent) -> some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.eventType)
                    .font(.headline.weight(.medium))
                Spacer()
                Text("#\(event.eventID)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: ObserverSpacing.x3) {
                Text(event.source.uppercased())
                Text(event.authoritative ? "EVENT FLAG: AUTHORITATIVE" : "EVENT FLAG: HINT")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            HStack {
                Text(event.createdAt, style: .time)
                Spacer()
                Text(event.sessionID.map { "SESSION \(short($0))" } ?? "NO SESSION LINK")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            if model.mode == .rawEvents {
                Text(trim(event.payloadSummary, max: 520))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, ObserverSpacing.x4)
    }

    private func effectRow(_ effect: ObserverReadEffect) -> some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
            HStack(alignment: .firstTextBaseline) {
                Text(effect.stateKnown ? effect.state : "UNKNOWN · \(effect.state)")
                    .font(.headline.weight(.medium))
                Spacer()
                Text("GEN \(effect.generation)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            evidenceMetadata(key: "EFFECT", value: short(effect.effectID))
            evidenceMetadata(key: "TASK", value: short(effect.taskID))

            if let code = effect.lastErrorCode {
                evidenceMetadata(key: "ERROR", value: code)
            }
            if let receipt = effect.receiptSummary {
                VStack(alignment: .leading, spacing: ObserverSpacing.x1) {
                    ObserverMetadataKey("RECEIPT")
                    Text(trim(receipt, max: 520))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Text("UPDATED \(effect.updatedAtRaw)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, ObserverSpacing.x4)
    }

    private func evidenceMetadata(key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            ObserverMetadataKey(key)
            Spacer(minLength: ObserverSpacing.x4)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func emptyState(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
            ObserverMetadataKey("EVIDENCE")
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, ObserverSpacing.x5)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func short(_ value: String) -> String {
        value.count <= 18 ? value : String(value.suffix(18))
    }

    private func trim(_ value: String, max: Int) -> String {
        guard value.count > max else { return value }
        return String(value.prefix(max)) + "…"
    }
}
