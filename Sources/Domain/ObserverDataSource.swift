import Foundation

public struct ObserverTransportMetadata: Sendable, Equatable {
    public let transportContractVersion: String
    public let snapshotContractVersion: String
    public let sourceInstanceID: String
    public let snapshotRevision: String
    public let eventCursor: Int
    public let availability: [String: String]
    public let rawSessionStates: [String: String]

    public init(
        transportContractVersion: String,
        snapshotContractVersion: String,
        sourceInstanceID: String,
        snapshotRevision: String,
        eventCursor: Int,
        availability: [String: String],
        rawSessionStates: [String: String]
    ) {
        self.transportContractVersion = transportContractVersion
        self.snapshotContractVersion = snapshotContractVersion
        self.sourceInstanceID = sourceInstanceID
        self.snapshotRevision = snapshotRevision
        self.eventCursor = eventCursor
        self.availability = availability
        self.rawSessionStates = rawSessionStates
    }
}

public struct ObserverDataEnvelope: Sendable, Equatable {
    public let snapshot: ObserverSnapshot
    public let preferredDetailRunID: String?
    public let systemHealth: SystemHealthSnapshot?
    public let transportMetadata: ObserverTransportMetadata?

    public init(
        snapshot: ObserverSnapshot,
        preferredDetailRunID: String? = nil,
        systemHealth: SystemHealthSnapshot? = nil,
        transportMetadata: ObserverTransportMetadata? = nil
    ) {
        self.snapshot = snapshot
        self.preferredDetailRunID = preferredDetailRunID
        self.systemHealth = systemHealth
        self.transportMetadata = transportMetadata
    }
}

public protocol ObserverDataSource: Sendable {
    func load() async throws -> ObserverDataEnvelope
}