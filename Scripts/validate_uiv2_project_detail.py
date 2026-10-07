#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
truth = (root / "Sources/Domain/ObserverB8Truth.swift").read_text()
source = (root / "Sources/Domain/ObserverB8LiveDataSource.swift").read_text()
presentation = (root / "Sources/Presentation/ObserverPresentation.swift").read_text()
view = (root / "Sources/SwiftUI/ProjectDetailLiveView.swift").read_text()
shell = (root / "Sources/SwiftUI/ObserverLiveShell.swift").read_text()
deadline = (root / "Sources/Presentation/ObserverDeadlinePresentation.swift").read_text()

checks = {
    "frozen-jobs-contract": 'jobs = "observer.jobs.v1"' in truth,
    "job-truth-model": "public struct ObserverB8JobTruth" in truth,
    "effect-truth-model": "public struct ObserverB8EffectTruth" in truth,
    "jobs-generation-chain": "let jobGeneration = issueGeneration()" in source
        and "activeGeneration = jobGeneration" in source,
    "jobs-source-continuity": "payload.sourceInstanceID == expectedSourceInstanceID" in source,
    "jobs-project-scope": "$0.projectID == configuration.projectID" in source,
    "jobs-state-class-boundary": '"LAST_OBSERVED_ACTIVE"' in source
        and '"TERMINAL_CONFIRMED"' in source,
    "project-detail-builder": "makeProjectDetail(" in presentation,
    "project-session-hierarchy": "let sessionID = runtime.session?.sessionID" in presentation,
    "jobs-bound-to-session": "return job.sessionID == sessionID" in presentation,
    "current-from-backend-runtime": "currentOperation: runtime.currentOperation" in presentation,
    "lifecycle-truth": "backend.lifecycleOperations" in presentation,
    "effect-truth": "backend.effects" in presentation,
    "last-observed-label": 'ObserverMetadataKey("JOBS · LAST OBSERVED")' in view,
    "last-observed-state-visible": "job.stateClass" in view,
    "offline-current-demotion": "NO LIVE CURRENT · LAST OBSERVED ONLY" in view,
    "server-deadline-phase": "session.deadlinePhase" in view,
    "close-required-not-expired": "ObserverSessionDeadlineView(deadline)" in view
        and "serverCloseRequired: session.closeRequired" in view
        and 'case .closeRequired: return "SAVE & EXIT"' in deadline
        and 'case .hardExpired: return "SESSION EXPIRED"' in deadline,
    "effect-attention-visible": "effect.needsAttention" in view,
    "lifecycle-unknown-visible": '"OUTCOME_UNKNOWN"' in view,
    "live-tab-is-projects": 'Label("Projects"' in shell
        and "ProjectDetailLiveView(" in shell
        and "presentation: project" in shell,
    "legacy-runs-not-live-tab": 'Label("Runs"' not in shell,
    "no-job-current-synthesis": 'job.gatewayState == "RUNNING"' not in presentation
        and 'job.gatewayState == "RUNNING"' not in view,
    "no-approval-mutation-in-project-detail": all(token not in view for token in (
        "ALLOW", "DENY", "APPROVAL_DECIDE"
    )),
    "swift-interpolation-preserved": r'Text("TASK \(String(effect.taskID.suffix(8)).uppercased()) · GEN \(effect.generation)")' in view,
    "no-lost-interpolation-artifact": 'TASK (String(effect.taskID' not in view,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL"), name)
print(f"checks={len(checks)} pass={len(checks)-len(failed)} fail={len(failed)}")
raise SystemExit(1 if failed else 0)
