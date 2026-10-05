import SwiftUI

public enum ObserverSpacing {
    public static let x1: CGFloat = 4
    public static let x2: CGFloat = 8
    public static let x3: CGFloat = 12
    public static let x4: CGFloat = 16
    public static let x5: CGFloat = 20
    public static let x6: CGFloat = 24
    public static let x8: CGFloat = 32
    public static let x10: CGFloat = 40
    public static let x14: CGFloat = 56
    public static let x18: CGFloat = 72
}

public enum ObserverRadius {
    public static let none: CGFloat = 0
    public static let micro: CGFloat = 4
    public static let control: CGFloat = 8
    public static let container: CGFloat = 12
}

public enum ObserverPalette {
    public static func color(for tone: SemanticTone) -> Color {
        switch tone {
        case .positive: .green
        case .warning: .orange
        case .negative: .red
        case .neutral: .secondary
        case .connection: .blue
        }
    }

    public static func healthColor(_ health: RuntimeHealth) -> Color {
        switch health {
        case .active: .green
        case .slow, .stale, .suspectedStuck: .orange
        case .unknown: .secondary
        }
    }
}

public struct ObserverDisplayText: View {
    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 58
    public let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.system(size: displaySize, weight: .medium, design: .default))
            .tracking(-1.4)
            .lineLimit(2)
            .accessibilityAddTraits(.isHeader)
    }
}

public struct ObserverMetadataKey: View {
    public let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.medium))
            .tracking(0.55)
            .foregroundStyle(.secondary)
    }
}

public extension View {
    @ViewBuilder
    func observerTabBarMinimizeIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    @ViewBuilder
    func observerSearchToolbarMinimizeIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            self.searchToolbarBehavior(.minimize)
        } else {
            self
        }
    }
}
