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

private func lifecycle(
    state: String,
    cleanupComplete: Bool
) -> ObserverOwnerLifecycle {
    ObserverOwnerLifecycle(
        operationID: "close:test",
        sessionID: "s_" + String(repeating: "a", count: 32),
        action: "CLOSE",
        state: state,
        requestedAt: 100,
        updatedAt: 101,
        completedAt: state == "SUCCEEDED" ? 101 : nil,
        reason: "TEST",
        errorCode: nil,
        errorMessage: nil,
        credentialRevoked: true,
        credentialRevokedAt: 100,
        sessionState: cleanupComplete ? "STOPPED" : "RECONCILE",
        cleanupComplete: cleanupComplete
    )
}

@main
struct ObserverSemanticMotionTests {
    static func main() {
        expect(
            ObserverSemanticMotionEmphasis.subtle.duration
                < ObserverSemanticMotionEmphasis.structural.duration,
            "subtle semantic motion remains shorter than structural"
        )
        expect(
            ObserverSemanticMotionEmphasis.structural.duration
                < ObserverSemanticMotionEmphasis.attention.duration,
            "attention semantic motion remains the strongest duration"
        )
        expect(
            abs(ObserverSemanticMotionEmphasis.structural.insertionOffset) <= 5,
            "structural semantic offset stays restrained"
        )

        let started = Date(timeIntervalSinceReferenceDate: 100)
        let operationA = CurrentOperationPresentation(
            kind: "shell",
            name: "Run tests",
            startedAt: started
        )
        let operationB = CurrentOperationPresentation(
            kind: "shell",
            name: "Build app",
            startedAt: started
        )
        expect(
            operationA.semanticMotionIdentity != operationB.semanticMotionIdentity,
            "CURRENT identity changes only when presentation truth changes"
        )

        let approvalIdle = ObserverOwnerMutationState.idle
        let approvalSubmitting = ObserverOwnerMutationState.submitting(
            decision: .allow,
            attemptID: "decision:test"
        )
        let approvalResolved = ObserverOwnerMutationState.resolved("APPROVED")
        expect(
            approvalIdle.semanticMotionIdentity != approvalSubmitting.semanticMotionIdentity,
            "Approval mutation identity changes on submitting state"
        )
        expect(
            approvalSubmitting.semanticMotionIdentity != approvalResolved.semanticMotionIdentity,
            "Approval mutation identity changes on resolution"
        )

        let closeExecuting = ObserverSessionCloseState.tracking(
            lifecycle(state: "EXECUTING", cleanupComplete: false)
        )
        let closeVerifying = ObserverSessionCloseState.tracking(
            lifecycle(state: "VERIFYING", cleanupComplete: false)
        )
        let closeSucceeded = ObserverSessionCloseState.tracking(
            lifecycle(state: "SUCCEEDED", cleanupComplete: true)
        )
        expect(
            closeExecuting.semanticMotionIdentity != closeVerifying.semanticMotionIdentity,
            "Close lifecycle identity changes from EXECUTING to VERIFYING"
        )
        expect(
            closeVerifying.semanticMotionIdentity != closeSucceeded.semanticMotionIdentity,
            "Close lifecycle identity changes from VERIFYING to SUCCEEDED"
        )

        let unknownA = ObserverSessionCloseState.outcomeUnknown(
            attemptID: "close:test",
            lifecycle: lifecycle(
                state: "OUTCOME_UNKNOWN",
                cleanupComplete: false
            )
        )
        let unknownB = ObserverSessionCloseState.outcomeUnknown(
            attemptID: "close:test",
            lifecycle: lifecycle(
                state: "OUTCOME_UNKNOWN",
                cleanupComplete: false
            )
        )
        expect(
            unknownA.semanticMotionIdentity == unknownB.semanticMotionIdentity,
            "same authoritative unknown truth keeps stable semantic identity"
        )

        if failures > 0 {
            print("ObserverSemanticMotionTests FAIL \(failures)")
            exit(1)
        }
        print("ObserverSemanticMotionTests PASS")
    }
}
