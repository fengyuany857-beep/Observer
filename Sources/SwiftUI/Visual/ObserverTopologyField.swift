import SwiftUI

public struct ObserverTopologyConfiguration {
    public let seedX: Float
    public let seedY: Float
    public let scale: Float
    public let levels: Float
    public let warp: Float
    public let minorLineWidth: Float
    public let majorLineWidth: Float
    public let minorOpacity: Float
    public let majorOpacity: Float
    public let majorEvery: Float
    public let baseColor: Color
    public let minorColor: Color
    public let majorColor: Color

    public init(
        seedX: Float,
        seedY: Float,
        scale: Float,
        levels: Float,
        warp: Float,
        minorLineWidth: Float,
        majorLineWidth: Float,
        minorOpacity: Float,
        majorOpacity: Float,
        majorEvery: Float = 5,
        baseColor: Color,
        minorColor: Color,
        majorColor: Color
    ) {
        self.seedX = seedX
        self.seedY = seedY
        self.scale = scale
        self.levels = levels
        self.warp = warp
        self.minorLineWidth = minorLineWidth
        self.majorLineWidth = majorLineWidth
        self.minorOpacity = minorOpacity
        self.majorOpacity = majorOpacity
        self.majorEvery = majorEvery
        self.baseColor = baseColor
        self.minorColor = minorColor
        self.majorColor = majorColor
    }
}

public enum ObserverTopologyPreset: String, CaseIterable, Identifiable {
    case barelyThere
    case balanced
    case upperBound

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .barelyThere: "A / BARELY THERE"
        case .balanced: "B / BALANCED"
        case .upperBound: "C / UPPER BOUND"
        }
    }

    public var configuration: ObserverTopologyConfiguration {
        switch self {
        case .barelyThere:
            return ObserverTopologyConfiguration(
                seedX: 14.27,
                seedY: -3.91,
                scale: 2.15,
                levels: 15,
                warp: 0.16,
                minorLineWidth: 0.045,
                majorLineWidth: 0.060,
                minorOpacity: 0.035,
                majorOpacity: 0.055,
                baseColor: ObserverPalette.surfaceBase,
                minorColor: ObserverPalette.topologyMinor,
                majorColor: ObserverPalette.topologyMajor
            )

        case .balanced:
            return ObserverTopologyConfiguration(
                seedX: 14.27,
                seedY: -3.91,
                scale: 2.15,
                levels: 15,
                warp: 0.16,
                minorLineWidth: 0.050,
                majorLineWidth: 0.070,
                minorOpacity: 0.060,
                majorOpacity: 0.095,
                baseColor: ObserverPalette.surfaceBase,
                minorColor: ObserverPalette.topologyMinor,
                majorColor: ObserverPalette.topologyMajor
            )

        case .upperBound:
            return ObserverTopologyConfiguration(
                seedX: 14.27,
                seedY: -3.91,
                scale: 2.15,
                levels: 15,
                warp: 0.16,
                minorLineWidth: 0.055,
                majorLineWidth: 0.080,
                minorOpacity: 0.110,
                majorOpacity: 0.170,
                baseColor: ObserverPalette.surfaceBase,
                minorColor: ObserverPalette.topologyMinor,
                majorColor: ObserverPalette.topologyMajor
            )
        }
    }
}

public struct ObserverTopologyField: View {
    public let configuration: ObserverTopologyConfiguration
    public let viewportOffset: ObserverTopologyViewportOffset

    public init(
        configuration: ObserverTopologyConfiguration,
        viewportOffset: ObserverTopologyViewportOffset = .zero
    ) {
        self.configuration = configuration
        self.viewportOffset = viewportOffset
    }

    public var body: some View {
        let baseColor = configuration.baseColor
        let seedX = configuration.seedX
        let seedY = configuration.seedY
        let viewportOffset = viewportOffset
        let scale = configuration.scale
        let levels = configuration.levels
        let warp = configuration.warp
        let minorLineWidth = configuration.minorLineWidth
        let majorLineWidth = configuration.majorLineWidth
        let minorOpacity = configuration.minorOpacity
        let majorOpacity = configuration.majorOpacity
        let majorEvery = configuration.majorEvery
        let minorColor = configuration.minorColor
        let majorColor = configuration.majorColor

        return Rectangle()
            .fill(baseColor)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.observerStaticTopology(
                        .float2(proxy.size),
                        .float(seedX),
                        .float(seedY),
                        .float(viewportOffset.x),
                        .float(viewportOffset.y),
                        .float(scale),
                        .float(levels),
                        .float(warp),
                        .float(minorLineWidth),
                        .float(majorLineWidth),
                        .float(minorOpacity),
                        .float(majorOpacity),
                        .float(majorEvery),
                        .color(minorColor),
                        .color(majorColor)
                    )
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
