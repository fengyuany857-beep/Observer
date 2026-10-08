#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
metal = (root / "Sources/SwiftUI/Visual/ObserverTopologyField.metal").read_text()
field = (root / "Sources/SwiftUI/Visual/ObserverTopologyField.swift").read_text()
surface = (root / "Sources/SwiftUI/Visual/ObserverScreenSurface.swift").read_text()
tokens = (root / "Sources/SwiftUI/ObserverDesignTokens.swift").read_text()
overview = (root / "Sources/SwiftUI/OverviewView.swift").read_text()
project = (root / "Sources/SwiftUI/ProjectDetailLiveView.swift").read_text()
approvals = (root / "Sources/SwiftUI/ApprovalsLiveView.swift").read_text()
shell = (root / "Sources/SwiftUI/ObserverLiveShell.swift").read_text()
project_yml = (root / "project.yml").read_text()
notices = (root / "Docs/Observer-UIV2-Visual-Graft-Third-Party-Notices.md").read_text()

production_pages = overview + project + approvals

checks = {
    "metal-stitchable-shader": "[[ stitchable ]] half4 observerStaticTopology" in metal,
    "metal-observation-window-only": "receives only a final viewport offset" in metal,
    "metal-no-time-parameter": "float time" not in metal and "timeSeconds" not in metal,
    "metal-no-scroll-parameter": "scrollOffset" not in metal and "scrollVelocity" not in metal,
    "metal-no-runtime-truth-input": all(token not in metal for token in (
        "isLive", "approvalState", "jobState", "operationState", "healthState"
    )),
    "field-calls-generated-shader": "ShaderLibrary.observerStaticTopology(" in field,
    "field-hit-testing-disabled": ".allowsHitTesting(false)" in field,
    "field-accessibility-hidden": ".accessibilityHidden(true)" in field,
    "palette-surface-token": "surfaceBase" in tokens,
    "palette-minor-token": "topologyMinor" in tokens,
    "palette-major-token": "topologyMajor" in tokens,
    "preset-a-levels-15": "levels: 15" in field,
    "preset-a-warp-016": "warp: 0.16" in field,
    "preset-a-minor-opacity-0035": "minorOpacity: 0.035" in field,
    "preset-a-major-opacity-0055": "majorOpacity: 0.055" in field,
    "surface-topology-optional": "ObserverTopologyConfiguration?" in surface,
    "surface-base-fallback": "ObserverPalette.surfaceBase" in surface,
    "overview-static-a": "ObserverTopologyPreset.barelyThere.configuration" in overview,
    "project-static-a": "ObserverTopologyPreset.barelyThere.configuration" in project,
    "approvals-static-a": "ObserverTopologyPreset.barelyThere.configuration" in approvals,
    "exactly-three-production-a-uses":
        production_pages.count("ObserverTopologyPreset.barelyThere.configuration") == 3,
    "no-balanced-production-use": ".balanced.configuration" not in production_pages,
    "no-upper-bound-production-use": ".upperBound.configuration" not in production_pages,
    "system-not-wrapped": "ObserverScreenSurface" not in shell.split(
        "private struct ObserverLiveSettingsView", 1
    )[-1],
    "xcodegen-recursive-swiftui-source": "- path: Sources/SwiftUI" in project_yml,
    "notices-topolines": "idleCyrex/topolines" in notices and "License: MIT" in notices,
    "notices-simplex": "Ashima Arts / Stefan Gustavson" in notices,
    "notices-inferno": "twostraws/Inferno" in notices,
    "no-runtime-package-dependency-added": "Inferno" not in project_yml and "topolines" not in project_yml,
    "overview-truth-content-retained": "CurrentOperationBlock" in overview
        and "ObserverSessionDeadlineView" in overview,
    "project-truth-content-retained": "CurrentOperationBlock" in project
        and "SessionCloseControl" in project,
    "approvals-truth-content-retained": "APPROVAL REQUIRED" in approvals
        and "ApprovalDecisionButton" in approvals,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL"), name)
print(f"checks={len(checks)} pass={len(checks)-len(failed)} fail={len(failed)}")
raise SystemExit(1 if failed else 0)
