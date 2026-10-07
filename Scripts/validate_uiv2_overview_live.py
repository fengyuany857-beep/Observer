from pathlib import Path

presentation = Path('Sources/Presentation/ObserverPresentation.swift').read_text()
view = Path('Sources/SwiftUI/OverviewView.swift').read_text()
live = Path('Sources/SwiftUI/ObserverLiveShell.swift').read_text()
components = Path('Sources/SwiftUI/ObserverComponents.swift').read_text()
deadline = Path('Sources/Presentation/ObserverDeadlinePresentation.swift').read_text()

checks = {
    'envelope-overview-entry': 'makeOverview(_ envelope: ObserverDataEnvelope)' in presentation,
    'backend-truth-source': 'guard let backend = envelope.backendTruth' in presentation,
    'project-session-runtime-model': 'OverviewLiveRuntimePresentation' in presentation and 'OverviewSessionPresentation' in presentation,
    'current-from-backend-only': 'backend.currentOperation(for:' in presentation,
    'no-job-current-synthesis': 'jobs.RUNNING' not in presentation and 'gateway_state' not in presentation,
    'session-deadline-server-truth': 'item.deadline.remainingSeconds' in presentation and 'item.deadline.phase' in presentation and 'item.deadline.closeRequired' in presentation,
    'pending-approval-count': 'backend.approvals.filter { $0.state == "PENDING" }.count' in presentation,
    'queued-session-count': 'backend.sessions.filter { $0.state == "QUEUED" }.count' in presentation,
    'live-overview-prefers-runtime': 'if let live = presentation.liveRuntime' in view,
    'offline-current-demotion': 'NO LIVE CURRENT · LAST OBSERVED ONLY' in view,
    'manual-refresh-read-path': 'refresh: { Task { await model.refresh() } }' in live,
    'manual-refresh-no-authority-copy': 'ALLOW' not in view and 'DENY' not in view,
    'close-required-save-exit': 'ObserverSessionDeadlineView(' in view and 'serverCloseRequired: session.closeRequired' in view and 'SAVE & EXIT' in deadline,
    'legacy-preview-fallback': 'focusContent' in view and 'liveRuntime: OverviewLiveRuntimePresentation? = nil' in presentation,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL'), name)
print(f'checks={len(checks)} pass={len(checks)-len(failed)} fail={len(failed)}')
raise SystemExit(1 if failed else 0)
