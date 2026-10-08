# UIV2-4 | Project Detail Live Graft

State: LOCAL_STATIC_VERIFIED
Base: 5c639da820320559bd340111294c3dab75442310
Backend Contract: OBSERVER-BACKEND-FREEZE-20261007-R1
Production: NOT MODIFIED
GitHub: NOT PUSHED

## Brownfield finding

The existing B8 iOS datasource fetched the frozen Session snapshot and CURRENT Operations, but it did not consume the frozen `/observer/v1/projects/{project_id}/jobs` route.

Instead, B8 compatibility projection mapped each Session into the legacy `RunStatusSnapshot` model. Therefore the old live Runs / Run Detail surface could not truthfully represent:

Project -> Session -> Job -> Operation

Using legacy Run rows as Job rows would have violated the frozen currentness contract because Job RUNNING is only LAST_OBSERVED_ACTIVE.

## Reuse decision

Reused existing components:

- frozen `observer.jobs.v1` backend contract
- existing `ObserverReadAPI` Job schema and route support
- existing B8 request_generation / read_intent / source_instance acceptance machinery
- existing CURRENT Operation truth and invalidation semantics
- existing B8 snapshot Effect and lifecycle truth
- existing WALLHACK primitives such as metadata nodes, functional signals and CurrentOperationBlock

No backend state machine, Authority owner, Session model, Job hierarchy, read-plane, owner-control plane or TTL semantics were redesigned.

## Read-chain graft

A full accepted read now follows:

snapshot generation N
-> operations generation N+1
-> jobs generation N+2
-> accept only if all required reads belong to the latest generation chain

Jobs validation requires:

- contract `observer.jobs.v1`
- exact project scope
- matching `source_instance_id`
- `AVAILABLE`
- frozen state classes:
  - LAST_OBSERVED_ACTIVE
  - TERMINAL_CONFIRMED
  - UNKNOWN

A partial jobs failure does not promote a half-refreshed snapshot to LIVE.

304 refresh also updates Operations and Jobs. Operation-only quiet polling preserves accepted Job history and never promotes Job state into CURRENT Operation.

## Effect truth

The existing B8 snapshot already carries Effect projection data. UIV2-4 now decodes that truth into the client model without adding a new backend route.

Attention includes unknown or unresolved states such as:

- DISPATCHING
- OUTCOME_UNKNOWN
- RECONCILING
- RECOVERY_BLOCKED
- explicit last_error_code

## Project Detail hierarchy

The live Projects surface now presents:

Project
-> current Session
-> Jobs as LAST OBSERVED
-> CURRENT Operation as a separate stronger live truth

It also shows:

- server-derived remaining Session time and deadline phase
- CLOSE_REQUIRED as Save & Exit, not expired
- Session lifecycle state including OUTCOME_UNKNOWN
- Effect attention / recovery state
- cached/offline freshness
- CURRENT Operation demotion when transport is not live

## Live IA change

The live app second tab is now user-visible as `Projects` instead of `Runs`.

The old Runs / Run Detail implementation remains in the repository for Preview / compatibility evidence, but it is no longer the live second-tab runtime authority surface.

## Explicit invariants

- Job RUNNING never synthesizes CURRENT Operation.
- LAST_OBSERVED_ACTIVE is visible as last-observed state, not live currentness.
- CURRENT Operation remains process-local in-flight BackendProxy truth.
- Offline/cached state clears live CURRENT treatment.
- Project Detail is read-only in UIV2-4.
- No Allow / Deny / APPROVAL_DECIDE / SESSION_CLOSE / obsw_ mutation was introduced.
- Raw VCW Session handles remain absent.

## Verification

Current local static and contract gates:

- B8 live/freeze validator: 52 / 52 PASS
- UIV2-3 Overview live validator: 14 / 14 PASS
- UIV2-4 Project Detail validator: 26 / 26 PASS
- B0 contract validator: 33 / 33 PASS
- B1 Approval contract validator: 69 / 69 PASS
- `git diff --check`: PASS
- `Scripts/run_core_tests.sh` shell syntax: PASS

Not available on this VPS:

- Swift compiler
- Xcode build
- iOS Simulator
- screenshot acceptance

Therefore UIV2-4 is not BUILD_VERIFIED yet.

## Remaining hard gate

macOS/Xcode CI must compile the updated B8 Job model, datasource regressions, Presentation layer and ProjectDetailLiveView, then pass Simulator and screenshot regression before the UI candidate can be upgraded to BUILD_VERIFIED.

## Terminal state

PARTIAL / LOCAL_STATIC_VERIFIED

Next planned stage: UIV2-5 Approvals + obsw_ Owner Control Binding.

Before starting UIV2-5, remember the user's explicit request to search GitHub for reusable Approvals / control-surface implementations.
