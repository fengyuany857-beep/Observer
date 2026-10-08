import Foundation

/// Bridge to the existing frozen Owner Control client. This adapter does not mint Sessions.
public struct ObserverBGOwnerAdapter: ObserverBGApprovalServicing, Sendable {
    private let owner: any ObserverOwnerControlServicing

    public init(owner: any ObserverOwnerControlServicing) { self.owner = owner }

    public func status(_ id: String) async throws -> ObserverBGApprovalStatus {
        let approval = try await owner.approvalStatus(id)
        return Self.presentation(approval)
    }

    public func decide(_ id: String, decision: String, attemptID: String, expectedVersion: Int) async throws -> ObserverBGApprovalStatus {
        guard let decision = ObserverOwnerDecision(rawValue: decision) else { throw ObserverOwnerControlError.invalidConfiguration("INVALID_DECISION") }
        let approval = try await owner.decideApproval(id, decision: decision, decisionAttemptID: attemptID, expectedStateVersion: expectedVersion)
        return Self.presentation(approval)
    }

    private static func presentation(_ approval: ObserverOwnerApproval) -> ObserverBGApprovalStatus {
        ObserverBGApprovalStatus(approvalID: approval.approvalID, projectID: approval.projectID, state: approval.state, stateVersion: approval.stateVersion, expiresAt: approval.expiresAt)
    }
}
