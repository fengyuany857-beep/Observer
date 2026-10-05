import Foundation
import SwiftUI

@main
struct ObserverApp: App {
    private let scenario: ObserverPreviewScenario
    private let surface: ObserverLaunchSurface

    init() {
        let args = ProcessInfo.processInfo.arguments
        self.scenario = Self.value(after: "--scenario", in: args)
            .flatMap(ObserverPreviewScenario.init(rawValue:)) ?? .runningActiveOnline
        self.surface = Self.value(after: "--surface", in: args)
            .flatMap(ObserverLaunchSurface.init(rawValue:)) ?? .overview
    }

    var body: some Scene {
        WindowGroup {
            ObserverLaunchRoot(scenario: scenario, surface: surface)
                .preferredColorScheme(.dark)
                .modifier(SnapshotReadinessReporter(scenario: scenario, surface: surface))
        }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
}

public enum ObserverLaunchSurface: String, Sendable {
    case overview
    case runs
    case detail
    case settings
}

public struct ObserverLaunchRoot: View {
    let scenario: ObserverPreviewScenario
    let surface: ObserverLaunchSurface

    public var body: some View {
        let fixture = ObserverFixtureFactory.make(scenario)
        switch surface {
        case .overview:
            ObserverPreviewShell(scenario: scenario, initialTab: .overview)
        case .runs:
            ObserverPreviewShell(scenario: scenario, initialTab: .runs)
        case .settings:
            ObserverPreviewShell(scenario: scenario, initialTab: .settings)
        case .detail:
            NavigationStack {
                if let runID = fixture.preferredDetailRunID,
                   let detail = ObserverProjectionBuilder.makeRunDetail(fixture.snapshot, runID: runID) {
                    RunDetailSummaryView(presentation: detail)
                } else {
                    ContentUnavailableView("No run detail", systemImage: "questionmark.circle")
                }
            }
        }
    }
}

private struct SnapshotReadinessReporter: ViewModifier {
    let scenario: ObserverPreviewScenario
    let surface: ObserverLaunchSurface

    func body(content: Content) -> some View {
        content.task(id: scenario.rawValue + "-" + surface.rawValue) {
            guard ProcessInfo.processInfo.arguments.contains("--snapshot-ci-ready") else { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let marker = directory.appendingPathComponent(
                "observer-snapshot-ready-\(scenario.rawValue)-\(surface.rawValue)"
            )
            try? Data("ready".utf8).write(to: marker, options: .atomic)
        }
    }
}
