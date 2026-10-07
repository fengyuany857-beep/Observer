import Foundation

private var failures = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("PASS \(message)")
    } else {
        print("FAIL \(message)")
        failures += 1
    }
}

private func deadline(
    phase: String,
    elapsed: Int,
    remaining: Int,
    closeRequired: Bool,
    live: Bool = true
) -> ObserverDeadlineUXPresentation {
    ObserverDeadlineUXPresentation(
        serverPhase: phase,
        remainingSeconds: remaining,
        elapsedSeconds: elapsed,
        hardTTLSeconds: 1500,
        closeReminderSeconds: 90,
        serverCloseRequired: closeRequired,
        transportLive: live
    )
}

@main
struct ObserverDeadlineUXTests {
    static func main() {
        let t2329 = deadline(
            phase: "ACTIVE",
            elapsed: 1409,
            remaining: 91,
            closeRequired: false
        )
        expect(t2329.phase == .active, "23:29 consumes server ACTIVE")
        expect(t2329.headline == "SESSION ACTIVE", "23:29 stays quiet active")
        expect(!t2329.isFinalWarningWindow, "23:29 is not final warning window")
        expect(t2329.allowsNewSessionClose, "23:29 owner close remains available")

        let t2330 = deadline(
            phase: "CLOSE_REQUIRED",
            elapsed: 1410,
            remaining: 90,
            closeRequired: true
        )
        expect(t2330.phase == .closeRequired, "23:30 consumes server CLOSE_REQUIRED")
        expect(t2330.headline == "SAVE & EXIT", "23:30 enters Save & Exit")
        expect(t2330.isFinalWarningWindow, "23:30 begins final 90 second window")
        expect(t2330.allowsNewSessionClose, "23:30 does not imply expiry")
        expect(
            t2330.detail?.contains("SESSION STILL ACTIVE") == true,
            "23:30 explicitly remains active"
        )

        let t2400 = deadline(
            phase: "CLOSE_REQUIRED",
            elapsed: 1440,
            remaining: 60,
            closeRequired: true
        )
        expect(t2400.headline == "SAVE & EXIT", "24:00 remains Save & Exit")
        expect(t2400.remainingSeconds == 60, "24:00 uses server remaining 60")

        let t2459 = deadline(
            phase: "CLOSE_REQUIRED",
            elapsed: 1499,
            remaining: 1,
            closeRequired: true
        )
        expect(t2459.isFinalWarningWindow, "24:59 remains warning not expired")
        expect(t2459.allowsNewSessionClose, "24:59 owner close remains available")

        let t2500 = deadline(
            phase: "HARD_EXPIRED",
            elapsed: 1500,
            remaining: 0,
            closeRequired: false
        )
        expect(t2500.phase == .hardExpired, "25:00 consumes server HARD_EXPIRED")
        expect(t2500.headline == "SESSION EXPIRED", "25:00 renders expired")
        expect(t2500.shouldPresentAsExpired, "25:00 is visually expired")
        expect(!t2500.allowsNewSessionClose, "25:00 blocks a new close attempt")

        let terminal = deadline(
            phase: "TERMINAL",
            elapsed: 1500,
            remaining: 0,
            closeRequired: false
        )
        expect(terminal.headline == "SESSION ENDED", "terminal renders ended")
        expect(!terminal.allowsNewSessionClose, "terminal blocks new close")

        let cachedWarning = deadline(
            phase: "CLOSE_REQUIRED",
            elapsed: 1420,
            remaining: 80,
            closeRequired: true,
            live: false
        )
        expect(
            cachedWarning.headline == "LAST OBSERVED · CLOSE_REQUIRED",
            "offline deadline is last-observed truth"
        )
        expect(!cachedWarning.allowsNewSessionClose, "offline deadline cannot authorize close")

        let inconsistent = deadline(
            phase: "ACTIVE",
            elapsed: 100,
            remaining: 1400,
            closeRequired: true
        )
        expect(!inconsistent.contractConsistent, "phase/close_required mismatch detected")
        expect(
            inconsistent.headline == "DEADLINE INCONSISTENT",
            "inconsistent server deadline is explicit"
        )
        expect(!inconsistent.allowsNewSessionClose, "inconsistent deadline fails closed")

        let unknown = deadline(
            phase: "FUTURE_PHASE",
            elapsed: 10,
            remaining: 1490,
            closeRequired: false
        )
        expect(unknown.phase == .unknown, "unknown server phase remains unknown")
        expect(!unknown.allowsNewSessionClose, "unknown phase withholds owner close")

        if failures > 0 {
            print("ObserverDeadlineUXTests FAIL \(failures)")
            exit(1)
        }
        print("ObserverDeadlineUXTests PASS")
    }
}
