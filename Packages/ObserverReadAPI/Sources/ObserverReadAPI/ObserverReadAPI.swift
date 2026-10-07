import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

public enum ObserverReadAPIError: Error, Sendable, Equatable {
    case invalidConfiguration(String)
    case invalidProjectID
    case invalidSessionID
    case invalidCursor
    case invalidLimit
    case transportContractMismatch(expected: String, actual: String?)
    case authFailed
    case forbidden
    case rateLimited
    case httpStatus(Int)
    case responseContractMismatch(expected: String, actual: String)
    case responseScopeMismatch
    case unavailable(String)
    case unexpectedResponse
}

public struct ObserverReadAPIConfiguration: Sendable {
    public let baseURL: URL
    public let bearerToken: String
    public let requestTimeout: TimeInterval

    public init(
        baseURL: URL,
        bearerToken: String,
        requestTimeout: TimeInterval = 8
    ) throws {
        guard baseURL.scheme?.lowercased() == "https" else {
            throw ObserverReadAPIError.invalidConfiguration("HTTPS_REQUIRED")
        }
        guard bearerToken.hasPrefix("obsr_"),
              !bearerToken.isEmpty,
              bearerToken.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw ObserverReadAPIError.invalidConfiguration("TOKEN_INVALID")
        }
        guard requestTimeout > 0 else {
            throw ObserverReadAPIError.invalidConfiguration("TIMEOUT_INVALID")
        }
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.requestTimeout = requestTimeout
    }
}

public enum ObserverJobStateClass: String, Sendable, Equatable {
    case terminalConfirmed = "TERMINAL_CONFIRMED"
    case lastObservedActive = "LAST_OBSERVED_ACTIVE"
    case unknown = "UNKNOWN"
}

public struct ObserverReadJob: Sendable, Equatable, Identifiable {
    public let jobID: String
    public let sessionID: String
    public let projectID: String
    public let gatewayState: String
    public let stateClass: ObserverJobStateClass
    public let heavy: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public let authority: String
    public let freshness: String

    public var id: String { jobID }
}

public struct ObserverReadJobsPage: Sendable, Equatable {
    public let sourceInstanceID: String
    public let projectID: String
    public let sessionID: String?
    public let availability: String
    public let jobs: [ObserverReadJob]
}

public struct ObserverReadOperation: Sendable, Equatable, Identifiable {
    public let operationID: String
    public let sessionID: String
    public let projectID: String
    public let kind: String
    public let name: String
    public let startedAt: Date
    public let currentness: String
    public let authority: String
    public let freshness: String

    public var id: String { operationID }
}

public struct ObserverReadOperationsPage: Sendable, Equatable {
    public let sourceInstanceID: String
    public let authorityInstanceID: String
    public let projectID: String
    public let sessionID: String?
    public let availability: String
    public let observedAt: Date
    public let operations: [ObserverReadOperation]

    public func currentOperation(for sessionID: String) -> ObserverReadOperation? {
        operations.first { $0.sessionID == sessionID }
    }
}

public struct ObserverReadEvent: Sendable, Equatable, Identifiable {
    public let eventID: Int
    public let eventIdentity: String
    public let eventType: String
    public let createdAt: Date
    public let sessionID: String?
    public let projectID: String?
    public let source: String
    public let authoritative: Bool
    public let payloadSummary: String

    public var id: Int { eventID }

    public init(
        eventID: Int,
        eventIdentity: String,
        eventType: String,
        createdAt: Date,
        sessionID: String?,
        projectID: String?,
        source: String,
        authoritative: Bool,
        payloadSummary: String
    ) {
        self.eventID = eventID
        self.eventIdentity = eventIdentity
        self.eventType = eventType
        self.createdAt = createdAt
        self.sessionID = sessionID
        self.projectID = projectID
        self.source = source
        self.authoritative = authoritative
        self.payloadSummary = payloadSummary
    }
}

public struct ObserverReadEventsPage: Sendable, Equatable {
    public let sourceInstanceID: String
    public let projectID: String
    public let eventCursor: Int
    public let events: [ObserverReadEvent]

