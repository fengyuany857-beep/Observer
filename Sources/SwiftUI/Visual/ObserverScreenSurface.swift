import Combine
import SwiftUI

public struct ObserverScreenSurface<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    public let topology: ObserverTopologyConfiguration?
    public let motionPolicy: ObserverTopologyMotionPolicy

    private let content: Content

    @State private var motionState = ObserverTopologyMotionState()
    @State private var motionEpoch = Date.timeIntervalSinceReferenceDate
    @State private var lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    public init(
        topology: ObserverTopologyConfiguration? = nil,
        motionPolicy: ObserverTopologyMotionPolicy = .observerDefault,
        @ViewBuilder content: () -> Content
    ) {
        self.topology = topology
        self.motionPolicy = motionPolicy
        self.content = content()
    }

    public var body: some View {
        ZStack {
            topologyBackground
            content
        }
        .coordinateSpace(name: ObserverTopologyScrollSpace.name)
        .onPreferenceChange(ObserverTopologyScrollOffsetPreferenceKey.self) { offset in
            guard motionEnabled else { return }
            motionState.observeScroll(
                offset: Double(offset),
                timestamp: Date.timeIntervalSinceReferenceDate,
                policy: motionPolicy
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name.NSProcessInfoPowerStateDidChange
            )
        ) { _ in
            lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                motionEpoch = Date.timeIntervalSinceReferenceDate
            }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled {
                motionState = ObserverTopologyMotionState()
            } else {
                motionEpoch = Date.timeIntervalSinceReferenceDate
            }
        }
    }

    @ViewBuilder
    private var topologyBackground: some View {
        if let topology {
            if motionEnabled {
                TimelineView(
                    .periodic(
                        from: Date(),
                        by: motionPolicy.frameInterval
                    )
                ) { context in
                    ObserverTopologyField(
                        configuration: topology,
                        viewportOffset: motionState.viewportOffset(
                            timestamp: context.date.timeIntervalSinceReferenceDate,
                            epoch: motionEpoch,
                            policy: motionPolicy,
                            motionEnabled: true
                        )
                    )
                    .ignoresSafeArea()
                }
            } else {
                ObserverTopologyField(
                    configuration: topology,
                    viewportOffset: .zero
                )
                .ignoresSafeArea()
            }
        } else {
            ObserverPalette.surfaceBase
                .ignoresSafeArea()
        }
    }

    private var motionEnabled: Bool {
        !reduceMotion
            && !lowPowerModeEnabled
            && scenePhase == .active
    }
}
