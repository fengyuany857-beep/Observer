import Foundation
import SwiftUI

public struct ObserverTopologyViewportOffset: Sendable, Equatable {
    public let x: Float
    public let y: Float

    public static let zero = ObserverTopologyViewportOffset(x: 0, y: 0)

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

public struct ObserverTopologyMotionPolicy: Sendable, Equatable {
    public let ambientVelocityX: Double
    public let ambientVelocityY: Double
    public let scrollVelocityToUV: Double
    public let maximumScrollImpulse: Double
    public let inertiaTimeConstant: Double
    public let frameInterval: TimeInterval

    public init(
        ambientVelocityX: Double = 0.0010,
        ambientVelocityY: Double = -0.00065,
        scrollVelocityToUV: Double = -0.000025,
        maximumScrollImpulse: Double = 0.12,
        inertiaTimeConstant: Double = 0.55,
        frameInterval: TimeInterval = 1.0 / 30.0
    ) {
        self.ambientVelocityX = ambientVelocityX
        self.ambientVelocityY = ambientVelocityY
        self.scrollVelocityToUV = scrollVelocityToUV
        self.maximumScrollImpulse = maximumScrollImpulse
        self.inertiaTimeConstant = inertiaTimeConstant
        self.frameInterval = frameInterval
    }

    public static let observerDefault = ObserverTopologyMotionPolicy()
}

public struct ObserverTopologyMotionState: Sendable, Equatable {
    private var lastScrollOffset: Double?
    private var lastScrollTimestamp: TimeInterval?
    private var impulseBaseY: Double = 0
    private var impulseVelocityY: Double = 0
    private var impulseStartTimestamp: TimeInterval = 0

    public init() {}

    public mutating func observeScroll(
        offset: Double,
        timestamp: TimeInterval,
        policy: ObserverTopologyMotionPolicy
    ) {
        let currentInertialY = inertialY(at: timestamp, policy: policy)
        impulseBaseY = currentInertialY

        if let previousOffset = lastScrollOffset,
           let previousTimestamp = lastScrollTimestamp {
            let deltaTime = max(1.0 / 240.0, min(0.25, timestamp - previousTimestamp))
            let pixelsPerSecond = (offset - previousOffset) / deltaTime
            impulseVelocityY = Self.clamp(
                pixelsPerSecond * policy.scrollVelocityToUV,
                minimum: -policy.maximumScrollImpulse,
                maximum: policy.maximumScrollImpulse
            )
            impulseStartTimestamp = timestamp
        } else {
            impulseVelocityY = 0
            impulseStartTimestamp = timestamp
        }

        lastScrollOffset = offset
        lastScrollTimestamp = timestamp
    }

    public func viewportOffset(
        timestamp: TimeInterval,
        epoch: TimeInterval,
        policy: ObserverTopologyMotionPolicy,
        motionEnabled: Bool
    ) -> ObserverTopologyViewportOffset {
        guard motionEnabled else { return .zero }

        let elapsed = max(0, timestamp - epoch)
        let ambientX = elapsed * policy.ambientVelocityX
        let ambientY = elapsed * policy.ambientVelocityY
        let inertialY = inertialY(at: timestamp, policy: policy)

        return ObserverTopologyViewportOffset(
            x: Float(ambientX),
            y: Float(ambientY + inertialY)
        )
    }

    private func inertialY(
        at timestamp: TimeInterval,
        policy: ObserverTopologyMotionPolicy
    ) -> Double {
        guard impulseStartTimestamp > 0 else { return impulseBaseY }

        let elapsed = max(0, timestamp - impulseStartTimestamp)
        let tau = max(0.05, policy.inertiaTimeConstant)
        let integratedImpulse = impulseVelocityY * tau * (1 - exp(-elapsed / tau))
        return impulseBaseY + integratedImpulse
    }

    private static func clamp(
        _ value: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        min(maximum, max(minimum, value))
    }
}

enum ObserverTopologyScrollSpace {
    static let name = "observer-topology-scroll-space"
}

struct ObserverTopologyScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

public extension View {
    func observerTopologyScrollProbe() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ObserverTopologyScrollOffsetPreferenceKey.self,
                    value: proxy.frame(
                        in: .named(ObserverTopologyScrollSpace.name)
                    ).minY
                )
            }
        }
    }
}
