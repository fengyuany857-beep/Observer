#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
motion = (root / "Sources/SwiftUI/Visual/ObserverTopologyMotion.swift").read_text()
surface = (root / "Sources/SwiftUI/Visual/ObserverScreenSurface.swift").read_text()
field = (root / "Sources/SwiftUI/Visual/ObserverTopologyField.swift").read_text()
metal = (root / "Sources/SwiftUI/Visual/ObserverTopologyField.metal").read_text()
overview = (root / "Sources/SwiftUI/OverviewView.swift").read_text()
project = (root / "Sources/SwiftUI/ProjectDetailLiveView.swift").read_text()
approvals = (root / "Sources/SwiftUI/ApprovalsLiveView.swift").read_text()
shell = (root / "Sources/SwiftUI/ObserverLiveShell.swift").read_text()
tests = (root / "Tests/ObserverTopologyMotionTests.swift").read_text()

production_pages = overview + project + approvals

semantic_tokens = (
    "ObserverB8",
    "approvalState",
    "sessionState",
    "jobState",
    "operationState",
    "healthState",
    "currentOperation",
    "ownerApprovals",
    "deadlinePhase",
    "transportLive",
    "LIVE",
    "STALE",
    "OFFLINE",
    "CURRENT",
)

checks = {
    "motion-policy-exists": "public struct ObserverTopologyMotionPolicy" in motion,
    "motion-state-exists": "public struct ObserverTopologyMotionState" in motion,
    "viewport-offset-exists": "public struct ObserverTopologyViewportOffset" in motion,
    "ambient-x-low-amplitude": "ambientVelocityX: Double = 0.0010" in motion,
    "ambient-y-low-amplitude": "ambientVelocityY: Double = -0.00065" in motion,
    "scroll-to-uv-low-amplitude": "scrollVelocityToUV: Double = -0.000025" in motion,
    "scroll-impulse-bounded": "maximumScrollImpulse: Double = 0.12" in motion
        and "Self.clamp(" in motion,
    "inertia-exp-decay": "1 - exp(-elapsed / tau)" in motion,
    "inertia-tau": "inertiaTimeConstant: Double = 0.55" in motion,
    "cadence-30fps": "frameInterval: TimeInterval = 1.0 / 30.0" in motion,
    "disabled-zero-offset": "guard motionEnabled else { return .zero }" in motion,
    "no-semantic-truth-in-motion-policy": all(token not in motion for token in semantic_tokens),
    "geometry-probe-only": "GeometryReader" in motion
        and "ObserverTopologyScrollOffsetPreferenceKey" in motion,
    "named-scroll-space": "observer-topology-scroll-space" in motion,
    "metal-final-offset-only": "viewportOffsetX" in metal
        and "viewportOffsetY" in metal
        and "receives only a final viewport offset" in metal,
    "metal-no-raw-time": "float time" not in metal and "timeSeconds" not in metal,
    "metal-no-raw-scroll": "scrollVelocity" not in metal and "scrollOffset" not in metal,
    "metal-no-runtime-truth": all(token not in metal for token in semantic_tokens),
    "field-passes-only-final-offset": ".float(viewportOffset.x)" in field
        and ".float(viewportOffset.y)" in field,
    "reduce-motion-gate": "accessibilityReduceMotion" in surface
        and "!reduceMotion" in surface,
    "low-power-gate": "isLowPowerModeEnabled" in surface
        and "NSProcessInfoPowerStateDidChange" in surface
        and "!lowPowerModeEnabled" in surface,
    "scene-phase-gate": "scenePhase == .active" in surface,
    "periodic-ambient-schedule": "TimelineView(" in surface
        and ".periodic(" in surface
        and "motionPolicy.frameInterval" in surface,
    "static-fallback-when-paused": "viewportOffset: .zero" in surface,
    "surface-does-not-read-runtime-truth": all(token not in surface for token in semantic_tokens),
    "no-repeat-forever": "repeatForever" not in motion
        and "repeatForever" not in surface,
    "overview-one-scroll-probe":
        overview.count("observerTopologyScrollProbe()") == 1,
    "project-one-scroll-probe":
        project.count("observerTopologyScrollProbe()") == 1,
    "approvals-one-scroll-probe":
        approvals.count("observerTopologyScrollProbe()") == 1,
    "exactly-three-production-probes":
        production_pages.count("observerTopologyScrollProbe()") == 3,
    "system-no-scroll-probe":
        "observerTopologyScrollProbe()" not in shell.split(
            "private struct ObserverLiveSettingsView", 1
        )[-1],
    "a-opacity-unchanged":
        "minorOpacity: 0.035" in field
        and "majorOpacity: 0.055" in field,
    "a-warp-unchanged": "warp: 0.16" in field,
    "motion-test-ambient": "ambient drift uses low-amplitude X velocity" in tests
        and "ambient drift uses low-amplitude Y velocity" in tests,
    "motion-test-not-one-to-one":
        "scroll impulse begins without one-to-one displacement jump" in tests,
    "motion-test-inertia": "inertial contribution decays over time" in tests,
    "motion-test-clamp": "extreme scroll velocity is clamped" in tests,
    "motion-test-disabled": "disabled ambient motion produces a static viewport" in tests,
    "motion-test-cadence": "capped at 30 fps or slower" in tests,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL"), name)
print(f"checks={len(checks)} pass={len(checks)-len(failed)} fail={len(failed)}")
raise SystemExit(1 if failed else 0)
