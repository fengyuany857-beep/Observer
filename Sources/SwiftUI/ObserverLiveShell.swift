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
    @Published public private(set) var lastOperationPollErrorCode: String?
    @Published public private(set) var ownerCredentialStored = false
    @Published public private(set) var ownerApprovals: [ObserverOwnerApproval] = []
    @Published public private(set) var ownerRecentApproval: ObserverOwnerApproval?
    @Published public private(set) var ownerMutationStates: [String: ObserverOwnerMutationState] = [:]
    @Published public private(set) var sessionCloseStates: [String: ObserverSessionCloseState] = [:]
    @Published public private(set) var ownerErrorCode: String?
    @Published public private(set) var isOwnerRefreshing = false

    private let configurationStore: ObserverRuntimeConfigurationStore
    private let ownerCredentialStore: ObserverOwnerCredentialStore
    private let ownerDecisionCoordinator = ObserverApprovalDecisionCoordinator()
    private let sessionCloseCoordinator = ObserverSessionCloseCoordinator()
    private var dataSource: ObserverB8LiveDataSource?
    private var eventClient: ObserverReadAPIClient?
    private var ownerClient: ObserverOwnerControlClient?
    private var eventCursorStore = ObserverEventCursorStore()

    private static let eventPollIntervalNanoseconds: UInt64 = 2_000_000_000
    private static let quietPollsBeforeSafetyRefresh = 15
    private static let unavailablePollsBeforeFallbackRefresh = 3
    private static let ownerPollIntervalNanoseconds: UInt64 = 5_000_000_000

    public init(
        configurationStore: ObserverRuntimeConfigurationStore = ObserverRuntimeConfigurationStore(),
        ownerCredentialStore: ObserverOwnerCredentialStore = ObserverOwnerCredentialStore()
    ) {
        self.configurationStore = configurationStore
        self.ownerCredentialStore = ownerCredentialStore
        let settings = configurationStore.loadSettings()
        self.baseURLString = settings.baseURL.absoluteString
        self.projectID = settings.projectID

        do {
            if let configuration = try configurationStore.makeTransportConfiguration() {
                self.dataSource = ObserverB8LiveDataSource(configuration: configuration)
                self.eventClient = try Self.makeEventClient(configuration)
                self.credentialStored = true
            }
            if let ownerConfiguration = try ownerCredentialStore.makeConfiguration(settings: settings) {
                self.ownerClient = ObserverOwnerControlClient(configuration: ownerConfiguration)
                self.ownerCredentialStored = true
            }
        } catch {
            self.lastErrorCode = Self.errorCode(error)
        }
    }

    public var isConfigured: Bool {
        dataSource != nil && credentialStored
    }

    public var isOwnerConfigured: Bool {
        ownerClient != nil && ownerCredentialStored
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

        if let ownerConfiguration = try ownerCredentialStore.makeConfiguration(settings: settings) {
            self.ownerClient = ObserverOwnerControlClient(configuration: ownerConfiguration)
            self.ownerCredentialStored = true
        } else {
            self.ownerClient = nil
            self.ownerCredentialStored = false
        }

        self.baseURLString = settings.baseURL.absoluteString
        self.projectID = settings.projectID
        self.dataSource = ObserverB8LiveDataSource(configuration: configuration)
        self.eventClient = try Self.makeEventClient(configuration)
        self.eventCursorStore.reset()
        self.eventCursor = nil
        self.lastInvalidationReason = nil
        self.lastEventPollErrorCode = nil
        self.lastOperationPollErrorCode = nil
        self.credentialStored = true
        self.envelope = nil
        self.lastErrorCode = nil
        self.ownerApprovals = []
        self.ownerRecentApproval = nil
        self.ownerMutationStates = [:]
        self.sessionCloseStates = [:]
        self.ownerErrorCode = nil
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
        lastOperationPollErrorCode = nil
        envelope = nil
        lastErrorCode = nil
        configurationRevision += 1
    }

    public func saveOwnerCredential(_ token: String) throws {
        try ownerCredentialStore.saveBearerToken(token)
        let settings = configurationStore.loadSettings()
        guard let configuration = try ownerCredentialStore.makeConfiguration(settings: settings) else {
            throw ObserverRuntimeConfigurationError.credentialMissing
        }
        ownerClient = ObserverOwnerControlClient(configuration: configuration)
        ownerCredentialStored = true
        ownerErrorCode = nil
        ownerApprovals = []
        ownerRecentApproval = nil
        ownerMutationStates = [:]
        sessionCloseStates = [:]
        configurationRevision += 1
    }

    public func forgetOwnerCredential() throws {
        try ownerCredentialStore.deleteBearerToken()
        ownerCredentialStored = false
        ownerClient = nil
        ownerApprovals = []
        ownerRecentApproval = nil
        ownerMutationStates = [:]
        ownerErrorCode = nil
        configurationRevision += 1
    }

    public func refreshApprovals() async {
        guard let ownerClient, !isOwnerRefreshing else { return }
        isOwnerRefreshing = true
        defer { isOwnerRefreshing = false }
        do {
            ownerApprovals = try await ownerClient.pendingApprovals()
            if let recent = ownerRecentApproval,
               let fresh = try? await ownerClient.approvalStatus(recent.approvalID) {
                ownerRecentApproval = fresh
            }
            ownerErrorCode = nil
        } catch let error as ObserverOwnerControlError {
            ownerErrorCode = ObserverApprovalDecisionCoordinator.code(error)
        } catch {
            ownerErrorCode = "OWNER_REFRESH_FAILED"
        }
    }

    public func decideApproval(
        _ approvalID: String,
        decision: ObserverOwnerDecision
    ) async {
        guard let ownerClient,
              let approval = ownerApprovals.first(where: { $0.approvalID == approvalID }) else {
            return
        }
        if ownerMutationStates[approvalID]?.isBusy == true { return }

        let attemptID = "decision:\(UUID().uuidString.lowercased())"
        ownerMutationStates[approvalID] = .submitting(
            decision: decision,
            attemptID: attemptID
        )
        let result = await ownerDecisionCoordinator.decide(
            approval: approval,
            decision: decision,
            decisionAttemptID: attemptID,
            client: ownerClient
        )
        applyOwnerDecisionResult(
            result,
            approvalID: approvalID,
            decision: decision
        )
    }

    public func reconcileApproval(_ approvalID: String) async {
        guard let ownerClient,
              case .outcomeUnknown(let decision, let attemptID) = ownerMutationStates[approvalID] else {
            return
        }
        let result = await ownerDecisionCoordinator.reconcile(
            approvalID: approvalID,
            decision: decision,
            attemptID: attemptID,
            client: ownerClient
        )
        applyOwnerDecisionResult(
            result,
            approvalID: approvalID,
            decision: decision
        )
    }

    private func applyOwnerDecisionResult(
        _ result: ObserverApprovalDecisionResult,
        approvalID: String,
        decision: ObserverOwnerDecision
    ) {
        switch result {
        case .resolved(let fresh):
            ownerRecentApproval = fresh
            ownerApprovals.removeAll { $0.approvalID == approvalID }
            ownerMutationStates[approvalID] = .resolved(fresh.state)
            ownerErrorCode = nil
        case .conflict(let fresh):
            if fresh.state == "PENDING",
               let index = ownerApprovals.firstIndex(where: { $0.approvalID == approvalID }) {
                ownerApprovals[index] = fresh
            } else {
                ownerRecentApproval = fresh
                ownerApprovals.removeAll { $0.approvalID == approvalID }
            }
            ownerMutationStates[approvalID] = .conflict(stateVersion: fresh.stateVersion)
            ownerErrorCode = "OWNER_STATE_CHANGED_REVIEW_AGAIN"
        case .expired(let fresh):
            ownerApprovals.removeAll { $0.approvalID == approvalID }
            ownerRecentApproval = fresh
            ownerMutationStates[approvalID] = .resolved(fresh?.state ?? "EXPIRED")
            ownerErrorCode = nil
        case .outcomeUnknown(let attemptID, let lastKnown):
            if let lastKnown, lastKnown.state == "PENDING",
               let index = ownerApprovals.firstIndex(where: { $0.approvalID == approvalID }) {
                ownerApprovals[index] = lastKnown
            }
            ownerMutationStates[approvalID] = .outcomeUnknown(
                decision: decision,
                attemptID: attemptID
            )
            ownerErrorCode = "OWNER_OUTCOME_UNKNOWN"
        case .failed(let code):
            ownerMutationStates[approvalID] = .failed(code)
            ownerErrorCode = code
        case .busy(let attemptID):
            ownerMutationStates[approvalID] = .submitting(
                decision: decision,
                attemptID: attemptID
            )
        }
    }

    public func closeSession(_ sessionID: String) async {
        guard let ownerClient else { return }
        if sessionCloseStates[sessionID]?.blocksNewClose == true { return }
        let attemptID = "close:\(UUID().uuidString.lowercased())"
        sessionCloseStates[sessionID] = .submitting(attemptID: attemptID)
        let result = await sessionCloseCoordinator.close(
            sessionID: sessionID,
            closeAttemptID: attemptID,
            client: ownerClient
        )
        applySessionCloseResult(result, sessionID: sessionID)
        if case .observed(let lifecycle) = result, lifecycle.isTerminal {
            _ = await refresh()
        }
    }

    public func checkSessionCloseStatus(_ sessionID: String) async {
        guard let ownerClient,
              let attemptID = sessionCloseStates[sessionID]?.attemptID else {
            return
        }
        let result = await sessionCloseCoordinator.status(
            sessionID: sessionID,
            closeAttemptID: attemptID,
            client: ownerClient
        )
        applySessionCloseResult(result, sessionID: sessionID)
        if case .observed(let lifecycle) = result, lifecycle.isTerminal {
            _ = await refresh()
        }
    }

    public func reconcileSessionClose(_ sessionID: String) async {
        guard let ownerClient,
              let attemptID = sessionCloseStates[sessionID]?.attemptID else {
            return
        }
        let result = await sessionCloseCoordinator.reconcileSameAttempt(
            sessionID: sessionID,
            closeAttemptID: attemptID,
            client: ownerClient
        )
        applySessionCloseResult(result, sessionID: sessionID)
        if case .observed(let lifecycle) = result, lifecycle.isTerminal {
            _ = await refresh()
        }
    }

    private func applySessionCloseResult(
        _ result: ObserverSessionCloseResult,
        sessionID: String
    ) {
        switch result {
        case .observed(let lifecycle):
            if lifecycle.state == "OUTCOME_UNKNOWN" {
                sessionCloseStates[sessionID] = .outcomeUnknown(
                    attemptID: lifecycle.operationID,
                    lifecycle: lifecycle
                )
                ownerErrorCode = "VCW_SESSION_CLOSE_OUTCOME_UNKNOWN"
            } else {
                sessionCloseStates[sessionID] = .tracking(lifecycle)
                ownerErrorCode = lifecycle.errorCode
            }
        case .outcomeUnknown(let attemptID, let lifecycle):
            sessionCloseStates[sessionID] = .outcomeUnknown(
                attemptID: attemptID,
                lifecycle: lifecycle
            )
            ownerErrorCode = "VCW_SESSION_CLOSE_OUTCOME_UNKNOWN"
        case .failed(let code):
            sessionCloseStates[sessionID] = .failed(code)
            ownerErrorCode = code
        case .busy(let attemptID):
            sessionCloseStates[sessionID] = .submitting(attemptID: attemptID)
        }
    }

    public func runApprovalPollingLoop() async {
        guard isOwnerConfigured else { return }
        await refreshApprovals()
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: Self.ownerPollIntervalNanoseconds)
            } catch {
                return
            }
            await refreshApprovals()
        }
    }

    @discardableResult
    public func refresh() async -> Bool {
        await refresh(intent: .manualRefresh)
    }

    @discardableResult
    private func refresh(intent: ObserverB8ReadIntent) async -> Bool {
        guard let dataSource else { return false }
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            var result = try await dataSource.load(intent: intent)
            if result.requiresFullSnapshot, intent != .reconnectBaseline {
                result = try await dataSource.load(intent: .reconnectBaseline)
            }

            if result.disposition == .superseded {
                return false
            }

            if let loaded = result.envelope {
                envelope = loaded
            }
            guard let loaded = result.envelope else {
                lastErrorCode = "B8_BASELINE_UNAVAILABLE"
                return false
            }
            let isLive = loaded.backendTruth?.transportLive == true
                && loaded.snapshot.provenance == .live

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

            lastErrorCode = isLive ? nil : loaded.snapshot.connectionState.rawValue
            return isLive
        } catch {
            lastErrorCode = Self.errorCode(error)
            return false
        }
    }

    public func runPollingLoop() async {
        guard isConfigured else { return }

        _ = await refresh(intent: .reconnectBaseline)
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
                let intent: ObserverB8ReadIntent
                switch reason {
                case .sourceChanged, .cursorRegressed, .projectChanged, .cursorInvalid:
                    intent = .reconnectBaseline
                case .cursorAdvanced, .eventsObserved:
                    intent = .poll
                }
                _ = await refresh(intent: intent)
                quietPolls = 0
                unavailablePolls = 0
            case .unchanged:
                quietPolls += 1
                unavailablePolls = 0
                if quietPolls >= Self.quietPollsBeforeSafetyRefresh {
                    _ = await refresh(intent: .poll)
                    quietPolls = 0
                } else {
                    await refreshCurrentOperationsOnly()
                }
            case .unavailable:
                unavailablePolls += 1
                if unavailablePolls >= Self.unavailablePollsBeforeFallbackRefresh {
                    _ = await refresh(intent: .poll)
                    quietPolls = 0
                    unavailablePolls = 0
                } else {
                    await refreshCurrentOperationsOnly()
                }
            case .deferred:
                continue
            }
        }
    }

    private func refreshCurrentOperationsOnly() async {
        guard !isRefreshing, let dataSource else { return }
        do {
            var result = try await dataSource.refreshCurrentOperations(intent: .poll)
            if result.requiresFullSnapshot {
                _ = await refresh(intent: .reconnectBaseline)
                return
            }
            if result.disposition == .superseded { return }
            if let updated = result.envelope {
                envelope = updated
            }
            switch result.disposition {
            case .accepted, .notModified:
                lastOperationPollErrorCode = nil
            case .transportFailure:
                lastOperationPollErrorCode = "TRANSPORT_FAILURE"
            case .requiresReconnectBaseline:
                lastOperationPollErrorCode = "RECONNECT_BASELINE_REQUIRED"
            case .superseded:
                break
            }
        } catch {
            lastOperationPollErrorCode = Self.errorCode(error)
            if let cached = await dataSource.cachedEnvelope() {
                envelope = cached
            }
        }
    }

    private func envelopeWithCurrentOperations(
        _ loaded: ObserverDataEnvelope
    ) async -> ObserverDataEnvelope {
        let cleared = Self.replacingSnapshot(
            in: loaded,
            with: ObserverCurrentOperationOverlay.clearing(loaded.snapshot)
        )

        guard loaded.snapshot.provenance == .live else {
            return cleared
        }
        guard let eventClient else {
            lastOperationPollErrorCode = "OPERATION_CLIENT_UNAVAILABLE"
            return cleared
        }
        guard let metadata = loaded.transportMetadata else {
            lastOperationPollErrorCode = "OPERATION_SOURCE_METADATA_MISSING"
            return cleared
        }

        do {
            let page = try await eventClient.operations(projectID: projectID)
            guard page.sourceInstanceID == metadata.sourceInstanceID else {
                lastOperationPollErrorCode = "OPERATION_SOURCE_MISMATCH"
                return cleared
            }

            var operationsByRunID: [String: OperationSnapshot] = [:]
            for operation in page.operations {
                operationsByRunID[operation.sessionID] = OperationSnapshot(
                    kind: operation.kind,
                    name: operation.name,
                    startedAt: operation.startedAt
                )
            }
            lastOperationPollErrorCode = nil
            return Self.replacingSnapshot(
                in: loaded,
                with: ObserverCurrentOperationOverlay.applying(
                    operationsByRunID,
                    to: loaded.snapshot
                )
            )
        } catch {
            lastOperationPollErrorCode = Self.readAPIErrorCode(error)
            return cleared
        }
    }

    private static func replacingSnapshot(
        in envelope: ObserverDataEnvelope,
        with snapshot: ObserverSnapshot
    ) -> ObserverDataEnvelope {
        ObserverDataEnvelope(
            snapshot: snapshot,
            preferredDetailRunID: envelope.preferredDetailRunID,
            systemHealth: envelope.systemHealth,
            transportMetadata: envelope.transportMetadata,
            backendTruth: envelope.backendTruth
        )
    }

    private func pollEventInvalidation() async -> ObserverEventPollOutcome {
        guard !isRefreshing else { return .deferred }
        guard let dataSource else {
            lastEventPollErrorCode = "EVENT_CLIENT_UNAVAILABLE"
            return .unavailable("EVENT_CLIENT_UNAVAILABLE")
        }
        guard let afterID = eventCursorStore.afterID(for: projectID) else {
            lastEventPollErrorCode = "EVENT_CURSOR_UNSEEDED"
            return .unavailable("EVENT_CURSOR_UNSEEDED")
        }

        do {
            let page = try await dataSource.pollEvents(afterID: afterID, intent: .poll)
            lastEventPollErrorCode = nil

            switch eventCursorStore.observe(
                projectID: page.projectID,
                sourceInstanceID: page.sourceInstanceID,
                eventCursor: page.eventCursor,
                eventCount: page.eventCount
            ) {
            case .unchanged:
                return .unchanged
            case .baselineMissing:
                return .unavailable("EVENT_CURSOR_UNSEEDED")
            case .invalidate(let reason):
                return .invalidated(reason)
            }
        } catch {
            let code = Self.errorCode(error)
            lastEventPollErrorCode = code
            if let cached = await dataSource.cachedEnvelope() {
                envelope = cached
            }
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
        if let b8 = error as? ObserverB8ReadError {
            switch b8 {
            case .invalidResponse: return "B8_INVALID_RESPONSE"
            case .contractMismatch: return "B8_CONTRACT_MISMATCH"
            case .generationMismatch: return "B8_GENERATION_MISMATCH"
            case .intentMismatch: return "B8_INTENT_MISMATCH"
            case .identityMismatch: return "B8_IDENTITY_MISMATCH"
            case .sourceChanged: return "B8_SOURCE_CHANGED"
            case .cursorRegressed: return "B8_CURSOR_REGRESSED"
            case .projectMismatch: return "B8_PROJECT_MISMATCH"
            case .unavailable(let state): return "B8_UNAVAILABLE_\(state)"
            case .schemaDecodeFailed: return "B8_SCHEMA_DECODE_FAILED"
            case .transport(let transport): return errorCode(transport)
            }
        }
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
        .task(id: model.configurationRevision) {
            await model.runApprovalPollingLoop()
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
                        presentation: ObserverProjectionBuilder.makeOverview(envelope),
                        detail: preferredDetail(for: envelope),
                        isRefreshing: model.isRefreshing,
                        refresh: { Task { await model.refresh() } }
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
                if let envelope = model.envelope,
                   let project = ObserverProjectionBuilder.makeProjectDetail(envelope) {
                    ProjectDetailLiveView(
                        presentation: project,
                        ownerConfigured: model.isOwnerConfigured,
                        closeState: project.session.map {
                            model.sessionCloseStates[$0.sessionID] ?? .idle
                        } ?? .idle,
                        closeSession: { sessionID in
                            Task { await model.closeSession(sessionID) }
                        },
                        checkCloseStatus: { sessionID in
                            Task { await model.checkSessionCloseStatus(sessionID) }
                        },
                        reconcileClose: { sessionID in
                            Task { await model.reconcileSessionClose(sessionID) }
                        }
                    )
                } else {
                    ObserverLivePlaceholder(
                        title: model.connectionLabel,
                        detail: model.lastErrorCode ?? "Waiting for accepted Project runtime truth."
                    )
                }
            }
            .tabItem { Label("Projects", systemImage: "square.stack.3d.up") }
            .tag(ObserverRootTab.runs)

            NavigationStack {
                ApprovalsLiveView(model: model)
            }
            .tabItem { Label("Approvals", systemImage: "checkmark.shield") }
            .tag(ObserverRootTab.approvals)

            NavigationStack {
                ObserverLiveSettingsView(model: model)
            }
            .tabItem { Label("System", systemImage: "gearshape") }
            .tag(ObserverRootTab.settings)
        }
        .tint(Color.secondary)
        .observerTabBarMinimizeIfAvailable()
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
    @State private var replacementOwnerToken = ""
    @State private var localMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ObserverSpacing.x10) {
                ObserverPageIdentity("SYSTEM", subtitle: "OBSERVER CONFIG")

                settingsGroup(
                    title: "OBSERVER",
                    rows: [
                        ("MODE", model.ownerCredentialStored ? "READ + OWNER CONTROL" : "READ ONLY"),
                        ("NETWORK", model.connectionLabel),
                        ("PROJECT", model.projectID),
                        ("READ CREDENTIAL", model.credentialStored ? "obsr_ · KEYCHAIN" : "MISSING"),
                        ("OWNER CREDENTIAL", model.ownerCredentialStored ? "obsw_ · KEYCHAIN" : "MISSING")
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
                    SecureField("Leave blank to keep current obsr_ token", text: $replacementToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.vertical, ObserverSpacing.x3)
                    Divider()

                    ObserverMetadataKey("OWNER TOKEN")
                    SecureField("Leave blank to keep current obsw_ token", text: $replacementOwnerToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
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
                            if !replacementOwnerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                try model.saveOwnerCredential(replacementOwnerToken)
                            }
                            replacementToken = ""
                            replacementOwnerToken = ""
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

                Button("FORGET READ CREDENTIAL", role: .destructive) {
                    do {
                        try model.forgetCredential()
                        replacementToken = ""
                        localMessage = "READ CREDENTIAL REMOVED"
                    } catch {
                        localMessage = "KEYCHAIN REMOVE FAILED"
                    }
                }
                .buttonStyle(.borderless)

                if model.ownerCredentialStored {
                    Button("FORGET OWNER CREDENTIAL", role: .destructive) {
                        do {
                            try model.forgetOwnerCredential()
                            replacementOwnerToken = ""
                            localMessage = "OWNER CREDENTIAL REMOVED"
                        } catch {
                            localMessage = "OWNER KEYCHAIN REMOVE FAILED"
                        }
                    }
                    .buttonStyle(.borderless)
                }

                VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                    ObserverMetadataKey("BOUNDARY")
                    Text("Read Plane and Owner Control Plane use separate credentials. obsr_ remains GET-only. obsw_ is limited to the frozen owner-control actions and never exposes raw VCW Grants or Session handles.")
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
