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
        let graphite = Color(red: 0.035, green: 0.039, blue: 0.043)
        let minor = Color(red: 0.42, green: 0.45, blue: 0.48)
        let major = Color(red: 0.55, green: 0.58, blue: 0.61)

        switch self {
        case .barelyThere:
            ObserverTopologyConfiguration(
                seedX: 14.27,
                seedY: -3.91,
                scale: 2.15,
                levels: 15,
                warp: 0.16,
                minorLineWidth: 0.045,
                majorLineWidth: 0.060,
                minorOpacity: 0.035,
                majorOpacity: 0.055,
                baseColor: graphite,
                minorColor: minor,
                majorColor: major
            )

        case .balanced:
            ObserverTopologyConfiguration(
                seedX: 14.27,
                seedY: -3.91,
                scale: 2.15,
                levels: 15,
                warp: 0.16,
                minorLineWidth: 0.050,
                majorLineWidth: 0.070,
                minorOpacity: 0.060,
                majorOpacity: 0.095,
                baseColor: graphite,
                minorColor: minor,
                majorColor: major
            )

        case .upperBound:
            ObserverTopologyConfiguration(
                seedX: 14.27,
                seedY: -3.91,
                scale: 2.15,
                levels: 15,
                warp: 0.16,
                minorLineWidth: 0.055,
                majorLineWidth: 0.080,
                minorOpacity: 0.110,
                majorOpacity: 0.170,
                baseColor: graphite,
                minorColor: minor,
                majorColor: major
            )
        }
    }
}

public struct ObserverTopologyField: View {
    public let configuration: ObserverTopologyConfiguration

    public init(configuration: ObserverTopologyConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        Rectangle()
            .fill(configuration.baseColor)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.observerStaticTopology(
                        .float2(proxy.size),
                        .float(configuration.seedX),
                        .float(configuration.seedY),
                        .float(configuration.scale),
                        .float(configuration.levels),
                        .float(configuration.warp),
                        .float(configuration.minorLineWidth),
                        .float(configuration.majorLineWidth),
                        .float(configuration.minorOpacity),
                        .float(configuration.majorOpacity),
                        .float(configuration.majorEvery),
                        .color(configuration.minorColor),
                        .color(configuration.majorColor)
                    )
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
