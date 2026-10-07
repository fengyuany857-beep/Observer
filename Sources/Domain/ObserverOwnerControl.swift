import Foundation

public enum ObserverOwnerContract {
    public static let transport = "observer.owner-control.transport.v1"
    public static let control = "observer.owner-control.v1"
    public static let tokenPrefix = "obsw_"
}

public enum ObserverOwnerDecision: String, Sendable, Codable, Equatable {
    case allow = "ALLOW"
    case deny = "DENY"
}

public struct ObserverOwnerApproval: Sendable, Codable, Equatable, Identifiable {
    public var id: String { approvalID }

    public let approvalID: String
    public let requestAttemptID: String
    public let projectID: String
    public let requestedScope: String
    public let actionClass: String
    public let effectClass: String
    public let state: String
    public let stateVersion: Int
    public let createdAt: TimeInterval
    public let expiresAt: TimeInterval
    public let reason: String?
    public let sessionID: String?

    enum CodingKeys: String, CodingKey {
        case approvalID = "approval_id"
        case requestAttemptID = "request_attempt_id"
        case projectID = "project_id"
        case requestedScope = "requested_scope"
        case actionClass = "action_class"
        case effectClass = "effect_class"
        case state
        case stateVersion = "state_version"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case reason
        case sessionID = "session_id"
    }

    public var isPending: Bool { state == "PENDING" }

    public var isTerminal: Bool {
        ["APPROVED", "DENIED", "EXPIRED", "CONSUMED", "INVALIDATED", "FAILED"]
            .contains(state)
    }
}

public struct ObserverOwnerLifecycle: Sendable, Codable, Equatable, Identifiable {
    public var id: String { operationID }

    public let operationID: String
    public let sessionID: String
    public let action: String
    public let state: String
    public let requestedAt: TimeInterval
    public let updatedAt: TimeInterval
    public let completedAt: TimeInterval?
    public let reason: String
    public let errorCode: String?
    public let errorMessage: String?
    public let credentialRevoked: Bool
    public let credentialRevokedAt: TimeInterval?
    public let sessionState: String
    public let cleanupComplete: Bool

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case sessionID = "session_id"
        case action
        case state
        case requestedAt = "requested_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case reason
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case credentialRevoked = "credential_revoked"
        case credentialRevokedAt = "credential_revoked_at"
        case sessionState = "session_state"
        case cleanupComplete = "cleanup_complete"
    }

    public var isTerminal: Bool {
        state == "SUCCEEDED" || state == "FAILED"
    }

    public var needsReconciliation: Bool {
        state == "OUTCOME_UNKNOWN" || (credentialRevoked && !cleanupComplete)
    }
}

public struct ObserverOwnerControlConfiguration: Sendable, Equatable {
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
        guard baseURL.scheme?.lowercased() == "https",
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.query == nil,
              baseURL.fragment == nil,
              baseURL.path.isEmpty || baseURL.path == "/" else {
            throw ObserverOwnerControlError.invalidConfiguration("HTTPS_REQUIRED")
        }
        guard bearerToken.hasPrefix(ObserverOwnerContract.tokenPrefix),
              !bearerToken.isEmpty,
              bearerToken.count <= 249,
              bearerToken.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw ObserverOwnerControlError.invalidConfiguration("OWNER_TOKEN_INVALID")
        }
        guard projectID.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#,
            options: .regularExpression
        ) != nil else {
            throw ObserverOwnerControlError.invalidConfiguration("PROJECT_ID_INVALID")
        }
        guard requestTimeout > 0 else {
            throw ObserverOwnerControlError.invalidConfiguration("TIMEOUT_INVALID")
        }
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.projectID = projectID
        self.requestTimeout = requestTimeout
    }
}