    public init(
        sourceInstanceID: String,
        projectID: String,
        eventCursor: Int,
        events: [ObserverReadEvent]
    ) {
        self.sourceInstanceID = sourceInstanceID
        self.projectID = projectID
        self.eventCursor = eventCursor
        self.events = events
    }

    public func eventsForSession(_ sessionID: String) -> [ObserverReadEvent] {
        events.filter { $0.sessionID == sessionID }
    }
}

public struct ObserverReadEffect: Sendable, Equatable, Identifiable {
    public let effectID: String
    public let taskID: String
    public let projectID: String
    public let state: String
    public let stateKnown: Bool
    public let generation: Int
    public let receiptSummary: String?
    public let lastErrorCode: String?
    public let createdAtRaw: String
    public let updatedAtRaw: String

    public var id: String { effectID }

    public init(
        effectID: String,
        taskID: String,
        projectID: String,
        state: String,
        stateKnown: Bool,
        generation: Int,
        receiptSummary: String?,
        lastErrorCode: String?,
        createdAtRaw: String,
        updatedAtRaw: String
    ) {
        self.effectID = effectID
        self.taskID = taskID
        self.projectID = projectID
        self.state = state
        self.stateKnown = stateKnown
        self.generation = generation
        self.receiptSummary = receiptSummary
        self.lastErrorCode = lastErrorCode
        self.createdAtRaw = createdAtRaw
        self.updatedAtRaw = updatedAtRaw
    }
}

public struct ObserverReadEffectsPage: Sendable, Equatable {
    public let projectID: String
    public let taskID: String?
    public let effects: [ObserverReadEffect]

    public init(projectID: String, taskID: String?, effects: [ObserverReadEffect]) {
        self.projectID = projectID
        self.taskID = taskID
        self.effects = effects
    }
}

final class ObserverNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct ObserverReadMiddleware: ClientMiddleware {
    let bearerToken: String
    let expectedTransportContract: String

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard request.method == .get else {
            throw ObserverReadAPIError.invalidConfiguration("READ_PLANE_GET_ONLY")
        }

        var authorizedRequest = request
        authorizedRequest.headerFields[.authorization] = "Bearer \(bearerToken)"
        let (response, responseBody) = try await next(authorizedRequest, body, baseURL)

        let transportHeaderName = HTTPField.Name("X-Observer-Transport")!
        let actualContract = response.headerFields[transportHeaderName]
        guard actualContract == expectedTransportContract else {
            throw ObserverReadAPIError.transportContractMismatch(
                expected: expectedTransportContract,
                actual: actualContract
            )
        }

        switch response.status.code {
        case 200:
            return (response, responseBody)
        case 401:
            throw ObserverReadAPIError.authFailed
        case 403:
            throw ObserverReadAPIError.forbidden
        case 429:
            throw ObserverReadAPIError.rateLimited
        default:
            throw ObserverReadAPIError.httpStatus(response.status.code)
        }
    }
}

public struct ObserverReadAPIClient: Sendable {
    private static let projectPattern = #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#
    private static let sessionPattern = #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$"#

    private let client: Client

    public init(configuration: ObserverReadAPIConfiguration) {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = configuration.requestTimeout
        sessionConfiguration.urlCache = nil
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.httpShouldSetCookies = false

        let session = URLSession(
            configuration: sessionConfiguration,
            delegate: ObserverNoRedirectDelegate(),
            delegateQueue: nil
        )
        let transport = URLSessionTransport(
            configuration: .init(session: session)
        )
        self.client = Client(
            serverURL: configuration.baseURL,
            transport: transport,
            middlewares: [
                ObserverReadMiddleware(
                    bearerToken: configuration.bearerToken,
                    expectedTransportContract: "observer.transport.v1"
                )
            ]
        )
    }

