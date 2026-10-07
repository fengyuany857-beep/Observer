import Foundation

public enum ObserverB8ReadError: Error, Sendable, Equatable {
    case invalidResponse
    case contractMismatch(expected: String, actual: String?)
    case generationMismatch(expected: Int64, actual: String?)
    case intentMismatch(expected: ObserverB8ReadIntent, actual: String?)
    case identityMismatch
    case sourceChanged
    case cursorRegressed
    case projectMismatch
    case unavailable(String)
    case schemaDecodeFailed
    case transport(ObserverTransportError)
}

public actor ObserverB8LiveDataSource {
    private let configuration: ObserverTransportConfiguration
    private let client: any ObserverHTTPClient

    private var latestIssuedGeneration: Int64 = 0
    private var acceptedGeneration: Int64 = 0
    private var acceptedIdentity: ObserverB8ReadIdentity?
    private var lastEnvelope: ObserverDataEnvelope?
    private var lastETag: String?

    public init(
        configuration: ObserverTransportConfiguration,
        client: (any ObserverHTTPClient)? = nil
    ) {
        self.configuration = configuration
        self.client = client ?? URLSessionObserverHTTPClient(configuration: configuration)
    }

    public func cachedEnvelope() -> ObserverDataEnvelope? {
        lastEnvelope
    }

    public func load(intent: ObserverB8ReadIntent) async throws -> ObserverB8LoadResult {
        let generation = issueGeneration()
        var activeGeneration = generation

        do {
            let response = try await client.get(
                snapshotRequest(generation: generation, intent: intent)
            )

            guard generation == latestIssuedGeneration else {
                return ObserverB8LoadResult(
                    disposition: .superseded,
                    envelope: lastEnvelope
                )
            }

            try validateCommonHeaders(
                response,
                generation: generation,
                intent: intent
            )

            if response.statusCode == 304 {
                return try await acceptNotModified(
                    response,
                    generation: generation,
                    intent: intent
                )
            }

            guard response.statusCode == 200 else {
                throw ObserverB8ReadError.transport(mapHTTPError(response))
            }

            let payload: B8SnapshotDTO
            do {
                payload = try JSONDecoder().decode(B8SnapshotDTO.self, from: response.data)
            } catch {
                throw ObserverB8ReadError.schemaDecodeFailed
            }

            guard payload.contractVersion == ObserverB8Contract.snapshot else {
                throw ObserverB8ReadError.contractMismatch(
                    expected: ObserverB8Contract.snapshot,
                    actual: payload.contractVersion
                )
            }
            guard payload.authority.contractVersion == ObserverB8Contract.authority else {
                throw ObserverB8ReadError.contractMismatch(
                    expected: ObserverB8Contract.authority,
                    actual: payload.authority.contractVersion
                )
            }

            let identity = payload.identity
            try validatePayloadIdentity(identity, response: response)

            guard payload.projects.contains(where: {
                $0.projectID == configuration.projectID
            }) else {
                throw ObserverB8ReadError.projectMismatch
            }
            guard payload.sessions.allSatisfy({
                $0.projectID == configuration.projectID
                    && $0.deadline.matchesFrozenConstants
            }) else {
                throw ObserverB8ReadError.contractMismatch(
                    expected: "PROJECT_SCOPED_SESSION_WITH_1500_90_DEADLINE",
                    actual: nil
                )
            }

            if intent != .reconnectBaseline, let previous = acceptedIdentity {
                if identity.sourceInstanceID != previous.sourceInstanceID {
                    return invalidateForReconnect()
                }
                if identity.eventCursor < previous.eventCursor {
                    return invalidateForReconnect()
                }
            }

            let operationGeneration = issueGeneration()
            activeGeneration = operationGeneration
            let operations = try await fetchOperations(
                generation: operationGeneration,
                intent: intent,
                expectedSourceInstanceID: identity.sourceInstanceID
            )
            guard operationGeneration == latestIssuedGeneration else {
                return ObserverB8LoadResult(
                    disposition: .superseded,
                    envelope: lastEnvelope
                )
            }

            let jobGeneration = issueGeneration()
            activeGeneration = jobGeneration
            let jobs = try await fetchJobs(
                generation: jobGeneration,
                intent: intent,
                expectedSourceInstanceID: identity.sourceInstanceID
            )
            guard jobGeneration == latestIssuedGeneration else {
                return ObserverB8LoadResult(
                    disposition: .superseded,
                    envelope: lastEnvelope
                )
            }

            let envelope = payload.makeEnvelope(
                projectID: configuration.projectID,
                generation: jobGeneration,
                jobs: jobs,
                operations: operations
            )
            acceptedGeneration = jobGeneration
            acceptedIdentity = identity
            lastEnvelope = envelope
            lastETag = response.header("ETag") ?? "\"\(identity.snapshotRevision)\""

            return ObserverB8LoadResult(
                disposition: .accepted,
                envelope: envelope
            )
        } catch let error as ObserverB8ReadError {
            if activeGeneration != latestIssuedGeneration {
                return ObserverB8LoadResult(
                    disposition: .superseded,
                    envelope: lastEnvelope
                )
            }
            switch error {
            case .sourceChanged, .cursorRegressed, .identityMismatch:
                return invalidateForReconnect()
            case .transport(let transport):
                return transportFailure(transport)
            case .invalidResponse,
                 .contractMismatch,
                 .generationMismatch,
                 .intentMismatch,
                 .projectMismatch,
                 .unavailable,
                 .schemaDecodeFailed:
                throw error
            }
        } catch let error as ObserverTransportError {
            if activeGeneration != latestIssuedGeneration {
                return ObserverB8LoadResult(
                    disposition: .superseded,
                    envelope: lastEnvelope
                )
            }
            return transportFailure(error)
        } catch is URLError {
            if activeGeneration != latestIssuedGeneration {
                return ObserverB8LoadResult(
                    disposition: .superseded,
                    envelope: lastEnvelope
                )
            }
            return transportFailure(.httpStatus(503, "NETWORK_UNREACHABLE"))
        }
    }

    private func acceptNotModified(
        _ response: ObserverHTTPResponse,
        generation: Int64,
        intent: ObserverB8ReadIntent
    ) async throws -> ObserverB8LoadResult {
        guard intent != .reconnectBaseline,
              let previousIdentity = acceptedIdentity,
              let previous = lastEnvelope else {
            return invalidateForReconnect()
        }

        let headerIdentity = try identityFromHeaders(response)
        guard headerIdentity.sourceInstanceID == previousIdentity.sourceInstanceID,
              headerIdentity.snapshotRevision == previousIdentity.snapshotRevision else {
            return invalidateForReconnect()
        }
        guard headerIdentity.eventCursor >= previousIdentity.eventCursor else {
            return invalidateForReconnect()
        }

        var activeGeneration = generation
        do {
            let operationGeneration = issueGeneration()
            activeGeneration = operationGeneration
            let operations = try await fetchOperations(
                generation: operationGeneration,
                intent: intent,
                expectedSourceInstanceID: previousIdentity.sourceInstanceID
            )
            guard operationGeneration == latestIssuedGeneration else {
                return ObserverB8LoadResult(disposition: .superseded, envelope: lastEnvelope)
            }

            let jobGeneration = issueGeneration()
            activeGeneration = jobGeneration
            let jobs = try await fetchJobs(
                generation: jobGeneration,
                intent: intent,
                expectedSourceInstanceID: previousIdentity.sourceInstanceID
            )
            guard jobGeneration == latestIssuedGeneration else {
                return ObserverB8LoadResult(disposition: .superseded, envelope: lastEnvelope)
            }

            let identity = ObserverB8ReadIdentity(
                sourceInstanceID: previousIdentity.sourceInstanceID,
                snapshotRevision: previousIdentity.snapshotRevision,
                eventCursor: max(previousIdentity.eventCursor, headerIdentity.eventCursor),
                observedAt: max(previousIdentity.observedAt, headerIdentity.observedAt)
            )
            let envelope = refreshedEnvelope(
                previous,
                generation: jobGeneration,
                identity: identity,
                jobs: jobs,
                operations: operations
            )
            acceptedGeneration = jobGeneration
            acceptedIdentity = identity
            lastEnvelope = envelope
            return ObserverB8LoadResult(disposition: .notModified, envelope: envelope)
        } catch let error as ObserverB8ReadError {
            if activeGeneration != latestIssuedGeneration {
                return ObserverB8LoadResult(disposition: .superseded, envelope: lastEnvelope)
            }
            switch error {
            case .sourceChanged, .cursorRegressed, .identityMismatch:
                return invalidateForReconnect()
            case .transport(let transport):
                return transportFailure(transport)
            case .invalidResponse, .contractMismatch, .generationMismatch, .intentMismatch,
                 .projectMismatch, .unavailable, .schemaDecodeFailed:
                throw error
            }
        } catch let error as ObserverTransportError {
            if activeGeneration != latestIssuedGeneration {
                return ObserverB8LoadResult(disposition: .superseded, envelope: lastEnvelope)
            }
            return transportFailure(error)
        } catch is URLError {
            if activeGeneration != latestIssuedGeneration {
                return ObserverB8LoadResult(disposition: .superseded, envelope: lastEnvelope)
            }
            return transportFailure(.httpStatus(503, "NETWORK_UNREACHABLE"))
        }
    }

    public func refreshCurrentOperations(
        intent: ObserverB8ReadIntent = .poll
    ) async throws -> ObserverB8LoadResult {
        guard let identity = acceptedIdentity, let previous = lastEnvelope else {
            return invalidateForReconnect()
        }
        guard previous.snapshot.provenance == .live,
              previous.backendTruth?.transportLive == true else {
            return ObserverB8LoadResult(
                disposition: .requiresReconnectBaseline,
                envelope: previous,
                requiresFullSnapshot: true
            )
        }
        let generation = issueGeneration()
        do {
            let operations = try await fetchOperations(
                generation: generation,
                intent: intent,
                expectedSourceInstanceID: identity.sourceInstanceID
            )
            guard generation == latestIssuedGeneration else {
                return ObserverB8LoadResult(disposition: .superseded, envelope: lastEnvelope)
            }
            let envelope = refreshedEnvelope(
                previous, generation: generation, identity: identity, operations: operations
            )
            acceptedGeneration = generation
            lastEnvelope = envelope
            return ObserverB8LoadResult(disposition: .accepted, envelope: envelope)
        } catch let error as ObserverB8ReadError {
            if generation != latestIssuedGeneration {
                return ObserverB8LoadResult(disposition: .superseded, envelope: lastEnvelope)
            }
            switch error {
            case .sourceChanged, .cursorRegressed, .identityMismatch:
                return invalidateForReconnect()
            case .transport(let transport):
                return transportFailure(transport)
            case .invalidResponse, .contractMismatch, .generationMismatch, .intentMismatch,
                 .projectMismatch, .unavailable, .schemaDecodeFailed:
                throw error
            }
        } catch is URLError {
            return transportFailure(.httpStatus(503, "NETWORK_UNREACHABLE"))
        }
    }

    public func pollEvents(
        afterID: Int,
        intent: ObserverB8ReadIntent = .poll
    ) async throws -> ObserverB8EventPage {
        guard afterID >= 0 else { throw ObserverB8ReadError.identityMismatch }
        let generation = issueGeneration()
        let response: ObserverHTTPResponse
        do {
            response = try await client.get(
                eventsRequest(afterID: afterID, generation: generation, intent: intent)
            )
        } catch is URLError {
            _ = transportFailure(.httpStatus(503, "NETWORK_UNREACHABLE"))
            throw ObserverB8ReadError.transport(.httpStatus(503, "NETWORK_UNREACHABLE"))
        }
        guard generation == latestIssuedGeneration else {
            throw ObserverB8ReadError.invalidResponse
        }
        try validateCommonHeaders(response, generation: generation, intent: intent)
        guard response.statusCode == 200 else {
            let transport = mapHTTPError(response)
            _ = transportFailure(transport)
            throw ObserverB8ReadError.transport(transport)
        }
        let payload: B8EventsDTO
        do {
            payload = try JSONDecoder().decode(B8EventsDTO.self, from: response.data)
        } catch {
            throw ObserverB8ReadError.schemaDecodeFailed
        }
        guard payload.contractVersion == "observer.events.v1",
              payload.projectID == configuration.projectID else {
            throw ObserverB8ReadError.projectMismatch
        }
        return ObserverB8EventPage(
            sourceInstanceID: payload.sourceInstanceID,
            projectID: payload.projectID,
            eventCursor: payload.eventCursor,
            eventCount: payload.events.count,
            generation: generation
        )
    }

    private func fetchJobs(
        generation: Int64,
        intent: ObserverB8ReadIntent,
        expectedSourceInstanceID: String
    ) async throws -> [ObserverB8JobTruth] {
        let response = try await client.get(
            jobsRequest(generation: generation, intent: intent)
        )
        guard generation == latestIssuedGeneration else { return [] }

        try validateCommonHeaders(
            response,
            generation: generation,
            intent: intent
        )
        guard response.statusCode == 200 else {
            throw ObserverB8ReadError.transport(mapHTTPError(response))
        }

        let payload: B8JobsDTO
        do {
            payload = try JSONDecoder().decode(B8JobsDTO.self, from: response.data)
        } catch {
            throw ObserverB8ReadError.schemaDecodeFailed
        }

        guard payload.contractVersion == ObserverB8Contract.jobs else {
            throw ObserverB8ReadError.contractMismatch(
                expected: ObserverB8Contract.jobs,
                actual: payload.contractVersion
            )
        }
        guard payload.projectID == configuration.projectID, payload.sessionID == nil else {
            throw ObserverB8ReadError.projectMismatch
        }
        guard payload.sourceInstanceID == expectedSourceInstanceID,
              response.header("X-Observer-Source-Instance") == expectedSourceInstanceID else {
            throw ObserverB8ReadError.sourceChanged
        }
        guard payload.availability == "AVAILABLE" else {
            throw ObserverB8ReadError.unavailable(payload.availability)
        }
        let allowedClasses = Set(["LAST_OBSERVED_ACTIVE", "TERMINAL_CONFIRMED", "UNKNOWN"])
        guard payload.jobs.allSatisfy({
            $0.projectID == configuration.projectID && allowedClasses.contains($0.stateClass)
        }) else {
            throw ObserverB8ReadError.contractMismatch(
                expected: "PROJECT_SCOPED_JOB_WITH_FROZEN_STATE_CLASS",
                actual: nil
            )
        }
        return payload.jobs.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.jobID < rhs.jobID
        }
    }

    private func fetchOperations(
        generation: Int64,
        intent: ObserverB8ReadIntent,
        expectedSourceInstanceID: String
    ) async throws -> [String: ObserverB8CurrentOperationTruth] {
        let response = try await client.get(
            operationsRequest(generation: generation, intent: intent)
        )
        guard generation == latestIssuedGeneration else { return [:] }

        try validateCommonHeaders(
            response,
            generation: generation,
            intent: intent
        )
        guard response.statusCode == 200 else {
            throw ObserverB8ReadError.transport(mapHTTPError(response))
        }

        let payload: B8OperationsDTO
        do {
            payload = try JSONDecoder().decode(B8OperationsDTO.self, from: response.data)
        } catch {
            throw ObserverB8ReadError.schemaDecodeFailed
        }

        guard payload.contractVersion == ObserverB8Contract.operations else {
            throw ObserverB8ReadError.contractMismatch(
                expected: ObserverB8Contract.operations,
                actual: payload.contractVersion
            )
        }
        guard payload.projectID == configuration.projectID else {
            throw ObserverB8ReadError.projectMismatch
        }
        guard payload.sourceInstanceID == expectedSourceInstanceID,
              response.header("X-Observer-Source-Instance") == expectedSourceInstanceID else {
            throw ObserverB8ReadError.sourceChanged
        }
        guard payload.availability == "AVAILABLE" else {
            throw ObserverB8ReadError.unavailable(payload.availability)
        }

        var bySession: [String: ObserverB8CurrentOperationTruth] = [:]
        for operation in payload.operations {
            guard operation.projectID == configuration.projectID,
                  operation.matchesFrozenCurrentness else {
                throw ObserverB8ReadError.contractMismatch(
                    expected: "CURRENT|GATEWAY_IN_FLIGHT_CALL|CURRENT_PROCESS",
                    actual: "\(operation.currentness)|\(operation.authority)|\(operation.freshness)"
                )
            }
            guard bySession[operation.sessionID] == nil else {
                throw ObserverB8ReadError.contractMismatch(
                    expected: "ONE_CURRENT_OPERATION_PER_SESSION",
                    actual: operation.sessionID
                )
            }
            bySession[operation.sessionID] = operation
        }
        return bySession
    }

    private func invalidateForReconnect() -> ObserverB8LoadResult {
        let stale = lastEnvelope.map {
            invalidatedEnvelope($0, freshness: .stale, connectionState: .reconnecting)
        }
        lastEnvelope = stale
        return ObserverB8LoadResult(
            disposition: .requiresReconnectBaseline,
            envelope: stale,
            requiresFullSnapshot: true
        )
    }

    private func transportFailure(
        _ error: ObserverTransportError
    ) -> ObserverB8LoadResult {
        let connection: ConnectionState
        switch error {
        case .authFailed:
            connection = .authFailed
        case .rateLimited:
            connection = .reconnecting
        default:
            connection = .serverUnreachable
        }
        let cached = lastEnvelope.map {
            invalidatedEnvelope($0, freshness: .offline, connectionState: connection)
        }
        lastEnvelope = cached
        return ObserverB8LoadResult(
            disposition: .transportFailure,
            envelope: cached
        )
    }

    private func invalidatedEnvelope(
        _ envelope: ObserverDataEnvelope,
        freshness: ObserverB8Freshness,
        connectionState: ConnectionState
    ) -> ObserverDataEnvelope {
        let old = envelope.snapshot
        let cleared = ObserverCurrentOperationOverlay.clearing(
            ObserverSnapshot(
                connectionState: connectionState,
                authoritativeFocusRunID: old.authoritativeFocusRunID,
                runs: old.runs,
                observedAt: Date(),
                lastSyncAt: old.lastSyncAt,
                provenance: .cached
            )
        )
        let health = envelope.systemHealth.map {
            SystemHealthSnapshot(
                components: $0.components,
                observedAt: $0.observedAt,
                provenance: .cached
            )
        }
        return ObserverDataEnvelope(
            snapshot: cleared,
            preferredDetailRunID: envelope.preferredDetailRunID,
            systemHealth: health,
            transportMetadata: envelope.transportMetadata,
            backendTruth: envelope.backendTruth?.invalidated(
                generation: acceptedGeneration,
                freshness: freshness
            )
        )
    }

    private func refreshedEnvelope(
        _ envelope: ObserverDataEnvelope,
        generation: Int64,
        identity: ObserverB8ReadIdentity,
        jobs: [ObserverB8JobTruth]? = nil,
        operations: [String: ObserverB8CurrentOperationTruth]
    ) -> ObserverDataEnvelope {
        let old = envelope.snapshot
        let liveBase = ObserverSnapshot(
            connectionState: .online,
            authoritativeFocusRunID: old.authoritativeFocusRunID,
            runs: old.runs,
            observedAt: Date(timeIntervalSince1970: identity.observedAt),
            lastSyncAt: Date(timeIntervalSince1970: identity.observedAt),
            provenance: .live
        )
        let overlay = ObserverCurrentOperationOverlay.applying(
            Dictionary(uniqueKeysWithValues: operations.values.map {
                (
                    $0.sessionID,
                    OperationSnapshot(
                        kind: $0.kind,
                        name: $0.name,
                        startedAt: Date(timeIntervalSince1970: $0.startedAt)
                    )
                )
            }),
            to: liveBase
        )

        let truth = envelope.backendTruth.map {
            ObserverB8BackendTruth(
                acceptedGeneration: generation,
                freshness: .live,
                transportLive: true,
                identity: identity,
                sessions: $0.sessions,
                jobs: jobs ?? $0.jobs,
                effects: $0.effects,
                approvals: $0.approvals,
                lifecycleOperations: $0.lifecycleOperations,
                currentOperationsBySession: operations
            )
        }

        let metadata = envelope.transportMetadata.map {
            ObserverTransportMetadata(
                transportContractVersion: $0.transportContractVersion,
                snapshotContractVersion: $0.snapshotContractVersion,
                sourceInstanceID: identity.sourceInstanceID,
                snapshotRevision: identity.snapshotRevision,
                eventCursor: identity.eventCursor,
                availability: $0.availability,
                rawSessionStates: $0.rawSessionStates
            )
        }

        return ObserverDataEnvelope(
            snapshot: overlay,
            preferredDetailRunID: envelope.preferredDetailRunID,
            systemHealth: envelope.systemHealth,
            transportMetadata: metadata,
            backendTruth: truth
        )
    }

    private func snapshotRequest(
        generation: Int64,
        intent: ObserverB8ReadIntent
    ) -> URLRequest {
        var components = URLComponents(
            url: configuration.baseURL
                .appendingPathComponent("observer")
                .appendingPathComponent("v1")
                .appendingPathComponent("snapshot"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "project_id", value: configuration.projectID)
        ]

        var request = URLRequest(url: components.url!)
        prepare(
            &request,
            generation: generation,
            intent: intent
        )
        if intent != .reconnectBaseline, let lastETag {
            request.setValue(lastETag, forHTTPHeaderField: "If-None-Match")
        }
        return request
    }

    private func jobsRequest(
        generation: Int64,
        intent: ObserverB8ReadIntent
    ) -> URLRequest {
        var components = URLComponents(
            url: configuration.baseURL
                .appendingPathComponent("observer")
                .appendingPathComponent("v1")
                .appendingPathComponent("projects")
                .appendingPathComponent(configuration.projectID)
                .appendingPathComponent("jobs"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "limit", value: "100")]
        var request = URLRequest(url: components.url!)
        prepare(&request, generation: generation, intent: intent)
        return request
    }

    private func operationsRequest(
        generation: Int64,
        intent: ObserverB8ReadIntent
    ) -> URLRequest {
        let url = configuration.baseURL
            .appendingPathComponent("observer")
            .appendingPathComponent("v1")
            .appendingPathComponent("projects")
            .appendingPathComponent(configuration.projectID)
            .appendingPathComponent("operations")
        var request = URLRequest(url: url)
        prepare(&request, generation: generation, intent: intent)
        return request
    }

    private func eventsRequest(
        afterID: Int,
        generation: Int64,
        intent: ObserverB8ReadIntent
    ) -> URLRequest {
        var components = URLComponents(
            url: configuration.baseURL
                .appendingPathComponent("observer")
                .appendingPathComponent("v1")
                .appendingPathComponent("projects")
                .appendingPathComponent(configuration.projectID)
                .appendingPathComponent("events"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "after_id", value: String(afterID)),
            URLQueryItem(name: "limit", value: "200"),
        ]
        var request = URLRequest(url: components.url!)
        prepare(&request, generation: generation, intent: intent)
        return request
    }

    private func issueGeneration() -> Int64 {
        latestIssuedGeneration += 1
        return latestIssuedGeneration
    }

    private func prepare(
        _ request: inout URLRequest,
        generation: Int64,
        intent: ObserverB8ReadIntent
    ) {
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = configuration.requestTimeout
        request.setValue(
            "Bearer \(configuration.bearerToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            String(generation),
            forHTTPHeaderField: "X-Observer-Request-Generation"
        )
        request.setValue(
            intent.rawValue,
            forHTTPHeaderField: "X-Observer-Read-Intent"
        )
    }

    private func validateCommonHeaders(
        _ response: ObserverHTTPResponse,
        generation: Int64,
        intent: ObserverB8ReadIntent
    ) throws {
        guard response.header("X-Observer-Transport") == ObserverB8Contract.transport else {
            throw ObserverB8ReadError.contractMismatch(
                expected: ObserverB8Contract.transport,
                actual: response.header("X-Observer-Transport")
            )
        }
        guard response.header("X-Observer-Read-Contract") == ObserverB8Contract.readPlane else {
            throw ObserverB8ReadError.contractMismatch(
                expected: ObserverB8Contract.readPlane,
                actual: response.header("X-Observer-Read-Contract")
            )
        }
        guard response.header("X-Observer-Request-Generation") == String(generation) else {
            throw ObserverB8ReadError.generationMismatch(
                expected: generation,
                actual: response.header("X-Observer-Request-Generation")
            )
        }
        guard response.header("X-Observer-Read-Intent") == intent.rawValue else {
            throw ObserverB8ReadError.intentMismatch(
                expected: intent,
                actual: response.header("X-Observer-Read-Intent")
            )
        }
    }

    private func identityFromHeaders(
        _ response: ObserverHTTPResponse
    ) throws -> ObserverB8ReadIdentity {
        guard let source = response.header("X-Observer-Source-Instance"),
              !source.isEmpty,
              let revision = response.header("X-Observer-Snapshot-Revision"),
              !revision.isEmpty,
              let cursorRaw = response.header("X-Observer-Event-Cursor"),
              let cursor = Int(cursorRaw),
              cursor >= 0,
              let observedRaw = response.header("X-Observer-Observed-At"),
              let observed = TimeInterval(observedRaw),
              observed >= 0 else {
            throw ObserverB8ReadError.identityMismatch
        }
        return ObserverB8ReadIdentity(
            sourceInstanceID: source,
            snapshotRevision: revision,
            eventCursor: cursor,
            observedAt: observed
        )
    }

    private func validatePayloadIdentity(
        _ identity: ObserverB8ReadIdentity,
        response: ObserverHTTPResponse
    ) throws {
        let header = try identityFromHeaders(response)
        guard header.sourceInstanceID == identity.sourceInstanceID,
              header.snapshotRevision == identity.snapshotRevision,
              header.eventCursor == identity.eventCursor,
              header.observedAt == identity.observedAt else {
            throw ObserverB8ReadError.identityMismatch
        }
    }

    private func mapHTTPError(_ response: ObserverHTTPResponse) -> ObserverTransportError {
        let code = (try? JSONDecoder().decode(
            B8TransportErrorEnvelope.self,
            from: response.data
        ))?.error.code
        switch response.statusCode {
        case 401: return .authFailed(code)
        case 403: return .forbidden(code)
        case 429: return .rateLimited
        default: return .httpStatus(response.statusCode, code)
        }
    }
}

