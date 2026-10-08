# UIV2-3 | Overview Live Graft

State: LOCAL_STATIC_VERIFIED
Base: e0040b071b2c001ee9f53268faa42b41def95723

## What changed

- Live Overview now consumes `ObserverDataEnvelope.backendTruth` instead of using Run state as the primary runtime truth.
- Visual hierarchy is now Project -> Session -> CURRENT Operation.
- Session deadline data comes from the frozen B8 server-derived deadline contract.
- CURRENT Operation is read only through `backend.currentOperation(for:)` and therefore disappears when transport truth is not live.
- Pending approval count, queued session count, freshness, transport state, Gateway/Runner health and read-only manual refresh are surfaced without creating command authority.
- Existing Run-based Overview remains as a legacy/fixture fallback when B8 backendTruth is absent.

## Explicit invariants

- jobs.RUNNING is not used to synthesize CURRENT Operation.
- Cached/offline truth cannot retain live CURRENT treatment.
- Manual Refresh calls the existing B8 read path only.
- `CLOSE_REQUIRED` is rendered as Save & Exit, not EXPIRED.
- No Allow/Deny or owner mutation is introduced in Overview.

## Verification

- B8 static live graft: 46/46 PASS
- B0 contract: 33/33 PASS
- B1 approval contract: 69/69 PASS
- UIV2 Overview static acceptance: 14/14 PASS
- `git diff --check`: PASS
- Local Swift/Xcode build: NOT AVAILABLE on VPS

Terminal: PARTIAL / LOCAL_STATIC_VERIFIED

Next: UIV2-4 Project Detail Live Graft, then Xcode/macOS CI gate before BUILD_VERIFIED.
