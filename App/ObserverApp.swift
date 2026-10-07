import Foundation
import SwiftUI

@main
struct ObserverApp: App {
    private let previewScenario: ObserverPreviewScenario?
    private let surface: ObserverLaunchSurface
    private let topologyPreset: ObserverTopologyPreset?

    init() {
        let args = ProcessInfo.processInfo.arguments

        if let rawPreset = Self.value(after: "--topology-preset", in: args) {
            self.topologyPreset = Self.topologyPreset(rawPreset)
        } else {
            self.topologyPreset = nil
        }

        if args.contains("--scenario") {
            self.previewScenario = Self.value(after: "--scenario", in: args)
                .flatMap(ObserverPreviewScenario.init(rawValue:)) ?? .runningActiveOnline
        } else {
            self.previewScenario = nil
        }

        self.surface = Self.value(after: "--surface", in: args)
            .flatMap(ObserverLaunchSurface.init(rawValue:)) ?? .overview
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if let topologyPreset {
                    ObserverTopologyPrototypeView(preset: topologyPreset)
                        .modifier(TopologySnapshotReadinessReporter(preset: topologyPreset))
                } else if let previewScenario {
                    ObserverLaunchRoot(scenario: previewScenario, surface: surface)
                        .modifier(
                            SnapshotReadinessReporter(
                                scenario: previewScenario,
                                surface: surface
                            )
                        )
                } else {
                    ObserverLiveRoot()
                }
#else
                if let previewScenario {
                    ObserverLaunchRoot(scenario: previewScenario, surface: surface)
                        .modifier(
                            SnapshotReadinessReporter(
                                scenario: previewScenario,
                                surface: surface
                            )
                        )
                } else {
                    ObserverLiveRoot()
                }
#endif
            }
            .preferredColorScheme(.dark)
        }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    private static func topologyPreset(_ raw: String) -> ObserverTopologyPreset? {
        switch raw.uppercased() {
        case "A": return .barelyThere
        case "B": return .balanced
        case "C": return .upperBound
        default: return ObserverTopologyPreset(rawValue: raw)
        }
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

#if DEBUG
private struct TopologySnapshotReadinessReporter: ViewModifier {
    let preset: ObserverTopologyPreset

    func body(content: Content) -> some View {
        content.task(id: preset.rawValue) {
            guard ProcessInfo.processInfo.arguments.contains("--snapshot-ci-ready") else { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let marker = directory.appendingPathComponent(
                "observer-topology-ready-\(preset.rawValue)"
            )
            try? Data("ready".utf8).write(to: marker, options: .atomic)
        }
    }
}
#endif
