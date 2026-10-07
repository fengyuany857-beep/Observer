import Foundation
import SwiftUI

private var failures = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("PASS \(message)")
    } else {
        print("FAIL \(message)")
        failures += 1
    }
}

private func approximately(
    _ lhs: Float,
    _ rhs: Float,
    tolerance: Float = 0.000_01
) -> Bool {
    abs(lhs - rhs) <= tolerance
}

@main
struct ObserverTopologyMotionTests {
    static func main() {
        let defaultPolicy = ObserverTopologyMotionPolicy.observerDefault

        do {
            let state = ObserverTopologyMotionState()
            let offset = state.viewportOffset(
                timestamp: 110,
                epoch: 100,
                policy: defaultPolicy,
                motionEnabled: true
            )
            expect(
                approximately(offset.x, 0.01),
                "ambient drift uses low-amplitude X velocity"
            )
            expect(
                approximately(offset.y, -0.0065),
                "ambient drift uses low-amplitude Y velocity"
            )
        }

        do {
            var state = ObserverTopologyMotionState()
            state.observeScroll(
                offset: 0,
                timestamp: 100,
                policy: defaultPolicy
            )
            state.observeScroll(
                offset: -100,
                timestamp: 100.1,
                policy: defaultPolicy
            )
            let start = state.viewportOffset(
                timestamp: 100.1,
                epoch: 100.1,
                policy: defaultPolicy,
                motionEnabled: true
            )
            let middle = state.viewportOffset(
                timestamp: 100.65,
                epoch: 100.1,
                policy: defaultPolicy,
                motionEnabled: true
            )
            let late = state.viewportOffset(
                timestamp: 102.3,
                epoch: 100.1,
                policy: defaultPolicy,
                motionEnabled: true
            )

            expect(
                approximately(start.y, 0),
                "scroll impulse begins without one-to-one displacement jump"
            )
            expect(
                middle.y > start.y,
                "scroll velocity creates low-amplitude inertial movement"
            )
            expect(
                late.y > middle.y,
                "inertia integrates toward a bounded resting offset"
            )
            expect(
                (late.y - middle.y) < (middle.y - start.y),
                "inertial contribution decays over time"
            )
        }

        do {
            let policy = ObserverTopologyMotionPolicy(
                ambientVelocityX: 0,
                ambientVelocityY: 0,
                scrollVelocityToUV: 1,
                maximumScrollImpulse: 0.12,
                inertiaTimeConstant: 0.55,
                frameInterval: 1.0 / 30.0
            )
            var state = ObserverTopologyMotionState()
            state.observeScroll(offset: 0, timestamp: 10, policy: policy)
            state.observeScroll(offset: 10_000, timestamp: 10.01, policy: policy)
            let value = state.viewportOffset(
                timestamp: 20,
                epoch: 10,
                policy: policy,
                motionEnabled: true
            )
            expect(
                abs(value.y) <= 0.067,
                "extreme scroll velocity is clamped before inertial integration"
            )
        }

        do {
            var state = ObserverTopologyMotionState()
            state.observeScroll(
                offset: 0,
                timestamp: 100,
                policy: defaultPolicy
            )
            state.observeScroll(
                offset: -500,
                timestamp: 100.05,
                policy: defaultPolicy
            )
            let disabled = state.viewportOffset(
                timestamp: 110,
                epoch: 100,
                policy: defaultPolicy,
                motionEnabled: false
            )
            expect(
                disabled == .zero,
                "disabled ambient motion produces a static viewport"
            )
        }

        expect(
            abs(defaultPolicy.ambientVelocityX) <= 0.001,
            "default ambient X drift remains deliberately slow"
        )
        expect(
            abs(defaultPolicy.ambientVelocityY) <= 0.001,
            "default ambient Y drift remains deliberately slow"
        )
        expect(
            defaultPolicy.frameInterval >= 1.0 / 30.0,
            "default ambient cadence is capped at 30 fps or slower"
        )

        if failures > 0 {
            print("ObserverTopologyMotionTests FAIL \(failures)")
            exit(1)
        }
        print("ObserverTopologyMotionTests PASS")
    }
}
