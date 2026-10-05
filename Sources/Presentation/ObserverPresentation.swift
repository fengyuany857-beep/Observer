import Foundation

public enum SemanticTone: String, Sendable, Equatable {
    case positive, warning, negative, neutral, connection
}

public struct StatusPresentation: Sendable, Equatable {
    public let primary: String
    public let secondary: String?
    public let rawValue: String
    public let symbolName: String
    public let tone: SemanticTone
}

public struct ConnectionIncidentPresentation: Sendable, Equatable {
    public let state: ConnectionState
    public let title: String
    public let detail: String?
    public let symbolName: String
    public let tone: SemanticTone
}

public struct MetadataFieldPresentation: Identifiable, Sendable, Equatable {
    public let id: String
    public let key: String
    public let value: String
}

public struct CurrentOperationPresentation: Sendable, Equatable {
    public let kind: String
    public let name: String
    public let startedAt: Date
}

public struct CompletionTruth: Sendable, Equatable {
    public let engineeringComplete: Bool
    public let artifactVerified: Bool
    public let presentationConfirmed: Bool
    public let presentationUnknown: Bool
}

public struct TestsPresentation: Sendable, Equatable {
    public let completed: Int
    public let total: Int
    public let passed: Int
    public let failed: Int
    public let skipped: Int
}

public struct CheckpointPresentation: Sendable, Equatable {
    public let id: String
    public let status: String
    public let createdAt: Date?
}

public struct HealthFreshnessPresentation: Sendable, Equatable {
    public let health: RuntimeHealth
    public let updatedAt: Date
    public let runLastSeen: Date?
    public let relayLastSeen: Date?
}

public struct RunSummaryPresentation: Identifiable, Sendable, Equatable {
    public var id: String { runID }
    public let runID: String
    public let projectName: String
    public let status: StatusPresentation
    public let health: RuntimeHealth
    public let stageText: String?
    public let updatedAt: Date
    public let startedAt: Date
    public let endedAt: Date?
    public let completionTruth: CompletionTruth
    public let currentOperation: CurrentOperationPresentation?
    public let metadata: [MetadataFieldPresentation]
    public let healthFreshness: HealthFreshnessPresentation
    public let tests: TestsPresentation
    public let checkpoint: CheckpointPresentation?
    public let isCached: Bool
}

public struct ActiveRunsAggregatePresentation: Sendable, Equatable {
    public let count: Int
    public let runIDs: [String]
    public let primaryLabel: String
    public let secondaryLabel: String
}

public enum OverviewFocusMode: Sendable, Equatable {
    case focused(RunSummaryPresentation)
    case aggregate(ActiveRunsAggregatePresentation)
    case lastRun(RunSummaryPresentation)
    case empty
}

public struct OverviewPresentation: Sendable, Equatable {
    public let pageIdentity: String
    public let connectionIncident: ConnectionIncidentPresentation?
    public let focusMode: OverviewFocusMode
    public let cachedNotice: String?
}

public struct RunRowPresentation: Identifiable, Sendable, Equatable {
    public let id: String
    public let projectName: String
    public let status: StatusPresentation
    public let secondaryLine: String
    public let abnormalHealth: RuntimeHealth?
    public let updatedAt: Date
    public let isCached: Bool
}

public struct TruthRowPresentation: Identifiable, Sendable, Equatable {
    public let id: String
    public let key: String
    public let value: String
    public let tone: SemanticTone
}

public enum RunDetailDestination: String, CaseIterable, Identifiable, Sendable {
    case timeline = "Timeline"
    case tests = "Tests"
    case checkpointsAndArtifacts = "Checkpoints & Artifacts"
    case logs = "Logs"
    case rawEvents = "Raw Events"
    public var id: String { rawValue }
}

public struct RunDetailPresentation: Sendable, Equatable {
    public let runID: String
    public let projectName: String
    public let liveConnectionIncident: ConnectionIncidentPresentation?
    public let hero: StatusPresentation
    public let completionTruth: CompletionTruth
    public let currentOperation: CurrentOperationPresentation?
    public let truthRows: [TruthRowPresentation]
    public let stageText: String?
    public let tests: TestsPresentation
    public let destinations: [RunDetailDestination]
    public let lastEventText: String?
    public let updatedAt: Date
    public let provenance: SnapshotProvenance
    public let startedAt: Date
    public let endedAt: Date?
}

