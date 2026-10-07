import Foundation

private var failures = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("PASS \(message)")
    } else {
        print("FAIL \(message)")
        failures += 1
    }
}

private let approvalID = "access-apr-" + String(repeating: "a", count: 32)

private func approval(
    state: String = "PENDING",
    version: Int = 1,
    id: String = approvalID
) -> ObserverOwnerApproval {
    ObserverOwnerApproval(
        approvalID: id,
        requestAttemptID: "request-1",
        projectID: "vcw-acceptance",
        requestedScope: "PROJECT_CODING_SESSION",
        actionClass: "START_CODING_SESSION",
        effectClass: "WORKSPACE_MUTATION",
        state: state,
        stateVersion: version,
        createdAt: 1000,
        expiresAt: 1120,
        reason: nil,
        sessionID: nil
    )
}

private actor HTTPStub: ObserverOwnerHTTPClient {
    enum Step: Sendable {
        case response(ObserverOwnerHTTPResponse)
        case networkFailure
    }

    private var steps: [Step]
    private var seen: [URLRequest] = []

    init(_ steps: [Step]) { self.steps = steps }

    func send(_ request: URLRequest) async throws -> ObserverOwnerHTTPResponse {
        seen.append(request)
        guard !steps.isEmpty else { fatalError("unexpected request") }
        switch steps.removeFirst() {
        case .response(let value):
            return value
        case .networkFailure:
            throw URLError(.networkConnectionLost)
        }
    }

    func requests() -> [URLRequest] { seen }
}

private func response(
    status: Int = 200,
    body: String,
    transport: String? = ObserverOwnerContract.transport
) -> ObserverOwnerHTTPResponse {
    var headers: [String: String] = ["Cache-Control": "no-store"]
    if let transport { headers["X-Observer-Transport"] = transport }
    return ObserverOwnerHTTPResponse(
        statusCode: status,
        headers: headers,
        data: Data(body.utf8)
    )
}

private func approvalJSON(state: String = "PENDING", version: Int = 1) -> String {
    """
    {
      "approval_id": "\(approvalID)",
      "request_attempt_id": "request-1",
      "project_id": "vcw-acceptance",
      "requested_scope": "PROJECT_CODING_SESSION",
      "action_class": "START_CODING_SESSION",
      "effect_class": "WORKSPACE_MUTATION",
      "state": "\(state)",
      "state_version": \(version),
      "created_at": 1000,
      "expires_at": 1120,
      "reason": null,
      "session_id": null
    }
    """
}

private func wrapper(_ approvalBody: String) -> String {
    """
    {
      "contract_version": "observer.owner-control.v1",
      "project_id": "vcw-acceptance",
      "grant_id": "owner-grant-redacted",
      "approval": \(approvalBody)
    }
    """
}

private actor ServiceStub: ObserverOwnerControlServicing {
    enum Mode: Sendable {
        case success
        case conflict
        case unknownThenApproved
        case unknownStillPending
    }

    let mode: Mode
    private var decisionCalls = 0
    private var statusCalls = 0

    init(_ mode: Mode) { self.mode = mode }

    func pendingApprovals() async throws -> [ObserverOwnerApproval] {
        [approval()]
    }

    func approvalStatus(_ approvalID: String) async throws -> ObserverOwnerApproval {
        statusCalls += 1
        switch mode {
        case .conflict:
            return approval(state: "PENDING", version: 2)
        case .unknownThenApproved:
            return approval(state: "APPROVED", version: 2)
        case .unknownStillPending:
            return approval(state: "PENDING", version: 1)
        case .success:
            return approval(state: "APPROVED", version: 2)
        }
    }

    func decideApproval(
        _ approvalID: String,
        decision: ObserverOwnerDecision,
        decisionAttemptID: String,
        expectedStateVersion: Int
    ) async throws -> ObserverOwnerApproval {
        decisionCalls += 1
        switch mode {
        case .success:
            return approval(
                state: decision == .allow ? "APPROVED" : "DENIED",
                version: expectedStateVersion + 1
            )
        case .conflict:
            throw ObserverOwnerControlError.conflict("VCW_ACCESS_APPROVAL_CONFLICT")
        case .unknownThenApproved, .unknownStillPending:
            throw ObserverOwnerControlError.transportOutcomeUnknown
        }
    }

    func closeSession(
        _ sessionID: String,
        closeAttemptID: String
    ) async throws -> ObserverOwnerLifecycle {
        fatalError("closeSession not used by approval tests")
    }

    func closeStatus(
        _ sessionID: String,
        closeAttemptID: String
    ) async throws -> ObserverOwnerLifecycle {
        fatalError("closeStatus not used by approval tests")
    }

    func counts() -> (Int, Int) { (decisionCalls, statusCalls) }
}

