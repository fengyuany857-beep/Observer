import Foundation

private enum StubStep: Sendable {
    case response(ObserverHTTPResponse)
    case networkFailure
}

private actor StubHTTPClient: ObserverHTTPClient {
    private var steps: [StubStep]
    private var seenAuthorization: [String?] = []
    private var seenURLs: [String] = []

    init(_ steps: [StubStep]) {
        self.steps = steps
    }

    func get(_ request: URLRequest) async throws -> ObserverHTTPResponse {
        seenAuthorization.append(request.value(forHTTPHeaderField: "Authorization"))
        seenURLs.append(request.url?.absoluteString ?? "")
        guard !steps.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let step = steps.removeFirst()
        switch step {
        case .response(let response):
            return response
        case .networkFailure:
            throw URLError(.cannotConnectToHost)
        }
    }

    func lastAuthorization() -> String? {
        seenAuthorization.last ?? nil
    }

    func lastURL() -> String? {
        seenURLs.last
    }
}

@main
struct ObserverTransportDataSourceTests {
    private static var checks = 0
    private static var failures = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !condition() {
            failures += 1
            print("FAIL \(name)")
        }
    }

    private static func snapshotResponse(
        contract: String = "observer.snapshot.v1",
        sessionState: String = "RUNNING",
        heartbeatsJSON: String = "[]"
    ) -> ObserverHTTPResponse {
        let json = """
        {
          "contract_version": "\(contract)",
          "source_instance_id": "vcw-store:abc123",
          "snapshot_revision": "rev-001",
          "observed_at": 1791151200.0,
          "authoritative_focus_task_id": null,
          "projects": [
            {
              "project_id": "vcw-acceptance",
              "display_name": "VCW Acceptance"
            }
          ],
          "sessions": [
            {
              "session_id": "session-live-1",
              "project_id": "vcw-acceptance",
              "state": "\(sessionState)",
              "state_class": "ACTIVE",
              "created_at": 1791150000.0,
              "expires_at": 1791153000.0,
              "started_at": 1791150100.0,
              "ended_at": null,
              "last_model_activity": 1791151190.0,
              "last_execution_activity": 1791151195.0,
              "failure_reason": null,
              "queue_position": null,
              "session_age_seconds": 1200.0,
              "execution_elapsed_seconds": 1100.0,
              "remaining_seconds": 1800.0
            }
          ],
          "heartbeats": \(heartbeatsJSON),
          "effects": [],
          "events": [],
          "event_cursor": 672,
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
            headers: ["X-Observer-Transport": "observer.transport.v1"],
            data: Data(json.utf8)
        )
    }

    private static func errorResponse(
        status: Int,
        code: String
    ) -> ObserverHTTPResponse {
        let json = "{\"error\":{\"code\":\"\(code)\"}}"
        return ObserverHTTPResponse(
            statusCode: status,
            headers: ["x-observer-transport": "observer.transport.v1"],
            data: Data(json.utf8)
        )
    }

    private static func configuration(token: String = "obsr_unit_test_token") throws
        -> ObserverTransportConfiguration
    {
        try ObserverTransportConfiguration(
            baseURL: URL(string: "https://observer.test")!,
            bearerToken: token,
            projectID: "vcw-acceptance",
            requestTimeout: 3
        )
    }

    static func main() async {
        do {
            _ = try ObserverTransportConfiguration(
                baseURL: URL(string: "http://observer.test")!,
                bearerToken: "obsr_unit_test_token",
                projectID: "vcw-acceptance"
            )
            expect(false, "HTTP configuration must be rejected")
        } catch let error as ObserverTransportError {
            expect(
                error == .invalidConfiguration("HTTPS_REQUIRED"),
                "HTTPS-only configuration gate"
            )
        } catch {
            expect(false, "unexpected HTTP configuration error")
        }

        do {
            let client = StubHTTPClient([.response(snapshotResponse())])
            let source = RealObserverDataSource(
                configuration: try configuration(),
                client: client
            )
            let envelope = try await source.load()

            expect(envelope.snapshot.connectionState == .online, "live snapshot online")
            expect(envelope.snapshot.provenance == .live, "live snapshot provenance")
            expect(envelope.snapshot.runs.count == 1, "one live run decoded")
            if let run = envelope.snapshot.runs.first {
                expect(run.runID == "session-live-1", "session identity preserved")
                expect(run.projectID == "vcw-acceptance", "project identity preserved")
                expect(run.projectName == "VCW Acceptance", "display name preserved")
                expect(run.executionStatus == .running, "RUNNING safely mapped")
                expect(run.directorTruth == nil, "session truth not forged as Director truth")
                expect(run.runtimeHealth == .unknown, "health remains unknown without binding")
                expect(run.runtimePhase == .unknown, "phase remains unknown without binding")
                expect(run.bundle.status == .unknown, "artifact remains unknown when unavailable")
                expect(run.presentationStatus == .unknown, "presentation remains unknown")
                expect(run.tests.total == 0, "unavailable aggregate does not fabricate tests")
            }

            expect(
                envelope.systemHealth?.isEmpty == true,
                "empty heartbeat set remains explicit empty system telemetry"
            )
            expect(
                envelope.snapshot.runs.first?.runtimeHealth == .unknown,
                "empty component telemetry does not fabricate run health"
            )

            expect(
                envelope.transportMetadata?.sourceInstanceID == "vcw-store:abc123",
                "source instance preserved"
            )
            expect(
                envelope.transportMetadata?.snapshotRevision == "rev-001",
                "snapshot revision preserved"
            )
            expect(
                envelope.transportMetadata?.eventCursor == 672,
                "event cursor preserved"
            )
            expect(
                envelope.transportMetadata?.availability["artifact"] == "UNAVAILABLE",
                "artifact availability preserved"
            )
            expect(
                envelope.transportMetadata?.rawSessionStates["session-live-1"] == "RUNNING",
                "raw session state preserved"
            )

            let authorization = await client.lastAuthorization()
            let lastURL = await client.lastURL()
            expect(
                authorization == "Bearer obsr_unit_test_token",
                "bearer credential sent only as header"
            )
            expect(
                lastURL?.contains("obsr_unit_test_token") == false,
                "bearer credential absent from URL"
            )
            expect(
                lastURL?.contains("project_id=vcw-acceptance") == true,
                "project scope is explicit in request"
            )
        } catch {
            print("FAIL live decode threw \(error)")
            failures += 1
        }

        do {
            let heartbeats = """
            [
              {
                "component": "gateway",
                "status": "HEALTHY",
                "observed_at": 1791151198.0,
                "detail": {"source": "gateway"},
                "age_seconds": 2.0,
                "freshness": "FRESH"
              },
              {
                "component": "runner",
                "status": "FUTURE_STATUS",
                "observed_at": 1791151180.0,
                "detail": {"source": "runner"},
                "age_seconds": 20.0,
                "freshness": "FUTURE_FRESHNESS"
              }
            ]
            """
            let client = StubHTTPClient([
                .response(snapshotResponse(heartbeatsJSON: heartbeats))
            ])
            let source = RealObserverDataSource(
                configuration: try configuration(),
                client: client
            )
            let envelope = try await source.load()
            let components = envelope.systemHealth?.components ?? []

            expect(envelope.systemHealth?.provenance == .live, "component health live provenance")
            expect(envelope.systemHealth?.observedAt == envelope.snapshot.observedAt, "component health shares source observation time")
            expect(components.count == 2, "component heartbeats decoded separately")
            expect(components.first?.component == "gateway", "component health ordering is deterministic")
            expect(components.first?.status == "HEALTHY", "known component status preserved raw")
            expect(components.first?.freshness == "FRESH", "component freshness preserved raw")
            expect(components.last?.status == "FUTURE_STATUS", "future component status preserved losslessly")
            expect(components.last?.freshness == "FUTURE_FRESHNESS", "future freshness preserved losslessly")
            expect(envelope.snapshot.runs.first?.runtimeHealth == .unknown, "component health does not overwrite run health")
            expect(envelope.snapshot.connectionState == .online, "component health does not overwrite transport connection state")
        } catch {
            print("FAIL component-health decode threw \(error)")
            failures += 1
        }

        do {
            let client = StubHTTPClient([.response(snapshotResponse(sessionState: "STOPPING"))])
            let source = RealObserverDataSource(
                configuration: try configuration(),
                client: client
            )
            let envelope = try await source.load()
            expect(
                envelope.snapshot.runs.first?.executionStatus == .unknown,
                "STOPPING is not flattened into a false legacy state"
            )
            expect(
                envelope.transportMetadata?.rawSessionStates["session-live-1"] == "STOPPING",
                "STOPPING raw truth remains available"
            )
        } catch {
            print("FAIL STOPPING mapping threw \(error)")
            failures += 1
        }

        do {
            let cache = ObserverLastGoodCache()
            let client = StubHTTPClient([
                .response(snapshotResponse()),
                .response(errorResponse(status: 401, code: "OBSERVER_READ_AUTH_EXPIRED"))
            ])
            let source = RealObserverDataSource(
                configuration: try configuration(),
                client: client,
                cache: cache
            )
            let first = try await source.load()
            let second = try await source.load()
            expect(first.snapshot.provenance == .live, "first auth sequence is live")
            expect(second.snapshot.connectionState == .authFailed, "401 becomes auth failed")
            expect(second.snapshot.provenance == .cached, "401 serves last-good cache")
            expect(
                second.snapshot.runs.first?.runID == first.snapshot.runs.first?.runID,
                "auth failure does not mutate cached execution truth"
            )
            expect(
                second.snapshot.lastSyncAt == first.snapshot.lastSyncAt,
                "cached lastSync remains last successful sync"
            )
        } catch {
            print("FAIL auth-cache sequence threw \(error)")
            failures += 1
        }

        do {
            let cache = ObserverLastGoodCache()
            let heartbeats = """
            [
              {
                "component": "gateway",
                "status": "HEALTHY",
                "observed_at": 1791151198.0,
                "detail": {},
                "age_seconds": 2.0,
                "freshness": "FRESH"
              }
            ]
            """
            let client = StubHTTPClient([
                .response(snapshotResponse(heartbeatsJSON: heartbeats)),
                .networkFailure
            ])
            let source = RealObserverDataSource(
                configuration: try configuration(),
                client: client,
                cache: cache
            )
            _ = try await source.load()
            let cached = try await source.load()
            expect(
                cached.snapshot.connectionState == .serverUnreachable,
                "network failure becomes server unreachable"
            )
            expect(cached.snapshot.provenance == .cached, "network failure serves cache")
            expect(cached.systemHealth?.provenance == .cached, "cached system health is marked cached")
            expect(cached.systemHealth?.components.first?.status == "HEALTHY", "cached component evidence is preserved without becoming live")
        } catch {
            print("FAIL network-cache sequence threw \(error)")
            failures += 1
        }

        do {
            let client = StubHTTPClient([
                .response(
                    ObserverHTTPResponse(
                        statusCode: 200,
                        headers: ["X-Observer-Transport": "observer.transport.v999"],
                        data: snapshotResponse().data
                    )
                )
            ])
            let source = RealObserverDataSource(
                configuration: try configuration(),
                client: client
            )
            _ = try await source.load()
            expect(false, "transport contract mismatch must fail")
        } catch let error as ObserverTransportError {
            if case .contractMismatch(let expected, let actual) = error {
                expect(expected == "observer.transport.v1", "transport expected version")
                expect(actual == "observer.transport.v999", "transport actual version")
            } else {
                expect(false, "wrong transport mismatch error")
            }
        } catch {
            expect(false, "unexpected transport mismatch error")
        }

        do {
            let client = StubHTTPClient([
                .response(snapshotResponse(contract: "observer.snapshot.v999"))
            ])
            let source = RealObserverDataSource(
                configuration: try configuration(),
                client: client
            )
            _ = try await source.load()
            expect(false, "snapshot contract mismatch must fail")
        } catch let error as ObserverTransportError {
            if case .contractMismatch(let expected, let actual) = error {
                expect(expected == "observer.snapshot.v1", "snapshot expected version")
                expect(actual == "observer.snapshot.v999", "snapshot actual version")
            } else {
                expect(false, "wrong snapshot mismatch error")
            }
        } catch {
            expect(false, "unexpected snapshot mismatch error")
        }

        print("checks=\(checks) pass=\(checks-failures) fail=\(failures)")
        if failures > 0 {
            exit(1)
        }
    }
}