#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
owner = (root / "Sources/Domain/ObserverOwnerControl.swift").read_text()
config = (root / "Sources/Domain/ObserverOwnerConfiguration.swift").read_text()
shell = (root / "Sources/SwiftUI/ObserverLiveShell.swift").read_text()
view = (root / "Sources/SwiftUI/ApprovalsLiveView.swift").read_text()
freeze = (root / "Reference/B8/observer-backend-contract-freeze-v1.json").read_text()

checks = {
    "frozen-owner-contract": '"owner_transport": "observer.owner-control.transport.v1"' in freeze
        and '"owner_control": "observer.owner-control.v1"' in freeze,
    "owner-token-prefix": 'tokenPrefix = "obsw_"' in owner,
    "read-token-not-owner": 'hasPrefix(ObserverOwnerContract.tokenPrefix)' in owner
        and 'obsr_' not in owner.split("public struct ObserverOwnerControlConfiguration", 1)[1].split("public enum ObserverOwnerControlError", 1)[0],
    "owner-keychain-separate-account": 'keychainAccount = "observer-owner-bearer"' in config,
    "owner-route-list": r'"/observer/v1/control/projects/\(configuration.projectID)/approvals"' in owner,
    "owner-route-status": r'"/observer/v1/control/approvals/\(approvalID)"' in owner,
    "owner-route-decision": r'"/observer/v1/control/approvals/\(approvalID)/decision"' in owner,
    "decision-exact-payload": '"decision": decision.rawValue' in owner
        and '"decision_attempt_id": decisionAttemptID' in owner
        and '"expected_state_version": expectedStateVersion' in owner,
    "decision-values-bounded": 'case allow = "ALLOW"' in owner and 'case deny = "DENY"' in owner,
    "cas-409-typed": 'case 409:' in owner and 'ObserverOwnerControlError.conflict' in owner,
    "cas-refetch": 'authoritativeConflict(' in owner and 'approvalStatus(approvalID)' in owner,
    "cas-no-auto-replay": 'return fresh.state == "PENDING" ? .conflict(fresh) : .resolved(fresh)' in owner,
    "unknown-no-blind-retry": 'reconcileAfterUnknown(' in owner
        and 'case .transportOutcomeUnknown, .unavailable:' in owner,
    "same-attempt-visible": 'case outcomeUnknown(decision: ObserverOwnerDecision, attemptID: String)' in owner,
    "unknown-locks-decision": 'case .submitting, .outcomeUnknown:' in owner,
    "single-flight-map": 'inFlightByApproval' in owner,
    "native-no-cookie-client": 'httpCookieStorage = nil' in owner and 'httpShouldSetCookies = false' in owner,
    "owner-transport-header": 'X-Observer-Transport' in owner and 'ObserverOwnerContract.transport' in owner,
    "scope-validation": 'payload.projectID == configuration.projectID' in owner
        and 'payload.approval.projectID == configuration.projectID' in owner,
    "owner-public-dto-not-read-projection": 'requestAttemptID' in owner
        and 'requesterPrincipal' not in owner,
    "approval-confirm-bound-to-button": '.confirmationDialog(' in view
        and 'private struct ApprovalDecisionButton' in view,
    "allow-does-not-mint-copy": 'It does not mint a Session' in view,
    "approved-not-session-copy": 'APPROVED does not mean a Session exists' in view,
    "unknown-check-status": 'CHECK AUTHORITATIVE STATUS' in view,
    "conflict-review-copy": 'STATE CHANGED · REVIEW AGAIN' in view
        and 'was not replayed' in view,
    "no-always-allow": 'ALWAYS ALLOW' not in view.upper()
        and 'ALWAYS TRUST' not in view.upper(),
    "no-raw-session-handle": 'session_handle' not in view.lower()
        and 'session_handle' not in owner.lower(),
    "approvals-live-tab": 'Label("Approvals"' in shell
        and '.tag(ObserverRootTab.approvals)' in shell,
    "system-owner-config": 'ObserverPageIdentity("SYSTEM"' in shell
        and 'OWNER TOKEN' in shell
        and 'saveOwnerCredential' in shell,
    "owner-recent-readback": 'ownerClient.approvalStatus(recent.approvalID)' in shell,
    "owner-poll-not-ui-authority": 'ownerApprovals = try await ownerClient.pendingApprovals()' in shell,
    "no-lost-owner-interpolation": all(token not in owner for token in (
        'path: "/observer/v1/control/projects/(configuration.projectID)/approvals"',
        'path: "/observer/v1/control/approvals/(approvalID)"',
        'path: "/observer/v1/control/approvals/(approvalID)/decision"',
        '"Bearer (configuration.bearerToken)"',
        '"OWNER_HTTP_(status)"'
    )),
    "no-lost-approval-ui-interpolation": all(token not in view for token in (
        'Text("V(approval.stateVersion)")',
        'ObserverFunctionalSignal("(decision.rawValue) · SUBMITTING"',
        'Text("ATTEMPT (String(attemptID',
        'version (version). Your previous click',
        'Text("(decision.rawValue) response was not confirmed'
    )),
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL"), name)
print(f"checks={len(checks)} pass={len(checks)-len(failed)} fail={len(failed)}")
raise SystemExit(1 if failed else 0)
