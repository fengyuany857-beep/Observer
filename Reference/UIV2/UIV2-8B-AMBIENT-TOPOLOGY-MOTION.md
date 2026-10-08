# UIV2-8B | Ambient Topology Motion

State: LOCAL_STATIC_VERIFIED
Base: cfbca376b2841c678119393d148db774e8b6f194
Production: NOT MODIFIED
GitHub: NOT PUSHED

## Goal

Add ambient motion to the UIV2-8A topology without allowing visual motion to become runtime truth.

Motion model:

- Ambient Drift
- Scroll Impulse
- Inertial Decay

Terrain remains stable.
Only the observation window / UV viewport moves.

## Architecture

Metal receives only:

- viewportOffsetX
- viewportOffsetY

Metal does not receive:

- raw time
- raw scroll offset
- raw scroll velocity
- LIVE / STALE / OFFLINE
- Approval state
- Session state
- Job state
- Operation state
- Health / progress

The visual motion policy is isolated in ObserverTopologyMotion.swift.

## Default motion policy

- ambientVelocityX: 0.0010 UV/s
- ambientVelocityY: -0.00065 UV/s
- scrollVelocityToUV: -0.000025
- maximumScrollImpulse: 0.12
- inertiaTimeConstant: 0.55s
- frame cadence: 30 fps maximum

The scroll signal is converted to a bounded velocity impulse.
Content offset is not mapped 1:1 into background displacement.

The impulse is integrated with exponential decay toward a finite resting offset.

## Power / accessibility boundaries

Ambient motion is enabled only when all are true:

- Reduce Motion is OFF
- Low Power Mode is OFF
- scenePhase is active

Otherwise the topology immediately falls back to the static A / BARELY THERE surface.

Low Power Mode is observed through NSProcessInfoPowerStateDidChange and ProcessInfo.isLowPowerModeEnabled.

## Scroll geometry

One non-authoritative geometry probe exists on each core scroll surface:

- Overview
- Project Detail
- Approvals

System has no topology motion probe.

The probe only reports content geometry to the visual motion layer.

## Visual contract preserved

A / BARELY THERE remains unchanged:

- levels 15
- warp 0.16
- minorOpacity 0.035
- majorOpacity 0.055

No topology density or opacity is coupled to system activity.

No repeatForever animation is used.

## Tests

ObserverTopologyMotionTests covers:

- low-amplitude ambient drift
- no one-to-one jump when scrolling starts
- scroll impulse movement
- exponential inertial decay
- extreme scroll velocity clamp
- static output when motion is disabled
- 30 fps-or-slower default cadence

## Verification

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
- git diff --check: PASS

Not available on this VPS:

- Swift compiler
- Xcode build
- iOS Simulator
- motion screenshot/video acceptance
- on-device thermal / battery trial

## Remaining evidence gap

UIV2-8B must still be verified on macOS/Xcode and Simulator.

Because the current procedural shader performs multiple simplex/fBM evaluations per pixel, sustained animated rendering on iPhone should be treated as an energy/performance risk until measured.

If sustained GPU cost is excessive, retain the same motion contract but replace real-time procedural height generation with a cached height texture and cheap contour sampling.

## Next

UIV2-8C | Semantic Motion Binding

Semantic Motion must remain a separate bus from Ambient Motion.

Only authoritative presentation transitions may drive semantic motion.

## Terminal state

PARTIAL / LOCAL_STATIC_VERIFIED
