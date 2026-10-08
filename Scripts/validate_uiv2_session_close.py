#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
owner = (root / "Sources/Domain/ObserverOwnerControl.swift").read_text()
shell = (root / "Sources/SwiftUI/ObserverLiveShell.swift").read_text()
view = (root / "Sources/SwiftUI/ProjectDetailLiveView.swift").read_text()
tests = (root / "Tests/ObserverOwnerControlTests.swift").read_text()
freeze = (root / "Reference/B8/observer-backend-contract-freeze-v1.json").read_text()

checks = {
    "frozen-close-post-route": '"path": "/observer/v1/control/sessions/{session_id}/close"' in freeze,
    "frozen-close-status-route": '"path": "/observer/v1/control/sessions/{session_id}/close/{close_attempt_id}"' in freeze,
    "frozen-close-body": '"body_exact": ["close_attempt_id"]' in freeze,
    "lifecycle-dto": "public struct ObserverOwnerLifecycle" in owner
        and 'case cleanupComplete = "cleanup_complete"' in owner
        and 'case credentialRevoked = "credential_revoked"' in owner,
    "close-post-route": r'path: "/observer/v1/control/sessions/\(sessionID)/close"' in owner,
    "close-status-route": r'path: "/observer/v1/control/sessions/\(sessionID)/close/\(closeAttemptID)"' in owner,
    "close-body-exact": '"close_attempt_id": closeAttemptID' in owner,
    "session-id-validation": r'^s_[0-9a-f]{32}$' in owner,
    "same-attempt-state": "public enum ObserverSessionCloseState" in owner
        and "case outcomeUnknown(attemptID: String" in owner,
    "response-loss-status-first": "case .transportOutcomeUnknown, .unavailable:" in owner
        and "return await status(" in owner,
    "no-random-id-in-coordinator": "UUID()" not in owner,
    "explicit-same-attempt-reconcile": "reconcileSameAttempt(" in owner
        and "closeAttemptID: closeAttemptID" in owner,
    "viewmodel-generates-one-close-id": r'let attemptID = "close:\(UUID().uuidString.lowercased())"' in shell,
    "viewmodel-status-same-attempt": "sessionCloseStates[sessionID]?.attemptID" in shell
        and "sessionCloseCoordinator.status(" in shell,
    "viewmodel-reconcile-same-attempt": "sessionCloseCoordinator.reconcileSameAttempt(" in shell,
    "new-close-requires-live-read": "CLOSE PAUSED · READ TRUTH NOT LIVE" in view
        and "A new close is not started from cached or stale Session truth." in view,
    "save-exit-close-required": 'deadline.isFinalWarningWindow ? "SAVE & EXIT" : "CLOSE SESSION"' in view,
    "credential-cleanup-separated": 'key: "CREDENTIAL"' in view
        and 'key: "CLEANUP"' in view
        and "Credential revoked does not mean cleanup succeeded." in view,
    "unknown-no-success-claim": "OUTCOME UNKNOWN" in view
        and "Do not create a new close attempt." in view,
    "check-status-visible": 'Button("CHECK STATUS")' in view,
    "explicit-reconcile-visible": 'Button("RECONCILE SAME ATTEMPT")' in view,
    "reconcile-copy-same-id": "This reuses the existing close_attempt_id." in view,
    "no-raw-session-handle": "session_handle" not in owner.lower()
        and "session_handle" not in view.lower(),
    "project-detail-live-wiring": "sessionCloseStates" in shell
        and "closeSession: { sessionID in" in shell
        and "checkCloseStatus:" in shell
        and "reconcileClose:" in shell,
    "close-tests-response-loss": "response loss does not auto-repeat POST close" in tests,
    "close-tests-same-attempt": "reconcile reuses exact close_attempt_id" in tests,
    "close-tests-revoke-cleanup-separate": "revoked never implies cleanup success" in tests,
    "project-detail-interpolation-fixed": r'Text("\(presentation.jobs.count)")' in view,
    "no-lost-project-detail-interpolation": 'Text("(presentation.jobs.count)")' not in view,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL"), name)
print(f"checks={len(checks)} pass={len(checks)-len(failed)} fail={len(failed)}")
raise SystemExit(1 if failed else 0)
