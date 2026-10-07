# UIV2-8C | Semantic Motion Binding

State: LOCAL_STATIC_VERIFIED
Base: 5a3893799ed57352138e347c1b3f8b8ffb4efe9e
Production: NOT MODIFIED
GitHub: NOT PUSHED

## Goal

Bind restrained foreground motion to authoritative presentation changes while keeping Semantic Motion completely separate from Ambient Topology Motion.

Semantic Motion may react only to existing presentation truth.

It does not create, infer, delay, predict, or promote backend state.

## Motion buses

### Ambient Motion

Owns:

- ambient drift
- scroll impulse
- inertial decay
- viewport offset
- Reduce Motion / Low Power / scene-active gating

Ambient Motion does not read runtime truth.

### Semantic Motion

Owns:

- CURRENT Operation appearance / replacement / disappearance
- freshness transition
- pending Approval attention
- Approval mutation-state transition
- Session deadline phase transition
- Session Close lifecycle transition

Semantic Motion does not read:

- time
- scroll offset
- scroll velocity
- topology viewport offset
- ambient velocity
- Low Power Mode
- scene phase

The two buses do not call each other.

## Motion profiles

ObserverSemanticMotionEmphasis defines three restrained profiles:

- subtle
  - duration 0.16s
  - insertion offset -2pt
- structural
  - duration 0.22s
  - insertion offset -5pt
- attention
  - duration 0.26s
  - insertion offset -3pt

No repeatForever animation is used.

Reduce Motion:

- removes explicit semantic animation
- replaces offset insertion with opacity-only transition

## CURRENT Operation

CurrentOperationPresentation derives a stable semantic identity from:

- kind
- name
- startedAt

No Job state is promoted to CURRENT.

Overview and Project Detail animate only when the authoritative CURRENT presentation identity changes.

The CurrentOperationBlock uses a structural insertion/removal transition.

When transport becomes non-live and CURRENT disappears, the existing "NO LIVE CURRENT · LAST OBSERVED ONLY" truth remains authoritative.

## Freshness

Overview and Project Detail bind semantic motion directly to:

ObserverB8Freshness.rawValue

Possible authoritative values remain:

- LIVE
- STALE
- CACHED
- OFFLINE
- UNKNOWN

No UI timer promotes freshness.

## Approval

Overview:

- pendingApprovalCount drives the presence/removal animation of the approval-attention signal

Approvals page:

- pending-list membership is driven by authoritative approval IDs
- recent authoritative state is driven by state_version
- mutation-state motion identity is derived from ObserverOwnerMutationState

Covered mutation identities:

- IDLE
- SUBMITTING
- CONFLICT
- OUTCOME_UNKNOWN
- RESOLVED
- FAILED

Animation does not change CAS, decision_attempt_id, or reconciliation behavior.

## Deadline

ObserverSessionDeadlineView now uses the shared semantic-motion policy for serverPhase changes.

The authoritative deadline contract remains:

- ACTIVE
- CLOSE_REQUIRED
- HARD_EXPIRED
- TERMINAL
- UNKNOWN / inconsistent

CLOSE_REQUIRED receives attention-level motion but remains explicitly "Session still active".

Numeric remaining_seconds transition remains presentation-only and server-derived.

## Session Close lifecycle

ObserverSessionCloseState derives semantic identity from existing owner-control lifecycle truth.

Tracking identity includes:

- operation_id
- lifecycle.state
- cleanup_complete truth

Therefore transitions such as:

- REQUESTED
- EXECUTING
- VERIFYING
- SUCCEEDED
- OUTCOME_UNKNOWN
- FAILED

can change foreground structure without inventing intermediate client states.

OUTCOME_UNKNOWN remains outcome unknown.
Credential revoked remains distinct from cleanup complete.

## Deliberate non-goals

Semantic Motion does not animate Job LAST_OBSERVED into CURRENT.

Semantic Motion does not:

- change topology speed
- change topology opacity
- change topology warp
- use progress to drive ambient movement
- make offline appear live
- synthesize liveness
- perform backend mutation

## Tests

ObserverSemanticMotionTests covers:

- restrained profile ordering
- restrained structural offset
- CURRENT identity changes on presentation truth change
- Approval identity changes on submitting / resolution
- Close lifecycle identity changes EXECUTING -> VERIFYING
- Close lifecycle identity changes VERIFYING -> SUCCEEDED
- stable semantic identity for the same OUTCOME_UNKNOWN truth

## Verification

Current static / contract gates:

- B0: 33 / 33 PASS
- B1: 69 / 69 PASS
- B8: 52 / 52 PASS
- UIV2-3 Overview: 14 / 14 PASS
- UIV2-4 Project Detail: 26 / 26 PASS
- UIV2-5 Approvals: 33 / 33 PASS
- UIV2-6 Session Close: 29 / 29 PASS
- UIV2-7 Deadline UX: 43 / 43 PASS
- UIV2-8A Static Topology: 32 / 32 PASS
- UIV2-8B Ambient Motion: 39 / 39 PASS
- UIV2-8C Semantic Motion: 31 / 31 PASS
- git diff --check: PASS

macOS CI additions:

- ObserverSemanticMotionTests.swift
- validate_uiv2_semantic_motion.py

Not available on this VPS:

- Swift compiler
- Xcode build
- iOS Simulator
- semantic-motion visual acceptance
- Reduce Motion Simulator acceptance

Therefore UIV2-8C is not BUILD_VERIFIED yet.

## Next gate

Before expanding the visual system further:

1. macOS/Xcode compile
2. Simulator motion acceptance
3. verify CURRENT transition remains the strongest "now" cue
4. verify LAST_OBSERVED Jobs remain visually subordinate
5. verify offline transition never looks like active execution
6. verify Approval attention is visible without becoming alarm UI
7. verify Reduce Motion remains complete and understandable
8. verify Ambient and Semantic buses remain visually distinguishable

## Terminal state

PARTIAL / LOCAL_STATIC_VERIFIED
