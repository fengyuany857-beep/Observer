import Foundation

@main
struct DTOContractTest {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() throws {
        let json = """
        {
          "contract_version":"observer.snapshot.v1",
          "source_instance_id":"vcw-store:test-lineage",
          "snapshot_revision":"abc123",
          "observed_at":1000,
          "authoritative_focus_task_id":null,
          "projects":[{"project_id":"p1","display_name":"Project 1"}],
          "sessions":[{
            "session_id":"s1","project_id":"p1","state":"RECONCILE","state_class":"ACTIVE",
            "created_at":900,"started_at":920,"ended_at":null,"expires_at":1200,
            "last_model_activity":980,"last_execution_activity":990,"failure_reason":"readback pending",
            "queue_position":null,"session_age_seconds":100,"execution_elapsed_seconds":80,"remaining_seconds":200
          }],
          "heartbeats":[{"component":"runner","status":"ONLINE","observed_at":990,"age_seconds":10,"freshness":"FRESH","detail":{}}],
          "effects":[{
            "effect_id":"effect-1234567890","task_id":"task-1","project_id":"p1",
            "state":"OUTCOME_UNKNOWN","state_known":true,"generation":3,
            "created_at":"2026-10-05T00:00:00Z","updated_at":"2026-10-05T00:01:00Z",
            "receipt":null,"last_error_code":"VCW_EFFECT_READBACK_INCONCLUSIVE"
          }],
          "events":[{
            "source_instance_id":"vcw-store:test-lineage","event_id":7,
            "event_identity":"vcw-store:test-lineage:7","event_type":"effect_reconciling",
            "created_at":995,"session_id":"s1","project_id":"p1","source":"gateway",
            "authoritative":false,"payload":{"generation":3}
          }],
          "event_cursor":7,
          "availability":{
            "tests_summary":"UNAVAILABLE_AGGREGATE","checkpoint":"UNAVAILABLE",
            "artifact":"UNAVAILABLE","presentation":"UNKNOWN","logs":"SESSION_JOB_TAIL_ONLY"
          }
        }
        """
        let dto = try JSONDecoder().decode(VCWObserverSnapshotDTO.self, from: Data(json.utf8))
        expect(dto.contractVersion == "observer.snapshot.v1", "contract version")
        expect(dto.authoritativeFocusTaskID == nil, "focus remains nil")
        expect(dto.sessions.first?.state == "RECONCILE", "raw session state preserved")
        expect(dto.effects.first?.state == "OUTCOME_UNKNOWN", "effect truth preserved")
        expect(dto.events.first?.authoritative == false, "event authority preserved")
        expect(dto.availability.presentation == "UNKNOWN", "presentation remains unknown")
        expect(dto.eventCursor == 7, "event cursor")
        print("VCWObserverProjectionDTO contract PASS")
    }
}
