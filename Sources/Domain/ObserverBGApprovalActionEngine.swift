import Foundation

public struct ObserverBGApprovalStatus: Sendable, Equatable {
    public let approvalID: String
    public let projectID: String
    public let state: String
    public let stateVersion: Int
    public let expiresAt: TimeInterval

    public init(approvalID: String, projectID: String, state: String, stateVersion: Int, expiresAt: TimeInterval) {
        self.approvalID = approvalID
        self.projectID = projectID
        self.state = state
        self.stateVersion = stateVersion
        self.expiresAt = expiresAt
    }
}

public protocol ObserverBGApprovalServicing: Sendable {
    func status(_ id: String) async throws -> ObserverBGApprovalStatus
    func decide(_ id: String, decision: String, attemptID: String, expectedVersion: Int) async throws -> ObserverBGApprovalStatus
}

/// An isolated, UI-independent entry point. Its result never grants a Session.
public struct ObserverBGApprovalActionEngine: Sendable {
    public enum Outcome: Sendable, Equatable {
        case rejectedInput
        case staleNotification(state: String)
        case expired
        case alreadyReserved(attemptID: String) // reconcile, no automatic re-POST
        case decisionConflict
        case submittedAndConfirmed(state: String) // direct acknowledged POST
        case outcomeUnknown(attemptID: String) // network loss, must reconcile
        case storageUnavailable
        case authorityUnavailable
    }

    public let journal: ObserverApprovalAttemptJournal
    public let service: any ObserverBGApprovalServicing
    public let scope: String
    public let configuredProjectID: String

    public init(journal: ObserverApprovalAttemptJournal, service: any ObserverBGApprovalServicing, scope: String, configuredProjectID: String) {
        self.journal = journal
        self.service = service
        self.scope = scope
        self.configuredProjectID = configuredProjectID
    }

    public func handle(approvalID: String, payloadProjectID: String, decision: String, now: TimeInterval) async -> Outcome {
        guard payloadProjectID == configuredProjectID,
              !approvalID.isEmpty, approvalID.count <= 256,
              approvalID.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              decision == "ALLOW" || decision == "DENY" else { return .rejectedInput }

        // A push is merely a hint. Always fetch the actual Approval from owner-control.
        let fresh: ObserverBGApprovalStatus
        do { fresh = try await service.status(approvalID) }
        catch { return .authorityUnavailable }
        guard fresh.approvalID == approvalID, fresh.projectID == configuredProjectID,
              fresh.stateVersion > 0 else { return .rejectedInput }
        guard fresh.state == "PENDING" else { return .staleNotification(state: fresh.state) }
        guard fresh.expiresAt > now else { return .expired }

        let record: ObserverApprovalAttemptJournal.Record
        do {
            if let existing = try journal.load(scope: scope, approvalID: approvalID) {
                return existing.decision == decision
                    ? .alreadyReserved(attemptID: existing.attemptID)
                    : .decisionConflict
            }
            record = try journal.claim(scope: scope, approvalID: approvalID, decision: decision, expectedVersion: fresh.stateVersion)
        } catch ObserverApprovalAttemptJournal.JournalError.conflictingDecision {
            return .decisionConflict
        } catch { return .storageUnavailable }

        // claim can race another process, so check for an earlier version / competing state.
        guard record.decision == decision, record.expectedVersion == fresh.stateVersion,
              record.phase == .reserved else { return .alreadyReserved(attemptID: record.attemptID) }
        do {
            guard try journal.acquireSubmission(scope: scope, approvalID: approvalID, attemptID: record.attemptID) else {
                return .alreadyReserved(attemptID: record.attemptID)
            }
        } catch { return .storageUnavailable }

        do {
            let decided = try await service.decide(approvalID, decision: decision, attemptID: record.attemptID, expectedVersion: record.expectedVersion)
            guard decided.approvalID == approvalID, decided.projectID == configuredProjectID else {
                _ = try? journal.transition(scope: scope, approvalID: approvalID, attemptID: record.attemptID, phase: .outcomeUnknown)
                return .outcomeUnknown(attemptID: record.attemptID)
            }
            _ = try? journal.transition(scope: scope, approvalID: approvalID, attemptID: record.attemptID, phase: .observed, observedState: decided.state)
            return .submittedAndConfirmed(state: decided.state)
        } catch {
            _ = try? journal.transition(scope: scope, approvalID: approvalID, attemptID: record.attemptID, phase: .outcomeUnknown)
            // Transport loss is never evidence of failure or success.
            return .outcomeUnknown(attemptID: record.attemptID)
        }
    }
}
