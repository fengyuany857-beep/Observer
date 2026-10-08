# UIV2-5 | Approvals + Owner Control Binding

State: LOCAL_STATIC_VERIFIED
Base: 8fd2bb2e91c7027df3e278186e4837af07b90b2c
Backend Contract: OBSERVER-BACKEND-FREEZE-20261007-R1
Production: NOT MODIFIED
GitHub: NOT PUSHED

## Goal

Bind the frozen Observer Owner Control Plane into the iOS app without moving backend Authority into UI.

This stage covers:

- authoritative Pending Approval reads
- Allow / Deny owner decisions
- decision_attempt_id
- expected_state_version CAS
- CAS conflict refetch
- response-loss reconciliation
- independent obsw_ Keychain credential
- Approvals live surface

Session Close remains UIV2-6.

## Brownfield truth

The frozen backend already owns:

- observer.owner-control.transport.v1
- observer.owner-control.v1
- obsw_ owner credentials
- B1 approval authority
- decision_attempt_id idempotency
- expected_state_version CAS
- owner project/action scoping
- exact Allow / Deny transitions
- HTTP error mapping for auth / forbidden / not-found / conflict / expired / rate limit / unavailable

UIV2-5 did not redesign these semantics.

## Credential separation

Read Plane:

- token prefix: obsr_
- Keychain account: observer-read-bearer
- GET-only read plane

Owner Control Plane:

- token prefix: obsw_
- Keychain account: observer-owner-bearer
- mutation surface limited to frozen owner-control routes

The owner token is not accepted by read configuration.
The read token is not accepted by owner configuration.

Raw credentials are never rendered in the UI.

## Owner HTTP client

The iOS owner client binds exactly to:

- GET /observer/v1/control/projects/{project_id}/approvals
- GET /observer/v1/control/approvals/{approval_id}
- POST /observer/v1/control/approvals/{approval_id}/decision

Decision request body is exactly:

- decision
- decision_attempt_id
- expected_state_version

Decision values:

- ALLOW
- DENY

The client validates:

- HTTPS root URL
- obsw_ credential role
- project scope
- observer.owner-control.transport.v1 response header
- observer.owner-control.v1 response body
- authoritative approval project scope

## CAS behavior

409 conflict never causes the original Allow / Deny click to be replayed.

Instead:

1. authoritative approval status is refetched
2. if still PENDING, UI enters STATE CHANGED / REVIEW AGAIN
3. updated state_version is shown
4. user must make a new decision
5. a new human decision receives a new decision_attempt_id

No stale click is silently applied to fresh state.

## Mutation single-flight

One Approval has at most one local decision attempt in flight.

While SUBMITTING:

- Allow disabled
- Deny disabled

While OUTCOME_UNKNOWN:

- Allow disabled
- Deny disabled
- CHECK AUTHORITATIVE STATUS remains available

This prevents response loss from creating a random second mutation attempt.

## Response loss

A network/transport loss after POST is treated as potentially effectful.

The client does not infer "no mutation occurred".

The coordinator performs authoritative GET reconciliation:

- matching APPROVED / DENIED -> RESOLVED
- EXPIRED -> EXPIRED
- terminal other state -> RESOLVED
- still PENDING -> OUTCOME_UNKNOWN
- readback unavailable -> OUTCOME_UNKNOWN

The original decision_attempt_id remains visible and preserved.

## Approval UI

The live App now includes an Approvals tab.

Each PENDING request shows:

- project
- requested_scope
- action_class
- effect_class
- server expires_at
- state_version
- Allow
- Deny

Allow and Deny each own their confirmationDialog.

Explicit copy states:

- APPROVED does not mean Session minted
- GPT / SessionAccessBroker must still claim access
- no Always Allow
- no Always Trust

Recent authoritative status is polled so an APPROVED item can later become CONSUMED after GPT claim.

## System configuration

The previous Settings live tab is user-visible as System.

System keeps separate credential slots for:

- READ CREDENTIAL / obsr_
- OWNER CREDENTIAL / obsw_

Owner credential can be added or removed independently of the read credential.

## Search / reuse result applied

External research converged on:

- native SwiftUI confirmation ownership
- single-flight async mutation
- CAS refetch without automatic replay
- permission request inbox patterns
- response-loss reconciliation

No external permission backend or third-party UI framework was added.

This stage uses Adapted interaction patterns plus a project-specific owner-control core because no external implementation matches the frozen VCW authority contract.

## Verification

UI/static contract gates:

- B0: 33 / 33 PASS
- B1: 69 / 69 PASS
- B8: 52 / 52 PASS
- UIV2-3 Overview: 14 / 14 PASS
- UIV2-4 Project Detail: 26 / 26 PASS
- UIV2-5 Owner Control: 33 / 33 PASS
- git diff --check: PASS

Frozen backend direct verification:

- owner HTTP / control / socket API / E2E:
  - 39 tests PASS
  - 7 subtests PASS

macOS CI additions:

- ObserverOwnerControlTests.swift
- owner/read credential role separation in ObserverRuntimeConfigurationTests.swift

Not executed on this VPS:

- Swift compiler
- Xcode build
- iOS Simulator
- screenshot acceptance

Therefore this stage is not BUILD_VERIFIED yet.

## Explicit non-goals

Not implemented in UIV2-5:

- Session Close UI
- close_attempt_id lifecycle UI
- OUTCOME_UNKNOWN Session Close reconciliation
- push notification approval actions
- Production deployment
- GitHub push
- main merge

## Terminal state

PARTIAL / LOCAL_STATIC_VERIFIED

Next:

UIV2-6 | Session Close Lifecycle UI

The existing owner-control client architecture is intentionally ready for SESSION_CLOSE, but UIV2-6 must preserve close_attempt_id and same-attempt reconciliation rather than reuse Approval CAS semantics.
