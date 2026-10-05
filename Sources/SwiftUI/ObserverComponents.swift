import SwiftUI

public struct ObserverPageIdentity: View {
    let title: String
    let subtitle: String?
    public init(_ title: String, subtitle: String? = nil) { self.title = title; self.subtitle = subtitle }
    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(1.0)
            Spacer()
            if let subtitle {
                Text(subtitle.uppercased()).font(.caption2).foregroundStyle(.secondary).tracking(0.5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

public struct ObserverStatusHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let presentation: StatusPresentation
    public init(_ presentation: StatusPresentation) { self.presentation = presentation }

    public var body: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
            HStack(alignment: .center, spacing: ObserverSpacing.x2) {
                ObserverMetadataKey("EXECUTION")
                Spacer(minLength: ObserverSpacing.x3)
                Image(systemName: presentation.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ObserverPalette.color(for: presentation.tone))
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                Text(presentation.rawValue)
                    .font(.caption2.weight(.medium))
                    .tracking(0.45)
                    .foregroundStyle(.secondary)
            }

            ObserverDisplayText(presentation.primary)
                .contentTransition(.opacity)

            if let secondary = presentation.secondary {
                ObserverFunctionalSignal(secondary, tone: presentation.tone)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: presentation.rawValue)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([presentation.primary, presentation.secondary].compactMap { $0 }.joined(separator: ", "))
    }
}

public struct ObserverFunctionalSignal: View {
    let title: String
    let tone: SemanticTone

    public init(_ title: String, tone: SemanticTone) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: ObserverSpacing.x3) {
            Rectangle()
                .fill(ObserverPalette.color(for: tone))
                .frame(width: 2, height: 24)
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.55)
            Spacer(minLength: 0)
        }
        .padding(.vertical, ObserverSpacing.x2)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

public struct RuntimeHealthAttentionNode: View {
    let health: RuntimeHealth

    public init(_ health: RuntimeHealth) {
        self.health = health
    }

