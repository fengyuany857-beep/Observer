import SwiftUI

public struct ProjectDetailLiveView: View {
    let presentation: ProjectDetailLivePresentation
    let ownerConfigured: Bool
    let sessionCloseAvailable: Bool
    let closeState: ObserverSessionCloseState
    let closeSession: (String) -> Void
    let checkCloseStatus: (String) -> Void
    let reconcileClose: (String) -> Void

    public init(
        presentation: ProjectDetailLivePresentation,
        ownerConfigured: Bool = false,
        sessionCloseAvailable: Bool = true,
        closeState: ObserverSessionCloseState = .idle,
        closeSession: @escaping (String) -> Void = { _ in },
        checkCloseStatus: @escaping (String) -> Void = { _ in },
        reconcileClose: @escaping (String) -> Void = { _ in }
    ) {
        self.presentation = presentation
        self.ownerConfigured = ownerConfigured
        self.sessionCloseAvailable = sessionCloseAvailable
        self.closeState = closeState
        self.closeSession = closeSession
        self.checkCloseStatus = checkCloseStatus
        self.reconcileClose = reconcileClose
    }

    public var body: some View {
        ObserverScreenSurface(
            topology: ObserverTopologyPreset.barelyThere.configuration
        ) {
            ScrollView {
            VStack(alignment: .leading, spacing: ObserverSpacing.x8) {
                ObserverPageIdentity(presentation.projectLabel, subtitle: "PROJECT")
                if let incident = presentation.connectionIncident {
                    ConnectionIncidentBar(incident)
                }
                if let cached = presentation.cachedNotice {
                    CachedSnapshotNotice(cached)
                }

                VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                    ObserverMetadataKey("PROJECT")
                    ObserverDisplayText(presentation.projectLabel)
                    Text(presentation.projectID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                ObserverFunctionalSignal(
                    presentation.freshness.rawValue,
                    tone: freshnessTone(presentation.freshness)
                )
                .observerSemanticChange(
                    value: presentation.freshness.rawValue,
                    emphasis: .subtle
                )

                sessionSection
                currentOperationSection
                jobsSection
                lifecycleSection
                effectsSection
            }
            .padding(.horizontal, ObserverSpacing.x5)
            .padding(.top, ObserverSpacing.x4)
            .padding(.bottom, ObserverSpacing.x18)
            .observerTopologyScrollProbe()
        }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
            ObserverMetadataKey("SESSION")
            if let session = presentation.session {
                let deadline = ObserverDeadlineUXPresentation(
                    serverPhase: session.deadlinePhase,
                    remainingSeconds: session.remainingSeconds,
                    elapsedSeconds: session.elapsedSeconds,
                    hardTTLSeconds: session.hardTTLSeconds,
                    closeReminderSeconds: session.closeReminderSeconds,
                    serverCloseRequired: session.closeRequired,
                    transportLive: presentation.transportLive
                )

                HStack(alignment: .firstTextBaseline) {
                    Text(String(session.sessionID.suffix(8)).uppercased())
                        .font(.headline.weight(.medium))
                        .monospaced()
                    Spacer()
                    Text(session.state)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ObserverSessionDeadlineView(deadline)

                DenseMetadataNode([
                    .init(id: "phase", key: "DEADLINE", value: session.deadlinePhase),
                    .init(id: "credential", key: "CREDENTIAL", value: session.credentialState),
                    .init(
                        id: "queue",
                        key: "QUEUE",
                        value: session.queuePosition.map { String($0) } ?? "—"
                    )
                ])

                SessionCloseControl(
                    sessionID: session.sessionID,
                    deadline: deadline,
                    available: sessionCloseAvailable,
                    ownerConfigured: ownerConfigured,
                    state: closeState,
                    close: closeSession,
                    checkStatus: checkCloseStatus,
                    reconcile: reconcileClose
                )
            } else {
                Text("NO ACTIVE SESSION")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, ObserverSpacing.x4)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var currentOperationSection: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
            if let operation = presentation.currentOperation {
                CurrentOperationBlock(operation)
            } else {
                ObserverMetadataKey("CURRENT OPERATION")
                Text(
                    presentation.transportLive
                        ? "NO IN-FLIGHT OPERATION"
                        : "NO LIVE CURRENT · LAST OBSERVED ONLY"
                )
                .font(.headline.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, ObserverSpacing.x3)
        .observerSemanticChange(
            value: presentation.currentOperation?.semanticMotionIdentity ?? "NO_CURRENT",
            emphasis: .structural
        )
    }

    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                ObserverMetadataKey("JOBS · LAST OBSERVED")
                Spacer()
                Text("\(presentation.jobs.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if presentation.jobs.isEmpty {
                Text("No Job has been observed for the current Session.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(presentation.jobs) { job in
                    VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(String(job.jobID.suffix(8)).uppercased())
                                .font(.callout.weight(.medium))
                                .monospaced()
                            Spacer()
                            Text(job.gatewayState)
                                .font(.caption.weight(.semibold))
                        }

                        HStack(spacing: ObserverSpacing.x2) {
                            Text(job.stateClass.replacingOccurrences(of: "_", with: " "))
                                .font(.caption2.weight(.medium))
                            if job.heavy {
                                Text("HEAVY")
                                    .font(.caption2.weight(.semibold))
                            }
                            Spacer()
                            Text(job.updatedAt, style: .time)
                                .font(.caption2)
                                .monospacedDigit()
                        }
                        .foregroundStyle(.secondary)

                        Text(job.freshness)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, ObserverSpacing.x2)
                    Divider()
                }
            }
        }
        .padding(.vertical, ObserverSpacing.x3)
    }

