#!/usr/bin/env python3
"""B4 isolated source invariants, not macOS compilation or handset verification."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
cfg=(root/"Sources/Domain/ObserverOwnerConfiguration.swift").read_text()
shell=(root/"Sources/SwiftUI/ObserverLiveShell.swift").read_text()
view=(root/"Sources/SwiftUI/ProjectDetailLiveView.swift").read_text()
tests=(root/"Tests/ObserverOwnerControlTests.swift").read_text()
runtime=(root/"Tests/ObserverRuntimeConfigurationTests.swift").read_text()
def between(begin,end):
    assert begin in shell and end in shell
    return shell.split(begin,1)[1].split(end,1)[0]
close=between("    public func closeSession(", "    private func applySessionCloseResult(")
approvals=between("    public func refreshApprovals()", "    public func closeSession(")
checks={
 "legacy-approval-keychain-id": 'case approvals = "observer-owner-bearer"' in cfg,
 "new-close-keychain-id": 'case sessionClose = "observer-owner-close-bearer"' in cfg,
 "all-keychain-ops-purpose-scoped": cfg.count("kSecAttrAccount as String: purpose.rawValue")==3,
 "legacy-owner-default-preserved": 'purpose: ObserverOwnerCredentialPurpose = .approvals' in cfg,
 "close-store-independent": 'closeCredentialStore: ObserverOwnerCredentialStore = ObserverOwnerCredentialStore(purpose: .sessionClose)' in shell,
 "two-client-fields": "private var closeClient: ObserverOwnerControlClient?" in shell and
                      "private var ownerClient: ObserverOwnerControlClient?" in shell,
 "approval-traffic-never-close-client": "client: closeClient" not in approvals and "ownerClient" in approvals,
 "close-traffic-never-approval-client": "client: ownerClient" not in close and close.count("client: closeClient")==3,
 "close-token-save-and-delete": "closeCredentialStore.saveBearerToken(token)" in shell and
                                "closeCredentialStore.deleteBearerToken()" in shell,
 "duplicate-owner-token-rejected": shell.count("OWNER_TOKENS_MUST_BE_DISTINCT")==2,
 "forget-close-preserves-approvals": "ownerCredentialStore.deleteBearerToken()" not in
                               between("    public func forgetSessionCloseCredential()", "    public func refreshApprovals()"),
 "forget-approval-preserves-close": "closeCredentialStore.deleteBearerToken()" not in
                               between("    public func forgetOwnerCredential()", "    public func saveSessionCloseCredential("),
 "close-UI-uses-only-close-client": "ownerConfigured: model.isSessionCloseConfigured" in shell,
 "close-UI-explicit-candidate-switch": "sessionCloseAvailable: true" in shell,
 "close-UI-explains-scope": "A separate session:close owner credential is required" in view,
 "settings-save-preserves-same-scope-close-id": "if closeScopeChanged { self.sessionCloseStates = [:] }" in shell,
 "settings-identity-scopes-close-id": "let closeScopeChanged = self.baseURLString != settings.baseURL.absoluteString" in shell,
 "same-attempt-reconcile": "sessionCloseCoordinator.reconcileSameAttempt(" in shell and
                           "sessionCloseStates[sessionID]?.attemptID" in shell,
 "wire-test-two-bearers": "Approval traffic exclusively uses approval credential" in tests and
                           "Close traffic exclusively uses Close credential" in tests,
 "keychain-purpose-Swift-tests": "legacy approval Keychain account preserved" in runtime and
                                  "Close Keychain account separate from approval" in runtime,
 "no-hardcoded-long-token": not re.search(r"obsw_[A-Za-z0-9]{35,}",cfg+shell+view),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():print(("PASS " if v else "FAIL ")+k)
print(f"checks={len(checks)} pass={len(checks)-len(failed)} fail={len(failed)}")
raise SystemExit(bool(failed))