public enum ObserverOwnerControlError: Error, Sendable, Equatable {
    case invalidConfiguration(String)
    case invalidResponse
    case authFailed(String?)
    case forbidden(String?)
    case notFound(String?)
    case gone(String?)
    case conflict(String?)
    case rateLimited
    case unavailable(String?)
    case httpStatus(Int, String?)
    case transportContractMismatch(expected: String, actual: String?)
    case responseContractMismatch(expected: String, actual: String?)
    case responseScopeMismatch
    case schemaDecodeFailed
    case transportOutcomeUnknown
}

public struct ObserverOwnerHTTPResponse: Sendable {
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

public protocol ObserverOwnerHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> ObserverOwnerHTTPResponse
}

public struct URLSessionObserverOwnerHTTPClient: ObserverOwnerHTTPClient, @unchecked Sendable {
    private let session: URLSession

    public init(configuration: ObserverOwnerControlConfiguration) {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = configuration.requestTimeout
        config.timeoutIntervalForResource = configuration.requestTimeout
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> ObserverOwnerHTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ObserverOwnerControlError.invalidResponse
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                headers[String(describing: key).lowercased()] = String(describing: value)
            }
            return ObserverOwnerHTTPResponse(
                statusCode: http.statusCode,
                headers: headers,
                data: data
            )
        } catch let error as ObserverOwnerControlError {
            throw error
        } catch {
            // A failed POST may have reached the authority owner even if the client
            // never observed the response. Never classify transport loss as "no effect".
            throw ObserverOwnerControlError.transportOutcomeUnknown
        }
    }
}

private struct ObserverOwnerApprovalListResponse: Decodable {
    let contractVersion: String
    let projectID: String
    let approvals: [ObserverOwnerApproval]

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case projectID = "project_id"
        case approvals
    }
}

private struct ObserverOwnerApprovalResponse: Decodable {
    let contractVersion: String
    let projectID: String
    let approval: ObserverOwnerApproval

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case projectID = "project_id"
        case approval
    }
}

private struct ObserverOwnerLifecycleResponse: Decodable {
    let contractVersion: String
    let projectID: String
    let lifecycle: ObserverOwnerLifecycle

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case projectID = "project_id"
        case lifecycle
    }
}

private struct ObserverOwnerErrorEnvelope: Decodable {
    struct Payload: Decodable { let code: String }
    let error: Payload
}

public protocol ObserverOwnerControlServicing: Sendable {
    func pendingApprovals() async throws -> [ObserverOwnerApproval]
    func approvalStatus(_ approvalID: String) async throws -> ObserverOwnerApproval
    func decideApproval(
        _ approvalID: String,
        decision: ObserverOwnerDecision,
        decisionAttemptID: String,
        expectedStateVersion: Int
    ) async throws -> ObserverOwnerApproval
    func closeSession(
        _ sessionID: String,
        closeAttemptID: String
    ) async throws -> ObserverOwnerLifecycle
    func closeStatus(
        _ sessionID: String,
        closeAttemptID: String
    ) async throws -> ObserverOwnerLifecycle
}

public struct ObserverOwnerControlClient: ObserverOwnerControlServicing, Sendable {
    public let configuration: ObserverOwnerControlConfiguration
    private let client: any ObserverOwnerHTTPClient

    public init(
        configuration: ObserverOwnerControlConfiguration,
        client: (any ObserverOwnerHTTPClient)? = nil
    ) {
        self.configuration = configuration
        self.client = client ?? URLSessionObserverOwnerHTTPClient(configuration: configuration)
    }

    public func pendingApprovals() async throws -> [ObserverOwnerApproval] {
        let request = makeRequest(
            path: "/observer/v1/control/projects/\(configuration.projectID)/approvals",
            method: "GET"
        )
        let response = try await client.send(request)
        try validateTransport(response)
        try throwForHTTPError(response)
        let payload: ObserverOwnerApprovalListResponse = try decode(response)
        guard payload.contractVersion == ObserverOwnerContract.control else {
            throw ObserverOwnerControlError.responseContractMismatch(
                expected: ObserverOwnerContract.control,
                actual: payload.contractVersion
            )
        }
        guard payload.projectID == configuration.projectID,
              payload.approvals.allSatisfy({
                  $0.projectID == configuration.projectID && $0.state == "PENDING"
              }) else {
            throw ObserverOwnerControlError.responseScopeMismatch
        }
        return payload.approvals
    }