private struct B8TransportErrorEnvelope: Decodable {
    struct ErrorBody: Decodable { let code: String }
    let error: ErrorBody
}

private struct B8ProjectDTO: Decodable {
    let projectID: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case displayName = "display_name"
    }
}

private struct B8HeartbeatDTO: Decodable {
    let component: String
    let status: String
    let observedAt: TimeInterval
    let ageSeconds: TimeInterval
    let freshness: String

    enum CodingKeys: String, CodingKey {
        case component
        case status
        case observedAt = "observed_at"
        case ageSeconds = "age_seconds"
        case freshness
    }
}

private struct B8AuthorityDTO: Decodable {
    let contractVersion: String
    let approvals: [ObserverB8ApprovalTruth]
    let lifecycleOperations: [ObserverB8LifecycleTruth]

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case approvals
        case lifecycleOperations = "lifecycle_operations"
    }
}

private struct B8SnapshotDTO: Decodable {
    let contractVersion: String
    let sourceInstanceID: String
    let snapshotRevision: String
    let observedAt: TimeInterval
    let authoritativeFocusTaskID: String?
    let projects: [B8ProjectDTO]
    let sessions: [ObserverB8SessionTruth]
    let heartbeats: [B8HeartbeatDTO]
    let effects: [ObserverB8EffectTruth]
    let eventCursor: Int
    let authority: B8AuthorityDTO
    let availability: [String: String]

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case sourceInstanceID = "source_instance_id"
        case snapshotRevision = "snapshot_revision"
        case observedAt = "observed_at"
        case authoritativeFocusTaskID = "authoritative_focus_task_id"
        case projects
        case sessions
        case heartbeats
        case effects
        case eventCursor = "event_cursor"
        case authority
        case availability
    }

    var identity: ObserverB8ReadIdentity {
        ObserverB8ReadIdentity(
            sourceInstanceID: sourceInstanceID,
            snapshotRevision: snapshotRevision,
            eventCursor: eventCursor,
            observedAt: observedAt
        )
    }

    func makeEnvelope(
        projectID: String,
        generation: Int64,
        jobs: [ObserverB8JobTruth],
        operations: [String: ObserverB8CurrentOperationTruth]
    ) -> ObserverDataEnvelope {
        let names = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.projectID, $0.displayName) }
        )
        let observedDate = Date(timeIntervalSince1970: observedAt)

        let runs = sessions
            .filter { $0.projectID == projectID }
            .map { session -> RunStatusSnapshot in
                let createdAt = Date(timeIntervalSince1970: session.createdAt)
                let startedAt = session.startedAt.map(Date.init(timeIntervalSince1970:))
                    ?? createdAt
                let endedAt = session.endedAt.map(Date.init(timeIntervalSince1970:))
                let updated = [
                    session.lastExecutionActivity,
                    session.lastModelActivity,
                    session.endedAt,
                    session.startedAt,
                    session.createdAt,
                ].compactMap { $0 }.max() ?? session.createdAt
                let operation = operations[session.sessionID].map {
                    OperationSnapshot(
                        kind: $0.kind,
                        name: $0.name,
                        startedAt: Date(timeIntervalSince1970: $0.startedAt)
                    )
                }

                return RunStatusSnapshot(
                    runID: session.sessionID,
                    projectID: session.projectID,
                    projectName: names[session.projectID] ?? session.projectID,
                    executionStatus: Self.executionStatus(for: session.state),
                    directorTruth: nil,
                    runtimeHealth: .unknown,
                    runtimePhase: .unknown,
                    stage: nil,
                    currentOperation: endedAt == nil ? operation : nil,
                    elapsedMS: Int64(max(0, session.executionElapsedSeconds ?? 0) * 1000),
                    startedAt: startedAt,
                    endedAt: endedAt,
                    heartbeats: HeartbeatSnapshot(
                        runLastSeen: nil,
                        toolLastSeen: nil,
                        relayLastSeen: nil
                    ),
                    tests: TestSummary(total: 0, completed: 0, passed: 0, failed: 0, skipped: 0),
                    checkpoint: CheckpointSummary(latestID: nil, status: nil, createdAt: nil),
                    bundle: BundleSummary(status: .unknown, id: nil),
                    presentationStatus: .unknown,
                    lastEvent: nil,
                    updatedAt: Date(timeIntervalSince1970: updated)
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }

        let focus = authoritativeFocusTaskID.flatMap { candidate in
            runs.contains(where: { $0.runID == candidate }) ? candidate : nil
        }
        let components = heartbeats.map {
            ComponentHealthSnapshot(
                component: $0.component,
                status: $0.status,
                observedAt: Date(timeIntervalSince1970: $0.observedAt),
                ageSeconds: $0.ageSeconds,
                freshness: $0.freshness
            )
        }.sorted { $0.component < $1.component }

        let truth = ObserverB8BackendTruth(
            acceptedGeneration: generation,
            freshness: .live,
            transportLive: true,
            identity: identity,
            sessions: sessions.filter { $0.projectID == projectID },
            jobs: jobs.filter { $0.projectID == projectID },
            effects: effects.filter { $0.projectID == projectID },
            approvals: authority.approvals.filter { $0.projectID == projectID },
            lifecycleOperations: authority.lifecycleOperations.filter { $0.projectID == projectID },
            currentOperationsBySession: operations
        )

        return ObserverDataEnvelope(
            snapshot: ObserverSnapshot(
                connectionState: .online,
                authoritativeFocusRunID: focus,
                runs: runs,
                observedAt: observedDate,
                lastSyncAt: observedDate,
                provenance: .live
            ),
            preferredDetailRunID: focus ?? runs.first?.runID,
            systemHealth: SystemHealthSnapshot(
                components: components,
                observedAt: observedDate,
                provenance: .live
            ),
            transportMetadata: ObserverTransportMetadata(
                transportContractVersion: ObserverB8Contract.transport,
                snapshotContractVersion: contractVersion,
                sourceInstanceID: sourceInstanceID,
                snapshotRevision: snapshotRevision,
                eventCursor: eventCursor,
                availability: availability,
                rawSessionStates: Dictionary(
                    uniqueKeysWithValues: sessions.map { ($0.sessionID, $0.state) }
                )
            ),
            backendTruth: truth
        )
    }

    private static func executionStatus(for state: String) -> ExecutionStatus {
        switch state {
        case "AUTHORIZED", "QUEUED": return .pending
        case "STARTING": return .starting
        case "RUNNING": return .running
        case "FINISHED": return .completed
        case "FAILED": return .failed
        case "STOPPED", "EXPIRED": return .aborted
        default: return .unknown
        }
    }
}

