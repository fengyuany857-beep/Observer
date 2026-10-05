import Foundation

public enum ObserverTransportError: Error, Sendable, Equatable {
    case invalidConfiguration(String)
    case invalidResponse
    case authFailed(String?)
    case forbidden(String?)
    case rateLimited
    case httpStatus(Int, String?)
    case contractMismatch(expected: String, actual: String?)
    case schemaDecodeFailed
}

public struct ObserverTransportConfiguration: Sendable {
    public let baseURL: URL
    public let bearerToken: String
    public let projectID: String
    public let requestTimeout: TimeInterval

    public init(
        baseURL: URL,
        bearerToken: String,
        projectID: String,
        requestTimeout: TimeInterval = 8
    ) throws {
        guard baseURL.scheme?.lowercased() == "https" else {
            throw ObserverTransportError.invalidConfiguration("HTTPS_REQUIRED")
        }
        guard !bearerToken.isEmpty,
              bearerToken.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw ObserverTransportError.invalidConfiguration("TOKEN_INVALID")
        }
        guard projectID.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#,
            options: .regularExpression
        ) != nil else {
            throw ObserverTransportError.invalidConfiguration("PROJECT_ID_INVALID")
        }
        guard requestTimeout > 0 else {
            throw ObserverTransportError.invalidConfiguration("TIMEOUT_INVALID")
        }

        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.projectID = projectID
        self.requestTimeout = requestTimeout
    }
}

public struct ObserverHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let data: Data

    public init(statusCode: Int, headers: [String: String], data: Data) {
        self.statusCode = statusCode
        self.headers = Dictionary(
            uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) }
        )
        self.data = data
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

public protocol ObserverHTTPClient: Sendable {
    func get(_ request: URLRequest) async throws -> ObserverHTTPResponse
}

public struct URLSessionObserverHTTPClient: ObserverHTTPClient, @unchecked Sendable {
    private let session: URLSession

    public init(configuration: ObserverTransportConfiguration) {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = configuration.requestTimeout
        config.timeoutIntervalForResource = configuration.requestTimeout
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)
    }

    public func get(_ request: URLRequest) async throws -> ObserverHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ObserverTransportError.invalidResponse
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }
        return ObserverHTTPResponse(
            statusCode: http.statusCode,
            headers: headers,
            data: data
        )
    }
}

public actor ObserverLastGoodCache {
    private var value: ObserverDataEnvelope?

    public init() {}

    public func read() -> ObserverDataEnvelope? {
        value
    }

    public func write(_ envelope: ObserverDataEnvelope) {
        value = envelope
    }

    public func clear() {
        value = nil
    }
}

public struct RealObserverDataSource: ObserverDataSource {
    private let configuration: ObserverTransportConfiguration
    private let client: any ObserverHTTPClient
    private let cache: ObserverLastGoodCache

    public init(
        configuration: ObserverTransportConfiguration,
        client: (any ObserverHTTPClient)? = nil,
        cache: ObserverLastGoodCache = ObserverLastGoodCache()
    ) {
        self.configuration = configuration
        self.client = client ?? URLSessionObserverHTTPClient(configuration: configuration)
        self.cache = cache
    }

    public func load() async throws -> ObserverDataEnvelope {
        do {
            let envelope = try await fetchLiveSnapshot()
            await cache.write(envelope)
            return envelope
        } catch let error as ObserverTransportError {
            switch error {
            case .authFailed:
                if let cached = await cache.read() {
                    return cachedEnvelope(
                        cached,
                        connectionState: .authFailed,
                        observedAt: Date()
                    )
                }
            case .rateLimited:
                if let cached = await cache.read() {
                    return cachedEnvelope(
                        cached,
                        connectionState: .reconnecting,
                        observedAt: Date()
                    )
                }
            case .httpStatus(let status, _):
                if status >= 500, let cached = await cache.read() {
                    return cachedEnvelope(
                        cached,
                        connectionState: .serverUnreachable,
                        observedAt: Date()
                    )
                }
            case .invalidConfiguration,
                 .invalidResponse,
                 .forbidden,
                 .contractMismatch,
                 .schemaDecodeFailed:
                break
            }
            throw error
        } catch is URLError {
            if let cached = await cache.read() {
                return cachedEnvelope(
                    cached,
                    connectionState: .serverUnreachable,
                    observedAt: Date()
                )
            }
            throw ObserverTransportError.httpStatus(503, "NETWORK_UNREACHABLE")
        }
    }

