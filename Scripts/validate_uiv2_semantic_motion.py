#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
semantic = (root / "Sources/SwiftUI/Visual/ObserverSemanticMotion.swift").read_text()
ambient = (root / "Sources/SwiftUI/Visual/ObserverTopologyMotion.swift").read_text()
surface = (root / "Sources/SwiftUI/Visual/ObserverScreenSurface.swift").read_text()
components = (root / "Sources/SwiftUI/ObserverComponents.swift").read_text()
overview = (root / "Sources/SwiftUI/OverviewView.swift").read_text()
project = (root / "Sources/SwiftUI/ProjectDetailLiveView.swift").read_text()
approvals = (root / "Sources/SwiftUI/ApprovalsLiveView.swift").read_text()
tests = (root / "Tests/ObserverSemanticMotionTests.swift").read_text()

semantic_forbidden = (
    "ObserverTopology",
    "viewportOffset",
    "scrollOffset",
    "scrollVelocity",
    "TimelineView",
    "ProcessInfo",
    "NSProcessInfoPowerStateDidChange",
    "scenePhase",
    "Date()",
    "ambientVelocity",
    "inertiaTimeConstant",
)

ambient_forbidden = (
    "observerSemantic",
    "CurrentOperationPresentation",
    "ObserverOwnerMutationState",
    "ObserverSessionCloseState",
    "approvalState",
    "deadlinePhase",
    "freshness",
)

checks = {
    "semantic-policy-exists":
        "public enum ObserverSemanticMotionEmphasis" in semantic,
    "semantic-three-levels":
        "case subtle" in semantic
        and "case structural" in semantic
        and "case attention" in semantic,
    "semantic-durations-restrained":
        "case .subtle: return 0.16" in semantic
        and "case .structural: return 0.22" in semantic
        and "case .attention: return 0.26" in semantic,
    "semantic-offsets-restrained":
        "case .subtle: return -2" in semantic
        and "case .structural: return -5" in semantic
        and "case .attention: return -3" in semantic,
    "semantic-reduce-motion":
        "accessibilityReduceMotion" in semantic
        and "reduceMotion ? nil" in semantic
        and "reduceMotion" in semantic
        and "? .opacity" in semantic,
    "semantic-transition-opacity-offset":
        ".asymmetric(" in semantic
        and ".opacity.combined(" in semantic
        and ".offset(" in semantic,
    "semantic-no-repeat":
        "repeatForever" not in semantic,
    "semantic-no-local-state-machine":
        "@State" not in semantic
        and "@Published" not in semantic,
    "semantic-no-ambient-input":
        all(token not in semantic for token in semantic_forbidden),
    "ambient-no-semantic-input":
        all(token not in ambient for token in ambient_forbidden)
        and all(token not in surface for token in (
            "observerSemantic",
            "CurrentOperationPresentation",
            "ObserverOwnerMutationState",
            "ObserverSessionCloseState",
        )),
    "current-identity-presentation-derived":
        "public extension CurrentOperationPresentation" in semantic
        and "kind" in semantic
        and "name" in semantic
        and "startedAt.timeIntervalSinceReferenceDate" in semantic,
    "approval-identity-authoritative-cases":
        "public extension ObserverOwnerMutationState" in semantic
        and "SUBMITTING|" in semantic
        and "CONFLICT|" in semantic
        and "OUTCOME_UNKNOWN|" in semantic
        and "RESOLVED|" in semantic
        and "FAILED|" in semantic,
    "close-identity-authoritative-cases":
        "public extension ObserverSessionCloseState" in semantic
        and '"TRACKING"' in semantic
        and "lifecycle.state" in semantic
        and "lifecycle.cleanupComplete" in semantic,
    "current-block-has-structural-transition":
        ".observerSemanticTransition(.structural)" in components,
    "deadline-server-phase-drives-semantic-motion":
        "value: presentation.serverPhase" in components
        and "presentation.isFinalWarningWindow ? .attention : .subtle" in components,
    "overview-freshness-authoritative":
        "value: live.freshness.rawValue" in overview,
    "overview-current-authoritative":
        'live.currentOperation?.semanticMotionIdentity ?? "NO_CURRENT"' in overview,
    "overview-approval-count-authoritative":
        "value: live.pendingApprovalCount" in overview
        and ".observerSemanticTransition(.attention)" in overview,
    "project-freshness-authoritative":
        "value: presentation.freshness.rawValue" in project,
    "project-current-authoritative":
        'presentation.currentOperation?.semanticMotionIdentity ?? "NO_CURRENT"' in project,
    "approval-list-membership-authoritative":
        r"value: model.ownerApprovals.map(\.approvalID)" in approvals,
    "approval-recent-authoritative":
        "value: model.ownerRecentApproval?.stateVersion ?? -1" in approvals,
    "approval-mutation-authoritative":
        "mutation.semanticMotionIdentity" in approvals
        and ".observerSemanticTransition(.attention)" in approvals,
    "close-state-authoritative":
        ".id(state.semanticMotionIdentity)" in project
        and "value: state.semanticMotionIdentity" in project,
    "close-structural-transition":
        ".observerSemanticTransition(.structural)" in project,
    "test-current-identity":
        "CURRENT identity changes only when presentation truth changes" in tests,
    "test-approval-submitting":
        "Approval mutation identity changes on submitting state" in tests,
    "test-approval-resolution":
        "Approval mutation identity changes on resolution" in tests,
    "test-close-executing-verifying":
        "Close lifecycle identity changes from EXECUTING to VERIFYING" in tests,
    "test-close-verifying-success":
        "Close lifecycle identity changes from VERIFYING to SUCCEEDED" in tests,
    "test-unknown-stable":
        "same authoritative unknown truth keeps stable semantic identity" in tests,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL"), name)
print(f"checks={len(checks)} pass={len(checks)-len(failed)} fail={len(failed)}")
raise SystemExit(1 if failed else 0)
