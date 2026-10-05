import SwiftUI

public struct RunDetailSummaryView: View {
    let presentation: RunDetailPresentation
    public init(presentation: RunDetailPresentation) { self.presentation = presentation }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ObserverSpacing.x6) {
                ObserverPageIdentity(presentation.projectName, subtitle: String(presentation.runID.suffix(10)))
                if let incident = presentation.liveConnectionIncident { ConnectionIncidentBar(incident, liveLabel: true) }
                if presentation.provenance == .cached { CachedSnapshotNotice("CACHED RUN SNAPSHOT") }
                ObserverStatusHero(presentation.hero)
                if presentation.completionTruth.engineeringComplete || presentation.hero.rawValue == ExecutionStatus.finalizing.rawValue {
                    CompletionTruthBlock(presentation.completionTruth)
                }
                if let operation = presentation.currentOperation { CurrentOperationBlock(operation) }
                truthMatrix
                if let stage = presentation.stageText {
                    VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                        ObserverMetadataKey("STAGE")
                        Text(stage).font(.headline.weight(.medium))
                    }
                }
                TestProgressRow(presentation.tests)
                VStack(spacing: 0) {
                    ForEach(presentation.destinations) { destination in
                        NavigationLink { PlaceholderDestinationView(title: destination.rawValue) } label: { DestinationRow(destination.rawValue) }
                            .buttonStyle(.plain)
                        Divider()
                    }
                }
                if let event = presentation.lastEventText {
                    VStack(alignment: .leading, spacing: ObserverSpacing.x1) {
                        ObserverMetadataKey("LAST EVENT")
                        Text(event).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                HStack {
                    VStack(alignment: .leading, spacing: ObserverSpacing.x1) {
                        ObserverMetadataKey("UPDATED")
                        Text(presentation.updatedAt, style: .time).font(.callout).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: ObserverSpacing.x1) {
                        ObserverMetadataKey("ELAPSED")
                        LocalElapsedClock(startedAt: presentation.startedAt, endedAt: presentation.endedAt)
                    }
                }
            }
            .padding(.horizontal, ObserverSpacing.x5)
            .padding(.top, ObserverSpacing.x4)
            .padding(.bottom, ObserverSpacing.x18)
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var truthMatrix: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
            ObserverMetadataKey("TRUTH MATRIX")
            ForEach(presentation.truthRows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.key).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: ObserverSpacing.x2) {
                        Circle().fill(ObserverPalette.color(for: row.tone)).frame(width: 6, height: 6)
                        Text(row.value).font(.callout.weight(.medium))
                    }
                }
            }
        }
        .padding(.vertical, ObserverSpacing.x3)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }
}

public struct PlaceholderDestinationView: View {
    let title: String
    public var body: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x5) {
            ObserverPageIdentity(title, subtitle: "SCAFFOLD")
            ObserverDisplayText(title.uppercased())
            Text("Destination intentionally left as a scaffold in Preview Harness V1. No network or command-plane behavior is connected.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(ObserverSpacing.x5)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
