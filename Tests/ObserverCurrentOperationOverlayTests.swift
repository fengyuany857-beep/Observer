import Foundation

@main
struct ObserverCurrentOperationOverlayTests {
    private static var checks = 0
    private static var failures = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !condition() {
            failures += 1
            print("FAIL \(name)")
        }
    }

    private static func run(
        id: String,
        status: ExecutionStatus,
        endedAt: Date? = nil
    ) -> RunStatusSnapshot {
        RunStatusSnapshot(
            runID: id,
            projectID: "project-a",
            projectName: "Project A",
            executionStatus: status,
            runtimeHealth: .unknown,
            runtimePhase: .unknown,
            stage: nil,
            currentOperation: nil,
            elapsedMS: 1000,
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: endedAt,
            heartbeats: .init(runLastSeen: nil, toolLastSeen: nil, relayLastSeen: nil),
            tests: .init(total: 0, completed: 0, passed: 0, failed: 0, skipped: 0),
            checkpoint: .init(latestID: nil, status: nil, createdAt: nil),
            bundle: .init(status: .unknown, id: nil),
            presentationStatus: .unknown,
            lastEvent: nil,
            updatedAt: Date(timeIntervalSince1970: 20)
        )
    }

    static func main() {
        let running = run(id: "run-a", status: .running)
        let terminal = run(
            id: "run-b",
            status: .completed,
            endedAt: Date(timeIntervalSince1970: 30)
        )
        let snapshot = ObserverSnapshot(
            connectionState: .online,
            authoritativeFocusRunID: "run-a",
            runs: [running, terminal],
            observedAt: Date(timeIntervalSince1970: 40),
            lastSyncAt: Date(timeIntervalSince1970: 40),
            provenance: .live
        )
        let operation = OperationSnapshot(
            kind: "TOOL",
            name: "Run shell command",
            startedAt: Date(timeIntervalSince1970: 39)
        )

        let applied = ObserverCurrentOperationOverlay.applying(
            ["run-a": operation, "run-b": operation],
            to: snapshot
        )
        expect(applied.runs[0].currentOperation == operation, "running run receives current operation")
        expect(applied.runs[1].currentOperation == nil, "terminal run rejects current operation")
        expect(applied.provenance == .live, "snapshot provenance preserved")
        expect(applied.observedAt == snapshot.observedAt, "snapshot observation time preserved")

        let cleared = ObserverCurrentOperationOverlay.clearing(applied)
        expect(cleared.runs.allSatisfy { $0.currentOperation == nil }, "clearing removes all current operations")
        expect(cleared.authoritativeFocusRunID == snapshot.authoritativeFocusRunID, "focus identity preserved")

        print("operation_overlay_checks=\(checks) pass=\(checks-failures) fail=\(failures)")
        if failures > 0 { exit(1) }
    }
}