private func lifecycle(
    state: String,
    attemptID: String,
    cleanupComplete: Bool,
    credentialRevoked: Bool = true
) -> ObserverOwnerLifecycle {
    ObserverOwnerLifecycle(
        operationID: attemptID,
        sessionID: "s_" + String(repeating: "b", count: 32),
        action: "CLOSE",
        state: state,
        requestedAt: 1000,
        updatedAt: 1001,
        completedAt: state == "SUCCEEDED" ? 1001 : nil,
        reason: "OBSERVER_OWNER_CLOSE",
        errorCode: state == "OUTCOME_UNKNOWN" ? "VCW_SESSION_CLOSE_OUTCOME_UNKNOWN" : nil,
        errorMessage: nil,
        credentialRevoked: credentialRevoked,
        credentialRevokedAt: credentialRevoked ? 1000 : nil,
        sessionState: cleanupComplete ? "STOPPED" : "RECONCILE",
        cleanupComplete: cleanupComplete
    )
}

private actor CloseServiceStub: ObserverOwnerControlServicing {
    enum Mode: Sendable {
        case success
        case responseLostUnknown
    }

    let mode: Mode
    private var closeAttempts: [String] = []
    private var statusAttempts: [String] = []

    init(_ mode: Mode) { self.mode = mode }

    func pendingApprovals() async throws -> [ObserverOwnerApproval] { [] }
    func approvalStatus(_ approvalID: String) async throws -> ObserverOwnerApproval { approval() }
    func decideApproval(_ approvalID: String, decision: ObserverOwnerDecision, decisionAttemptID: String, expectedStateVersion: Int) async throws -> ObserverOwnerApproval { approval() }

    func closeSession(_ sessionID: String, closeAttemptID: String) async throws -> ObserverOwnerLifecycle {
        closeAttempts.append(closeAttemptID)
        switch mode {
        case .success:
            return lifecycle(state: "SUCCEEDED", attemptID: closeAttemptID, cleanupComplete: true)
        case .responseLostUnknown:
            if closeAttempts.count == 1 {
                throw ObserverOwnerControlError.transportOutcomeUnknown
            }
            return lifecycle(state: "SUCCEEDED", attemptID: closeAttemptID, cleanupComplete: true)
        }
    }

    func closeStatus(_ sessionID: String, closeAttemptID: String) async throws -> ObserverOwnerLifecycle {
        statusAttempts.append(closeAttemptID)
        return lifecycle(
            state: "OUTCOME_UNKNOWN",
            attemptID: closeAttemptID,
            cleanupComplete: false
        )
    }

    func attempts() -> ([String], [String]) { (closeAttempts, statusAttempts) }
}