    public func approvalStatus(_ approvalID: String) async throws -> ObserverOwnerApproval {
        try validateApprovalID(approvalID)
        let request = makeRequest(
            path: "/observer/v1/control/approvals/\(approvalID)",
            method: "GET"
        )
        return try await approvalResponse(request)
    }

    public func decideApproval(
        _ approvalID: String,
        decision: ObserverOwnerDecision,
        decisionAttemptID: String,
        expectedStateVersion: Int
    ) async throws -> ObserverOwnerApproval {
        try validateApprovalID(approvalID)
        try validateAttemptID(decisionAttemptID)
        guard expectedStateVersion > 0 else {
            throw ObserverOwnerControlError.invalidConfiguration("STATE_VERSION_INVALID")
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "decision": decision.rawValue,
            "decision_attempt_id": decisionAttemptID,
            "expected_state_version": expectedStateVersion,
        ])
        let request = makeRequest(
            path: "/observer/v1/control/approvals/\(approvalID)/decision",
            method: "POST",
            body: body
        )
        return try await approvalResponse(request)
    }

    public func closeSession(
        _ sessionID: String,
        closeAttemptID: String
    ) async throws -> ObserverOwnerLifecycle {
        try validateSessionID(sessionID)
        try validateAttemptID(closeAttemptID)
        let body = try JSONSerialization.data(withJSONObject: [
            "close_attempt_id": closeAttemptID
        ])
        let request = makeRequest(
            path: "/observer/v1/control/sessions/\(sessionID)/close",
            method: "POST",
            body: body
        )
        return try await lifecycleResponse(request, sessionID: sessionID, closeAttemptID: closeAttemptID)
    }

    public func closeStatus(
        _ sessionID: String,
        closeAttemptID: String
    ) async throws -> ObserverOwnerLifecycle {
        try validateSessionID(sessionID)
        try validateAttemptID(closeAttemptID)
        let request = makeRequest(
            path: "/observer/v1/control/sessions/\(sessionID)/close/\(closeAttemptID)",
            method: "GET"
        )
        return try await lifecycleResponse(request, sessionID: sessionID, closeAttemptID: closeAttemptID)
    }

    private func lifecycleResponse(
        _ request: URLRequest,
        sessionID: String,
        closeAttemptID: String
    ) async throws -> ObserverOwnerLifecycle {
        let response = try await client.send(request)
        try validateTransport(response)
        try throwForHTTPError(response)
        let payload: ObserverOwnerLifecycleResponse = try decode(response)
        guard payload.contractVersion == ObserverOwnerContract.control else {
            throw ObserverOwnerControlError.responseContractMismatch(
                expected: ObserverOwnerContract.control,
                actual: payload.contractVersion
            )
        }
        guard payload.projectID == configuration.projectID,
              payload.lifecycle.sessionID == sessionID,
              payload.lifecycle.operationID == closeAttemptID,
              payload.lifecycle.action == "CLOSE" else {
            throw ObserverOwnerControlError.responseScopeMismatch
        }
        return payload.lifecycle
    }

    private func approvalResponse(_ request: URLRequest) async throws -> ObserverOwnerApproval {
        let response = try await client.send(request)
        try validateTransport(response)
        try throwForHTTPError(response)
        let payload: ObserverOwnerApprovalResponse = try decode(response)
        guard payload.contractVersion == ObserverOwnerContract.control else {
            throw ObserverOwnerControlError.responseContractMismatch(
                expected: ObserverOwnerContract.control,
                actual: payload.contractVersion
            )
        }
        guard payload.projectID == configuration.projectID,
              payload.approval.projectID == configuration.projectID else {
            throw ObserverOwnerControlError.responseScopeMismatch
        }
        return payload.approval
    }

    private func makeRequest(path: String, method: String, body: Data? = nil) -> URLRequest {
        var components = URLComponents(
            url: configuration.baseURL,
            resolvingAgainstBaseURL: false
        )!
        components.path = path
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Bearer \(configuration.bearerToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func validateTransport(_ response: ObserverOwnerHTTPResponse) throws {
        let actual = response.header("X-Observer-Transport")
        guard actual == ObserverOwnerContract.transport else {
            throw ObserverOwnerControlError.transportContractMismatch(
                expected: ObserverOwnerContract.transport,
                actual: actual
            )
        }
    }

    private func throwForHTTPError(_ response: ObserverOwnerHTTPResponse) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        let code = (try? JSONDecoder().decode(
            ObserverOwnerErrorEnvelope.self,
            from: response.data
        ))?.error.code
        switch response.statusCode {
        case 401:
            throw ObserverOwnerControlError.authFailed(code)
        case 403:
            throw ObserverOwnerControlError.forbidden(code)
        case 404:
            throw ObserverOwnerControlError.notFound(code)
        case 409:
            throw ObserverOwnerControlError.conflict(code)
        case 410:
            throw ObserverOwnerControlError.gone(code)
        case 429:
            throw ObserverOwnerControlError.rateLimited
        case 500...599:
            throw ObserverOwnerControlError.unavailable(code)
        default:
            throw ObserverOwnerControlError.httpStatus(response.statusCode, code)
        }
    }

    private func decode<T: Decodable>(_ response: ObserverOwnerHTTPResponse) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: response.data)
        } catch {
            throw ObserverOwnerControlError.schemaDecodeFailed
        }
    }

    private func validateSessionID(_ value: String) throws {
        guard value.range(
            of: #"^s_[0-9a-f]{32}$"#,
            options: .regularExpression
        ) != nil else {
            throw ObserverOwnerControlError.invalidConfiguration("SESSION_ID_INVALID")
        }
    }

    private func validateApprovalID(_ value: String) throws {
        guard value.range(
            of: #"^access-apr-[0-9a-f]{32}$"#,
            options: .regularExpression
        ) != nil else {
            throw ObserverOwnerControlError.invalidConfiguration("APPROVAL_ID_INVALID")
        }
    }

    private func validateAttemptID(_ value: String) throws {
        guard value.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,127}$"#,
            options: .regularExpression
        ) != nil else {
            throw ObserverOwnerControlError.invalidConfiguration("DECISION_ATTEMPT_ID_INVALID")
        }
    }
}

