import ActivityKit
import SwiftUI
import WidgetKit

struct ObserverWidgetEntry: TimelineEntry {
    let date: Date
}

struct ObserverWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ObserverWidgetEntry { .init(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (ObserverWidgetEntry) -> Void) { completion(.init(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ObserverWidgetEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: .now)], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct ObserverStatusWidget: Widget {
    let kind = "ObserverStatusWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ObserverWidgetProvider()) { _ in
            VStack(alignment: .leading, spacing: 6) {
                Text("OBSERVER").font(.caption2.weight(.semibold))
                Text("RUNNING").font(.title3.weight(.semibold))
                Text("Preview scaffold · open app for current truth")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Observer Status")
        .description("Glanceable projection only. The app remains the complete observer surface.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ObserverActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var stage: String
        var progress: Double
    }
    var runID: String
}

struct ObserverLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ObserverActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(context.state.status).font(.headline)
                Text(context.state.stage).font(.caption)
                ProgressView(value: context.state.progress)
            }
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(context.state.status).font(.caption.weight(.semibold)) }
                DynamicIslandExpandedRegion(.trailing) { Text("\(Int(context.state.progress * 100))%") }
                DynamicIslandExpandedRegion(.bottom) { ProgressView(value: context.state.progress) }
            } compactLeading: {
                Image(systemName: "scope")
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))")
            } minimal: {
                Image(systemName: "scope")
            }
        }
    }
}

@main
struct ObserverWidgets: WidgetBundle {
    var body: some Widget {
        ObserverStatusWidget()
        ObserverLiveActivityWidget()
    }
}