public enum FocusRunResolver {
    public static func activeRuns(_ runs: [RunStatusSnapshot]) -> [RunStatusSnapshot] {
        runs.filter { $0.isActivePresentationCandidate }
    }
}

public enum ObserverProjectionBuilder {
    public static func status(_ status: ExecutionStatus) -> StatusPresentation {
        switch status {
        case .pending: .init(primary: "PENDING", secondary: nil, rawValue: status.rawValue, symbolName: "clock", tone: .neutral)
        case .starting: .init(primary: "STARTING", secondary: nil, rawValue: status.rawValue, symbolName: "arrowtriangle.right.circle", tone: .neutral)
        case .running: .init(primary: "RUNNING", secondary: nil, rawValue: status.rawValue, symbolName: "waveform.path.ecg", tone: .positive)
        case .waitingApproval: .init(primary: "WAITING", secondary: "APPROVAL REQUIRED", rawValue: status.rawValue, symbolName: "pause.circle", tone: .warning)
        case .verifying: .init(primary: "VERIFYING", secondary: nil, rawValue: status.rawValue, symbolName: "checkmark.circle.badge.questionmark", tone: .neutral)
        case .finalizing: .init(primary: "FINALIZING", secondary: nil, rawValue: status.rawValue, symbolName: "flag.checkered", tone: .neutral)
        case .completed: .init(primary: "COMPLETED", secondary: nil, rawValue: status.rawValue, symbolName: "checkmark.circle", tone: .positive)
        case .failed: .init(primary: "FAILED", secondary: nil, rawValue: status.rawValue, symbolName: "xmark.octagon", tone: .negative)
        case .aborted: .init(primary: "ABORTED", secondary: nil, rawValue: status.rawValue, symbolName: "stop.circle", tone: .negative)
        case .resumable: .init(primary: "RESUMABLE", secondary: nil, rawValue: status.rawValue, symbolName: "arrow.clockwise.circle", tone: .warning)
        case .unknown: .init(primary: "UNKNOWN", secondary: nil, rawValue: status.rawValue, symbolName: "questionmark.circle", tone: .neutral)
        }
    }

    public static func status(_ run: RunStatusSnapshot) -> StatusPresentation {
        if let truth = run.directorTruth {
            return status(truth)
        }
        return status(run.executionStatus)
    }

    public static func status(_ truth: DirectorTaskTruth) -> StatusPresentation {
        let raw = "\(truth.state.rawValue)|\(truth.outcome.rawValue)"

        if truth.terminal || truth.state == .terminal {
            if truth.outcome == .succeeded {
                return .init(primary: "COMPLETED", secondary: nil, rawValue: raw, symbolName: "checkmark.circle", tone: .positive)
            }
            if truth.outcome == .failed {
                return .init(primary: "FAILED", secondary: truth.blockingReason, rawValue: raw, symbolName: "xmark.octagon", tone: .negative)
            }
            if truth.outcome == .cancelled {
                return .init(primary: "ABORTED", secondary: nil, rawValue: raw, symbolName: "stop.circle", tone: .negative)
            }
            if truth.outcome == .partial {
                return .init(primary: "PARTIAL", secondary: truth.blockingReason, rawValue: raw, symbolName: "exclamationmark.circle", tone: .warning)
            }
            if truth.outcome == .blocked {
                return .init(primary: "BLOCKED", secondary: truth.blockingReason, rawValue: raw, symbolName: "lock.circle", tone: .warning)
            }
            if truth.outcome == .outcomeUnknown {
                return .init(primary: "OUTCOME UNKNOWN", secondary: truth.blockingReason, rawValue: raw, symbolName: "questionmark.circle", tone: .warning)
            }
            return .init(primary: "TERMINAL", secondary: truth.outcome.rawValue, rawValue: raw, symbolName: "circle", tone: .neutral)
        }

        if truth.state == .created {
            return .init(primary: "PENDING", secondary: nil, rawValue: raw, symbolName: "clock", tone: .neutral)
        }
        if truth.state == .waiting {
            return .init(primary: "WAITING", secondary: truth.waitReason, rawValue: raw, symbolName: "pause.circle", tone: .warning)
        }
        if truth.state == .running {
            return .init(primary: "RUNNING", secondary: nil, rawValue: raw, symbolName: "waveform.path.ecg", tone: .positive)
        }
        if truth.state == .needsDecision {
            return .init(primary: "NEEDS DECISION", secondary: truth.blockingReason ?? truth.waitReason, rawValue: raw, symbolName: "questionmark.diamond", tone: .warning)
        }
        if truth.state == .paused {
            return .init(primary: "PAUSED", secondary: truth.waitReason, rawValue: raw, symbolName: "pause.circle", tone: .warning)
        }
        if truth.state == .reconciling {
            return .init(primary: "RECONCILING", secondary: truth.blockingReason, rawValue: raw, symbolName: "arrow.triangle.2.circlepath", tone: .warning)
        }
        if truth.state == .cancelling {
            return .init(primary: "CANCELLING", secondary: nil, rawValue: raw, symbolName: "xmark.circle", tone: .warning)
        }

        return .init(primary: "UNKNOWN STATE", secondary: truth.state.rawValue, rawValue: raw, symbolName: "questionmark.circle", tone: .neutral)
    }

