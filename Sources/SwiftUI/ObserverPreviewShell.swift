import SwiftUI

public enum ObserverRootTab: Hashable {
    case overview
    case runs
    case settings
}

public struct ObserverPreviewShell: View {
    let fixture: ObserverFixture
    @State private var selectedTab: ObserverRootTab

    public init(scenario: ObserverPreviewScenario, initialTab: ObserverRootTab = .overview) {
        self.fixture = ObserverFixtureFactory.make(scenario)
        self._selectedTab = State(initialValue: initialTab)
    }

    private var overview: OverviewPresentation { ObserverProjectionBuilder.makeOverview(fixture.snapshot) }
    private var rows: [RunRowPresentation] { ObserverProjectionBuilder.makeRunRows(fixture.snapshot) }
    private var details: [String: RunDetailPresentation] {
        Dictionary(uniqueKeysWithValues: fixture.snapshot.runs.compactMap { run in
            ObserverProjectionBuilder.makeRunDetail(fixture.snapshot, runID: run.runID).map { (run.runID, $0) }
        })
    }
    private var preferredDetail: RunDetailPresentation? {
        fixture.preferredDetailRunID.flatMap { details[$0] }
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { OverviewView(presentation: overview, detail: preferredDetail) }
                .tabItem { Label("Overview", systemImage: "scope") }
                .tag(ObserverRootTab.overview)
            NavigationStack {
                RunsView(rows: rows, details: details, incident: overview.connectionIncident, cachedNotice: overview.cachedNotice)
            }
            .tabItem { Label("Runs", systemImage: "list.bullet.rectangle") }
            .tag(ObserverRootTab.runs)
            NavigationStack { SettingsPreviewView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(ObserverRootTab.settings)
        }
    }
}

public struct SettingsPreviewView: View {
    public var body: some View {
        List {
            Section("Observer") {
                LabeledContent("Mode", value: "Read Only")
                LabeledContent("Motion", value: "System + semantic")
                LabeledContent("Sensitive Mode", value: "Preview only")
            }
            Section("Harness") {
                Text("No network, VPS, push, approval, retry, restore, deploy, or command execution is connected in this sandbox preview package.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
