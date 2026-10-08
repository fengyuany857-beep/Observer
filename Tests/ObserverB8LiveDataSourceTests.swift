import Foundation

private enum B8HTTPStubStep: Sendable {
    case response(ObserverHTTPResponse)
    case networkFailure
}

private actor B8HTTPStubClient: ObserverHTTPClient {
    private var steps: [B8HTTPStubStep]
    private var seen: [URLRequest] = []

    init(_ steps: [B8HTTPStubStep]) {
        self.steps = steps
    }

    func get(_ request: URLRequest) async throws -> ObserverHTTPResponse {
        seen.append(request)
        guard !steps.isEmpty else {
            throw URLError(.badServerResponse)
        }
        switch steps.removeFirst() {
        case .response(let response):
            return response
        case .networkFailure:
            throw URLError(.cannotConnectToHost)
        }
    }

    func requests() -> [URLRequest] { seen }
}

@main
struct ObserverB8LiveDataSourceTests {
    private static var checks = 0
    private static var failures = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !condition() {
            failures += 1
            print("FAIL \(name)")
        }
    }

    private static func configuration() throws -> ObserverTransportConfiguration {
        try ObserverTransportConfiguration(
            baseURL: URL(string: "https://observer.test")!,
            bearerToken: "obsr_b8_test_token",
            projectID: "vcw-acceptance",
            requestTimeout: 3
        )
    }

    private static func snapshotHeaders(
        generation: Int64,
        intent: ObserverB8ReadIntent,
        source: String = "vcw-store:test",
        revision: String = "rev-001",
        cursor: Int = 42,
        observedAt: TimeInterval = 1791358000
    ) -> [String: String] {
        [
            "X-Observer-Transport": ObserverB8Contract.transport,
            "X-Observer-Read-Contract": ObserverB8Contract.readPlane,
            "X-Observer-Source-Instance": source,
            "X-Observer-Snapshot-Revision": revision,
            "X-Observer-Event-Cursor": String(cursor),
            "X-Observer-Observed-At": String(observedAt),
            "X-Observer-Request-Generation": String(generation),
            "X-Observer-Read-Intent": intent.rawValue,
            "ETag": "\"\(revision)\"",
        ]
    }

    private static func snapshotResponse(
        generation: Int64,
        intent: ObserverB8ReadIntent,
        source: String = "vcw-store:test",
        revision: String = "rev-001",
        cursor: Int = 42
    ) -> ObserverHTTPResponse {
        let json = """
        {
          "contract_version": "observer.snapshot.v1",
          "source_instance_id": "\(source)",
          "snapshot_revision": "\(revision)",
          "observed_at": 1791358000,
          "authoritative_focus_task_id": null,
          "projects": [
            {"project_id": "vcw-acceptance", "display_name": "VCW Acceptance"}
          ],
          "sessions": [
            {
              "session_id": "s_live",
              "project_id": "vcw-acceptance",
              "state": "RUNNING",
              "state_class": "ACTIVE",
              "created_at": 1791356500,
              "expires_at": 1791358000,
              "started_at": 1791356510,
              "ended_at": null,
              "last_model_activity": 1791357990,
              "last_execution_activity": 1791357995,
              "failure_reason": null,
              "queue_position": null,
              "session_age_seconds": 1500,
              "execution_elapsed_seconds": 1490,
              "remaining_seconds": 0,
              "authority": {
                "origin": "DIRECT_GRANT",
                "approval_id": null,
                "requested_scope": "coding",
                "action_class": "CODING",
                "effect_class": "WORKSPACE_WRITE",
                "credential_state": "VALID",
                "credential_revoked_at": null,
                "credential_revocation_reason": null
              },
              "deadline": {
                "phase": "HARD_EXPIRED",
                "hard_ttl_seconds": 1500,
                "close_reminder_seconds": 90,
                "close_required_at": 1791357910,
                "expires_at": 1791358000,
                "elapsed_seconds": 1500,
                "remaining_seconds": 0,
                "close_required": false
              }
            }
          ],
          "heartbeats": [
            {
              "component": "gateway",
              "status": "ONLINE",
              "observed_at": 1791357999,
              "detail": {},
              "age_seconds": 1,
              "freshness": "FRESH"
            }
          ],
          "effects": [],
          "events": [],
          "event_cursor": \(cursor),
          "authority": {
            "contract_version": "observer.authority.v1",
            "approvals": [
              {
                "approval_id": "ap-1",
                "project_id": "vcw-acceptance",
                "requester_principal": "gpt",
                "requested_scope": "coding",
                "action_class": "CODING",
                "effect_class": "WORKSPACE_WRITE",
                "state": "APPROVED",
                "state_version": 2,
                "created_at": 1791356400,
                "expires_at": 1791357000,
                "decided_at": 1791356410,
                "consumed_session_id": "s_live",
                "consumed_at": 1791356420,
                "reason": null,
                "authority": "ACCESS_APPROVAL_LEDGER"
              }
            ],
            "lifecycle_operations": []
          },
          "availability": {
            "tests_summary": "UNAVAILABLE_AGGREGATE",
            "checkpoint": "UNAVAILABLE",
            "artifact": "UNAVAILABLE",
            "presentation": "UNKNOWN",
            "logs": "SESSION_JOB_TAIL_ONLY"
          }
        }
        """
        return ObserverHTTPResponse(
            statusCode: 200,
            headers: snapshotHeaders(
                generation: generation,
                intent: intent,
                source: source,
                revision: revision,
                cursor: cursor
            ),
            data: Data(json.utf8)
        )
    }

    private static func notModifiedResponse(
        generation: Int64,
        intent: ObserverB8ReadIntent,
        cursor: Int = 42
    ) -> ObserverHTTPResponse {
        ObserverHTTPResponse(
            statusCode: 304,
            headers: snapshotHeaders(
                generation: generation,
                intent: intent,
                cursor: cursor,
                observedAt: 1791358002
            ),
            data: Data()
        )
    }

    private static func operationsResponse(
        generation: Int64,
        intent: ObserverB8ReadIntent,
        source: String = "vcw-store:test",
        withOperation: Bool = true
    ) -> ObserverHTTPResponse {
        let operations = withOperation
            ? """
              [{
                "operation_id": "op-1",
                "session_id": "s_live",
                "project_id": "vcw-acceptance",
                "kind": "TOOL",
                "name": "Write file",
                "started_at": 1791357998,
                "currentness": "CURRENT",
                "authority": "GATEWAY_IN_FLIGHT_CALL",
                "freshness": "CURRENT_PROCESS"
              }]
              """
            : "[]"
        let json = """
        {
          "contract_version": "observer.operations.v1",
          "source_instance_id": "\(source)",
          "authority_instance_id": "opreg-test",
          "project_id": "vcw-acceptance",
          "session_id": null,
          "availability": "AVAILABLE",
          "observed_at": 1791358001,
          "operations": \(operations)
        }
        """
        let headers: [String: String] = [
            "X-Observer-Transport": ObserverB8Contract.transport,
            "X-Observer-Read-Contract": ObserverB8Contract.readPlane,
            "X-Observer-Source-Instance": source,
            "X-Observer-Observed-At": "1791358001",
            "X-Observer-Request-Generation": String(generation),
            "X-Observer-Read-Intent": intent.rawValue,
        ]
        return ObserverHTTPResponse(
            statusCode: 200,
            headers: headers,
            data: Data(json.utf8)
        )
    }

    private static func jobsResponse(
        generation: Int64,
        intent: ObserverB8ReadIntent,
        source: String = "vcw-store:test",
        gatewayState: String = "RUNNING",
        stateClass: String = "LAST_OBSERVED_ACTIVE"
    ) -> ObserverHTTPResponse {
        let json = """
        {
          "contract_version": "observer.jobs.v1",
          "source_instance_id": "\(source)",
          "project_id": "vcw-acceptance",
          "session_id": null,
          "availability": "AVAILABLE",
          "jobs": [{
            "job_id": "job-1",
            "session_id": "s_live",
            "project_id": "vcw-acceptance",
            "gateway_state": "\(gatewayState)",
            "state_class": "\(stateClass)",
            "heavy": false,
            "created_at": 1791357900,
            "updated_at": 1791357999,
            "authority": "GATEWAY_JOB_REGISTRY",
            "freshness": "LAST_OBSERVED"
          }]
        }
        """
        let headers: [String: String] = [
            "X-Observer-Transport": ObserverB8Contract.transport,
            "X-Observer-Read-Contract": ObserverB8Contract.readPlane,
            "X-Observer-Source-Instance": source,
            "X-Observer-Observed-At": "1791358001",
            "X-Observer-Request-Generation": String(generation),
            "X-Observer-Read-Intent": intent.rawValue,
        ]
        return ObserverHTTPResponse(
            statusCode: 200,
            headers: headers,
            data: Data(json.utf8)
        )
    }

    static func main() async {
        do {
            let client = B8HTTPStubClient([
                .response(snapshotResponse(generation: 1, intent: .reconnectBaseline)),
                .response(operationsResponse(generation: 2, intent: .reconnectBaseline)),
                .response(jobsResponse(generation: 3, intent: .reconnectBaseline)),
            ])
            let source = ObserverB8LiveDataSource(
                configuration: try configuration(),
                client: client
            )
            let result = try await source.load(intent: .reconnectBaseline)

            expect(result.disposition == .accepted, "baseline accepted")
            expect(result.envelope?.snapshot.provenance == .live, "baseline is live")
            expect(result.envelope?.backendTruth?.transportLive == true, "truth transport live")
            expect(
                result.envelope?.backendTruth?.sessions.first?.deadline.matchesFrozenConstants == true,
                "deadline is frozen 1500/90"
            )
            expect(
                result.envelope?.backendTruth?.approvals.first?.approvalID == "ap-1",
                "approval truth decoded"
            )
            expect(
                result.envelope?.backendTruth?.currentOperation(for: "s_live")?.operationID == "op-1",
                "CURRENT operation comes from operations plane"
            )
            expect(
                result.envelope?.snapshot.runs.first?.currentOperation?.name == "Write file",
                "CURRENT operation projected into existing UI"
            )
            expect(
                result.envelope?.backendTruth?.jobs.first?.jobID == "job-1"
                    && result.envelope?.backendTruth?.jobs.first?.isLastObservedActive == true,
                "Job truth comes from observer.jobs.v1 as LAST_OBSERVED_ACTIVE"
            )

            let requests = await client.requests()
            expect(requests.count == 3, "baseline uses snapshot plus operations plus jobs")
            expect(
                requests.first?.value(forHTTPHeaderField: "X-Observer-Request-Generation") == "1",
                "generation header sent"
            )
            expect(
                requests[1].value(forHTTPHeaderField: "X-Observer-Request-Generation") == "2",
                "operations receives a distinct next generation"
            )
            expect(
                requests[2].value(forHTTPHeaderField: "X-Observer-Request-Generation") == "3",
                "jobs receives the final accepted generation"
            )
            expect(
                requests.first?.value(forHTTPHeaderField: "X-Observer-Read-Intent")
                    == ObserverB8ReadIntent.reconnectBaseline.rawValue,
                "intent header sent"
            )
            expect(
                requests.first?.value(forHTTPHeaderField: "If-None-Match") == nil,
                "reconnect baseline bypasses ETag"
            )
        } catch {
            print("FAIL baseline sequence threw \(error)")
            failures += 1
        }

        do {
            let client = B8HTTPStubClient([
                .response(snapshotResponse(generation: 1, intent: .reconnectBaseline)),
                .response(operationsResponse(generation: 2, intent: .reconnectBaseline)),
                .response(jobsResponse(generation: 3, intent: .reconnectBaseline)),
                .response(notModifiedResponse(generation: 4, intent: .poll)),
                .response(operationsResponse(generation: 5, intent: .poll, withOperation: false)),
                .response(jobsResponse(generation: 6, intent: .poll, gatewayState: "SUCCEEDED", stateClass: "TERMINAL_CONFIRMED")),
            ])
            let source = ObserverB8LiveDataSource(
                configuration: try configuration(),
                client: client
            )
            _ = try await source.load(intent: .reconnectBaseline)
            let result = try await source.load(intent: .poll)

            expect(result.disposition == .notModified, "304 accepted for latest generation")
            expect(result.envelope?.backendTruth?.transportLive == true, "304 keeps transport live")
            expect(
                result.envelope?.backendTruth?.currentOperation(for: "s_live") == nil,
                "304 still refreshes operations and clears ended in-flight call"
            )
            expect(
                result.envelope?.backendTruth?.jobs.first?.stateClass == "TERMINAL_CONFIRMED",
                "304 also refreshes last-observed Job truth"
            )

            let requests = await client.requests()
            expect(
                requests[3].value(forHTTPHeaderField: "If-None-Match") == "\"rev-001\"",
                "poll sends prior ETag"
            )
            expect(
                requests.map { $0.value(forHTTPHeaderField: "X-Observer-Request-Generation") ?? "" }
                    == ["1", "2", "3", "4", "5", "6"],
                "every snapshot/operation/job read advances generation monotonically"
            )
        } catch {
            print("FAIL 304 sequence threw \(error)")
            failures += 1
        }

        do {
            let client = B8HTTPStubClient([
                .response(snapshotResponse(generation: 1, intent: .reconnectBaseline)),
                .networkFailure,
            ])
            let source = ObserverB8LiveDataSource(
                configuration: try configuration(),
                client: client
            )
            let failed = try await source.load(intent: .reconnectBaseline)

            expect(
                failed.disposition == .transportFailure,
                "operations failure after snapshot is not misclassified as superseded"
            )
            let requests = await client.requests()
            expect(
                requests.map { $0.value(forHTTPHeaderField: "X-Observer-Request-Generation") ?? "" }
                    == ["1", "2"],
                "failed operations request owns generation 2"
            )
        } catch {
            print("FAIL operations-failure ownership sequence threw \(error)")
            failures += 1
        }

        do {
            let client = B8HTTPStubClient([
                .response(snapshotResponse(generation: 1, intent: .reconnectBaseline)),
                .response(operationsResponse(generation: 2, intent: .reconnectBaseline)),
                .response(jobsResponse(generation: 3, intent: .reconnectBaseline)),
                .response(notModifiedResponse(generation: 4, intent: .poll)),
                .networkFailure,
            ])
            let source = ObserverB8LiveDataSource(
                configuration: try configuration(),
                client: client
            )
            _ = try await source.load(intent: .reconnectBaseline)
            let failed = try await source.load(intent: .poll)

            expect(
                failed.disposition == .transportFailure,
                "304 operations failure is not misclassified as superseded"
            )
            expect(
                failed.envelope?.backendTruth?.transportLive == false,
                "304 operations failure invalidates live transport truth"
            )
            expect(
                failed.envelope?.backendTruth?.currentOperation(for: "s_live") == nil,
                "304 operations failure suppresses stale CURRENT operation"
            )
            let requests = await client.requests()
            expect(
                requests.map { $0.value(forHTTPHeaderField: "X-Observer-Request-Generation") ?? "" }
                    == ["1", "2", "3", "4", "5"],
                "304 failed operations request owns generation 5"
            )
        } catch {
            print("FAIL 304 operations-failure ownership sequence threw \(error)")
            failures += 1
        }

        do {
            let client = B8HTTPStubClient([
                .response(snapshotResponse(generation: 1, intent: .reconnectBaseline)),
                .response(operationsResponse(generation: 2, intent: .reconnectBaseline)),
                .networkFailure,
            ])
            let source = ObserverB8LiveDataSource(
                configuration: try configuration(),
                client: client
            )
            let failed = try await source.load(intent: .reconnectBaseline)
            expect(failed.disposition == .transportFailure, "jobs failure rejects partial baseline")
            let requests = await client.requests()
            expect(
                requests.map { $0.value(forHTTPHeaderField: "X-Observer-Request-Generation") ?? "" }
                    == ["1", "2", "3"],
                "failed jobs request owns generation 3"
            )
        } catch {
            print("FAIL jobs-failure ownership sequence threw \(error)")
            failures += 1
        }

        do {
            let client = B8HTTPStubClient([
                .response(snapshotResponse(generation: 1, intent: .reconnectBaseline)),
                .response(operationsResponse(generation: 2, intent: .reconnectBaseline)),
                .response(jobsResponse(generation: 3, intent: .reconnectBaseline)),
                .response(notModifiedResponse(generation: 4, intent: .poll)),
                .response(operationsResponse(generation: 5, intent: .poll, withOperation: false)),
                .networkFailure,
            ])
            let source = ObserverB8LiveDataSource(
                configuration: try configuration(),
                client: client
            )
            _ = try await source.load(intent: .reconnectBaseline)
            let failed = try await source.load(intent: .poll)
            expect(failed.disposition == .transportFailure, "304 jobs failure rejects partial refresh")
            expect(failed.envelope?.backendTruth?.transportLive == false, "304 jobs failure demotes live truth")
            expect(failed.envelope?.backendTruth?.jobs.first?.jobID == "job-1", "last-good Job history retained")
            expect(failed.envelope?.backendTruth?.currentOperation(for: "s_live") == nil, "304 jobs failure clears CURRENT")
            let requests = await client.requests()
            expect(
                requests.map { $0.value(forHTTPHeaderField: "X-Observer-Request-Generation") ?? "" }
                    == ["1", "2", "3", "4", "5", "6"],
                "304 failed jobs request owns generation 6"
            )
        } catch {
            print("FAIL 304 jobs-failure ownership sequence threw \(error)")
            failures += 1
        }

        do {
            let client = B8HTTPStubClient([
                .response(snapshotResponse(generation: 1, intent: .reconnectBaseline)),
                .response(operationsResponse(generation: 2, intent: .reconnectBaseline)),
                .response(jobsResponse(generation: 3, intent: .reconnectBaseline)),
                .networkFailure,
            ])
            let source = ObserverB8LiveDataSource(
                configuration: try configuration(),
                client: client
            )
            _ = try await source.load(intent: .reconnectBaseline)
            let offline = try await source.load(intent: .poll)

            expect(offline.disposition == .transportFailure, "transport failure surfaced")
            expect(offline.envelope?.snapshot.provenance == .cached, "offline uses cached history")
            expect(offline.envelope?.backendTruth?.transportLive == false, "offline truth non-live")
            expect(
                offline.envelope?.snapshot.runs.first?.currentOperation == nil,
                "offline suppresses CURRENT operation in presentation"
            )
            expect(
                offline.envelope?.backendTruth?.currentOperation(for: "s_live") == nil,
                "offline suppresses CURRENT operation in truth layer"
            )
        } catch {
            print("FAIL offline sequence threw \(error)")
            failures += 1
        }

        do {
            let client = B8HTTPStubClient([
                .response(snapshotResponse(generation: 1, intent: .reconnectBaseline)),
                .response(operationsResponse(generation: 2, intent: .reconnectBaseline)),
                .response(jobsResponse(generation: 3, intent: .reconnectBaseline)),
                .networkFailure,
            ])
            let source = ObserverB8LiveDataSource(
                configuration: try configuration(),
                client: client
            )
            _ = try await source.load(intent: .reconnectBaseline)
            let offline = try await source.load(intent: .poll)
            expect(offline.envelope?.snapshot.provenance == .cached, "fixture is cached before operation-only gate")

            let guarded = try await source.refreshCurrentOperations(intent: .poll)
            expect(
                guarded.disposition == .requiresReconnectBaseline,
                "operation-only refresh cannot resurrect cached snapshot as live"
            )
            expect(guarded.requiresFullSnapshot, "cached operation-only path requests full snapshot")
            let requests = await client.requests()
            expect(requests.count == 4, "cached operation-only guard performs no additional request")
        } catch {
            print("FAIL cached operation-only gate sequence threw \(error)")
            failures += 1
        }

        do {
            let client = B8HTTPStubClient([
                .response(snapshotResponse(generation: 1, intent: .reconnectBaseline)),
                .response(operationsResponse(generation: 2, intent: .reconnectBaseline)),
                .response(jobsResponse(generation: 3, intent: .reconnectBaseline)),
                .response(
                    snapshotResponse(
                        generation: 4,
                        intent: .poll,
                        source: "vcw-store:restarted",
                        revision: "rev-002",
                        cursor: 1
                    )
                ),
            ])
            let source = ObserverB8LiveDataSource(
                configuration: try configuration(),
                client: client
            )
            _ = try await source.load(intent: .reconnectBaseline)
            let changed = try await source.load(intent: .poll)

            expect(
                changed.disposition == .requiresReconnectBaseline,
                "source change requires reconnect baseline"
            )
            expect(changed.requiresFullSnapshot, "source change requests full snapshot")
            expect(changed.envelope?.backendTruth?.transportLive == false, "old truth invalidated")
            expect(
                changed.envelope?.snapshot.runs.first?.currentOperation == nil,
                "source change suppresses stale CURRENT operation"
            )
        } catch {
            print("FAIL source-change sequence threw \(error)")
            failures += 1
        }

        do {
            _ = try ObserverTransportConfiguration(
                baseURL: URL(string: "https://observer.test")!,
                bearerToken: "obsw_wrong_role",
                projectID: "vcw-acceptance"
            )
            expect(false, "owner token must not enter read plane")
        } catch let error as ObserverTransportError {
            expect(
                error == .invalidConfiguration("TOKEN_INVALID"),
                "obsw_ rejected by read configuration"
            )
        } catch {
            expect(false, "unexpected token-role error")
        }

        print("Observer B8 live datasource tests: checks=\(checks) pass=\(checks - failures) fail=\(failures)")
        if failures > 0 {
            exit(1)
        }
    }
}