    public static func connectionIncident(_ state: ConnectionState, lastSyncAt: Date, observedAt: Date) -> ConnectionIncidentPresentation? {
        switch state {
        case .online: nil
        case .connecting: .init(state: state, title: "CONNECTING", detail: "Establishing observer connection", symbolName: "antenna.radiowaves.left.and.right", tone: .connection)
        case .reconnecting: .init(state: state, title: "RECONNECTING", detail: "Last sync \(relativeAge(lastSyncAt, now: observedAt))", symbolName: "arrow.triangle.2.circlepath", tone: .connection)
        case .offline: .init(state: state, title: "CONNECTION OFFLINE", detail: "Showing last known truth · sync \(relativeAge(lastSyncAt, now: observedAt))", symbolName: "wifi.slash", tone: .connection)
        case .serverUnreachable: .init(state: state, title: "SERVER UNREACHABLE", detail: "Relay/server unreachable · last sync \(relativeAge(lastSyncAt, now: observedAt))", symbolName: "exclamationmark.triangle", tone: .connection)
        case .authFailed: .init(state: state, title: "AUTH FAILED", detail: "Cached truth · last sync \(relativeAge(lastSyncAt, now: observedAt))", symbolName: "key.fill", tone: .warning)
        }
    }

    public static func liveConnection(_ state: ConnectionState, lastSyncAt: Date, observedAt: Date) -> ConnectionIncidentPresentation {
        if let incident = connectionIncident(state, lastSyncAt: lastSyncAt, observedAt: observedAt) {
            return incident
        }
        return .init(state: .online, title: "ONLINE", detail: "Current observer connection", symbolName: "wifi", tone: .positive)
    }

    public static func completionTruth(_ run: RunStatusSnapshot) -> CompletionTruth {
        .init(
            engineeringComplete: run.directorTruth?.engineeringComplete ?? (run.executionStatus == .completed),
            artifactVerified: run.bundle.status == .verified,
            presentationConfirmed: run.presentationStatus == .confirmedPresented,
            presentationUnknown: run.presentationStatus == .unknown
        )
    }