    public var body: some View {
        HStack(spacing: ObserverSpacing.x3) {
            Rectangle()
                .fill(ObserverPalette.healthColor(health))
                .frame(width: 2, height: 30)
            VStack(alignment: .leading, spacing: ObserverSpacing.x1) {
                ObserverMetadataKey("RUNTIME HEALTH")
                Text(health.rawValue.split(separator: "_").joined(separator: " "))
                    .font(.headline.weight(.medium))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, ObserverSpacing.x2)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

public struct ConnectionIncidentBar: View {
    let incident: ConnectionIncidentPresentation
    let liveLabel: Bool
    public init(_ incident: ConnectionIncidentPresentation, liveLabel: Bool = false) { self.incident = incident; self.liveLabel = liveLabel }
    public var body: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
            if liveLabel { ObserverMetadataKey("LIVE CONNECTION") }
            HStack(alignment: .top, spacing: ObserverSpacing.x3) {
                Image(systemName: incident.symbolName)
                    .foregroundStyle(ObserverPalette.color(for: incident.tone))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: ObserverSpacing.x1) {
                    Text(incident.title).font(.headline)
                    if let detail = incident.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, ObserverSpacing.x3)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

public struct ObserverLiveConnectionRail: View {
    let incident: ConnectionIncidentPresentation

    public init(_ incident: ConnectionIncidentPresentation) {
        self.incident = incident
    }

    public var body: some View {
        HStack(spacing: ObserverSpacing.x2) {
            ObserverMetadataKey("LIVE CONNECTION")
            Spacer(minLength: ObserverSpacing.x3)
            Circle()
                .fill(ObserverPalette.color(for: incident.tone))
                .frame(width: 5, height: 5)
            Text(incident.title.uppercased())
                .font(.caption2.weight(.medium))
                .tracking(0.45)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, ObserverSpacing.x2)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

public struct CompletionTruthBlock: View {
    let truth: CompletionTruth
    public init(_ truth: CompletionTruth) { self.truth = truth }
    public var body: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
            ObserverMetadataKey("COMPLETION TRUTH")
            TruthLine(symbol: truth.engineeringComplete ? "checkmark" : "minus", label: "Engineering complete", active: truth.engineeringComplete)
            TruthLine(symbol: truth.artifactVerified ? "checkmark" : "minus", label: "Artifact verified", active: truth.artifactVerified)
            if truth.presentationConfirmed {
                TruthLine(symbol: "checkmark", label: "Final reply presented", active: true)
            } else if truth.presentationUnknown {
                TruthLine(symbol: "questionmark", label: "Final reply presentation unknown", active: false)
            }
        }
        .padding(.vertical, ObserverSpacing.x2)
    }

    private struct TruthLine: View {
        let symbol: String
        let label: String
        let active: Bool
        var body: some View {
            HStack(spacing: ObserverSpacing.x2) {
                Image(systemName: symbol).frame(width: 16)
                Text(label).font(.callout)
            }
            .foregroundStyle(active ? .primary : .secondary)
        }
    }
}

public struct DenseMetadataNode: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let fields: [MetadataFieldPresentation]
    public init(_ fields: [MetadataFieldPresentation]) { self.fields = fields }

    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ObserverSpacing.x3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: ObserverSpacing.x6))

        layout {
            ForEach(fields.prefix(6)) { field in
                VStack(alignment: .leading, spacing: ObserverSpacing.x1) {
                    ObserverMetadataKey(field.key)
                    Text(field.value)
                        .font(.callout)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, ObserverSpacing.x2)
    }
}

public struct ObserverInstrumentNode: View {
    let fields: [MetadataFieldPresentation]
    let healthFreshness: HealthFreshnessPresentation
    let terminal: Bool
    let startedAt: Date
    let endedAt: Date?
    let tests: TestsPresentation
    let checkpoint: CheckpointPresentation?
    let healthAttentionElevated: Bool

    public init(
        fields: [MetadataFieldPresentation],
        healthFreshness: HealthFreshnessPresentation,
        terminal: Bool,
        startedAt: Date,
        endedAt: Date?,
        tests: TestsPresentation,
        checkpoint: CheckpointPresentation?,
        healthAttentionElevated: Bool = false
    ) {
        self.fields = fields
        self.healthFreshness = healthFreshness
        self.terminal = terminal
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.tests = tests
        self.checkpoint = checkpoint
        self.healthAttentionElevated = healthAttentionElevated
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                ObserverMetadataKey("RUN INSTRUMENTS")
                Spacer()
                ObserverMetadataKey(terminal ? "FINAL SNAPSHOT" : "LIVE SNAPSHOT")
            }

            DenseMetadataNode(fields)

            Divider()

            HStack(alignment: .bottom, spacing: ObserverSpacing.x4) {
                if healthAttentionElevated {
                    VStack(alignment: .leading, spacing: ObserverSpacing.x1) {
                        ObserverMetadataKey(terminal ? "FINAL OBSERVED" : "UPDATED")
                        Text(healthFreshness.updatedAt, style: .time)
                            .font(.callout)
                            .monospacedDigit()
                    }
                } else {
                    HealthFreshnessBlock(healthFreshness, terminal: terminal)
                }

                Spacer(minLength: ObserverSpacing.x3)

                VStack(alignment: .trailing, spacing: ObserverSpacing.x1) {
                    ObserverMetadataKey("ELAPSED")
                    LocalElapsedClock(startedAt: startedAt, endedAt: endedAt)
                }
            }

            Divider()

            TestProgressRow(tests)

            if let checkpoint {
                Divider()
                CheckpointRow(checkpoint)
            }
        }
        .padding(.vertical, ObserverSpacing.x4)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }
}

public struct CurrentOperationBlock: View {
    let operation: CurrentOperationPresentation
    public init(_ operation: CurrentOperationPresentation) { self.operation = operation }
    public var body: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
            ObserverMetadataKey("CURRENT OPERATION")
            HStack(alignment: .firstTextBaseline) {
                Text(operation.name).font(.headline.weight(.medium))
                Spacer()
                Text(operation.kind.uppercased()).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

public struct StageProgressRule: View {
    let completed: Int
    let total: Int
    public init(completed: Int, total: Int) { self.completed = completed; self.total = max(total, 1) }
    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(.quaternary).frame(height: 1)
                Rectangle().fill(.primary).frame(width: proxy.size.width * min(max(CGFloat(completed) / CGFloat(total), 0), 1), height: 2)
            }
        }
        .frame(height: 2)
        .accessibilityLabel("Stage progress")
        .accessibilityValue("\(completed) of \(total)")
    }
}

