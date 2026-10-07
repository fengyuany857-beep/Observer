import SwiftUI

public struct OverviewView: View {
    let presentation: OverviewPresentation
    let detail: RunDetailPresentation?
    let isRefreshing: Bool
    let refresh: (() -> Void)?

    public init(
        presentation: OverviewPresentation,
        detail: RunDetailPresentation?,
        isRefreshing: Bool = false,
        refresh: (() -> Void)? = nil
    ) {
        self.presentation = presentation
        self.detail = detail
        self.isRefreshing = isRefreshing
        self.refresh = refresh
    }

    public var body: some View {
        ObserverScreenSurface(
            topology: ObserverTopologyPreset.barelyThere.configuration
        ) {
            ScrollView {
            VStack(alignment: .leading, spacing: ObserverSpacing.x8) {
                ObserverPageIdentity(presentation.pageIdentity, subtitle: "READ ONLY")
                if let incident = presentation.connectionIncident { ConnectionIncidentBar(incident) }
                if let cached = presentation.cachedNotice { CachedSnapshotNotice(cached) }
                if let live = presentation.liveRuntime {
                    liveRuntimeContent(live)
                } else {
                    focusContent
                }
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
    private func liveRuntimeContent(_ live: OverviewLiveRuntimePresentation) -> some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x8) {
            HStack(alignment: .firstTextBaseline, spacing: ObserverSpacing.x4) {
                VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                    ObserverMetadataKey("ACTIVE PROJECT")
                    ObserverDisplayText(live.projectLabel)
                    Text(live.projectID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: ObserverSpacing.x3)
                if let refresh {
                    Button(action: refresh) {
                        HStack(spacing: ObserverSpacing.x2) {
                            if isRefreshing { ProgressView().controlSize(.mini) }
                            Text(isRefreshing ? "REFRESHING" : "REFRESH")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                }
            }

            ObserverFunctionalSignal(
                isRefreshing ? "REFRESHING" : live.freshness.rawValue,
                tone: freshnessTone(live.freshness)
            )
            .observerSemanticChange(
                value: live.freshness.rawValue,
                emphasis: .subtle
            )

            sessionNode(live.session, transportLive: live.transportLive)

            VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
                if let operation = live.currentOperation {
                    CurrentOperationBlock(operation)
                } else {
                    ObserverMetadataKey("CURRENT OPERATION")
                    Text(live.transportLive ? "NO IN-FLIGHT OPERATION" : "NO LIVE CURRENT · LAST OBSERVED ONLY")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(live.transportLive ? .secondary : .primary)
                }
            }
            .padding(.vertical, ObserverSpacing.x4)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
            .observerSemanticChange(
                value: live.currentOperation?.semanticMotionIdentity ?? "NO_CURRENT",
                emphasis: .structural
            )

            if live.pendingApprovalCount > 0 {
                ObserverFunctionalSignal(
                    "\(live.pendingApprovalCount) APPROVAL\(live.pendingApprovalCount == 1 ? "" : "S") NEED ATTENTION",
                    tone: .warning
                )
                .observerSemanticTransition(.attention)
            }

            DenseMetadataNode([
                .init(id: "queue", key: "QUEUED", value: String(live.queuedSessionCount)),
                .init(id: "freshness", key: "FRESHNESS", value: live.freshness.rawValue),
                .init(id: "transport", key: "TRANSPORT", value: live.transportLive ? "LIVE" : "NOT LIVE")
            ])

            if !live.health.isEmpty {
                VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
                    ObserverMetadataKey("SYSTEM")
                    ForEach(live.health) { item in
                        HStack(alignment: .firstTextBaseline, spacing: ObserverSpacing.x4) {
                            Text(item.component)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: ObserverSpacing.x4)
                            Text(item.status)
                                .font(.callout.weight(.medium))
                            Text(item.freshness)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
            }
        }
        .observerSemanticChange(
            value: live.pendingApprovalCount,
            emphasis: .attention
        )
    }

    @ViewBuilder
    private func sessionNode(
        _ session: OverviewSessionPresentation?,
        transportLive: Bool
    ) -> some View {
        if let session {
            VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
                HStack(alignment: .firstTextBaseline) {
                    ObserverMetadataKey("SESSION")
                    Spacer()
                    Text(session.state)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ObserverSessionDeadlineView(
                    ObserverDeadlineUXPresentation(
                        serverPhase: session.deadlinePhase,
                        remainingSeconds: session.remainingSeconds,
                        elapsedSeconds: session.elapsedSeconds,
                        hardTTLSeconds: session.hardTTLSeconds,
                        closeReminderSeconds: session.closeReminderSeconds,
                        serverCloseRequired: session.closeRequired,
                        transportLive: transportLive
                    )
                )

                DenseMetadataNode([
                    .init(id: "session-id", key: "SESSION", value: String(session.sessionID.suffix(8)).uppercased()),
                    .init(id: "deadline", key: "DEADLINE", value: session.deadlinePhase),
                    .init(id: "credential", key: "CREDENTIAL", value: session.credentialState),
                    .init(id: "queue-position", key: "QUEUE", value: session.queuePosition.map { String($0) } ?? "—")
                ])
            }
            .padding(.vertical, ObserverSpacing.x3)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
        } else {
            VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                ObserverMetadataKey("SESSION")
                Text("NO ACTIVE SESSION")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, ObserverSpacing.x4)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
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

    private static func duration(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    @ViewBuilder private var focusContent: some View {
        switch presentation.focusMode {
        case .focused(let run):
            runContent(run, lastRun: false)
        case .lastRun(let run):
            runContent(run, lastRun: true)
        case .aggregate(let aggregate):
            VStack(alignment: .leading, spacing: ObserverSpacing.x8) {
                ObserverDisplayText(aggregate.primaryLabel)
                Text(aggregate.secondaryLabel)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                    ObserverMetadataKey("ACTIVE RUN IDS")
                    ForEach(aggregate.runIDs, id: \.self) {
                        Text(String($0.suffix(10))).font(.callout).monospaced()
                    }
                }
                .padding(.vertical, ObserverSpacing.x4)
                .overlay(alignment: .top) { Divider() }
                .overlay(alignment: .bottom) { Divider() }
            }
        case .empty:
            VStack(alignment: .leading, spacing: ObserverSpacing.x8) {
                ObserverDisplayText("NO RUN")
                Text("No observed run is available.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                DenseMetadataNode([.init(id: "truth", key: "SOURCE", value: "NO RUN SNAPSHOT")])
            }
        }
    }

    @ViewBuilder private func runContent(_ run: RunSummaryPresentation, lastRun: Bool) -> some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x8) {
            if lastRun { ObserverMetadataKey("LAST RUN") }

            ObserverStatusHero(run.status)

            if run.health != .active {
                RuntimeHealthAttentionNode(run.health)
            }

            if run.completionTruth.engineeringComplete || run.status.rawValue == ExecutionStatus.finalizing.rawValue {
                CompletionTruthBlock(run.completionTruth)
            }

            if let op = run.currentOperation {
                CurrentOperationBlock(op)
            }

            ObserverInstrumentNode(
                fields: run.metadata,
                healthFreshness: run.healthFreshness,
                terminal: run.endedAt != nil,
                startedAt: run.startedAt,
                endedAt: run.endedAt,
                tests: run.tests,
                checkpoint: run.checkpoint,
                healthAttentionElevated: run.health != .active
            )

            if let detail {
                NavigationLink { RunDetailSummaryView(presentation: detail) } label: {
                    DestinationRow("Run Detail", detail: "Truth, evidence, timeline, logs")
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Divider() }
            }
        }
    }
}
