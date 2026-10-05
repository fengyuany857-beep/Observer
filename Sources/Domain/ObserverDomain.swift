import Foundation

public enum ExecutionStatus: String, CaseIterable, Sendable, Codable {
    case pending = "PENDING"
    case starting = "STARTING"
    case running = "RUNNING"
    case waitingApproval = "WAITING_APPROVAL"
    case verifying = "VERIFYING"
    case finalizing = "FINALIZING"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case aborted = "ABORTED"
    case resumable = "RESUMABLE"
    case unknown = "UNKNOWN"

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .aborted: true
        default: false
        }
    }

    public var isActivePresentationCandidate: Bool {
        switch self {
        case .pending, .starting, .running, .waitingApproval, .verifying, .finalizing: true
        case .completed, .failed, .aborted, .resumable, .unknown: false
        }
    }
}


public protocol DirectorRawStringValue: RawRepresentable, Codable, Hashable, Sendable where RawValue == String {}

public extension DirectorRawStringValue {
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct DirectorTaskState: DirectorRawStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let created = Self(rawValue: "CREATED")
    public static let waiting = Self(rawValue: "WAITING")
    public static let running = Self(rawValue: "RUNNING")
    public static let needsDecision = Self(rawValue: "NEEDS_DECISION")
    public static let paused = Self(rawValue: "PAUSED")
    public static let reconciling = Self(rawValue: "RECONCILING")
    public static let cancelling = Self(rawValue: "CANCELLING")
    public static let terminal = Self(rawValue: "TERMINAL")
}

public struct DirectorTaskOutcome: DirectorRawStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let unresolved = Self(rawValue: "UNRESOLVED")
    public static let succeeded = Self(rawValue: "SUCCEEDED")
    public static let partial = Self(rawValue: "PARTIAL")
    public static let failed = Self(rawValue: "FAILED")
    public static let outcomeUnknown = Self(rawValue: "OUTCOME_UNKNOWN")
    public static let blocked = Self(rawValue: "BLOCKED")
    public static let cancelled = Self(rawValue: "CANCELLED")
}

public struct DirectorRecoveryState: DirectorRawStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let clean = Self(rawValue: "CLEAN")
    public static let dirtyKnown = Self(rawValue: "DIRTY_KNOWN")
    public static let reconciliationRequired = Self(rawValue: "RECONCILIATION_REQUIRED")
    public static let recoveryRequired = Self(rawValue: "RECOVERY_REQUIRED")
    public static let recoveryBlocked = Self(rawValue: "RECOVERY_BLOCKED")
}

public struct DirectorAccessState: DirectorRawStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let pending = Self(rawValue: "PENDING")
    public static let authorized = Self(rawValue: "AUTHORIZED")
    public static let denied = Self(rawValue: "DENIED")
    public static let expired = Self(rawValue: "EXPIRED")
    public static let notRequired = Self(rawValue: "NOT_REQUIRED")
    public static let unknown = Self(rawValue: "UNKNOWN")
}

public enum DirectorStateVersion: Sendable, Codable, Equatable {
    case integer(Int64)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

public struct DirectorTaskTruth: Sendable, Codable, Equatable {
    public let taskID: String
    public let projectID: String
    public let state: DirectorTaskState
    public let stateClass: String?
    public let stateVersion: DirectorStateVersion
    public let terminal: Bool
    public let settled: Bool
    public let outcome: DirectorTaskOutcome
    public let recoveryState: DirectorRecoveryState
    public let access: DirectorAccessState?
    public let waitReason: String?
    public let blockingReason: String?
    public let cancellable: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        taskID: String,
        projectID: String,
        state: DirectorTaskState,
        stateClass: String? = nil,
        stateVersion: DirectorStateVersion,
        terminal: Bool,
        settled: Bool,
        outcome: DirectorTaskOutcome,
        recoveryState: DirectorRecoveryState,
        access: DirectorAccessState? = nil,
        waitReason: String? = nil,
        blockingReason: String? = nil,
        cancellable: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.taskID = taskID
        self.projectID = projectID
        self.state = state
        self.stateClass = stateClass
        self.stateVersion = stateVersion
        self.terminal = terminal
        self.settled = settled
        self.outcome = outcome
        self.recoveryState = recoveryState
        self.access = access
        self.waitReason = waitReason
        self.blockingReason = blockingReason
        self.cancellable = cancellable
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isActivePresentationCandidate: Bool {
        guard !terminal else { return false }
        return state == .created
            || state == .waiting
            || state == .running
            || state == .needsDecision
            || state == .paused
            || state == .reconciling
            || state == .cancelling
    }

