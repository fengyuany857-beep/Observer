import SwiftUI

public enum ObserverRootTab: Hashable {
    case overview
    case runs
    case approvals
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
            NavigationStack {
                OverviewView(presentation: overview, detail: preferredDetail)
            }
            .tabItem {
                Label("Overview", systemImage: "scope")
            }
            .tag(ObserverRootTab.overview)

            NavigationStack {
                RunsView(rows: rows, details: details, incident: overview.connectionIncident, cachedNotice: overview.cachedNotice)
            }
            .tabItem {
                Label("Runs", systemImage: "list.bullet.rectangle")
            }
            .tag(ObserverRootTab.runs)

            NavigationStack {
                SettingsPreviewView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(ObserverRootTab.settings)
        }
        .tint(Color.secondary)
        .observerTabBarMinimizeIfAvailable()
    }
}

public struct SettingsPreviewView: View {
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ObserverSpacing.x10) {
                ObserverPageIdentity("SETTINGS", subtitle: "OBSERVER CONFIG")

                settingsGroup(
                    title: "OBSERVER",
                    rows: [
                        ("MODE", "READ ONLY"),
                        ("MOTION", "SYSTEM + SEMANTIC"),
                        ("SENSITIVE MODE", "PREVIEW ONLY")
                    ]
                )

                settingsGroup(
                    title: "HARNESS",
                    rows: [
                        ("NETWORK", "NOT CONNECTED"),
                        ("COMMAND PLANE", "DISCONNECTED"),
                        ("MUTATION", "DISABLED")
                    ]
                )

                VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                    ObserverMetadataKey("SANDBOX BOUNDARY")
                    Text("No VPS, push, approval, retry, restore, deploy, or command execution is connected in this preview package.")
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