    public static func runSummary(_ run: RunStatusSnapshot, provenance: SnapshotProvenance) -> RunSummaryPresentation {
        let stage = run.stage.map { "\($0.name) · \($0.index)/\($0.total)" }
        let metadata: [MetadataFieldPresentation] = [
            .init(id: "run", key: "RUN", value: shortID(run.runID)),
            .init(id: "phase", key: "PHASE", value: run.runtimePhase.rawValue),
            .init(id: "stage", key: "STAGE", value: run.stage.map { String(format: "%02d/%02d", $0.index, $0.total) } ?? "—"),
            .init(id: "seq", key: "SEQ", value: run.lastEvent.map { String($0.seq) } ?? "—")
        ]
        let currentOperation = run.currentOperation.map { CurrentOperationPresentation(kind: $0.kind, name: $0.name, startedAt: $0.startedAt) }
        let checkpoint = run.checkpoint.latestID.map { CheckpointPresentation(id: $0, status: run.checkpoint.status ?? "UNKNOWN", createdAt: run.checkpoint.createdAt) }
        return .init(
            runID: run.runID,
            projectName: run.projectName,
            status: status(run),
            health: run.runtimeHealth,
            stageText: stage,
            updatedAt: run.updatedAt,
            startedAt: run.startedAt,
            endedAt: run.endedAt,
            completionTruth: completionTruth(run),
            currentOperation: currentOperation,
            metadata: metadata,
            healthFreshness: .init(health: run.runtimeHealth, updatedAt: run.updatedAt, runLastSeen: run.heartbeats.runLastSeen, relayLastSeen: run.heartbeats.relayLastSeen),
            tests: .init(completed: run.tests.completed, total: run.tests.total, passed: run.tests.passed, failed: run.tests.failed, skipped: run.tests.skipped),
            checkpoint: checkpoint,
            isCached: provenance == .cached
        )
    }

    public static func makeOverview(_ snapshot: ObserverSnapshot) -> OverviewPresentation {
        let connection = connectionIncident(snapshot.connectionState, lastSyncAt: snapshot.lastSyncAt, observedAt: snapshot.observedAt)
        let cachedNotice = snapshot.provenance == .cached ? "CACHED SNAPSHOT · LAST SYNC \(timeOnly(snapshot.lastSyncAt))" : nil
        if let focusID = snapshot.authoritativeFocusRunID,
           let run = snapshot.runs.first(where: { $0.runID == focusID }) {
            return .init(pageIdentity: "OBSERVER", connectionIncident: connection, focusMode: .focused(runSummary(run, provenance: snapshot.provenance)), cachedNotice: cachedNotice)
        }
        let active = FocusRunResolver.activeRuns(snapshot.runs)
        if active.count == 1, let run = active.first {
            return .init(pageIdentity: "OBSERVER", connectionIncident: connection, focusMode: .focused(runSummary(run, provenance: snapshot.provenance)), cachedNotice: cachedNotice)
        }
        if active.count > 1 {
            let aggregate = ActiveRunsAggregatePresentation(count: active.count, runIDs: active.map(\.runID), primaryLabel: "\(active.count) ACTIVE", secondaryLabel: "MULTIPLE RUNS · SELECT FROM RUNS")
            return .init(pageIdentity: "OBSERVER", connectionIncident: connection, focusMode: .aggregate(aggregate), cachedNotice: cachedNotice)
        }
        if let latest = snapshot.runs.max(by: { $0.updatedAt < $1.updatedAt }) {
            return .init(pageIdentity: "OBSERVER", connectionIncident: connection, focusMode: .lastRun(runSummary(latest, provenance: snapshot.provenance)), cachedNotice: cachedNotice)
        }
        return .init(pageIdentity: "OBSERVER", connectionIncident: connection, focusMode: .empty, cachedNotice: cachedNotice)
    }

    public static func makeRunRows(_ snapshot: ObserverSnapshot) -> [RunRowPresentation] {
        snapshot.runs.sorted { $0.updatedAt > $1.updatedAt }.map { run in
            let secondary = [run.stage.map { "\($0.name) \($0.index)/\($0.total)" }, "UPDATED \(timeOnly(run.updatedAt))"].compactMap { $0 }.joined(separator: " · ")
            let abnormal: RuntimeHealth? = run.runtimeHealth == .active ? nil : run.runtimeHealth
            return .init(id: run.runID, projectName: run.projectName, status: status(run), secondaryLine: secondary, abnormalHealth: abnormal, updatedAt: run.updatedAt, isCached: snapshot.provenance == .cached)
        }
    }

