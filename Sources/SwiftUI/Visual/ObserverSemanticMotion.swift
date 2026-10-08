import Foundation
import SwiftUI

public enum ObserverSemanticMotionEmphasis: String, Sendable, Equatable {
    case subtle
    case structural
    case attention

    var duration: TimeInterval {
        switch self {
        case .subtle: return 0.16
        case .structural: return 0.22
        case .attention: return 0.26
        }
    }

    var insertionOffset: CGFloat {
        switch self {
        case .subtle: return -2
        case .structural: return -5
        case .attention: return -3
        }
    }
}

private struct ObserverSemanticChangeModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Value
    let emphasis: ObserverSemanticMotionEmphasis

    func body(content: Content) -> some View {
        content.animation(
            reduceMotion ? nil : .easeOut(duration: emphasis.duration),
            value: value
        )
    }
}

private struct ObserverSemanticTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let emphasis: ObserverSemanticMotionEmphasis

    func body(content: Content) -> some View {
        content.transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .opacity.combined(
                        with: .offset(
                            x: 0,
                            y: emphasis.insertionOffset
                        )
                    ),
                    removal: .opacity
                )
        )
    }
}

public extension View {
    func observerSemanticChange<Value: Equatable>(
        value: Value,
        emphasis: ObserverSemanticMotionEmphasis = .subtle
    ) -> some View {
        modifier(
            ObserverSemanticChangeModifier(
                value: value,
                emphasis: emphasis
            )
        )
    }

    func observerSemanticTransition(
        _ emphasis: ObserverSemanticMotionEmphasis = .subtle
    ) -> some View {
        modifier(
            ObserverSemanticTransitionModifier(
                emphasis: emphasis
            )
        )
    }
}

public extension CurrentOperationPresentation {
    var semanticMotionIdentity: String {
        [
            kind,
            name,
            String(startedAt.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
    }
}

public extension ObserverOwnerMutationState {
    var semanticMotionIdentity: String {
        switch self {
        case .idle:
            return "IDLE"
        case .submitting(let decision, let attemptID):
            return "SUBMITTING|\(decision.rawValue)|\(attemptID)"
        case .conflict(let stateVersion):
            return "CONFLICT|\(stateVersion)"
        case .outcomeUnknown(let decision, let attemptID):
            return "OUTCOME_UNKNOWN|\(decision.rawValue)|\(attemptID)"
        case .resolved(let state):
            return "RESOLVED|\(state)"
        case .failed(let code):
            return "FAILED|\(code)"
        }
    }
}

public extension ObserverSessionCloseState {
    var semanticMotionIdentity: String {
        switch self {
        case .idle:
            return "IDLE"
        case .submitting(let attemptID):
            return "SUBMITTING|\(attemptID)"
        case .tracking(let lifecycle):
            return [
                "TRACKING",
                lifecycle.operationID,
                lifecycle.state,
                lifecycle.cleanupComplete ? "CLEAN" : "UNCERTAIN"
            ].joined(separator: "|")
        case .outcomeUnknown(let attemptID, let lifecycle):
            return [
                "OUTCOME_UNKNOWN",
                attemptID,
                lifecycle?.state ?? "NO_STATUS"
            ].joined(separator: "|")
        case .failed(let code):
            return "FAILED|\(code)"
        }
    }
}