    public func jobs(
        projectID: String,
        sessionID: String? = nil,
        limit: Int = 100
    ) async throws -> ObserverReadJobsPage {
        try Self.validateProjectID(projectID)
        if let sessionID,
           sessionID.range(of: Self.sessionPattern, options: .regularExpression) == nil {
            throw ObserverReadAPIError.invalidSessionID
        }
        guard (1...100).contains(limit) else {
            throw ObserverReadAPIError.invalidLimit
        }

        let output = try await client.getJobs(
            path: .init(projectId: projectID),
            query: .init(sessionId: sessionID, limit: limit)
        )
        let payload: Components.Schemas.ObserverJobsEnvelope
        do {
            payload = try output.ok.body.json
        } catch {
            throw ObserverReadAPIError.unexpectedResponse
        }

        guard payload.contractVersion == "observer.jobs.v1" else {
            throw ObserverReadAPIError.responseContractMismatch(
                expected: "observer.jobs.v1",
                actual: payload.contractVersion
            )
        }
        guard payload.projectId == projectID,
              payload.sessionId == sessionID else {
            throw ObserverReadAPIError.responseScopeMismatch
        }
        guard payload.availability == "AVAILABLE" else {
            throw ObserverReadAPIError.unavailable(payload.availability)
        }

        return ObserverReadJobsPage(
            sourceInstanceID: payload.sourceInstanceId,
            projectID: payload.projectId,
            sessionID: payload.sessionId,
            availability: payload.availability,
            jobs: payload.jobs.map { row in
                ObserverReadJob(
                    jobID: row.jobId,
                    sessionID: row.sessionId,
                    projectID: row.projectId,
                    gatewayState: row.gatewayState,
                    stateClass: ObserverJobStateClass(rawValue: row.stateClass) ?? .unknown,
                    heavy: row.heavy,
                    createdAt: Date(timeIntervalSince1970: row.createdAt),
                    updatedAt: Date(timeIntervalSince1970: row.updatedAt),
                    authority: row.authority,
                    freshness: row.freshness
                )
            }
        )
    }

    public func operations(
        projectID: String,
        sessionID: String? = nil
    ) async throws -> ObserverReadOperationsPage {
        try Self.validateProjectID(projectID)
        if let sessionID,
           sessionID.range(of: Self.sessionPattern, options: .regularExpression) == nil {
            throw ObserverReadAPIError.invalidSessionID
        }

        let output = try await client.getOperations(
            path: .init(projectId: projectID),
            query: .init(sessionId: sessionID)
        )
        let payload: Components.Schemas.ObserverOperationsEnvelope
        do {
            payload = try output.ok.body.json
        } catch {
            throw ObserverReadAPIError.unexpectedResponse
        }

        guard payload.contractVersion == "observer.operations.v1" else {
            throw ObserverReadAPIError.responseContractMismatch(
                expected: "observer.operations.v1",
                actual: payload.contractVersion
            )
        }
        guard payload.projectId == projectID,
              payload.sessionId == sessionID else {
            throw ObserverReadAPIError.responseScopeMismatch
        }
        guard payload.availability == "AVAILABLE" else {
            throw ObserverReadAPIError.unavailable(payload.availability)
        }
        guard let authorityInstanceID = payload.authorityInstanceId,
              !authorityInstanceID.isEmpty else {
            throw ObserverReadAPIError.responseContractMismatch(
                expected: "CURRENT_PROCESS_AUTHORITY_INSTANCE",
                actual: payload.authorityInstanceId ?? ""
            )
        }

        var seenSessions = Set<String>()
        let operations = try payload.operations.map { row -> ObserverReadOperation in
            guard row.projectId == projectID,
                  sessionID == nil || row.sessionId == sessionID else {
                throw ObserverReadAPIError.responseScopeMismatch
            }
            guard row.currentness == "CURRENT",
                  row.authority == "GATEWAY_IN_FLIGHT_CALL",
                  row.freshness == "CURRENT_PROCESS" else {
                throw ObserverReadAPIError.responseContractMismatch(
                    expected: "CURRENT_GATEWAY_IN_FLIGHT_CALL",
                    actual: "\(row.currentness)|\(row.authority)|\(row.freshness)"
                )
            }
            guard seenSessions.insert(row.sessionId).inserted else {
                throw ObserverReadAPIError.responseContractMismatch(
                    expected: "ONE_CURRENT_OPERATION_PER_SESSION",
                    actual: row.sessionId
                )
            }
            return ObserverReadOperation(
                operationID: row.operationId,
                sessionID: row.sessionId,
                projectID: row.projectId,
                kind: row.kind,
                name: row.name,
                startedAt: Date(timeIntervalSince1970: row.startedAt),
                currentness: row.currentness,
                authority: row.authority,
                freshness: row.freshness
            )
        }

        return ObserverReadOperationsPage(
            sourceInstanceID: payload.sourceInstanceId,
            authorityInstanceID: authorityInstanceID,
            projectID: payload.projectId,
            sessionID: payload.sessionId,
            availability: payload.availability,
            observedAt: Date(timeIntervalSince1970: payload.observedAt),
            operations: operations
        )
    }

