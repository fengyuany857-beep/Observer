import SwiftUI

public enum ObserverRunScope: String, CaseIterable, Identifiable {
    case all = "ALL"
    case active = "ACTIVE"
    case attention = "ATTENTION"
    public var id: String { rawValue }
}

public struct RunsView: View {
    let rows: [RunRowPresentation]
    let details: [String: RunDetailPresentation]
    let incident: ConnectionIncidentPresentation?
    let cachedNotice: String?
    @State private var query = ""
    @State private var scope: ObserverRunScope = .all

    public init(rows: [RunRowPresentation], details: [String: RunDetailPresentation], incident: ConnectionIncidentPresentation?, cachedNotice: String?) {
        self.rows = rows; self.details = details; self.incident = incident; self.cachedNotice = cachedNotice
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ObserverPageIdentity("RUNS", subtitle: "ARCHIVE INDEX")
                    .padding(.bottom, ObserverSpacing.x4)

                HStack(alignment: .firstTextBaseline) {
                    ObserverMetadataKey("SCOPE")
                    Spacer()

                    Menu {
                        Picker("Scope", selection: $scope) {
                            ForEach(ObserverRunScope.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                    } label: {
                        HStack(spacing: ObserverSpacing.x1) {
                            Text(scope.rawValue)
                                .font(.caption.weight(.medium))
                                .tracking(0.45)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Run scope")
                    .accessibilityValue(scope.rawValue)
                }
                .padding(.bottom, ObserverSpacing.x4)
                .overlay(alignment: .bottom) { Divider() }

                if let incident { ConnectionIncidentBar(incident) }
                if let cachedNotice { CachedSnapshotNotice(cachedNotice) }

                if filteredRows.isEmpty {
                    VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
                        ObserverDisplayText("NO MATCH")
                        Text("No run matches the current search and scope.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, ObserverSpacing.x10)
                } else {
                    ForEach(filteredRows) { row in
                        Group {
                            if let detail = details[row.id] {
                                NavigationLink { RunDetailSummaryView(presentation: detail) } label: {
                                    RunArchiveRow(row)
                                }
                                .buttonStyle(.plain)
                            } else {
                                RunArchiveRow(row)
                            }
                        }
                        Divider()
                    }
                }
            }
            .padding(.horizontal, ObserverSpacing.x4)
            .padding(.top, ObserverSpacing.x4)
            .padding(.bottom, ObserverSpacing.x18)
        }
        .searchable(text: $query, prompt: "Search runs")
        .observerSearchToolbarMinimizeIfAvailable()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filteredRows: [RunRowPresentation] {
        rows.filter { row in
            let queryMatch = query.isEmpty
                || row.projectName.localizedCaseInsensitiveContains(query)
                || row.status.rawValue.localizedCaseInsensitiveContains(query)

            let scopeMatch: Bool = {
                switch scope {
                case .all:
                    true
                case .active:
                    ["PENDING","STARTING","RUNNING","WAITING_APPROVAL","VERIFYING","FINALIZING"].contains(row.status.rawValue)
                case .attention:
                    row.abnormalHealth != nil || ["FAILED","WAITING_APPROVAL","RESUMABLE"].contains(row.status.rawValue)
                }
            }()
            return queryMatch && scopeMatch
        }
    }
}
