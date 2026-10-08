# Observer UI V2 Live Graft — B8 Candidate R1

Date: 2026-10-07

## Identity

- Base branch: `observer-b1-approval-broker-20261006`
- Base commit: `3f923557512777cda2ce9797ac98ba8ae241834d`
- Candidate branch: `observer-ui-v2-b8-live-graft-20261007`
- Frozen backend checkpoint: `OBSERVER-BACKEND-FREEZE-20261007-R1`
- Frozen backend commit: `3ff3a14f3b2d529d44f0d849bb627183987ee5e1`
- Frozen contract SHA-256: `ff59dc0310701cb9790f0045a49dfb288f4fd44a579ee4aefe3f6265bdfd1968`

## Graft scope

This candidate grafts the B8 frozen backend truth model into the existing B1/A6 Observer UI/runtime line without redesigning the frozen backend contract.

Implemented:

- B8 frozen Session / Approval / lifecycle / Current Operation truth models.
- Generation-aware snapshot boot.
- Per-request monotonic `X-Observer-Request-Generation`.
- Explicit `X-Observer-Read-Intent`.
- Snapshot 304 + Current Operation refresh path.
- Source-instance and event-cursor reconnect-baseline gates.
- Incremental event polling retained from A6.4.
- Operation-only polling retained without full-snapshot churn.
- Operation-only polling cannot promote cached/offline Session truth back to LIVE.
- CURRENT Operation is cleared whenever transport truth becomes non-live.
- Current Operation accepts only:
  - `currentness=CURRENT`
  - `authority=GATEWAY_IN_FLIGHT_CALL`
  - `freshness=CURRENT_PROCESS`
- Read-plane credential role is enforced as `obsr_` in runtime config, transport config, and ObserverReadAPI.
- `obsw_` owner tokens are rejected by read-plane clients.
- No raw VCW session handle is introduced into the B8 UI truth layer.

## Regression evidence

Verified on VPS:

- B0 contract regression: 33/33 PASS.
- B1 approval broker regression: 69/69 PASS.
- B8 UI frozen-contract static regression: 46/46 PASS.
- Frozen backend contract regression: 7/7 PASS.
- Backend Read Plane / HTTP / Current Operation / B5 invariant / Authority Projection regression: 27/27 PASS.
- Freeze JSON SHA-256 matches the B8 handoff.
- No conflict markers.
- No trailing whitespace in changed/new implementation files.
- `git diff --check`: PASS.
- Remote target branch revalidated at `3f923557512777cda2ce9797ac98ba8ae241834d`.

## Important fixes found during graft

1. Snapshot and Operations initially shared one request generation. Corrected so every read request owns a distinct monotonically increasing generation.
2. After splitting generation N / N+1, Operations failure could be mistaken for a superseded Snapshot response. Corrected by binding error handling to the active request generation.
3. A successful operation-only request could have revived an offline cached Session snapshot as LIVE. Corrected by requiring a still-live snapshot baseline; otherwise the client requests a reconnect/full snapshot baseline.

## Verification boundary

The VPS does not have `swiftc`/Xcode available. Therefore this candidate is not yet Swift BUILD_VERIFIED.

Required next verification:

1. Push the candidate branch only with fresh GitHub write authorization.
2. Run the existing macOS/Xcode Observer CI via workflow dispatch or an explicitly enabled candidate-branch trigger.
3. Require:
   - ObserverReadAPI package tests PASS.
   - core Swift tests PASS, including `ObserverB8LiveDataSourceTests`.
   - Simulator build PASS.
   - existing screenshot/evidence workflow still PASS.
4. Only after CI success may this candidate be promoted from STATIC/BACKEND_REGRESSION_VERIFIED to BUILD_VERIFIED.

No Production runtime, frozen B8 backend workspace, or remote GitHub branch was modified by this local graft.