    @ViewBuilder
    private var lifecycleSection: some View {
        if !presentation.lifecycle.isEmpty {
            VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
                ObserverMetadataKey("SESSION LIFECYCLE")
                ForEach(presentation.lifecycle) { item in
                    VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.action)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(item.state)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(lifecycleTone(item.state))
                        }
                        HStack {
                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(item.updatedAt, style: .time)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        if let error = item.errorCode {
                            Text(error)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, ObserverSpacing.x2)
                    Divider()
                }
            }
            .padding(.vertical, ObserverSpacing.x3)
        }
    }

    @ViewBuilder
    private var effectsSection: some View {
        if !presentation.effects.isEmpty {
            VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
                ObserverMetadataKey("EFFECTS")
                ForEach(presentation.effects) { effect in
                    HStack(alignment: .top, spacing: ObserverSpacing.x3) {
                        Rectangle()
                            .fill(
                                ObserverPalette.color(
                                    for: effect.needsAttention ? .warning : .neutral
                                )
                            )
                            .frame(width: 2)
                        VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(String(effect.effectID.suffix(8)).uppercased())
                                    .font(.callout.weight(.medium))
                                    .monospaced()
                                Spacer()
                                Text(effect.stateKnown ? effect.state : "UNKNOWN")
                                    .font(.caption.weight(.semibold))
                            }
                            Text("TASK \(String(effect.taskID.suffix(8)).uppercased()) · GEN \(effect.generation)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            if let error = effect.errorCode {
                                Text(error)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, ObserverSpacing.x2)
                    Divider()
                }
            }
            .padding(.vertical, ObserverSpacing.x3)
        }
    }

    private func freshnessTone(_ freshness: ObserverB8Freshness) -> SemanticTone {
        switch freshness {
        case .live: .positive
        case .stale, .cached: .warning
        case .offline: .negative
        case .unknown: .neutral
        }
    }

    private func lifecycleTone(_ state: String) -> Color {
        switch state {
        case "SUCCEEDED":
            return ObserverPalette.color(for: .positive)
        case "OUTCOME_UNKNOWN", "FAILED", "RECONCILE", "RECONCILING":
            return ObserverPalette.color(for: .warning)
        default:
            return .secondary
        }
    }

    private struct SessionCloseControl: View {
        let sessionID: String
        let deadline: ObserverDeadlineUXPresentation
        let available: Bool
        let ownerConfigured: Bool
        let state: ObserverSessionCloseState
        let close: (String) -> Void
        let checkStatus: (String) -> Void
        let reconcile: (String) -> Void

        @State private var confirmingClose = false
        @State private var confirmingReconcile = false

        var body: some View {
            VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
                ObserverMetadataKey("OWNER CONTROL · SESSION CLOSE")

                Group {
                    switch state {
                    case .idle:
                    if !available {
                        ObserverFunctionalSignal(
                            "SESSION CLOSE · DEFERRED",
                            tone: .neutral
                        )
                        Text("Session Close is disabled in this build. No close request will be sent.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !ownerConfigured {
                        Text("A separate session:close owner credential is required. Configure it in System; the Approval token cannot close Sessions.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if !deadline.allowsNewSessionClose {
                        ObserverFunctionalSignal(closeBlockedTitle, tone: closeBlockedTone)
                        Text(closeBlockedDetail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Button(deadline.isFinalWarningWindow ? "SAVE & EXIT" : "CLOSE SESSION", role: .destructive) {
                            confirmingClose = true
                        }
                        .buttonStyle(.bordered)
                        .confirmationDialog(
                            deadline.isFinalWarningWindow ? "Save & Exit this Session?" : "Close this Session?",
                            isPresented: $confirmingClose,
                            titleVisibility: .visible
                        ) {
                            Button(deadline.isFinalWarningWindow ? "SAVE & EXIT" : "CLOSE SESSION", role: .destructive) {
                                close(sessionID)
                            }
                            Button("CANCEL", role: .cancel) {}
                        } message: {
                            Text("This revokes the Session credential before cleanup. Cleanup success is verified separately by the backend lifecycle.")
                        }
                    }

                case .submitting(let attemptID):
                    ObserverFunctionalSignal("CLOSE REQUESTED", tone: .warning)
                    closeAttempt(attemptID)
                    ProgressView().controlSize(.small)

                case .tracking(let lifecycle):
                    lifecycleBlock(lifecycle)
                    if !lifecycle.cleanupComplete {
                        Button("CHECK STATUS") { checkStatus(sessionID) }
                            .buttonStyle(.bordered)
                        Button("RECONCILE SAME ATTEMPT") { confirmingReconcile = true }
                            .buttonStyle(.bordered)
                            .confirmationDialog(
                                "Reconcile the existing Close request?",
                                isPresented: $confirmingReconcile,
                                titleVisibility: .visible
                            ) {
                                Button("RECONCILE SAME ATTEMPT") { reconcile(sessionID) }
                                Button("CANCEL", role: .cancel) {}
                            } message: {
                                Text("Reuses the existing close_attempt_id. No new Close request identity is created.")
                            }
                    }

                case .outcomeUnknown(let attemptID, let lifecycle):
                    ObserverFunctionalSignal("OUTCOME UNKNOWN", tone: .warning)
                    if let lifecycle { lifecycleBlock(lifecycle) } else { closeAttempt(attemptID) }
                    Text("The credential may already be revoked, but runtime cleanup is not authoritatively confirmed. Do not create a new close attempt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: ObserverSpacing.x3) {
                        Button("CHECK STATUS") { checkStatus(sessionID) }
                            .buttonStyle(.bordered)
                        Button("RECONCILE SAME ATTEMPT") { confirmingReconcile = true }
                            .buttonStyle(.bordered)
                            .confirmationDialog(
                                "Reconcile this same close attempt?",
                                isPresented: $confirmingReconcile,
                                titleVisibility: .visible
                            ) {
                                Button("RECONCILE SAME ATTEMPT") { reconcile(sessionID) }
                                Button("CANCEL", role: .cancel) {}
                            } message: {
                                Text("This reuses the existing close_attempt_id. It does not create a new Session Close request identity.")
                            }
                    }

                    case .failed(let code):
                        ObserverFunctionalSignal(code, tone: .negative)
                        Text("No successful close is claimed from this client state.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .id(state.semanticMotionIdentity)
                .observerSemanticTransition(.structural)
            }
            .padding(.top, ObserverSpacing.x3)
            .observerSemanticChange(
                value: state.semanticMotionIdentity,
                emphasis: .structural
            )
        }

        private var closeBlockedTitle: String {
            if !deadline.transportLive { return "CLOSE PAUSED · READ TRUTH NOT LIVE" }
            if !deadline.contractConsistent { return "CLOSE PAUSED · DEADLINE INCONSISTENT" }
            switch deadline.phase {
            case .hardExpired: return "SESSION EXPIRED · CLOSE NOT STARTED"
            case .terminal: return "SESSION ENDED"
            case .unknown: return "CLOSE PAUSED · DEADLINE UNKNOWN"
            case .active, .closeRequired: return "CLOSE AVAILABLE"
            }
        }

        private var closeBlockedDetail: String {
            if !deadline.transportLive {
                return "A new close is not started from cached or stale Session truth."
            }
            if !deadline.contractConsistent {
                return "Server deadline fields disagree, so a new owner mutation is withheld until fresh authoritative truth arrives."
            }
            switch deadline.phase {
            case .hardExpired:
                return "Hard expiry is authoritative. Wait for lifecycle/read-plane reconciliation instead of creating a new close attempt."
            case .terminal:
                return "The Session is already terminal. No new close attempt is needed."
            case .unknown:
                return "The server deadline phase is unknown, so a new owner mutation is withheld."
            case .active, .closeRequired:
                return "Session Close is available."
            }
        }

        private var closeBlockedTone: SemanticTone {
            (!deadline.contractConsistent || deadline.phase == .hardExpired) ? .negative : .warning
        }

        @ViewBuilder
        private func lifecycleBlock(_ lifecycle: ObserverOwnerLifecycle) -> some View {
            ObserverFunctionalSignal(lifecycle.state, tone: closeLifecycleTone(lifecycle))
            closeAttempt(lifecycle.operationID)
            DenseMetadataNode([
                .init(id: "credential", key: "CREDENTIAL", value: lifecycle.credentialRevoked ? "REVOKED" : "ACTIVE"),
                .init(id: "cleanup", key: "CLEANUP", value: lifecycle.cleanupComplete ? "VERIFIED" : "NOT CONFIRMED"),
                .init(id: "session", key: "SESSION STATE", value: lifecycle.sessionState)
            ])
            if lifecycle.state == "OUTCOME_UNKNOWN" {
                Text("Credential revoked does not mean cleanup succeeded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if lifecycle.state == "SUCCEEDED" && lifecycle.cleanupComplete {
                Text("Session close verified by the authoritative lifecycle.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let code = lifecycle.errorCode {
                Text(code).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }

        private func closeAttempt(_ attemptID: String) -> some View {
            Text("ATTEMPT \(String(attemptID.suffix(12)).uppercased())")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }

        private func closeLifecycleTone(_ lifecycle: ObserverOwnerLifecycle) -> SemanticTone {
            switch lifecycle.state {
            case "SUCCEEDED": return lifecycle.cleanupComplete ? .positive : .warning
            case "FAILED": return .negative
            default: return .warning
            }
        }
    }

    private static func duration(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