    public static func makeRunDetail(_ snapshot: ObserverSnapshot, runID: String) -> RunDetailPresentation? {
        guard let run = snapshot.runs.first(where: { $0.runID == runID }) else { return nil }
        let truth: [TruthRowPresentation] = {
            if let director = run.directorTruth {
                var rows: [TruthRowPresentation] = [
                    .init(id: "task-state", key: "TASK STATE", value: director.state.rawValue, tone: .neutral),
                    .init(id: "outcome", key: "OUTCOME", value: director.outcome.rawValue, tone: outcomeTone(director.outcome)),
                    .init(id: "recovery", key: "RECOVERY", value: director.recoveryState.rawValue, tone: director.recoveryState == .clean ? .neutral : .warning)
                ]
                if let access = director.access {
                    rows.append(.init(id: "access", key: "ACCESS", value: access.rawValue, tone: access == .denied || access == .expired ? .warning : .neutral))
                }
                rows.append(.init(id: "health", key: run.isTerminalObservation ? "FINAL HEALTH" : "HEALTH", value: run.runtimeHealth.rawValue, tone: run.runtimeHealth == .suspectedStuck ? .warning : .neutral))
                rows.append(.init(id: "artifact", key: "ARTIFACT", value: run.bundle.status.rawValue, tone: run.bundle.status == .verified ? .positive : (run.bundle.status == .failed ? .negative : .neutral)))
                rows.append(.init(id: "presentation", key: "PRESENTATION", value: run.presentationStatus.rawValue, tone: .neutral))
                return rows
            }
            return [
                .init(id: "execution", key: "EXECUTION", value: run.executionStatus.rawValue, tone: run.executionStatus == .failed ? .negative : .neutral),
                .init(id: "health", key: run.executionStatus.isTerminal ? "FINAL HEALTH" : "HEALTH", value: run.runtimeHealth.rawValue, tone: run.runtimeHealth == .suspectedStuck ? .warning : .neutral),
                .init(id: "artifact", key: "ARTIFACT", value: run.bundle.status.rawValue, tone: run.bundle.status == .verified ? .positive : (run.bundle.status == .failed ? .negative : .neutral)),
                .init(id: "presentation", key: "PRESENTATION", value: run.presentationStatus.rawValue, tone: .neutral)
            ]
        }()
        let current = run.currentOperation.map { CurrentOperationPresentation(kind: $0.kind, name: $0.name, startedAt: $0.startedAt) }
        let stage = run.stage.map { "\($0.name) · \($0.index)/\($0.total)" }
        let lastEvent = run.lastEvent.map { "EPOCH \($0.epoch) · SEQ \($0.seq) · \($0.type)" }
        return .init(
            runID: run.runID,
            projectName: run.projectName,
            liveConnectionIncident: liveConnection(snapshot.connectionState, lastSyncAt: snapshot.lastSyncAt, observedAt: snapshot.observedAt),
            hero: status(run),
            completionTruth: completionTruth(run),
            currentOperation: current,
            truthRows: truth,
            stageText: stage,
            tests: .init(completed: run.tests.completed, total: run.tests.total, passed: run.tests.passed, failed: run.tests.failed, skipped: run.tests.skipped),
            destinations: RunDetailDestination.allCases,
            lastEventText: lastEvent,
            updatedAt: run.updatedAt,
            provenance: snapshot.provenance,
            startedAt: run.startedAt,
            endedAt: run.endedAt
        )
    }

    private static func outcomeTone(_ outcome: DirectorTaskOutcome) -> SemanticTone {
        if outcome == .failed || outcome == .cancelled { return .negative }
        if outcome == .partial || outcome == .blocked || outcome == .outcomeUnknown { return .warning }
        if outcome == .succeeded { return .positive }
        return .neutral
    }

    private static func shortID(_ value: String) -> String { String(value.suffix(6)).uppercased() }
    public static func timeOnly(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "HH:mm:ss"; return f.string(from: date)
    }
    public static func relativeAge(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

public enum AccessibilitySemanticEvent: Equatable, Sendable {
    case completed(eventID: String)
    case failed(eventID: String)
    case waitingApproval(eventID: String)
    case suspectedStuck(eventID: String)
    case reconnected(eventID: String)
    case heartbeat(eventID: String)
    case testCountChanged(eventID: String)
}

public enum AccessibilityAnnouncementPolicy {
    public static func announcement(for event: AccessibilitySemanticEvent) -> String? {
        switch event {
        case .completed: "Run completed"
        case .failed: "Run failed"
        case .waitingApproval: "Approval required"
        case .suspectedStuck: "Run may be stuck"
        case .reconnected: "Connection restored"
        case .heartbeat, .testCountChanged: nil
        }
    }
}
