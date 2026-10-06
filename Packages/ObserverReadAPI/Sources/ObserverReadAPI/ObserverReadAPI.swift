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
        guard !bearerToken.isEmpty,
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
        guard projectID.range(
            of: Self.projectPattern,
            options: .regularExpression
        ) != nil else {
            throw ObserverReadAPIError.invalidProjectID
        }
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
}
