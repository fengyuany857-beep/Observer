import Foundation

public enum ObserverPreviewScenario: String, CaseIterable, Sendable {
    case runningActiveOnline
    case startingActiveOnline
    case verifyingActiveOnline
    case finalizingActiveOnline
    case completedVerifiedPresentationUnknown
    case completedPresentationConfirmed
    case failedOnline
    case aborted
    case resumable
    case waitingApproval
    case runningSlow
    case runningStale
    case runningSuspectedStuck
    case runningLastKnownOffline
    case runningReconnecting
    case authFailedCached
    case multipleActiveAggregate
    case noRunEmpty

    public var ordinal: Int { Self.allCases.firstIndex(of: self)! + 1 }
    public var title: String { String(format: "%02d · %@", ordinal, rawValue) }
}

public struct ObserverFixture: Sendable {
    public let scenario: ObserverPreviewScenario
    public let snapshot: ObserverSnapshot
    public let preferredDetailRunID: String?
}

public enum ObserverFixtureFactory {
    public static let now = Date(timeIntervalSince1970: 1_791_151_200) // deterministic 2026 fixture clock

    public static func make(_ scenario: ObserverPreviewScenario) -> ObserverFixture {
        let live: SnapshotProvenance = scenario == .authFailedCached || scenario == .runningLastKnownOffline ? .cached : .live
        let connection: ConnectionState = {
            switch scenario {
            case .runningLastKnownOffline: .offline
            case .runningReconnecting: .reconnecting
            case .authFailedCached: .authFailed
            default: .online
            }
        }()

        if scenario == .noRunEmpty {
            return .init(scenario: scenario, snapshot: .init(connectionState: .online, authoritativeFocusRunID: nil, runs: [], observedAt: now, lastSyncAt: now, provenance: .live), preferredDetailRunID: nil)
        }

        if scenario == .multipleActiveAggregate {
            let a = makeRun(id: "run-alpha-8F72A1", project: "Observer UI", execution: .running, health: .active, artifact: .creating, presentation: .unknown, stageName: "BUILD", stageIndex: 4, testsCompleted: 24, updatedAgo: 2)
            let b = makeRun(id: "run-beta-2C118E", project: "Continuity Guard", execution: .verifying, health: .active, artifact: .verifying, presentation: .unknown, stageName: "VERIFY", stageIndex: 6, testsCompleted: 48, updatedAgo: 4)
            let snapshot = ObserverSnapshot(connectionState: .online, authoritativeFocusRunID: nil, runs: [a,b], observedAt: now, lastSyncAt: now.addingTimeInterval(-1), provenance: .live)
            return .init(scenario: scenario, snapshot: snapshot, preferredDetailRunID: a.runID)
        }

        let config = configForScenario(scenario)
        let run = makeRun(
            id: "run-main-8F72A1",
            project: "GPT Local Guard",
            execution: config.execution,
            health: config.health,
            artifact: config.artifact,
            presentation: config.presentation,
            stageName: config.stage,
            stageIndex: config.stageIndex,
            testsCompleted: config.testsCompleted,
            updatedAgo: config.updatedAgo,
            terminalEndedAgo: config.terminalEndedAgo
        )
        let older = makeRun(id: "run-older-77A019", project: "Observer Motion", execution: .completed, health: .active, artifact: .verified, presentation: .confirmedPresented, stageName: "DONE", stageIndex: 7, testsCompleted: 57, updatedAgo: 3600, terminalEndedAgo: 3550)
        let snapshot = ObserverSnapshot(connectionState: connection, authoritativeFocusRunID: config.authoritativeFocus ? run.runID : nil, runs: [run, older], observedAt: now, lastSyncAt: now.addingTimeInterval(-config.lastSyncAgo), provenance: live)
        return .init(scenario: scenario, snapshot: snapshot, preferredDetailRunID: run.runID)
    }

    private struct ScenarioConfig {
        let execution: ExecutionStatus
        let health: RuntimeHealth
        let artifact: ArtifactStatus
        let presentation: PresentationStatus
        let stage: String
        let stageIndex: Int
        let testsCompleted: Int
        let updatedAgo: TimeInterval
        let lastSyncAgo: TimeInterval
        let terminalEndedAgo: TimeInterval?
        let authoritativeFocus: Bool
    }

