#!/usr/bin/env python3
"""B4 Close attempt persistence source invariants; not a substitute for Swift Keychain CI tests."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
cfg = (root / "Sources/Domain/ObserverOwnerConfiguration.swift").read_text()
shell = (root / "Sources/SwiftUI/ObserverLiveShell.swift").read_text()
view = (root / "Sources/SwiftUI/ProjectDetailLiveView.swift").read_text()
swift_tests = (root / "Tests/ObserverRuntimeConfigurationTests.swift").read_text()
close = shell.split("    public func closeSession(_ sessionID:", 1)[1].split(
    "    public func runApprovalPollingLoop()", 1
)[0]

checks = {
    "owner-approval-account-retained": 'case approvals = "observer-owner-bearer"' in cfg,
    "owner-close-account-retained": 'case sessionClose = "observer-owner-close-bearer"' in cfg,
    "journal-separate-account": 'accountPrefix = "observer-close-attempt-v1:"' in cfg,
    "journal-uses-keychain": "SecItemAdd(add as CFDictionary, nil)" in cfg,
    "atomic-duplicate-detection": "errSecDuplicateItem" in cfg,
    "immutable-attempt": "CLOSE_ATTEMPT_ALREADY_EXISTS" in cfg,
    "keychain-fails-closed": "ObserverRuntimeConfigurationError.keychainFailure(status)" in cfg,
    "journal-survives-restart": "SecItemCopyMatching(query as CFDictionary, &item)" in cfg,
    "journal-no-delete": "SecItemDelete" not in cfg.split(
        "public struct ObserverSessionCloseAttemptStore", 1
    )[1],
    "journal-three-way-scope": "[baseURL.absoluteString, projectID, sessionID]" in cfg,
    "journal-attempt-validation": "Self.isValidAttemptID(attemptID)" in cfg,
    "keychain-config-injection": "closeAttemptStore: ObserverSessionCloseAttemptStore" in shell,
    "read-on-relaunch": "closeAttemptStore.load(" in shell,
    "relaunch-outcome-unknown": "return .outcomeUnknown(attemptID: attemptID, lifecycle: nil)" in shell,
    "relaunch-storage-failure-closed": 'return .failed("CLOSE_ATTEMPT_STORAGE_UNAVAILABLE")' in shell,
    "close-only-from-idle": "guard case .idle = closeState(for: sessionID)" in close,
    "persist-before-POST": close.index("closeAttemptStore.record(") < close.index(
        "await sessionCloseCoordinator.close("
    ),
    "fail-persist-blocks-post": close.index('sessionCloseStates[sessionID] = .failed("CLOSE_ATTEMPT_STORAGE_UNAVAILABLE")') < close.index(
        "await sessionCloseCoordinator.close("
    ),
    "no-new-id-in-status": "UUID()" not in close.split(
        "    public func checkSessionCloseStatus", 1
    )[1],
    "same-attempt-reconcile": "sessionCloseCoordinator.reconcileSameAttempt(" in close,
    "same-attempt-restore": "?? closeState(for: sessionID).attemptID" in close,
    "response-scope-fence": "scopeURL.absoluteString == baseURLString" in close
        and "scopeProject == projectID" in close,
    "response-failed-remains-unknown": 'ownerErrorCode = "VCW_SESSION_CLOSE_OUTCOME_UNKNOWN"' in close,
    "ui-uses-recovered-attempt": "model.closeState(for: $0.sessionID)" in shell,
    "tracking-shows-status": 'Button("CHECK STATUS")' in view,
    "tracking-shows-reconcile": 'Button("RECONCILE SAME ATTEMPT")' in view,
    "test-host-isolation": "different host cannot reuse another Close identity" in swift_tests,
    "test-project-isolation": "different project cannot reuse another Close identity" in swift_tests,
    "test-keychain-reload": "Close attempt survives a new store instance" in swift_tests,
    "test-second-attempt-rejected": "second different Close attempt cannot replace persisted identity" in swift_tests,
}
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL"), name)
passed = sum(checks.values())
print(f"checks={len(checks)} pass={passed} fail={len(checks) - passed}")
raise SystemExit(passed != len(checks))
