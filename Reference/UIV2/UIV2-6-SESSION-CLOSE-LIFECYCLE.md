# UIV2-6 | Session Close Lifecycle UI

State: LOCAL_STATIC_VERIFIED
Base: b22d08c5ceff6bddf4e22d0c3e44b5fa5380ee56
Backend Contract: OBSERVER-BACKEND-FREEZE-20261007-R1
Production: NOT MODIFIED
GitHub: NOT PUSHED

## Goal

Bind the frozen SESSION_CLOSE owner action into Project Detail without treating UI state as backend Authority.

This stage implements:

- POST Session Close using public session_id
- stable close_attempt_id
- GET close status using the same close_attempt_id
- response-loss reconciliation
- explicit same-attempt reconcile
- authoritative lifecycle rendering
- credential revoke vs cleanup truth separation
- Save & Exit control during CLOSE_REQUIRED

## Frozen backend routes

Owner Control Plane:

- POST /observer/v1/control/sessions/{session_id}/close
- GET /observer/v1/control/sessions/{session_id}/close/{close_attempt_id}

Auth:

- obsw_

POST body:

- close_attempt_id

The App never receives or uses a raw VCW Session handle.

## Lifecycle truth

The client decodes the frozen authoritative lifecycle:

- operation_id
- session_id
- action
- state
- requested_at
- updated_at
- completed_at
- reason
- error_code
- error_message
- credential_revoked
- credential_revoked_at
- session_state
- cleanup_complete

UI states preserve backend states such as:

- REQUESTED
- EXECUTING
- VERIFYING
- SUCCEEDED
- OUTCOME_UNKNOWN
- FAILED

## Critical invariant

credential_revoked != cleanup_complete

A revoked credential is rendered separately from runtime cleanup.

UI never renders "Session closed" merely because credential_revoked is true.

Verified close requires the authoritative lifecycle to prove the final lifecycle outcome and cleanup truth.

## New close

A new close is only initiated when:

- obsw_ owner control is configured
- current Session truth is live

Cached or stale read-plane Session truth does not start a new close.

The iOS client creates exactly one close_attempt_id for the user action.

## Response loss

If the POST transport response is lost or owner transport is unavailable:

1. do not issue a second POST automatically
2. GET status for the exact same close_attempt_id
3. if status is found, render authoritative lifecycle truth
4. if status cannot be proven, enter OUTCOME_UNKNOWN

This avoids interpreting a missing response as proof that no effect occurred.

## OUTCOME_UNKNOWN

OUTCOME_UNKNOWN explicitly states:

- credential may already be revoked
- runtime cleanup is not authoritatively confirmed
- a new random close attempt must not be created

Available user actions:

- CHECK STATUS
  - GET same-attempt status only
- RECONCILE SAME ATTEMPT
  - explicit user confirmation
  - reuses the existing close_attempt_id
  - relies on the frozen backend idempotent/recovery path
  - does not create a new mutation identity

## Project Detail UI

The existing Session section now includes:

- CLOSE SESSION during normal live Session state
- SAVE & EXIT during CLOSE_REQUIRED
- confirmation dialog before new close
- lifecycle state
- attempt suffix
- credential state
- cleanup state
- backend Session state
- error code when present
- CHECK STATUS / RECONCILE SAME ATTEMPT for OUTCOME_UNKNOWN

T+23:30 remains a warning window only.

The UI does not reinterpret CLOSE_REQUIRED as expiry and does not auto-close the Session.

## Brownfield fixes

During UIV2-6 recon two older Project Detail display interpolation defects were found and repaired:

- SAVE & EXIT remaining-time string
- Jobs count string

A new UIV2-6 static gate now checks those strings so they cannot regress into literal parenthesis text.

## System UI

System mode now reflects actual capability:

- READ ONLY when no owner credential is configured
- READ + OWNER CONTROL when obsw_ is configured

Read and owner credentials remain separate.

## Verification

Observer/UI contract gates:

- B0: 33 / 33 PASS
- B1: 69 / 69 PASS
- B8: 52 / 52 PASS
- UIV2-3 Overview: 14 / 14 PASS
- UIV2-4 Project Detail: 26 / 26 PASS
- UIV2-5 Approvals Owner Control: 33 / 33 PASS
- UIV2-6 Session Close: 29 / 29 PASS
- git diff --check: PASS

Frozen backend direct verification:

- owner HTTP
- owner control
- owner socket API
- owner E2E
- Session lifecycle
- lifecycle surface

Result:

- 59 tests PASS
- 7 subtests PASS

macOS/Xcode tests extended:

- ObserverOwnerControlTests now includes close success
- response-loss status reconciliation
- same-attempt explicit reconcile
- credential revoke / cleanup separation

Not executed on this VPS:

- Swift compiler
- Xcode build
- iOS Simulator
- screenshot acceptance

Therefore UIV2-6 is not BUILD_VERIFIED yet.

## Explicit non-goals

Not performed:

- Production deployment
- main merge
- GitHub push
- push-notification approval actions
- Activity/System visual completion
- WALLHACK motion/topographic final integration

## Terminal state

PARTIAL / LOCAL_STATIC_VERIFIED

Next planned stage:

UIV2-7 | T+23:30 -> T+25:00 Deadline UX integration and state-transition polish.
