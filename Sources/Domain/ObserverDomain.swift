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
    public let workspaceID: String
    public let projectName: String
    public let executionStatus: ExecutionStatus
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
