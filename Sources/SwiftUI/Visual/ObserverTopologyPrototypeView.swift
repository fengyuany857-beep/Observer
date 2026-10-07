#if DEBUG
import SwiftUI

public struct ObserverTopologyPrototypeView: View {
    public let preset: ObserverTopologyPreset

    public init(preset: ObserverTopologyPreset) {
        self.preset = preset
    }

    public var body: some View {
        ObserverScreenSurface(topology: preset.configuration) {
            ScrollView {
                VStack(alignment: .leading, spacing: ObserverSpacing.x8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("OBSERVER")
                            .font(.caption.weight(.semibold))
                            .tracking(1.0)
                        Spacer()
                        Text("STATIC TOPOLOGY")
                            .font(.caption2)
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
                        ObserverMetadataKey("EXECUTION")
                        ObserverDisplayText("RUNNING")
                        Text("Truth remains the first visual read.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
                        ObserverMetadataKey("CURRENT OPERATION")
                        Text("Resolve observation semantics")
                            .font(.headline.weight(.medium))
                        Text("OPERATION PROJECTION")
                            .font(.caption2)
                            .tracking(0.45)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, ObserverSpacing.x3)
                    .overlay(alignment: .top) { Divider() }
                    .overlay(alignment: .bottom) { Divider() }

                    VStack(alignment: .leading, spacing: ObserverSpacing.x4) {
                        HStack {
                            ObserverMetadataKey("RUN INSTRUMENTS")
                            Spacer()
                            ObserverMetadataKey("LIVE SNAPSHOT")
                        }

                        HStack(alignment: .top, spacing: ObserverSpacing.x6) {
                            prototypeField("RUN", "8F72A1")
                            prototypeField("STAGE", "04/07")
                            prototypeField("SEQ", "1842")
                        }

                        Divider()

                        HStack(alignment: .top, spacing: ObserverSpacing.x6) {
                            prototypeField("UPDATED", "14:32:18")
                            prototypeField("CURSOR", "184")
                        }
                    }
                    .padding(.vertical, ObserverSpacing.x4)
                    .overlay(alignment: .top) { Divider() }
                    .overlay(alignment: .bottom) { Divider() }

                    VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                        ObserverMetadataKey("PROTOTYPE")
                        Text(preset.title)
                            .font(.callout.monospaced())
                        Text("The topology field is decorative environment only. It carries no execution, health, connection, approval, or progress semantics.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, ObserverSpacing.x10)

                    Spacer(minLength: ObserverSpacing.x18)
                }
                .padding(.horizontal, ObserverSpacing.x5)
                .padding(.top, ObserverSpacing.x4)
                .padding(.bottom, ObserverSpacing.x18)
            }
        }
        .foregroundStyle(.primary)
    }

    private func prototypeField(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x1) {
            ObserverMetadataKey(key)
            Text(value)
                .font(.callout)
                .monospacedDigit()
        }
    }
}

#Preview("Topology A - Barely There") {
    ObserverTopologyPrototypeView(preset: .barelyThere)
        .preferredColorScheme(.dark)
        .frame(width: 390, height: 844)
}

#Preview("Topology B - Balanced") {
    ObserverTopologyPrototypeView(preset: .balanced)
        .preferredColorScheme(.dark)
        .frame(width: 390, height: 844)
}

#Preview("Topology C - Upper Bound") {
    ObserverTopologyPrototypeView(preset: .upperBound)
        .preferredColorScheme(.dark)
        .frame(width: 390, height: 844)
}
#endif