    private static func configForScenario(_ s: ObserverPreviewScenario) -> ScenarioConfig {
        switch s {
        case .runningActiveOnline: .init(execution: .running, health: .active, artifact: .creating, presentation: .unknown, stage: "BUILD", stageIndex: 4, testsCompleted: 24, updatedAgo: 2, lastSyncAgo: 1, terminalEndedAgo: nil, authoritativeFocus: true)
        case .startingActiveOnline: .init(execution: .starting, health: .active, artifact: .notStarted, presentation: .unknown, stage: "PREPARE", stageIndex: 1, testsCompleted: 0, updatedAgo: 1, lastSyncAgo: 1, terminalEndedAgo: nil, authoritativeFocus: true)
        case .verifyingActiveOnline: .init(execution: .verifying, health: .active, artifact: .verifying, presentation: .unknown, stage: "VERIFY", stageIndex: 6, testsCompleted: 48, updatedAgo: 2, lastSyncAgo: 1, terminalEndedAgo: nil, authoritativeFocus: true)
        case .finalizingActiveOnline: .init(execution: .finalizing, health: .active, artifact: .verified, presentation: .unknown, stage: "FINALIZE", stageIndex: 7, testsCompleted: 57, updatedAgo: 1, lastSyncAgo: 1, terminalEndedAgo: nil, authoritativeFocus: true)
        case .completedVerifiedPresentationUnknown: .init(execution: .completed, health: .active, artifact: .verified, presentation: .unknown, stage: "DONE", stageIndex: 7, testsCompleted: 57, updatedAgo: 16, lastSyncAgo: 10, terminalEndedAgo: 15, authoritativeFocus: true)
        case .completedPresentationConfirmed: .init(execution: .completed, health: .active, artifact: .verified, presentation: .confirmedPresented, stage: "DONE", stageIndex: 7, testsCompleted: 57, updatedAgo: 20, lastSyncAgo: 12, terminalEndedAgo: 18, authoritativeFocus: true)
        case .failedOnline: .init(execution: .failed, health: .active, artifact: .failed, presentation: .unknown, stage: "TEST", stageIndex: 5, testsCompleted: 39, updatedAgo: 7, lastSyncAgo: 2, terminalEndedAgo: 6, authoritativeFocus: true)
        case .aborted: .init(execution: .aborted, health: .unknown, artifact: .created, presentation: .unknown, stage: "BUILD", stageIndex: 4, testsCompleted: 20, updatedAgo: 30, lastSyncAgo: 8, terminalEndedAgo: 28, authoritativeFocus: true)
        case .resumable: .init(execution: .resumable, health: .stale, artifact: .created, presentation: .unknown, stage: "CHECKPOINT", stageIndex: 4, testsCompleted: 20, updatedAgo: 900, lastSyncAgo: 60, terminalEndedAgo: nil, authoritativeFocus: true)
        case .waitingApproval: .init(execution: .waitingApproval, health: .active, artifact: .creating, presentation: .unknown, stage: "APPROVAL", stageIndex: 4, testsCompleted: 24, updatedAgo: 3, lastSyncAgo: 1, terminalEndedAgo: nil, authoritativeFocus: true)
        case .runningSlow: .init(execution: .running, health: .slow, artifact: .creating, presentation: .unknown, stage: "BUILD", stageIndex: 4, testsCompleted: 24, updatedAgo: 12, lastSyncAgo: 3, terminalEndedAgo: nil, authoritativeFocus: true)
        case .runningStale: .init(execution: .running, health: .stale, artifact: .creating, presentation: .unknown, stage: "BUILD", stageIndex: 4, testsCompleted: 24, updatedAgo: 180, lastSyncAgo: 10, terminalEndedAgo: nil, authoritativeFocus: true)
        case .runningSuspectedStuck: .init(execution: .running, health: .suspectedStuck, artifact: .creating, presentation: .unknown, stage: "BUILD", stageIndex: 4, testsCompleted: 24, updatedAgo: 420, lastSyncAgo: 10, terminalEndedAgo: nil, authoritativeFocus: true)
        case .runningLastKnownOffline: .init(execution: .running, health: .active, artifact: .creating, presentation: .unknown, stage: "BUILD", stageIndex: 4, testsCompleted: 24, updatedAgo: 85, lastSyncAgo: 90, terminalEndedAgo: nil, authoritativeFocus: true)
        case .runningReconnecting: .init(execution: .running, health: .active, artifact: .creating, presentation: .unknown, stage: "BUILD", stageIndex: 4, testsCompleted: 24, updatedAgo: 8, lastSyncAgo: 9, terminalEndedAgo: nil, authoritativeFocus: true)
        case .authFailedCached: .init(execution: .running, health: .stale, artifact: .creating, presentation: .unknown, stage: "BUILD", stageIndex: 4, testsCompleted: 24, updatedAgo: 600, lastSyncAgo: 620, terminalEndedAgo: nil, authoritativeFocus: true)
        case .multipleActiveAggregate, .noRunEmpty: fatalError("handled before config")
        }
    }