public struct HealthFreshnessBlock: View {
    let value: HealthFreshnessPresentation
    let terminal: Bool
    public init(_ value: HealthFreshnessPresentation, terminal: Bool = false) {
        self.value = value
        self.terminal = terminal
    }
    public var body: some View {
        HStack(alignment: .top, spacing: ObserverSpacing.x6) {
            VStack(alignment: .leading, spacing: ObserverSpacing.x1) {
                ObserverMetadataKey(terminal ? "FINAL HEALTH" : "HEALTH")
                Label(value.health.rawValue.split(separator: "_").joined(separator: " "), systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ObserverPalette.healthColor(value.health))
            }
            VStack(alignment: .leading, spacing: ObserverSpacing.x1) {
                ObserverMetadataKey(terminal ? "FINAL OBSERVED" : "UPDATED")
                Text(value.updatedAt, style: .time).font(.callout).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
    }
}

public struct TestProgressRow: View {
    let tests: TestsPresentation
    public init(_ tests: TestsPresentation) { self.tests = tests }
    public var body: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
            HStack {
                ObserverMetadataKey("TESTS")
                Spacer()
                Text("\(tests.completed)/\(tests.total)").font(.callout).monospacedDigit()
            }
            StageProgressRule(completed: tests.completed, total: tests.total)
        }
    }
}

public struct CheckpointRow: View {
    let checkpoint: CheckpointPresentation
    public init(_ checkpoint: CheckpointPresentation) { self.checkpoint = checkpoint }
    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: ObserverSpacing.x1) {
                ObserverMetadataKey("CHECKPOINT")
                Text(checkpoint.id).font(.callout.weight(.medium))
            }
            Spacer()
            Text(checkpoint.status).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

public struct MotionNumericText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Int
    public init(_ value: Int) { self.value = value }
    public var body: some View {
        Text(value.formatted())
            .monospacedDigit()
            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(value)))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: value)
    }
}

public struct LocalElapsedClock: View {
    let startedAt: Date
    let endedAt: Date?
    public init(startedAt: Date, endedAt: Date?) { self.startedAt = startedAt; self.endedAt = endedAt }
    public var body: some View {
        Group {
            if let endedAt {
                Text(Self.format(max(0, endedAt.timeIntervalSince(startedAt))))
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.format(max(0, context.date.timeIntervalSince(startedAt))))
                }
            }
        }
        .font(.callout)
        .monospacedDigit()
        .accessibilityLabel("Elapsed time")
    }
    static func format(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}

public struct RunArchiveRow: View {
    let row: RunRowPresentation
    public init(_ row: RunRowPresentation) { self.row = row }
    public var body: some View {
        HStack(alignment: .top, spacing: ObserverSpacing.x3) {
            Rectangle()
                .fill(ObserverPalette.color(for: row.status.tone))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.projectName).font(.headline.weight(.medium))
                    Spacer(minLength: ObserverSpacing.x2)
                    Text(row.status.primary).font(.caption.weight(.semibold))
                }
                Text(row.secondaryLine).font(.caption).foregroundStyle(.secondary)
                if let health = row.abnormalHealth {
                    Text(health.rawValue.split(separator: "_").joined(separator: " ")).font(.caption2.weight(.semibold)).foregroundStyle(ObserverPalette.healthColor(health))
                }
            }
        }
        .padding(.vertical, ObserverSpacing.x3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

public struct CachedSnapshotNotice: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        HStack(spacing: ObserverSpacing.x2) {
            Image(systemName: "archivebox")
            Text(text).font(.caption.weight(.medium)).monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, ObserverSpacing.x2)
        .accessibilityElement(children: .combine)
    }
}

public struct NewEventsGate: View {
    let count: Int
    let resume: () -> Void
    public init(count: Int, resume: @escaping () -> Void) { self.count = count; self.resume = resume }
    public var body: some View {
        Button(action: resume) {
            HStack {
                Text("\(count) NEW EVENTS").font(.caption.weight(.semibold)).monospacedDigit()
                Spacer()
                Text("RESUME LIVE").font(.caption.weight(.semibold))
                Image(systemName: "arrow.down.to.line")
            }
            .padding(.vertical, ObserverSpacing.x3)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }
}

public struct DestinationRow: View {
    let title: String
    let detail: String?
    public init(_ title: String, detail: String? = nil) { self.title = title; self.detail = detail }
    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: ObserverSpacing.x1) {
                Text(title).font(.body.weight(.medium))
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, ObserverSpacing.x3)
    }
}