private struct B8JobsDTO: Decodable {
    let contractVersion: String
    let sourceInstanceID: String
    let projectID: String
    let sessionID: String?
    let availability: String
    let jobs: [ObserverB8JobTruth]

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case sourceInstanceID = "source_instance_id"
        case projectID = "project_id"
        case sessionID = "session_id"
        case availability
        case jobs
    }
}

private struct B8OperationsDTO: Decodable {
    let contractVersion: String
    let sourceInstanceID: String
    let authorityInstanceID: String?
    let projectID: String
    let sessionID: String?
    let availability: String
    let observedAt: TimeInterval
    let operations: [ObserverB8CurrentOperationTruth]

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case sourceInstanceID = "source_instance_id"
        case authorityInstanceID = "authority_instance_id"
        case projectID = "project_id"
        case sessionID = "session_id"
        case availability
        case observedAt = "observed_at"
        case operations
    }
}


private struct B8EventsDTO: Decodable {
    let contractVersion: String
    let sourceInstanceID: String
    let projectID: String
    let events: [B8EventIdentityDTO]
    let eventCursor: Int

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case sourceInstanceID = "source_instance_id"
        case projectID = "project_id"
        case events
        case eventCursor = "event_cursor"
    }
}

private struct B8EventIdentityDTO: Decodable {
    let eventID: Int
    enum CodingKeys: String, CodingKey { case eventID = "event_id" }
}
