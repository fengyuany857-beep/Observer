import SwiftUI

public struct OverviewView: View {
    let presentation: OverviewPresentation
    let detail: RunDetailPresentation?
    public init(presentation: OverviewPresentation, detail: RunDetailPresentation?) { self.presentation = presentation; self.detail = detail }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ObserverSpacing.x6) {
                ObserverPageIdentity(presentation.pageIdentity, subtitle: "READ ONLY")
                if let incident = presentation.connectionIncident { ConnectionIncidentBar(incident) }
                if let cached = presentation.cachedNotice { CachedSnapshotNotice(cached) }
                focusContent
            }
            .padding(.horizontal, ObserverSpacing.x5)
            .padding(.top, ObserverSpacing.x4)
            .padding(.bottom, ObserverSpacing.x18)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var focusContent: some View {
        switch presentation.focusMode {
        case .focused(let run): runContent(run, lastRun: false)
        case .lastRun(let run): runContent(run, lastRun: true)
        case .aggregate(let aggregate):
            VStack(alignment: .leading, spacing: ObserverSpacing.x6) {
                ObserverDisplayText(aggregate.primaryLabel)
                Text(aggregate.secondaryLabel).font(.headline).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                    ObserverMetadataKey("ACTIVE RUN IDS")
                    ForEach(aggregate.runIDs, id: \.self) { Text(String($0.suffix(10))).font(.callout).monospaced() }
                }
                .padding(.vertical, ObserverSpacing.x3)
                .overlay(alignment: .top) { Divider() }
            }
        case .empty:
            VStack(alignment: .leading, spacing: ObserverSpacing.x5) {
                ObserverDisplayText("IDLE")
                Text("No observed run is available.").font(.body).foregroundStyle(.secondary)
                DenseMetadataNode([.init(id: "truth", key: "SOURCE", value: "NO RUN SNAPSHOT")])
            }
        }
    }

    @ViewBuilder private func runContent(_ run: RunSummaryPresentation, lastRun: Bool) -> some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x6) {
            if lastRun { ObserverMetadataKey("LAST RUN") }
            ObserverStatusHero(run.status)
            if run.completionTruth.engineeringComplete || run.status.rawValue == ExecutionStatus.finalizing.rawValue {
                CompletionTruthBlock(run.completionTruth)
            }
            if let op = run.currentOperation { CurrentOperationBlock(op) }
            DenseMetadataNode(run.metadata)
            HStack(alignment: .bottom) {
                HealthFreshnessBlock(run.healthFreshness)
                Spacer(minLength: ObserverSpacing.x4)
                VStack(alignment: .trailing, spacing: ObserverSpacing.x1) {
                    ObserverMetadataKey("ELAPSED")
                    LocalElapsedClock(startedAt: run.startedAt, endedAt: run.endedAt)
                }
            }
            TestProgressRow(run.tests)
            if let cp = run.checkpoint { CheckpointRow(cp) }
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