    private static func makeRun(
        id: String,
        project: String,
        execution: ExecutionStatus,
        health: RuntimeHealth,
        artifact: ArtifactStatus,
        presentation: PresentationStatus,
        stageName: String,
        stageIndex: Int,
        testsCompleted: Int,
        updatedAgo: TimeInterval,
        terminalEndedAgo: TimeInterval? = nil
    ) -> RunStatusSnapshot {
        let start = now.addingTimeInterval(-1122)
        let ended = terminalEndedAgo.map { now.addingTimeInterval(-$0) }
        let updated = now.addingTimeInterval(-updatedAgo)
        let isLive = ended == nil && !execution.isTerminal
        let operation: OperationSnapshot? = isLive ? .init(kind: "TOOL", name: operationName(execution), startedAt: now.addingTimeInterval(-37)) : nil
        return .init(
            runID: id,
            workspaceID: "workspace-default",
            projectName: project,
            executionStatus: execution,
            runtimeHealth: health,
            runtimePhase: execution == .finalizing ? .finalizeOnly : (health == .suspectedStuck ? .cautious : .normal),
            stage: .init(id: "stage-\(stageIndex)", name: stageName, index: stageIndex, total: 7),
            currentOperation: operation,
            elapsedMS: Int64((ended ?? now).timeIntervalSince(start) * 1000),
            startedAt: start,
            endedAt: ended,
            heartbeats: .init(runLastSeen: updated, toolLastSeen: updated.addingTimeInterval(-1), relayLastSeen: updated.addingTimeInterval(-2)),
            tests: .init(total: 57, completed: testsCompleted, passed: max(0, testsCompleted - (execution == .failed ? 1 : 0)), failed: execution == .failed ? 1 : 0, skipped: 0),
            checkpoint: .init(latestID: "cp-04F9", status: execution == .failed ? "FAILED" : "VERIFIED", createdAt: now.addingTimeInterval(-240)),
            bundle: .init(status: artifact, id: artifact == .notStarted ? nil : "bundle-C91A"),
            presentationStatus: presentation,
            lastEvent: .init(eventID: "evt-1842", epoch: 3, seq: 1842, type: execution == .failed ? "TEST_FAILED" : "TOOL_FINISHED", severity: execution == .failed ? "ERROR" : "INFO", createdAt: updated),
            updatedAt: updated
        )
    }

    private static func operationName(_ status: ExecutionStatus) -> String {
        switch status {
        case .starting: "Prepare workspace"
        case .verifying: "Run verification suite"
        case .finalizing: "Assemble final evidence"
        case .waitingApproval: "Await approval"
        default: "Apply UI contract"
        }
    }
}

public enum SyntheticScaleFixtures {
    public static func timeline(count: Int) -> [TimelineEventFixture] {
        precondition(count >= 0)
        return (0..<count).map { i in
            .init(id: "evt-\(i)", epoch: 3, seq: i + 1, type: i % 11 == 0 ? "HEARTBEAT_GROUP" : "TOOL_EVENT", message: "Synthetic event \(i + 1)")
        }
    }

    public static func logLine(index: Int) -> String {
        "[\(String(format: "%08d", index))] synthetic observer log line"
    }
}
