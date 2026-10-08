# UIV2-8A | Static Topology Graft

State: LOCAL_STATIC_VERIFIED
Base: 5b64844d281acb47061280e8b8e97ebcc3d4fcf8
Donor Bundle: Observer-UIV2-8-Topology-Donor-Handoff-20261007
Donor Base: 3f923557512777cda2ce9797ac98ba8ae241834d
Donor Head: 8fad8c79607202ff069a92c17343e737d7045bf0
Production: NOT MODIFIED
GitHub: NOT PUSHED

## Donor decision

Selective Adapt.

Copied only the donor production minimum:

- ObserverTopologyField.metal
- ObserverTopologyField.swift
- ObserverScreenSurface.swift
- Observer-UIV2-Visual-Graft-Third-Party-Notices.md

Did not copy:

- prototype app entrypoint
- render harness
- donor CI workflow
- donor branch history

No wholesale merge from the old B1 donor baseline was performed.

## Integrity

The supplied donor bundle SHA256SUMS was independently checked before graft:

- 20 files checked
- 20 matched
- 0 mismatches

## Selected visual baseline

Production candidate:

A / BARELY THERE

Parameters preserved from donor:

- seedX: 14.27
- seedY: -3.91
- scale: 2.15
- levels: 15
- warp: 0.16
- minorLineWidth: 0.045
- majorLineWidth: 0.060
- minorOpacity: 0.035
- majorOpacity: 0.055
- majorEvery: 5

Balanced / Upper Bound remain donor comparison presets only and are not used by production live pages.

## Adaptation

The donor hard-coded graphite/minor/major colors were moved into the existing ObserverPalette:

- surfaceBase
- topologyMinor
- topologyMajor

No second design-token system was created.

## Static-only boundary

UIV2-8A intentionally has:

- no time input
- no scroll offset input
- no scroll velocity input
- no live/stale/offline input
- no Approval input
- no Session input
- no Job input
- no Operation input
- no Health input

The Metal shader is non-authoritative visual infrastructure.

## Live surfaces

Static barely-there topology is applied only to:

- Overview
- Project Detail
- Approvals

System is intentionally unchanged in UIV2-8A.

The topology layer:

- ignores safe area
- does not receive hit testing
- is accessibility hidden
- remains behind existing truth content

ObserverScreenSurface supports topology == nil and retains a complete base-color fallback.

## Existing truth retained

Overview still owns:

- Project / Session / CURRENT Operation
- deadline truth
- refresh/freshness truth

Project Detail still owns:

- Project -> Session -> Jobs -> CURRENT Operation
- lifecycle/effects
- Session Close
- deadline truth

Approvals still owns:

- authoritative pending approvals
- Allow / Deny
- CAS / attempt state
- owner-control result truth

No topology parameter is part of Domain, Backend, Authority, or Presentation truth.

## Third-party notices

The donor notice is retained for:

- idleCyrex/topolines
- Ashima Arts / Stefan Gustavson simplex-noise lineage
- twostraws/Inferno

No runtime package dependency was added for these references.

## Build evidence boundary

Donor evidence:

- donor static topology component BUILD_VERIFIED on its isolated donor branch
- build isolation run: 37593826365
- render reference success run: 37597414530
- selected visual baseline: A / BARELY THERE

Current UIV2-8A integration:

- NOT Xcode BUILD_VERIFIED yet
- NOT Simulator screenshot accepted yet

Donor BUILD_VERIFIED evidence is not promoted to the current 5b64844-based integration.

## Verification

Current local static/contract gates:

- UIV2-8A Static Topology: 32 / 32 PASS
- B0: 33 / 33 PASS
- B1: 69 / 69 PASS
- B8: 52 / 52 PASS
- UIV2-3 Overview: 14 / 14 PASS
- UIV2-4 Project Detail: 26 / 26 PASS
- UIV2-5 Approvals: 33 / 33 PASS
- UIV2-6 Session Close: 29 / 29 PASS
- UIV2-7 Deadline UX: 43 / 43 PASS
- git diff --check: PASS

Not available on this VPS:

- Swift compiler
- Xcode
- iOS Simulator

## Next gate

Before UIV2-8B Ambient Motion:

1. macOS/Xcode compile
2. Simulator static screenshots for:
   - Overview LIVE current
   - Overview stale/offline
   - Project Detail current vs last-observed
   - Approvals pending/decision
3. confirm truth remains first focal point
4. confirm background reads on second glance
5. confirm offline does not look live
6. confirm topology-off fallback remains usable

## Next planned stage

UIV2-8B | Ambient Topology Motion

Preferred model:

Ambient Drift + Scroll Impulse + Inertial Decay

The terrain itself remains stable. Motion should move the observation window/UV offset.

Semantic Motion remains a separate bus and must never reuse topology velocity as liveness/progress truth.

## Terminal state

PARTIAL / LOCAL_STATIC_VERIFIED
