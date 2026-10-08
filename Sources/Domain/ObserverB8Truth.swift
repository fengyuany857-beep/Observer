import Foundation

public enum ObserverB8Contract {
    public static let freezeID = "OBSERVER-BACKEND-FREEZE-20261007-R1"
    public static let transport = "observer.transport.v1"
    public static let readPlane = "observer.read-plane.v1"
    public static let snapshot = "observer.snapshot.v1"
    public static let authority = "observer.authority.v1"
    public static let jobs = "observer.jobs.v1"
    public static let operations = "observer.operations.v1"
    public static let readTokenPrefix = "obsr_"

    public static let hardTTLSeconds = 1500
    public static let closeReminderSeconds = 90
    public static let closeRequiredElapsedSeconds = 1410
}

public enum ObserverB8ReadIntent: String, Sendable, Codable {
    case poll = "POLL"
    case manualRefresh = "MANUAL_REFRESH"
    case reconnectBaseline = "RECONNECT_BASELINE"
}

public enum ObserverB8Freshness: String, Sendable, Codable {
    case live = "LIVE"
    case stale = "STALE"
    case cached = "CACHED"
    case offline = "OFFLINE"
    case unknown = "UNKNOWN"
}

public struct ObserverB8ReadIdentity: Sendable, Equatable {
    public let sourceInstanceID: String
    public let snapshotRevision: String
    public let eventCursor: Int
    public let observedAt: TimeInterval
}

public struct ObserverB8SessionAuthority: Sendable, Codable, Equatable {
    public let origin: String?
    public let approvalID: String?
    public let requestedScope: String?
    public let actionClass: String?
    public let effectClass: String?
    public let credentialState: String
    public let credentialRevokedAt: TimeInterval?
    public let credentialRevocationReason: String?

    enum CodingKeys: String, CodingKey {
        case origin
        case approvalID = "approval_id"
        case requestedScope = "requested_scope"
        case actionClass = "action_class"
        case effectClass = "effect_class"
        case credentialState = "credential_state"
        case credentialRevokedAt = "credential_revoked_at"
        case credentialRevocationReason = "credential_revocation_reason"
    }
}

public struct ObserverB8SessionDeadline: Sendable, Codable, Equatable {
    public let phase: String
    public let hardTTLSeconds: Int
    public let closeReminderSeconds: Int
    public let closeRequiredAt: TimeInterval
    public let expiresAt: TimeInterval
    public let elapsedSeconds: TimeInterval
    public let remainingSeconds: TimeInterval
    public let closeRequired: Bool

    enum CodingKeys: String, CodingKey {
        case phase
        case hardTTLSeconds = "hard_ttl_seconds"
        case closeReminderSeconds = "close_reminder_seconds"
        case closeRequiredAt = "close_required_at"
        case expiresAt = "expires_at"
        case elapsedSeconds = "elapsed_seconds"
        case remainingSeconds = "remaining_seconds"
        case closeRequired = "close_required"
    }

    public var matchesFrozenConstants: Bool {
        hardTTLSeconds == ObserverB8Contract.hardTTLSeconds
            && closeReminderSeconds == ObserverB8Contract.closeReminderSeconds
    }
}

public struct ObserverB8SessionTruth: Sendable, Codable, Equatable, Identifiable {
    public var id: String { sessionID }

    public let sessionID: String
    public let projectID: String
    public let state: String
    public let stateClass: String
    public let createdAt: TimeInterval
    public let expiresAt: TimeInterval
    public let startedAt: TimeInterval?
    public let endedAt: TimeInterval?
    public let lastModelActivity: TimeInterval?
    public let lastExecutionActivity: TimeInterval?
    public let failureReason: String?
    public let queuePosition: Int?
    public let sessionAgeSeconds: TimeInterval
    public let executionElapsedSeconds: TimeInterval?
    public let remainingSeconds: TimeInterval
    public let authority: ObserverB8SessionAuthority
    public let deadline: ObserverB8SessionDeadline

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case projectID = "project_id"
        case state
        case stateClass = "state_class"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case lastModelActivity = "last_model_activity"
        case lastExecutionActivity = "last_execution_activity"
        case failureReason = "failure_reason"
        case queuePosition = "queue_position"
        case sessionAgeSeconds = "session_age_seconds"
        case executionElapsedSeconds = "execution_elapsed_seconds"
        case remainingSeconds = "remaining_seconds"
        case authority
        case deadline
    }
}

public struct ObserverB8ApprovalTruth: Sendable, Codable, Equatable, Identifiable {
    public var id: String { approvalID }

    public let approvalID: String
    public let projectID: String
    public let requesterPrincipal: String
    public let requestedScope: String
    public let actionClass: String
    public let effectClass: String
    public let state: String
    public let stateVersion: Int
    public let createdAt: TimeInterval
    public let expiresAt: TimeInterval
    public let decidedAt: TimeInterval?
    public let consumedSessionID: String?
    public let consumedAt: TimeInterval?
    public let reason: String?
    public let authority: String

    enum CodingKeys: String, CodingKey {
        case approvalID = "approval_id"
        case projectID = "project_id"
        case requesterPrincipal = "requester_principal"
        case requestedScope = "requested_scope"
        case actionClass = "action_class"
        case effectClass = "effect_class"
        case state
        case stateVersion = "state_version"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case decidedAt = "decided_at"
        case consumedSessionID = "consumed_session_id"
        case consumedAt = "consumed_at"
        case reason
        case authority
    }
}

