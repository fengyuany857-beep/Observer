# UIV2-7 | T+23:30 -> T+25:00 Deadline UX

State: LOCAL_STATIC_VERIFIED
Base: 784a0c9868ef2998cf50a20053f1e66272957090
Backend Contract: OBSERVER-BACKEND-FREEZE-20261007-R1
Production: NOT MODIFIED
GitHub: NOT PUSHED

## Goal

Make the frozen Session deadline model visible and actionable in Observer without introducing a second local timing authority.

This stage covers:

- ACTIVE
- CLOSE_REQUIRED
- HARD_EXPIRED
- TERMINAL
- UNKNOWN / inconsistent deadline truth
- T+23:30 -> T+25:00 visual transition
- Save & Exit emphasis during the final 90-second window
- hard-expiry presentation
- Session Close gating after expiry / terminal / offline / inconsistent truth
- restrained motion with Reduce Motion support

## Authority boundary

Observer does not calculate or promote deadline phase from a local 1 Hz timer.

The client consumes accepted server values:

- deadline.phase
- deadline.remaining_seconds
- deadline.elapsed_seconds
- deadline.hard_ttl_seconds
- deadline.close_reminder_seconds
- deadline.close_required

No TimelineView, Date.now, or local elapsed threshold owns Session deadline phase.

If a cached snapshot is shown, deadline timing is rendered as LAST OBSERVED.

## Frozen constants

- hard TTL: 1500 seconds / 25:00
- close reminder: 90 seconds
- close-required threshold: T+23:30 / elapsed 1410
- hard expiry: T+25:00 / elapsed 1500

## Shared deadline policy

New presentation layer:

- ObserverDeadlineServerPhase
- ObserverDeadlineUXPresentation

Server phase values:

- ACTIVE
- CLOSE_REQUIRED
- HARD_EXPIRED
- TERMINAL
- UNKNOWN

The policy also receives the server close_required boolean.

The fields must agree:

close_required == (phase == CLOSE_REQUIRED)

If they disagree:

- UI renders DEADLINE INCONSISTENT
- owner Session Close is withheld
- no local guess chooses one server field over the other

## T+23:30 behavior

CLOSE_REQUIRED is explicitly rendered as:

SAVE & EXIT

The detail states that this is the final 01:30 window and the Session is still active.

It does not imply:

- expired
- logged out
- credential revoked
- worker stopped
- cleanup complete

A new owner Session Close remains allowed while authoritative deadline phase is CLOSE_REQUIRED.

## T+25:00 behavior

HARD_EXPIRED is rendered as:

SESSION EXPIRED

At HARD_EXPIRED:

- remaining can display 00:00
- a new Session Close attempt is not started
- UI waits for backend read/lifecycle reconciliation
- hard expiry is not synthesized from a local countdown

## TERMINAL

TERMINAL is rendered as:

SESSION ENDED

No new Session Close is needed or allowed.

## Offline / cached behavior

If read truth is no longer live:

- deadline is labeled LAST OBSERVED
- cached timing remains historical
- no local timer promotes cached timing to live truth
- new owner Session Close is withheld

## Motion

New shared SwiftUI component:

ObserverSessionDeadlineView

Motion is presentation-only.

Allowed:

- one restrained symbol replacement on server phase change
- numeric content transition when a new accepted remaining_seconds arrives
- slight rule emphasis in CLOSE_REQUIRED

Not used:

- repeatForever
- perpetual pulse
- local timer-driven authority animation
- full-screen alarm
- fake critical scan effects

Reduce Motion:

- replaces state/numeric movement with opacity/static presentation
- semantic text remains complete

## Shared surfaces

The same deadline component is used by:

- Overview
- Project Detail

Project Detail Session Close uses the same deadline policy for owner-action availability.

This prevents the page from showing HARD_EXPIRED while still offering CLOSE SESSION.

## Boundary tests

ObserverDeadlineUXTests covers explicit server inputs for:

- 23:29 / ACTIVE / remaining 91
- 23:30 / CLOSE_REQUIRED / remaining 90
- 24:00 / CLOSE_REQUIRED / remaining 60
- 24:59 / CLOSE_REQUIRED / remaining 1
- 25:00 / HARD_EXPIRED / remaining 0
- TERMINAL
- offline cached CLOSE_REQUIRED
- contradictory phase / close_required
- unknown future phase

The test does not derive phase from elapsed_seconds.

## Brownfield findings

During implementation the UIV2-7 gate caught two real source-writing defects:

- LAST OBSERVED Swift interpolation was written as literal parenthesis text
- FINAL 01:30 WINDOW interpolation was written as literal parenthesis text

It also caught a missing contractConsistent property that would have caused Swift compilation failure.

These were fixed without weakening the tests.

Historical UIV2-3/4/6 validators were updated only to follow the new shared deadline implementation while preserving their original semantic requirements.

## Verification

Observer/UI contract gates:

- B0: 33 / 33 PASS
- B1: 69 / 69 PASS
- B8: 52 / 52 PASS
- UIV2-3 Overview: 14 / 14 PASS
- UIV2-4 Project Detail: 26 / 26 PASS
- UIV2-5 Approvals Owner Control: 33 / 33 PASS
- UIV2-6 Session Close: 29 / 29 PASS
- UIV2-7 Deadline UX: 43 / 43 PASS
- git diff --check: PASS

Frozen backend direct verification:

- Session close reminder projection
- backend contract freeze
- Session lifecycle
- lifecycle surface

Result:

- 30 tests PASS

macOS CI additions:

- ObserverDeadlineUXTests.swift
- UIV2-7 static deadline gate

Not executed on this VPS:

- Swift compiler
- Xcode build
- iOS Simulator
- screenshot acceptance

Therefore UIV2-7 is not BUILD_VERIFIED yet.

## Explicit non-goals

Not performed:

- Production deployment
- GitHub push
- main merge
- Activity page completion
- topographic background integration
- final WALLHACK motion pass
- Simulator acceptance

## Terminal state

PARTIAL / LOCAL_STATIC_VERIFIED

Next planned stage:

UIV2-8 | WALLHACK Motion / Topographic Field Integration
