import SwiftUI

public struct ObserverScreenSurface<Content: View>: View {
    public let topology: ObserverTopologyConfiguration?
    private let content: Content

    public init(
        topology: ObserverTopologyConfiguration? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.topology = topology
        self.content = content()
    }

    public var body: some View {
        ZStack {
            if let topology {
                ObserverTopologyField(configuration: topology)
                    .ignoresSafeArea()
            } else {
                Color(red: 0.035, green: 0.039, blue: 0.043)
                    .ignoresSafeArea()
            }

            content
        }
    }
}
