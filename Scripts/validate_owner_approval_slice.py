from pathlib import Path

root = Path(__file__).resolve().parents[1]
project = (root / "Sources/SwiftUI/ProjectDetailLiveView.swift").read_text()
shell = (root / "Sources/SwiftUI/ObserverLiveShell.swift").read_text()
owner = (root / "Sources/Domain/ObserverOwnerControl.swift").read_text()
approvals = (root / "Sources/SwiftUI/ApprovalsLiveView.swift").read_text()

checks = {
    "approval-list-route": "/observer/v1/control/projects/\\(configuration.projectID)/approvals" in owner,
    "approval-status-route": "/observer/v1/control/approvals/\\(approvalID)" in owner,
    "approval-decision-route": "/observer/v1/control/approvals/\\(approvalID)/decision" in owner,
    "allow-button-live": 'title: "ALLOW"' in approvals,
    "deny-button-live": 'title: "DENY"' in approvals,
    "approved-not-session-copy": "It does not mint a Session" in approvals,
    "close-capability-flag": "sessionCloseAvailable: Bool" in project,
    "close-capability-forwarded": "available: sessionCloseAvailable" in project,
    "live-shell-enables-close-with-separate-owner": "sessionCloseAvailable: true" in shell
        and "ownerConfigured: model.isSessionCloseConfigured" in shell,
    "approval-token-still-used-for-allow": "ownerClient.pendingApprovals()" in shell
        and "client: ownerClient" in shell,
    "close-only-token-uses-separate-client": "private var closeClient: ObserverOwnerControlClient?" in shell
        and "client: closeClient" in shell,
    "close-deferred-signal": "SESSION CLOSE · DEFERRED" in project,
    "close-secret-missing-prompts-scope": "A separate session:close owner credential is required" in project,
}

failed = []
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL"), name)
    if not ok:
        failed.append(name)

print(f"checks={len(checks)} pass={len(checks)-len(failed)} fail={len(failed)}")
if failed:
    raise SystemExit(1)