public struct ObserverB8LifecycleTruth: Sendable, Codable, Equatable, Identifiable {
    public var id: String { operationID }

    public let operationID: String
    public let sessionID: String
    public let projectID: String
    public let action: String
    public let state: String
    public let requestedAt: TimeInterval
    public let updatedAt: TimeInterval
    public let completedAt: TimeInterval?
    public let reason: String
    public let finalSessionState: String?
    public let errorCode: String?
    public let authority: String

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case sessionID = "session_id"
        case projectID = "project_id"
        case action
        case state
        case requestedAt = "requested_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case reason
        case finalSessionState = "final_session_state"
        case errorCode = "error_code"
        case authority
    }
}

public struct ObserverB8EffectTruth: Sendable, Codable, Equatable, Identifiable {
    public var id: String { effectID }

    public let effectID: String
    public let taskID: String
    public let projectID: String
    public let state: String
    public let stateKnown: Bool
    public let generation: Int
    public let lastErrorCode: String?
    public let createdAtRaw: String
    public let updatedAtRaw: String

    enum CodingKeys: String, CodingKey {
        case effectID = "effect_id"
        case taskID = "task_id"
        case projectID = "project_id"
        case state
        case stateKnown = "state_known"
        case generation
        case lastErrorCode = "last_error_code"
        case createdAtRaw = "created_at"
        case updatedAtRaw = "updated_at"
    }

    public var needsAttention: Bool {
        !stateKnown || [
            "DISPATCHING", "OUTCOME_UNKNOWN", "RECONCILING", "RECOVERY_BLOCKED"
        ].contains(state) || lastErrorCode != nil
    }
}

public struct ObserverB8JobTruth: Sendable, Codable, Equatable, Identifiable {
    public var id: String { jobID }

    public let jobID: String
    public let sessionID: String
    public let projectID: String
    public let gatewayState: String
    public let stateClass: String
    public let heavy: Bool
    public let createdAt: TimeInterval
    public let updatedAt: TimeInterval
    public let authority: String
    public let freshness: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case sessionID = "session_id"
        case projectID = "project_id"
        case gatewayState = "gateway_state"
        case stateClass = "state_class"
        case heavy
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case authority
        case freshness
    }

    public var isLastObservedActive: Bool {
        stateClass == "LAST_OBSERVED_ACTIVE"
    }
}

public struct ObserverB8CurrentOperationTruth: Sendable, Codable, Equatable, Identifiable {
    public var id: String { operationID }

    public let operationID: String
    public let sessionID: String
    public let projectID: String
    public let kind: String
    public let name: String
    public let startedAt: TimeInterval
    public let currentness: String
    public let authority: String
    public let freshness: String

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case sessionID = "session_id"
        case projectID = "project_id"
        case kind
        case name
        case startedAt = "started_at"
        case currentness
        case authority
        case freshness
    }

    public var matchesFrozenCurrentness: Bool {
        currentness == "CURRENT"
            && authority == "GATEWAY_IN_FLIGHT_CALL"
            && freshness == "CURRENT_PROCESS"
    }
}

public struct ObserverB8BackendTruth: Sendable, Equatable {
    public let acceptedGeneration: Int64
    public let freshness: ObserverB8Freshness
    public let transportLive: Bool
    public let identity: ObserverB8ReadIdentity
    public let sessions: [ObserverB8SessionTruth]
    public let jobs: [ObserverB8JobTruth]
    public let effects: [ObserverB8EffectTruth]
    public let approvals: [ObserverB8ApprovalTruth]
    public let lifecycleOperations: [ObserverB8LifecycleTruth]
    public let currentOperationsBySession: [String: ObserverB8CurrentOperationTruth]

    public func currentOperation(for sessionID: String) -> ObserverB8CurrentOperationTruth? {
        guard transportLive else { return nil }
        return currentOperationsBySession[sessionID]
    }

    public func invalidated(
        generation: Int64,
        freshness: ObserverB8Freshness
    ) -> ObserverB8BackendTruth {
        ObserverB8BackendTruth(
            acceptedGeneration: generation,
            freshness: freshness,
            transportLive: false,
            identity: identity,
            sessions: sessions,
            jobs: jobs,
            effects: effects,
            approvals: approvals,
            lifecycleOperations: lifecycleOperations,
            currentOperationsBySession: [:]
        )
    }
}

public enum ObserverB8LoadDisposition: String, Sendable, Equatable {
    case accepted = "ACCEPTED"
    case notModified = "NOT_MODIFIED"
    case superseded = "SUPERSEDED"
    case requiresReconnectBaseline = "REQUIRES_RECONNECT_BASELINE"
    case transportFailure = "TRANSPORT_FAILURE"
}

public struct ObserverB8LoadResult: Sendable, Equatable {
    public let disposition: ObserverB8LoadDisposition
    public let envelope: ObserverDataEnvelope?
    public let requiresFullSnapshot: Bool

    public init(
        disposition: ObserverB8LoadDisposition,
        envelope: ObserverDataEnvelope?,
        requiresFullSnapshot: Bool = false
    ) {
        self.disposition = disposition
        self.envelope = envelope
        self.requiresFullSnapshot = requiresFullSnapshot
    }
}


public struct ObserverB8EventPage: Sendable, Equatable {
    public let sourceInstanceID: String
    public let projectID: String
    public let eventCursor: Int
    public let eventCount: Int
    public let generation: Int64
}
