import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

public struct VCWObserverSnapshotDTO: Codable, Sendable, Equatable {
    public let contractVersion: String
    public let sourceInstanceID: String
    public let snapshotRevision: String
    public let observedAt: Double
    public let authoritativeFocusTaskID: String?
    public let projects: [Project]
    public let sessions: [Session]
    public let heartbeats: [Heartbeat]
    public let effects: [Effect]
    public let events: [Event]
    public let eventCursor: Int64
    public let availability: Availability

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case sourceInstanceID = "source_instance_id"
        case snapshotRevision = "snapshot_revision"
        case observedAt = "observed_at"
        case authoritativeFocusTaskID = "authoritative_focus_task_id"
        case projects, sessions, heartbeats, effects, events
        case eventCursor = "event_cursor"
        case availability
    }

    public struct Project: Codable, Sendable, Equatable {
        public let projectID: String
        public let displayName: String?
        enum CodingKeys: String, CodingKey {
            case projectID = "project_id"
            case displayName = "display_name"
        }
    }

    public struct Session: Codable, Sendable, Equatable {
        public let sessionID: String
        public let projectID: String?
        public let state: String
        public let stateClass: String
        public let createdAt: Double
        public let startedAt: Double?
        public let endedAt: Double?
        public let expiresAt: Double
        public let lastModelActivity: Double?
        public let lastExecutionActivity: Double?
        public let failureReason: String?
        public let queuePosition: Int?
        public let sessionAgeSeconds: Double
        public let executionElapsedSeconds: Double?
        public let remainingSeconds: Double
        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case projectID = "project_id"
            case state
            case stateClass = "state_class"
            case createdAt = "created_at"
            case startedAt = "started_at"
            case endedAt = "ended_at"
            case expiresAt = "expires_at"
            case lastModelActivity = "last_model_activity"
            case lastExecutionActivity = "last_execution_activity"
            case failureReason = "failure_reason"
            case queuePosition = "queue_position"
            case sessionAgeSeconds = "session_age_seconds"
            case executionElapsedSeconds = "execution_elapsed_seconds"
            case remainingSeconds = "remaining_seconds"
        }
    }

    public struct Heartbeat: Codable, Sendable, Equatable {
        public let component: String
        public let status: String
        public let observedAt: Double
        public let ageSeconds: Double
        public let freshness: String
        public let detail: [String: JSONValue]
        enum CodingKeys: String, CodingKey {
            case component, status
            case observedAt = "observed_at"
            case ageSeconds = "age_seconds"
            case freshness, detail
        }
    }

    public struct Effect: Codable, Sendable, Equatable {
        public let effectID: String
        public let taskID: String
        public let projectID: String
        public let state: String
        public let stateKnown: Bool
        public let generation: Int
        public let createdAt: String
        public let updatedAt: String
        public let receipt: [String: JSONValue]?
        public let lastErrorCode: String?
        enum CodingKeys: String, CodingKey {
            case effectID = "effect_id"
            case taskID = "task_id"
            case projectID = "project_id"
            case state
            case stateKnown = "state_known"
            case generation
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case receipt
            case lastErrorCode = "last_error_code"
        }
    }

    public struct Event: Codable, Sendable, Equatable {
        public let sourceInstanceID: String
        public let eventID: Int64
        public let eventIdentity: String
        public let eventType: String
        public let createdAt: Double
        public let sessionID: String?
        public let projectID: String?
        public let source: String
        public let authoritative: Bool
        public let payload: [String: JSONValue]
        enum CodingKeys: String, CodingKey {
            case sourceInstanceID = "source_instance_id"
            case eventID = "event_id"
            case eventIdentity = "event_identity"
            case eventType = "event_type"
            case createdAt = "created_at"
            case sessionID = "session_id"
            case projectID = "project_id"
            case source, authoritative, payload
        }
    }

    public struct Availability: Codable, Sendable, Equatable {
        public let testsSummary: String
        public let checkpoint: String
        public let artifact: String
        public let presentation: String
        public let logs: String
        enum CodingKeys: String, CodingKey {
            case testsSummary = "tests_summary"
            case checkpoint, artifact, presentation, logs
        }
    }
}