    public func events(
        projectID: String,
        afterID: Int = 0,
        limit: Int = 200
    ) async throws -> ObserverReadEventsPage {
        try Self.validateProjectID(projectID)
        guard afterID >= 0 else {
            throw ObserverReadAPIError.invalidCursor
        }
        guard (1...200).contains(limit) else {
            throw ObserverReadAPIError.invalidLimit
        }

        let output = try await client.getEvents(
            path: .init(projectId: projectID),
            query: .init(afterId: afterID, limit: limit)
        )
        let payload: Components.Schemas.ObserverEventsEnvelope
        do {
            payload = try output.ok.body.json
        } catch {
            throw ObserverReadAPIError.unexpectedResponse
        }

        guard payload.contractVersion == "observer.events.v1" else {
            throw ObserverReadAPIError.responseContractMismatch(
                expected: "observer.events.v1",
                actual: payload.contractVersion
            )
        }
        guard payload.projectId == projectID,
              payload.events.allSatisfy({ $0.projectId == nil || $0.projectId == projectID }) else {
            throw ObserverReadAPIError.responseScopeMismatch
        }

        return ObserverReadEventsPage(
            sourceInstanceID: payload.sourceInstanceId,
            projectID: payload.projectId,
            eventCursor: payload.eventCursor,
            events: payload.events.map { row in
                ObserverReadEvent(
                    eventID: row.eventId,
                    eventIdentity: row.eventIdentity,
                    eventType: row.eventType,
                    createdAt: Date(timeIntervalSince1970: row.createdAt),
                    sessionID: row.sessionId,
                    projectID: row.projectId,
                    source: row.source,
                    authoritative: row.authoritative,
                    payloadSummary: String(describing: row.payload)
                )
            }
        )
    }

    public func effects(
        projectID: String,
        taskID: String? = nil,
        limit: Int = 100
    ) async throws -> ObserverReadEffectsPage {
        try Self.validateProjectID(projectID)
        guard (1...100).contains(limit) else {
            throw ObserverReadAPIError.invalidLimit
        }

        let output = try await client.getEffects(
            path: .init(projectId: projectID),
            query: .init(taskId: taskID, limit: limit)
        )
        let payload: Components.Schemas.ObserverEffectsEnvelope
        do {
            payload = try output.ok.body.json
        } catch {
            throw ObserverReadAPIError.unexpectedResponse
        }

        guard payload.contractVersion == "observer.effects.v1" else {
            throw ObserverReadAPIError.responseContractMismatch(
                expected: "observer.effects.v1",
                actual: payload.contractVersion
            )
        }
        guard payload.projectId == projectID,
              (taskID == nil || payload.taskId == taskID),
              payload.effects.allSatisfy({ effect in
                  effect.projectId == projectID && (taskID == nil || effect.taskId == taskID)
              }) else {
            throw ObserverReadAPIError.responseScopeMismatch
        }

        return ObserverReadEffectsPage(
            projectID: payload.projectId,
            taskID: payload.taskId,
            effects: payload.effects.map { row in
                ObserverReadEffect(
                    effectID: row.effectId,
                    taskID: row.taskId,
                    projectID: row.projectId,
                    state: row.state,
                    stateKnown: row.stateKnown,
                    generation: row.generation,
                    receiptSummary: row.receipt.map { String(describing: $0) },
                    lastErrorCode: row.lastErrorCode,
                    createdAtRaw: row.createdAt,
                    updatedAtRaw: row.updatedAt
                )
            }
        )
    }

    private static func validateProjectID(_ projectID: String) throws {
        guard projectID.range(of: projectPattern, options: .regularExpression) != nil else {
            throw ObserverReadAPIError.invalidProjectID
        }
    }
}