    public var engineeringComplete: Bool {
        terminal && outcome == .succeeded
    }
}

public enum RuntimeHealth: String, CaseIterable, Sendable, Codable {
    case active = "ACTIVE"
    case slow = "SLOW"
    case stale = "STALE"
    case suspectedStuck = "SUSPECTED_STUCK"
    case unknown = "UNKNOWN"
}

public enum RuntimePhase: String, CaseIterable, Sendable, Codable {
    case normal = "NORMAL"
    case checkpointDue = "CHECKPOINT_DUE"
    case cautious = "CAUTIOUS"
    case conservative = "CONSERVATIVE"
    case finalCheckpoint = "FINAL_CHECKPOINT"
    case handoffDue = "HANDOFF_DUE"
    case finalizeOnly = "FINALIZE_ONLY"
}

public enum ConnectionState: String, CaseIterable, Sendable, Codable {
    case connecting = "CONNECTING"
    case online = "ONLINE"
    case reconnecting = "RECONNECTING"
    case offline = "OFFLINE"
    case serverUnreachable = "SERVER_UNREACHABLE"
    case authFailed = "AUTH_FAILED"
}

public enum ArtifactStatus: String, CaseIterable, Sendable, Codable {
    case notStarted = "NOT_STARTED"
    case creating = "CREATING"
    case created = "CREATED"
    case verifying = "VERIFYING"
    case verified = "VERIFIED"
    case exported = "EXPORTED"
    case failed = "FAILED"
}

public enum PresentationStatus: String, CaseIterable, Sendable, Codable {
    case unknown = "UNKNOWN"
    case confirmedPresented = "CONFIRMED_PRESENTED"
}

public enum SnapshotProvenance: String, Sendable, Codable {
    case live = "LIVE"
    case cached = "CACHED"
}

public struct StageSnapshot: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let index: Int
    public let total: Int
}

public struct OperationSnapshot: Sendable, Codable, Equatable {
    public let kind: String
    public let name: String
    public let startedAt: Date
}

public struct HeartbeatSnapshot: Sendable, Codable, Equatable {
    public let runLastSeen: Date?
    public let toolLastSeen: Date?
    public let relayLastSeen: Date?
}

public struct TestSummary: Sendable, Codable, Equatable {
    public let total: Int
    public let completed: Int
    public let passed: Int
    public let failed: Int
    public let skipped: Int
}

public struct CheckpointSummary: Sendable, Codable, Equatable {
    public let latestID: String?
    public let status: String?
    public let createdAt: Date?
}

public struct BundleSummary: Sendable, Codable, Equatable {
    public let status: ArtifactStatus
    public let id: String?
}

public struct LastEventSummary: Sendable, Codable, Equatable {
    public let eventID: String
    public let epoch: Int
    public let seq: Int
    public let type: String
    public let severity: String
    public let createdAt: Date
}

public struct RunStatusSnapshot: Identifiable, Sendable, Codable, Equatable {
    public var id: String { runID }
    public let runID: String
    public let projectID: String
    public let projectName: String

    // V2 fixture compatibility only. Real V3 truth lives in directorTruth when present.
    public let executionStatus: ExecutionStatus
    public let directorTruth: DirectorTaskTruth?

    public let runtimeHealth: RuntimeHealth
    public let runtimePhase: RuntimePhase
    public let stage: StageSnapshot?
    public let currentOperation: OperationSnapshot?
    public let elapsedMS: Int64
    public let startedAt: Date
    public let endedAt: Date?
    public let heartbeats: HeartbeatSnapshot
    public let tests: TestSummary
    public let checkpoint: CheckpointSummary
    public let bundle: BundleSummary
    public let presentationStatus: PresentationStatus
    public let lastEvent: LastEventSummary?
    public let updatedAt: Date

    @available(*, deprecated, renamed: "projectID")
    public var workspaceID: String { projectID }

    public var isTerminalObservation: Bool {
        directorTruth?.terminal ?? executionStatus.isTerminal
    }

    public var isActivePresentationCandidate: Bool {
        directorTruth?.isActivePresentationCandidate ?? executionStatus.isActivePresentationCandidate
    }

    public init(
        runID: String,
        projectID: String,
        projectName: String,
        executionStatus: ExecutionStatus,
        directorTruth: DirectorTaskTruth? = nil,
        runtimeHealth: RuntimeHealth,
        runtimePhase: RuntimePhase,
        stage: StageSnapshot?,
        currentOperation: OperationSnapshot?,
        elapsedMS: Int64,
        startedAt: Date,
        endedAt: Date?,
        heartbeats: HeartbeatSnapshot,
        tests: TestSummary,
        checkpoint: CheckpointSummary,
        bundle: BundleSummary,
        presentationStatus: PresentationStatus,
        lastEvent: LastEventSummary?,
        updatedAt: Date
    ) {
        self.runID = runID
        self.projectID = projectID
        self.projectName = projectName
        self.executionStatus = executionStatus
        self.directorTruth = directorTruth
        self.runtimeHealth = runtimeHealth
        self.runtimePhase = runtimePhase
        self.stage = stage
        self.currentOperation = currentOperation
        self.elapsedMS = elapsedMS
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.heartbeats = heartbeats
        self.tests = tests
        self.checkpoint = checkpoint
        self.bundle = bundle
        self.presentationStatus = presentationStatus
        self.lastEvent = lastEvent
        self.updatedAt = updatedAt
    }
}

public struct ObserverSnapshot: Sendable, Codable, Equatable {
    public let connectionState: ConnectionState
    public let authoritativeFocusRunID: String?
    public let runs: [RunStatusSnapshot]
    public let observedAt: Date
    public let lastSyncAt: Date
    public let provenance: SnapshotProvenance
}

public struct TimelineEventFixture: Identifiable, Sendable, Equatable {
    public let id: String
    public let epoch: Int
    public let seq: Int
    public let type: String
    public let message: String
}
