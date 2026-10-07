#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
deadline = (root / "Sources/Presentation/ObserverDeadlinePresentation.swift").read_text()
presentation = (root / "Sources/Presentation/ObserverPresentation.swift").read_text()
components = (root / "Sources/SwiftUI/ObserverComponents.swift").read_text()
overview = (root / "Sources/SwiftUI/OverviewView.swift").read_text()
project = (root / "Sources/SwiftUI/ProjectDetailLiveView.swift").read_text()
tests = (root / "Tests/ObserverDeadlineUXTests.swift").read_text()
freeze = (root / "Reference/B8/observer-backend-contract-freeze-v1.json").read_text()

checks = {
    "frozen-hard-ttl": '"hard_ttl_seconds": 1500' in freeze,
    "frozen-close-reminder": '"close_reminder_seconds": 90' in freeze,
    "frozen-phases": all(value in freeze for value in (
        '"ACTIVE"', '"CLOSE_REQUIRED"', '"HARD_EXPIRED"', '"TERMINAL"'
    )),
    "deadline-policy-file": "public struct ObserverDeadlineUXPresentation" in deadline,
    "server-phase-enum": 'case closeRequired = "CLOSE_REQUIRED"' in deadline
        and 'case hardExpired = "HARD_EXPIRED"' in deadline,
    "server-derived-remaining": "remainingSeconds: Int" in deadline,
    "server-derived-elapsed": "elapsedSeconds: Int" in deadline,
    "server-derived-hard-ttl": "hardTTLSeconds: Int" in deadline,
    "server-derived-reminder": "closeReminderSeconds: Int" in deadline,
    "server-close-required-input": "serverCloseRequired: Bool" in deadline,
    "phase-close-required-consistency": "serverCloseRequired == (phase == .closeRequired)" in deadline,
    "inconsistent-fails-closed": "DEADLINE INCONSISTENT" in deadline
        and "OWNER CLOSE WITHHELD" in deadline
        and "guard transportLive && contractConsistent else { return false }" in deadline,
    "active-not-expired": 'case .active: return "SESSION ACTIVE"' in deadline,
    "close-required-save-exit": 'case .closeRequired: return "SAVE & EXIT"' in deadline,
    "hard-expired-expired": 'case .hardExpired: return "SESSION EXPIRED"' in deadline,
    "terminal-ended": 'case .terminal: return "SESSION ENDED"' in deadline,
    "close-required-still-active": "SESSION STILL ACTIVE" in deadline,
    "hard-expired-blocks-close": "phase == .active || phase == .closeRequired" in deadline,
    "cached-is-last-observed": r'return "LAST OBSERVED · \(serverPhase)"' in deadline,
    "no-local-deadline-clock": "TimelineView" not in deadline
        and "Date()" not in deadline
        and ".now" not in deadline,
    "no-local-phase-inference-from-seconds": "remainingSeconds ==" not in deadline
        and "elapsedSeconds >=" not in deadline
        and "elapsedSeconds ==" not in deadline,
    "shared-deadline-view": "public struct ObserverSessionDeadlineView" in components,
    "reduce-motion": "accessibilityReduceMotion" in components
        and "reduceMotion ? nil" in components,
    "no-repeat-forever": "repeatForever" not in components,
    "numeric-transition-only": ".numericText(value: Double(presentation.remainingSeconds))" in components,
    "phase-transition-motion": "value: presentation.serverPhase" in components,
    "overview-uses-shared-deadline": "ObserverSessionDeadlineView(" in overview,
    "project-uses-shared-deadline": "ObserverSessionDeadlineView(deadline)" in project,
    "overview-passes-close-required": "serverCloseRequired: session.closeRequired" in overview,
    "project-passes-close-required": "serverCloseRequired: session.closeRequired" in project,
    "project-close-uses-deadline-policy": "deadline.allowsNewSessionClose" in project,
    "project-expired-copy": "SESSION EXPIRED · CLOSE NOT STARTED" in project,
    "project-terminal-copy": "The Session is already terminal." in project,
    "project-inconsistent-copy": "CLOSE PAUSED · DEADLINE INCONSISTENT" in project,
    "presentation-carries-server-fields": all(token in presentation for token in (
        "item.deadline.remainingSeconds",
        "item.deadline.elapsedSeconds",
        "item.deadline.hardTTLSeconds",
        "item.deadline.closeReminderSeconds",
        "item.deadline.phase",
        "item.deadline.closeRequired",
    )),
    "test-2329": '23:29 consumes server ACTIVE' in tests,
    "test-2330": '23:30 consumes server CLOSE_REQUIRED' in tests,
    "test-2400": '24:00 remains Save & Exit' in tests,
    "test-2459": '24:59 remains warning not expired' in tests,
    "test-2500": '25:00 consumes server HARD_EXPIRED' in tests,
    "test-offline": 'offline deadline cannot authorize close' in tests,
    "test-inconsistent": 'inconsistent deadline fails closed' in tests,
    "test-unknown": 'unknown phase withholds owner close' in tests,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL"), name)
print(f"checks={len(checks)} pass={len(checks)-len(failed)} fail={len(failed)}")
raise SystemExit(1 if failed else 0)
