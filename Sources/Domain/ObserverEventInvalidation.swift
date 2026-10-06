import Foundation

public enum ObserverEventInvalidationReason: String, Sendable, Equatable {
    case projectChanged = "PROJECT_CHANGED"
    case sourceChanged = "SOURCE_CHANGED"
    case cursorAdvanced = "CURSOR_ADVANCED"
    case eventsObserved = "EVENTS_OBSERVED"
    case cursorRegressed = "CURSOR_REGRESSED"
    case cursorInvalid = "CURSOR_INVALID"
}

public enum ObserverEventCursorDecision: Sendable, Equatable {
    case baselineMissing
    case unchanged
    case invalidate(ObserverEventInvalidationReason)
}

public struct ObserverEventCursorCheckpoint: Sendable, Equatable {
    public let projectID: String
    public let sourceInstanceID: String
    public let cursor: Int
}

public struct ObserverEventCursorStore: Sendable, Equatable {
    public private(set) var checkpoint: ObserverEventCursorCheckpoint?

    public init(checkpoint: ObserverEventCursorCheckpoint? = nil) {
        self.checkpoint = checkpoint
    }

    public mutating func reset() {
        checkpoint = nil
    }

    @discardableResult
    public mutating func seed(projectID: String, sourceInstanceID: String, cursor: Int) -> Bool {
        guard !projectID.isEmpty, !sourceInstanceID.isEmpty, cursor >= 0 else {
            checkpoint = nil
            return false
        }
        checkpoint = .init(projectID: projectID, sourceInstanceID: sourceInstanceID, cursor: cursor)
        return true
    }

    public func afterID(for projectID: String) -> Int? {
        guard let checkpoint, checkpoint.projectID == projectID else { return nil }
        return checkpoint.cursor
    }

    public func observe(
        projectID: String,
        sourceInstanceID: String,
        eventCursor: Int,
        eventCount: Int
    ) -> ObserverEventCursorDecision {
        guard let checkpoint else { return .baselineMissing }
        guard eventCursor >= 0 else { return .invalidate(.cursorInvalid) }
        guard checkpoint.projectID == projectID else { return .invalidate(.projectChanged) }
        guard checkpoint.sourceInstanceID == sourceInstanceID else { return .invalidate(.sourceChanged) }
        if eventCursor < checkpoint.cursor { return .invalidate(.cursorRegressed) }
        if eventCursor > checkpoint.cursor {
            return .invalidate(eventCount > 0 ? .eventsObserved : .cursorAdvanced)
        }
        if eventCount > 0 { return .invalidate(.eventsObserved) }
        return .unchanged
    }
}