@main
struct ObserverOwnerControlTests {
    static func main() async {
        do {
            _ = try ObserverOwnerControlConfiguration(
                baseURL: URL(string: "https://example.test")!,
                bearerToken: "obsw_unit_test",
                projectID: "vcw-acceptance"
            )
            expect(true, "obsw owner credential accepted")
        } catch {
            expect(false, "obsw owner credential accepted")
        }

        do {
            _ = try ObserverOwnerControlConfiguration(
                baseURL: URL(string: "https://example.test")!,
                bearerToken: "obsr_wrong_role",
                projectID: "vcw-acceptance"
            )
            expect(false, "obsr rejected by owner configuration")
        } catch {
            expect(true, "obsr rejected by owner configuration")
        }

        do {
            let listJSON = """
            {
              "contract_version": "observer.owner-control.v1",
              "project_id": "vcw-acceptance",
              "grant_id": "not-exposed-by-model",
              "approvals": [\(approvalJSON())]
            }
            """
            let stub = HTTPStub([.response(response(body: listJSON))])
            let config = try ObserverOwnerControlConfiguration(
                baseURL: URL(string: "https://example.test")!,
                bearerToken: "obsw_unit_test",
                projectID: "vcw-acceptance"
            )
            let client = ObserverOwnerControlClient(configuration: config, client: stub)
            let rows = try await client.pendingApprovals()
            expect(rows.count == 1 && rows[0].stateVersion == 1, "pending owner approval decoded")
            let requests = await stub.requests()
            expect(
                requests.first?.url?.path
                    == "/observer/v1/control/projects/vcw-acceptance/approvals",
                "owner pending route exact"
            )
            expect(
                requests.first?.value(forHTTPHeaderField: "Authorization")
                    == "Bearer obsw_unit_test",
                "owner request uses obsw bearer"
            )
            expect(requests.first?.value(forHTTPHeaderField: "Cookie") == nil, "owner request has no cookie")
        } catch {
            print("FAIL owner list sequence threw \(error)")
            failures += 1
        }

        do {
            let stub = HTTPStub([
                .response(response(body: wrapper(approvalJSON(state: "APPROVED", version: 2))))
            ])
            let config = try ObserverOwnerControlConfiguration(
                baseURL: URL(string: "https://example.test")!,
                bearerToken: "obsw_unit_test",
                projectID: "vcw-acceptance"
            )
            let client = ObserverOwnerControlClient(configuration: config, client: stub)
            let result = try await client.decideApproval(
                approvalID,
                decision: .allow,
                decisionAttemptID: "decision:stable-1",
                expectedStateVersion: 1
            )
            expect(result.state == "APPROVED" && result.stateVersion == 2, "allow returns authoritative state")
            let request = (await stub.requests()).first!
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            expect(body["decision"] as? String == "ALLOW", "decision body carries ALLOW")
            expect(body["decision_attempt_id"] as? String == "decision:stable-1", "stable decision attempt sent")
            expect(body["expected_state_version"] as? Int == 1, "CAS state version sent")
        } catch {
            print("FAIL decision wire sequence threw \(error)")
            failures += 1
        }

        do {
            let stub = HTTPStub([
                .response(response(
                    status: 409,
                    body: #"{"error":{"code":"VCW_ACCESS_APPROVAL_CONFLICT"}}"#
                ))
            ])
            let config = try ObserverOwnerControlConfiguration(
                baseURL: URL(string: "https://example.test")!,
                bearerToken: "obsw_unit_test",
                projectID: "vcw-acceptance"
            )
            let client = ObserverOwnerControlClient(configuration: config, client: stub)
            do {
                _ = try await client.decideApproval(
                    approvalID,
                    decision: .allow,
                    decisionAttemptID: "decision:conflict",
                    expectedStateVersion: 1
                )
                expect(false, "409 maps to CAS conflict")
            } catch ObserverOwnerControlError.conflict(let code) {
                expect(code == "VCW_ACCESS_APPROVAL_CONFLICT", "409 maps to CAS conflict")
            } catch {
                expect(false, "409 maps to CAS conflict")
            }
        } catch {
            print("FAIL conflict wire setup threw \(error)")
            failures += 1
        }

        do {
            let stub = HTTPStub([
                .response(response(
                    status: 401,
                    body: #"{"error":{"code":"OBSERVER_OWNER_AUTH_REVOKED"}}"#
                ))
            ])
            let config = try ObserverOwnerControlConfiguration(
                baseURL: URL(string: "https://example.test")!,
                bearerToken: "obsw_unit_test",
                projectID: "vcw-acceptance"
            )
            let client = ObserverOwnerControlClient(configuration: config, client: stub)
            do {
                _ = try await client.pendingApprovals()
                expect(false, "revoked owner token remains distinct auth failure")
            } catch ObserverOwnerControlError.authFailed(let code) {
                expect(code == "OBSERVER_OWNER_AUTH_REVOKED", "revoked owner token remains distinct auth failure")
            } catch {
                expect(false, "revoked owner token remains distinct auth failure")
            }
        } catch {
            print("FAIL owner auth setup threw \(error)")
            failures += 1
        }

        do {
            let coordinator = ObserverApprovalDecisionCoordinator()
            let service = ServiceStub(.conflict)
            let result = await coordinator.decide(
                approval: approval(),
                decision: .allow,
                decisionAttemptID: "decision:cas-1",
                client: service
            )
            if case .conflict(let fresh) = result {
                expect(fresh.state == "PENDING" && fresh.stateVersion == 2, "CAS conflict refetches authoritative state")
            } else {
                expect(false, "CAS conflict refetches authoritative state")
            }
            let counts = await service.counts()
            expect(counts.0 == 1 && counts.1 == 1, "CAS conflict never auto-replays Allow")
        }

        do {
            let coordinator = ObserverApprovalDecisionCoordinator()
            let service = ServiceStub(.unknownThenApproved)
            let result = await coordinator.decide(
                approval: approval(),
                decision: .allow,
                decisionAttemptID: "decision:unknown-1",
                client: service
            )
            if case .resolved(let fresh) = result {
                expect(fresh.state == "APPROVED", "response loss reconciles authoritative approval")
            } else {
                expect(false, "response loss reconciles authoritative approval")
            }
            let counts = await service.counts()
            expect(counts.0 == 1 && counts.1 == 1, "unknown response does not issue second POST")
        }

        do {
            let coordinator = ObserverApprovalDecisionCoordinator()
            let service = ServiceStub(.unknownStillPending)
            let result = await coordinator.decide(
                approval: approval(),
                decision: .deny,
                decisionAttemptID: "decision:unknown-2",
                client: service
            )
            if case .outcomeUnknown(let attempt, let lastKnown) = result {
                expect(attempt == "decision:unknown-2", "unknown result preserves same attempt identity")
                expect(lastKnown?.state == "PENDING", "unknown result keeps authoritative pending truth")
            } else {
                expect(false, "unknown result preserves same attempt identity")
            }
            let counts = await service.counts()
            expect(counts.0 == 1 && counts.1 == 1, "pending after response loss is not blindly retried")
        }

        do {
            let coordinator = ObserverSessionCloseCoordinator()
            let service = CloseServiceStub(.success)
            let sessionID = "s_" + String(repeating: "b", count: 32)
            let result = await coordinator.close(
                sessionID: sessionID,
                closeAttemptID: "close:success-1",
                client: service
            )
            if case .observed(let value) = result {
                expect(value.state == "SUCCEEDED", "close success returns authoritative lifecycle")
                expect(value.credentialRevoked && value.cleanupComplete, "close success proves revoke and cleanup separately")
            } else {
                expect(false, "close success returns authoritative lifecycle")
            }
        }

        do {
            let coordinator = ObserverSessionCloseCoordinator()
            let service = CloseServiceStub(.responseLostUnknown)
            let sessionID = "s_" + String(repeating: "b", count: 32)
            let attempt = "close:unknown-1"
            let first = await coordinator.close(
                sessionID: sessionID,
                closeAttemptID: attempt,
                client: service
            )
            if case .outcomeUnknown(let preserved, let value) = first {
                expect(preserved == attempt, "response loss preserves close attempt")
                expect(value?.credentialRevoked == true, "unknown lifecycle may prove credential revoked")
                expect(value?.cleanupComplete == false, "revoked never implies cleanup success")
            } else {
                expect(false, "response loss preserves close attempt")
            }
            let afterFirst = await service.attempts()
            expect(afterFirst.0 == [attempt], "response loss does not auto-repeat POST close")
            expect(afterFirst.1 == [attempt], "response loss checks same-attempt status")

            let reconciled = await coordinator.reconcileSameAttempt(
                sessionID: sessionID,
                closeAttemptID: attempt,
                client: service
            )
            if case .observed(let value) = reconciled {
                expect(value.state == "SUCCEEDED", "explicit reconcile may resume same close attempt")
            } else {
                expect(false, "explicit reconcile may resume same close attempt")
            }
            let afterReconcile = await service.attempts()
            expect(afterReconcile.0 == [attempt, attempt], "reconcile reuses exact close_attempt_id")
        }

        if failures > 0 {
            print("ObserverOwnerControlTests FAIL \(failures)")
            exit(1)
        }
        print("ObserverOwnerControlTests PASS")
    }
}