public enum ObserverSessionCloseState: Sendable, Equatable {
    case idle
    case submitting(attemptID: String)
    case tracking(ObserverOwnerLifecycle)
    case outcomeUnknown(attemptID: String, lifecycle: ObserverOwnerLifecycle?)
    case failed(String)

    public var attemptID: String? {
        switch self {
        case .submitting(let attemptID): return attemptID
        case .tracking(let lifecycle): return lifecycle.operationID
        case .outcomeUnknown(let attemptID, _): return attemptID
        case .idle, .failed: return nil
        }
    }

    public var blocksNewClose: Bool {
        switch self {
        case .idle, .failed: return false
        case .submitting, .tracking, .outcomeUnknown: return true
        }
    }
}

public enum ObserverSessionCloseResult: Sendable, Equatable {
    case observed(ObserverOwnerLifecycle)
    case outcomeUnknown(attemptID: String, lifecycle: ObserverOwnerLifecycle?)
    case failed(String)
    case busy(attemptID: String)
}

public actor ObserverSessionCloseCoordinator {
    private var inFlightBySession: [String: String] = [:]

    public init() {}

    public func close(
        sessionID: String,
        closeAttemptID: String,
        client: any ObserverOwnerControlServicing
    ) async -> ObserverSessionCloseResult {
        if let existing = inFlightBySession[sessionID] {
            return .busy(attemptID: existing)
        }
        inFlightBySession[sessionID] = closeAttemptID
        defer { inFlightBySession.removeValue(forKey: sessionID) }

        do {
            return .observed(try await client.closeSession(sessionID, closeAttemptID: closeAttemptID))
        } catch let error as ObserverOwnerControlError {
            switch error {
            case .transportOutcomeUnknown, .unavailable:
                return await status(
                    sessionID: sessionID,
                    closeAttemptID: closeAttemptID,
                    client: client
                )
            default:
                return .failed(ObserverApprovalDecisionCoordinator.code(error))
            }
        } catch {
            return await status(
                sessionID: sessionID,
                closeAttemptID: closeAttemptID,
                client: client
            )
        }
    }

    public func status(
        sessionID: String,
        closeAttemptID: String,
        client: any ObserverOwnerControlServicing
    ) async -> ObserverSessionCloseResult {
        do {
            let lifecycle = try await client.closeStatus(
                sessionID,
                closeAttemptID: closeAttemptID
            )
            if lifecycle.state == "OUTCOME_UNKNOWN" {
                return .outcomeUnknown(
                    attemptID: closeAttemptID,
                    lifecycle: lifecycle
                )
            }
            return .observed(lifecycle)
        } catch let error as ObserverOwnerControlError {
            switch error {
            case .notFound, .unavailable, .transportOutcomeUnknown:
                return .outcomeUnknown(attemptID: closeAttemptID, lifecycle: nil)
            default:
                return .failed(ObserverApprovalDecisionCoordinator.code(error))
            }
        } catch {
            return .outcomeUnknown(attemptID: closeAttemptID, lifecycle: nil)
        }
    }

    public func reconcileSameAttempt(
        sessionID: String,
        closeAttemptID: String,
        client: any ObserverOwnerControlServicing
    ) async -> ObserverSessionCloseResult {
        // The frozen backend makes the same close_attempt_id idempotent and uses
        // it to resume an OUTCOME_UNKNOWN lifecycle. Never generate a new id here.
        await close(
            sessionID: sessionID,
            closeAttemptID: closeAttemptID,
            client: client
        )
    }
}

