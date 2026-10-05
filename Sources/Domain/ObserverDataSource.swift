import Foundation

public struct ObserverDataEnvelope: Sendable, Equatable {
    public let snapshot: ObserverSnapshot
    public let preferredDetailRunID: String?

    public init(snapshot: ObserverSnapshot, preferredDetailRunID: String? = nil) {
        self.snapshot = snapshot
        self.preferredDetailRunID = preferredDetailRunID
    }
}

public protocol ObserverDataSource: Sendable {
    func load() async throws -> ObserverDataEnvelope
}