    private func fetchLiveSnapshot() async throws -> ObserverDataEnvelope {
        var components = URLComponents(
            url: configuration.baseURL
                .appendingPathComponent("observer")
                .appendingPathComponent("v1")
                .appendingPathComponent("snapshot"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "project_id", value: configuration.projectID)
        ]
        guard let url = components?.url else {
            throw ObserverTransportError.invalidConfiguration("SNAPSHOT_URL_INVALID")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = configuration.requestTimeout
        request.setValue(
            "Bearer \(configuration.bearerToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response = try await client.get(request)

        guard let transportContract = response.header("X-Observer-Transport"),
              transportContract == "observer.transport.v1" else {
            throw ObserverTransportError.contractMismatch(
                expected: "observer.transport.v1",
                actual: response.header("X-Observer-Transport")
            )
        }

        if response.statusCode != 200 {
            let code = decodeServerErrorCode(response.data)
            switch response.statusCode {
            case 401:
                throw ObserverTransportError.authFailed(code)
            case 403:
                throw ObserverTransportError.forbidden(code)
            case 429:
                throw ObserverTransportError.rateLimited
            default:
                throw ObserverTransportError.httpStatus(response.statusCode, code)
            }
        }

        let decoded: TransportSnapshotDTO
        do {
            decoded = try JSONDecoder().decode(TransportSnapshotDTO.self, from: response.data)
        } catch {
            throw ObserverTransportError.schemaDecodeFailed
        }

        guard decoded.contractVersion == "observer.snapshot.v1" else {
            throw ObserverTransportError.contractMismatch(
                expected: "observer.snapshot.v1",
                actual: decoded.contractVersion
            )
        }

        return decoded.makeEnvelope(
            projectID: configuration.projectID,
            transportContractVersion: transportContract
        )
    }

    private func decodeServerErrorCode(_ data: Data) -> String? {
        (try? JSONDecoder().decode(TransportErrorEnvelope.self, from: data))?.error.code
    }

    private func cachedEnvelope(
        _ envelope: ObserverDataEnvelope,
        connectionState: ConnectionState,
        observedAt: Date
    ) -> ObserverDataEnvelope {
        let old = envelope.snapshot
        let snapshot = ObserverSnapshot(
            connectionState: connectionState,
            authoritativeFocusRunID: old.authoritativeFocusRunID,
            runs: old.runs,
            observedAt: observedAt,
            lastSyncAt: old.lastSyncAt,
            provenance: .cached
        )
        return ObserverDataEnvelope(
            snapshot: snapshot,
            preferredDetailRunID: envelope.preferredDetailRunID,
            transportMetadata: envelope.transportMetadata
        )
    }
}

private struct TransportErrorEnvelope: Decodable {
    struct ErrorBody: Decodable {
        let code: String
    }

    let error: ErrorBody
}

private struct TransportSnapshotDTO: Decodable {
    let contractVersion: String
    let sourceInstanceID: String
    let snapshotRevision: String
    let observedAt: TimeInterval
    let authoritativeFocusTaskID: String?
    let projects: [ProjectDTO]
    let sessions: [SessionDTO]
    let eventCursor: Int
    let availability: [String: String]

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case sourceInstanceID = "source_instance_id"
        case snapshotRevision = "snapshot_revision"
        case observedAt = "observed_at"
        case authoritativeFocusTaskID = "authoritative_focus_task_id"
        case projects
        case sessions
        case eventCursor = "event_cursor"
        case availability
    }

    func makeEnvelope(
        projectID: String,
        transportContractVersion: String
    ) -> ObserverDataEnvelope {
        let names = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.projectID, $0.displayName) }
        )
        let observedDate = Date(timeIntervalSince1970: observedAt)

        let runs = sessions
            .filter { $0.projectID == projectID }
            .map { session -> RunStatusSnapshot in
                let createdAt = Date(timeIntervalSince1970: session.createdAt)
                let startedAt = session.startedAt
                    .map(Date.init(timeIntervalSince1970:))
                    ?? createdAt
                let endedAt = session.endedAt.map(Date.init(timeIntervalSince1970:))
                let updatedCandidates = [
                    session.lastExecutionActivity,
                    session.lastModelActivity,
                    session.endedAt,
                    session.startedAt,
                    session.createdAt
                ].compactMap { $0 }
                let updatedAt = Date(
                    timeIntervalSince1970: updatedCandidates.max() ?? session.createdAt
                )
                let elapsedMS = Int64(
                    max(0, session.executionElapsedSeconds ?? 0) * 1000
                )

                return RunStatusSnapshot(
                    runID: session.sessionID,
                    projectID: session.projectID,
                    projectName: names[session.projectID] ?? session.projectID,
                    executionStatus: Self.executionStatus(for: session.state),
                    directorTruth: nil,
                    runtimeHealth: .unknown,
                    runtimePhase: .unknown,
                    stage: nil,
                    currentOperation: nil,
                    elapsedMS: elapsedMS,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    heartbeats: HeartbeatSnapshot(
                        runLastSeen: nil,
                        toolLastSeen: nil,
                        relayLastSeen: nil
                    ),
                    tests: TestSummary(
                        total: 0,
                        completed: 0,
                        passed: 0,
                        failed: 0,
                        skipped: 0
                    ),
                    checkpoint: CheckpointSummary(
                        latestID: nil,
                        status: nil,
                        createdAt: nil
                    ),
                    bundle: BundleSummary(
                        status: .unknown,
                        id: nil
                    ),
                    presentationStatus: .unknown,
                    lastEvent: nil,
                    updatedAt: updatedAt
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }

        let exactFocus = authoritativeFocusTaskID.flatMap { focus in
            runs.contains(where: { $0.runID == focus }) ? focus : nil
        }
        let preferred = exactFocus ?? runs.first?.runID

        return ObserverDataEnvelope(
            snapshot: ObserverSnapshot(
                connectionState: .online,
                authoritativeFocusRunID: exactFocus,
                runs: runs,
                observedAt: observedDate,
                lastSyncAt: observedDate,
                provenance: .live
            ),
            preferredDetailRunID: preferred,
            transportMetadata: ObserverTransportMetadata(
                transportContractVersion: transportContractVersion,
                snapshotContractVersion: contractVersion,
                sourceInstanceID: sourceInstanceID,
                snapshotRevision: snapshotRevision,
                eventCursor: eventCursor,
                availability: availability,
                rawSessionStates: Dictionary(
                    uniqueKeysWithValues: sessions.map { ($0.sessionID, $0.state) }
                )
            )
        )
    }

    private static func executionStatus(for rawState: String) -> ExecutionStatus {
        switch rawState {
        case "AUTHORIZED", "QUEUED":
            return .pending
        case "STARTING":
            return .starting
        case "RUNNING":
            return .running
        case "FINISHED":
            return .completed
        case "FAILED":
            return .failed
        case "STOPPED", "EXPIRED":
            return .aborted
        case "STOPPING", "RECONCILE":
            return .unknown
        default:
            return .unknown
        }
    }
}

private struct ProjectDTO: Decodable {
    let projectID: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case displayName = "display_name"
    }
}

private struct SessionDTO: Decodable {
    let sessionID: String
    let projectID: String
    let state: String
    let stateClass: String
    let createdAt: TimeInterval
    let expiresAt: TimeInterval
    let startedAt: TimeInterval?
    let endedAt: TimeInterval?
    let lastModelActivity: TimeInterval?
    let lastExecutionActivity: TimeInterval?
    let failureReason: String?
    let queuePosition: Int?
    let sessionAgeSeconds: TimeInterval
    let executionElapsedSeconds: TimeInterval?
    let remainingSeconds: TimeInterval

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
    }
}