public enum ObserverOwnerMutationState: Sendable, Equatable {
    case idle
    case submitting(decision: ObserverOwnerDecision, attemptID: String)
    case conflict(stateVersion: Int)
    case outcomeUnknown(decision: ObserverOwnerDecision, attemptID: String)
    case resolved(String)
    case failed(String)

    public var isBusy: Bool {
        switch self {
        case .submitting, .outcomeUnknown:
            return true
        case .idle, .conflict, .resolved, .failed:
            return false
        }
    }
}

public enum ObserverApprovalDecisionResult: Sendable, Equatable {
    case resolved(ObserverOwnerApproval)
    case conflict(ObserverOwnerApproval)
    case expired(ObserverOwnerApproval?)
    case outcomeUnknown(attemptID: String, lastKnown: ObserverOwnerApproval?)
    case failed(String)
    case busy(attemptID: String)
}

public actor ObserverApprovalDecisionCoordinator {
    private var inFlightByApproval: [String: String] = [:]

    public init() {}

    public func decide(
        approval: ObserverOwnerApproval,
        decision: ObserverOwnerDecision,
        decisionAttemptID: String,
        client: any ObserverOwnerControlServicing
    ) async -> ObserverApprovalDecisionResult {
        if let existing = inFlightByApproval[approval.approvalID] {
            return .busy(attemptID: existing)
        }
        inFlightByApproval[approval.approvalID] = decisionAttemptID
        defer { inFlightByApproval.removeValue(forKey: approval.approvalID) }

        do {
            let resolved = try await client.decideApproval(
                approval.approvalID,
                decision: decision,
                decisionAttemptID: decisionAttemptID,
                expectedStateVersion: approval.stateVersion
            )
            return .resolved(resolved)
        } catch let error as ObserverOwnerControlError {
            switch error {
            case .conflict:
                return await authoritativeConflict(
                    approvalID: approval.approvalID,
                    client: client
                )
            case .gone:
                let fresh = try? await client.approvalStatus(approval.approvalID)
                return .expired(fresh)
            case .transportOutcomeUnknown, .unavailable:
                return await reconcileAfterUnknown(
                    approvalID: approval.approvalID,
                    decision: decision,
                    attemptID: decisionAttemptID,
                    client: client
                )
            default:
                return .failed(Self.code(error))
            }
        } catch {
            return await reconcileAfterUnknown(
                approvalID: approval.approvalID,
                decision: decision,
                attemptID: decisionAttemptID,
                client: client
            )
        }
    }

    public func reconcile(
        approvalID: String,
        decision: ObserverOwnerDecision,
        attemptID: String,
        client: any ObserverOwnerControlServicing
    ) async -> ObserverApprovalDecisionResult {
        await reconcileAfterUnknown(
            approvalID: approvalID,
            decision: decision,
            attemptID: attemptID,
            client: client
        )
    }

    private func authoritativeConflict(
        approvalID: String,
        client: any ObserverOwnerControlServicing
    ) async -> ObserverApprovalDecisionResult {
        do {
            let fresh = try await client.approvalStatus(approvalID)
            return fresh.state == "PENDING" ? .conflict(fresh) : .resolved(fresh)
        } catch let error as ObserverOwnerControlError {
            return .failed(Self.code(error))
        } catch {
            return .failed("OWNER_CONFLICT_REFETCH_FAILED")
        }
    }

    private func reconcileAfterUnknown(
        approvalID: String,
        decision: ObserverOwnerDecision,
        attemptID: String,
        client: any ObserverOwnerControlServicing
    ) async -> ObserverApprovalDecisionResult {
        do {
            let fresh = try await client.approvalStatus(approvalID)
            if fresh.state == "APPROVED" || fresh.state == "DENIED" {
                let expected = decision == .allow ? "APPROVED" : "DENIED"
                if fresh.state == expected {
                    return .resolved(fresh)
                }
                return .conflict(fresh)
            }
            if fresh.state == "EXPIRED" {
                return .expired(fresh)
            }
            if fresh.isTerminal {
                return .resolved(fresh)
            }
            return .outcomeUnknown(attemptID: attemptID, lastKnown: fresh)
        } catch {
            return .outcomeUnknown(attemptID: attemptID, lastKnown: nil)
        }
    }

    public static func code(_ error: ObserverOwnerControlError) -> String {
        switch error {
        case .invalidConfiguration(let code): return code
        case .invalidResponse: return "OWNER_INVALID_RESPONSE"
        case .authFailed(let code): return code ?? "OWNER_AUTH_FAILED"
        case .forbidden(let code): return code ?? "OWNER_FORBIDDEN"
        case .notFound(let code): return code ?? "OWNER_NOT_FOUND"
        case .gone(let code): return code ?? "OWNER_GONE"
        case .conflict(let code): return code ?? "OWNER_CONFLICT"
        case .rateLimited: return "OWNER_RATE_LIMITED"
        case .unavailable(let code): return code ?? "OWNER_UNAVAILABLE"
        case .httpStatus(let status, let code): return code ?? "OWNER_HTTP_\(status)"
        case .transportContractMismatch: return "OWNER_TRANSPORT_CONTRACT_MISMATCH"
        case .responseContractMismatch: return "OWNER_RESPONSE_CONTRACT_MISMATCH"
        case .responseScopeMismatch: return "OWNER_RESPONSE_SCOPE_MISMATCH"
        case .schemaDecodeFailed: return "OWNER_SCHEMA_DECODE_FAILED"
        case .transportOutcomeUnknown: return "OWNER_OUTCOME_UNKNOWN"
        }
    }
}
