import Foundation

actor MockAuthority: ObserverBGApprovalServicing {
    var truth: ObserverBGApprovalStatus
    var submits = 0
    var failPost = false
    var failGet = false

    init(_ truth: ObserverBGApprovalStatus) { self.truth = truth }

    func status(_ id: String) async throws -> ObserverBGApprovalStatus {
        if failGet { throw URLError(.notConnectedToInternet) }
        return truth
    }

    func decide(_ id: String, decision: String, attemptID: String, expectedVersion: Int) async throws -> ObserverBGApprovalStatus {
        submits += 1
        try await Task.sleep(for: .milliseconds(30))
        if failPost { throw URLError(.networkConnectionLost) }
        truth = ObserverBGApprovalStatus(approvalID: truth.approvalID, projectID: truth.projectID, state: decision == "ALLOW" ? "APPROVED" : "DENIED", stateVersion: truth.stateVersion + 1, expiresAt: truth.expiresAt)
        return truth
    }

    func getSubmits() -> Int { submits }
    func setFailures(post: Bool = false, get: Bool = false) { failPost = post; failGet = get }
}

@main
@MainActor
struct BGTests {
    static var total = 0
    static func check(_ test: Bool, _ label: String) {
        total += 1
        if test { print("PASS \(total): \(label)") }
        else { fatalError("FAIL \(total): \(label)") }
    }

    static func path() -> URL { URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("observer-r4-\(UUID().uuidString)/attempts.sqlite") }
    static func status(_ state: String = "PENDING", version: Int = 3, expires: Double = 500) -> ObserverBGApprovalStatus { .init(approvalID: "apr-1", projectID: "vcw-acceptance", state: state, stateVersion: version, expiresAt: expires) }
    static func engine(_ path: URL, _ svc: MockAuthority) -> ObserverBGApprovalActionEngine {
        .init(journal: .init(databaseURL: path), service: svc, scope: "scope/v1", configuredProjectID: "vcw-acceptance")
    }
    static func run() async throws {
        let file=path(), j=ObserverApprovalAttemptJournal(databaseURL:file)
        let a=try j.claim(scope:"a",approvalID:"apr-1",decision:"ALLOW",expectedVersion:1)
        let b=try j.claim(scope:"a",approvalID:"apr-1",decision:"ALLOW",expectedVersion:1)
        check(a.attemptID == b.attemptID, "same approval reserves same attempt identity")
        check(a.attemptID.hasPrefix("decision:"), "wire attempt id format")
        do { _=try j.claim(scope:"a",approvalID:"apr-1",decision:"DENY",expectedVersion:1); check(false,"conflicting DENY blocked") }
        catch ObserverApprovalAttemptJournal.JournalError.conflictingDecision { check(true,"conflicting DENY blocked") }
        check(try j.acquireSubmission(scope:"a",approvalID:"apr-1",attemptID:a.attemptID),"one atomic submission acquired")
        check(try !j.acquireSubmission(scope:"a",approvalID:"apr-1",attemptID:a.attemptID),"duplicate acquisition blocked")
        _=try j.transition(scope:"a",approvalID:"apr-1",attemptID:a.attemptID,phase:.outcomeUnknown)
        let recovered=try ObserverApprovalAttemptJournal(databaseURL:file).load(scope:"a",approvalID:"apr-1")
        check(recovered?.attemptID == a.attemptID && recovered?.phase == .outcomeUnknown,"restart can recover uncertainty")
        _=try j.transition(scope:"a",approvalID:"apr-1",attemptID:a.attemptID,phase:.observed,observedState:"APPROVED")
        check(try j.load(scope:"a",approvalID:"apr-1")?.observedState == "APPROVED", "authoritative observation durable")
        do { _=try j.transition(scope:"a",approvalID:"apr-1",attemptID:a.attemptID,phase:.submitting);check(false,"terminal cannot regress") }
        catch ObserverApprovalAttemptJournal.JournalError.conflictingDecision {check(true,"terminal cannot regress")}

        let concurrentPath=path(), j1=ObserverApprovalAttemptJournal(databaseURL:concurrentPath), j2=ObserverApprovalAttemptJournal(databaseURL:concurrentPath)
        let winners=try await withThrowingTaskGroup(of:Bool.self) { group in
            for i in 0..<24 {group.addTask {
                let journal = i.isMultiple(of:2) ? j1 : j2
                let r=try journal.claim(scope:"a",approvalID:"apr-2",decision:"ALLOW",expectedVersion:3)
                return try journal.acquireSubmission(scope:"a",approvalID:"apr-2",attemptID:r.attemptID)
            }}
            var count=0; for try await won in group { if won {count+=1} }; return count
        }
        check(winners == 1,"24 simultaneous contenders yield exactly one sender")
        let a2=try j1.load(scope:"a",approvalID:"apr-2")
        check(a2?.phase == .submitting,"atomic phase persisted across independent instances")

        let svc=MockAuthority(status()), e=engine(path(),svc)
        check(await e.handle(approvalID:"apr-1",payloadProjectID:"wrong",decision:"ALLOW",now:20) == .rejectedInput, "push project mismatch rejected")
        check(await e.handle(approvalID:"apr-1",payloadProjectID:"vcw-acceptance",decision:"GRANT",now:20) == .rejectedInput,"no invented grant action")
        check(await e.handle(approvalID:"apr-1",payloadProjectID:"vcw-acceptance",decision:"ALLOW",now:501) == .expired,"expiry advisory blocks client")
        let result=await e.handle(approvalID:"apr-1",payloadProjectID:"vcw-acceptance",decision:"ALLOW",now:20)
        check(result == .submittedAndConfirmed(state:"APPROVED"),"fresh GET + CAS submitted")
        check(await svc.getSubmits() == 1,"single POST on success")
        check(await e.handle(approvalID:"apr-1",payloadProjectID:"vcw-acceptance",decision:"ALLOW",now:20) == .staleNotification(state:"APPROVED"),"stale notice can't mutate")

        let netSvc=MockAuthority(status()), e2=engine(path(),netSvc)
        await netSvc.setFailures(post:true)
        let failure=await e2.handle(approvalID:"apr-1",payloadProjectID:"vcw-acceptance",decision:"DENY",now:20)
        guard case .outcomeUnknown(let attempt)=failure else {fatalError("uncertainty must retain attempt")}
        check(attempt.hasPrefix("decision:"),"lost POST receipt preserves attempt")
        let duplicate=await e2.handle(approvalID:"apr-1",payloadProjectID:"vcw-acceptance",decision:"DENY",now:21)
        check(duplicate == .alreadyReserved(attemptID:attempt),"no blind re-POST after receipt loss")
        check(await netSvc.getSubmits() == 1,"one network mutation despite retry")
        let opposite=await e2.handle(approvalID:"apr-1",payloadProjectID:"vcw-acceptance",decision:"ALLOW",now:21)
        check(opposite == .decisionConflict,"opposite action blocked by journal")
        await netSvc.setFailures(get:true)
        check(await e2.handle(approvalID:"apr-1",payloadProjectID:"vcw-acceptance",decision:"ALLOW",now:21) == .authorityUnavailable,"authority unavailable fails closed")
        print("RESULT: \(total)/\(total) PASS")
    }
    static func main() async throws { try await run() }
}
