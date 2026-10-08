# B4 iOS Session Close | Isolated Candidate Handoff
Date: 2026-10-08
Base: Observer UI commit 507e43f95613a9266d5b58e27ba11a5e1666ca9e
Project: vcw-acceptance / Observer SwiftUI
Scope: isolate Approval Owner bearer from Session Close Owner bearer; enable Close UI in candidate only.

## Invariants
- Existing iOS Keychain account observer-owner-bearer unchanged, still used only for Approval read/ALLOW/DENY.
- Separate Keychain account observer-owner-close-bearer is used only for POST Close, GET Close Status, and same-attempt reconcile.
- The Read bearer obsr_ remains a third, independent credential and GET-only.
- No existing Production Owner grant is upgraded. Any Close bearer must be explicitly provisioned as session:close for the exact project by a separate authorized operation.
- UI Close button is only offered in this candidate when a Close credential is configured and fresh Project/Deadline truth permits new Close. Server remains authoritative over bearer scopes.
- Same-scope System settings saves preserve in-memory close_attempt_id; no new identity is generated for explicit reconciliation.
- Tokens never enter Git, app diagnostics, screenshots, source fixtures, or artifacts.

## Tested
- 12 original Python B0/B1/B8/UI static and model validations PASS (see console run).
- Existing approvals and lifecycle checks remain PASS after updating old assertions to the new dual-token contract.
- New 21 static B4 role/Keychain safety checks PASS.
- New Swift unit assertions added for role-specific Keychain account IDs and independent HTTP Authorization headers.
- No swiftc or Xcode available inside this Linux VCW Session. Swift tests and IPA build are NOT YET EXECUTED. These are mandatory macOS CI Gates.

## Not authorized / not yet performed
- No Production Owner session:close bearer provision, revoked/granted scope mutation, or iOS Keychain installation.
- No GitHub remote branch push, CI trigger, signed/unsigned IPA delivery, App upgrade, or iPhone real Close execution.
- No real Runner stop or Production Session credential revocation during this candidate work.
- An app restart may lose an unresolved close_attempt_id because the current attempt state remains in memory. Keep this as an open P1 for robust iPhone reconciliation; do not declare full lifecycle acceptance until addressed.

## Next gates
1. Run macOS Swift core test script + simulator build + unsigned iOS IPA build in isolated GitHub candidate branch, after authorization for GitHub remote write.
2. Provision a NEW Close-only project-scoped owner bearer in Production with separate explicit authorization and securely enter it in the iOS System Close credential field; never replace old Approval bearer.
3. Confirm actual Production Owner Close entitlement with a strictly read-only check, then use a fresh, disposable test Session explicitly approved for real closure.
4. On-device POST Close -> authoritative revoke -> Runner cleanup -> STOPPED; GET status and same-attempt replay; negative cross-project and approval-only bearer paths.
5. Readback production authority, no unrelated Session modified, original B1 approval flow still functional.
