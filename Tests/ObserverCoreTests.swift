import Foundation

@main
struct ObserverCoreTests {
    private static var checks = 0
    private static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !condition() {
            failures += 1
            print("FAIL \(name)")
        }
    }

    static func main() {
        expect(ObserverPreviewScenario.allCases.count == 18, "preview scenario count = 18")
        expect(Set(ObserverPreviewScenario.allCases.map(\.rawValue)).count == 18, "preview scenarios unique")

        let running = ObserverFixtureFactory.make(.runningActiveOnline)
        let runningOverview = ObserverProjectionBuilder.makeOverview(running.snapshot)
        if case .focused(let run) = runningOverview.focusMode {
            expect(run.status.rawValue == "RUNNING", "running focus remains RUNNING")
            expect(run.completionTruth.engineeringComplete == false, "running not engineering complete")
            expect(run.endedAt == nil, "live run has no endedAt")
        } else { expect(false, "running resolves focused") }

        let multi = ObserverProjectionBuilder.makeOverview(ObserverFixtureFactory.make(.multipleActiveAggregate).snapshot)
        if case .aggregate(let aggregate) = multi.focusMode {
            expect(aggregate.count == 2, "multi active aggregate count")
            expect(aggregate.runIDs.count == 2, "multi aggregate keeps run identities")
        } else { expect(false, "multiple active does not fabricate one focused run") }

        let empty = ObserverProjectionBuilder.makeOverview(ObserverFixtureFactory.make(.noRunEmpty).snapshot)
        if case .empty = empty.focusMode { expect(true, "empty state") } else { expect(false, "empty state") }

        let offlineFixture = ObserverFixtureFactory.make(.runningLastKnownOffline)
        let offlineOverview = ObserverProjectionBuilder.makeOverview(offlineFixture.snapshot)
        expect(offlineOverview.connectionIncident?.state == .offline, "offline is connection incident")
        expect(offlineOverview.connectionIncident?.detail?.contains("1m ago") == true, "offline freshness derived from fixture timestamps")
        if case .focused(let run) = offlineOverview.focusMode {
            expect(run.status.rawValue == "RUNNING", "offline preserves last-known RUNNING")
            expect(run.isCached == true, "offline fixture explicitly cached")
        } else { expect(false, "offline still has focused last-known run") }

        let completedUnknownFixture = ObserverFixtureFactory.make(.completedVerifiedPresentationUnknown)
        let completedUnknown = ObserverProjectionBuilder.makeOverview(completedUnknownFixture.snapshot)
        if case .focused(let run) = completedUnknown.focusMode {
            expect(run.completionTruth.engineeringComplete, "completed = engineering complete")
            expect(run.completionTruth.artifactVerified, "VERIFIED exact artifact state")
            expect(run.completionTruth.presentationUnknown, "presentation unknown remains unknown")
            expect(run.completionTruth.presentationConfirmed == false, "unknown not presented")
            expect(run.endedAt != nil, "terminal fixture has endedAt for static elapsed")
        } else { expect(false, "authoritative completed focus") }

        if let completedDetail = ObserverProjectionBuilder.makeRunDetail(completedUnknownFixture.snapshot, runID: completedUnknownFixture.snapshot.runs[0].runID) {
            expect(completedDetail.truthRows.contains(where: { $0.key == "FINAL HEALTH" }), "terminal detail labels health as final observation")
        } else { expect(false, "completed detail projection exists") }

        let completedBase = completedUnknownFixture.snapshot.runs[0]
        let exportedRun = RunStatusSnapshot(
            runID: completedBase.runID,
            workspaceID: completedBase.workspaceID,
            projectName: completedBase.projectName,
            executionStatus: .completed,
            runtimeHealth: completedBase.runtimeHealth,
            runtimePhase: completedBase.runtimePhase,
            stage: completedBase.stage,
            currentOperation: nil,
            elapsedMS: completedBase.elapsedMS,
            startedAt: completedBase.startedAt,
            endedAt: completedBase.endedAt,
            heartbeats: completedBase.heartbeats,
            tests: completedBase.tests,
            checkpoint: completedBase.checkpoint,
            bundle: .init(status: .exported, id: "bundle-exported"),
            presentationStatus: .unknown,
            lastEvent: completedBase.lastEvent,
            updatedAt: completedBase.updatedAt
        )
        expect(ObserverProjectionBuilder.completionTruth(exportedRun).artifactVerified == false, "EXPORTED != VERIFIED")

        let resumableFixture = ObserverFixtureFactory.make(.resumable)
        let resumableWithoutAuthoritativeFocus = ObserverSnapshot(
            connectionState: resumableFixture.snapshot.connectionState,
            authoritativeFocusRunID: nil,
            runs: resumableFixture.snapshot.runs,
            observedAt: resumableFixture.snapshot.observedAt,
            lastSyncAt: resumableFixture.snapshot.lastSyncAt,
            provenance: resumableFixture.snapshot.provenance
        )
        let resumableOverview = ObserverProjectionBuilder.makeOverview(resumableWithoutAuthoritativeFocus)
        if case .lastRun(let run) = resumableOverview.focusMode {
            expect(run.status.rawValue == "RESUMABLE", "resumable can be last run")
        } else { expect(false, "RESUMABLE not auto active") }

        expect(ExecutionStatus.resumable.isActivePresentationCandidate == false, "RESUMABLE active guard")
        expect(ExecutionStatus.failed.isTerminal, "FAILED terminal")
        expect(ExecutionStatus.running.isTerminal == false, "RUNNING not terminal")

        expect(AccessibilityAnnouncementPolicy.announcement(for: .heartbeat(eventID: "h1")) == nil, "heartbeat silent for VoiceOver")
        expect(AccessibilityAnnouncementPolicy.announcement(for: .testCountChanged(eventID: "t1")) == nil, "test increment silent")
        expect(AccessibilityAnnouncementPolicy.announcement(for: .completed(eventID: "c1")) == "Run completed", "completed announcement")
        expect(AccessibilityAnnouncementPolicy.announcement(for: .waitingApproval(eventID: "a1")) == "Approval required", "approval announcement")

        let timeline = SyntheticScaleFixtures.timeline(count: 10_000)
        expect(timeline.count == 10_000, "10k timeline fixture")
        expect(timeline.first?.seq == 1 && timeline.last?.seq == 10_000, "timeline stable ordering")
        expect(Set(timeline.map(\.id)).count == 10_000, "timeline stable unique ids")
        expect(SyntheticScaleFixtures.logLine(index: 999_999).contains("00999999"), "million-scale log line can be generated without materializing million rows")

        let rows = ObserverProjectionBuilder.makeRunRows(running.snapshot)
        expect(rows.count == running.snapshot.runs.count, "run rows cover snapshots")
        expect(zip(rows, rows.dropFirst()).allSatisfy { $0.updatedAt >= $1.updatedAt }, "run rows sorted newest first")

        if let detailID = running.preferredDetailRunID,
           let detail = ObserverProjectionBuilder.makeRunDetail(running.snapshot, runID: detailID) {
            expect(detail.destinations.count == 5, "detail has five navigation destinations")
            expect(detail.truthRows.count == 4, "truth matrix separates four run truth dimensions")
            expect(detail.liveConnectionIncident?.state == .online, "online detail exposes live connection")
            expect(detail.liveConnectionIncident?.title == "ONLINE", "online detail labels live connection explicitly")
        } else { expect(false, "run detail projection exists") }

        let auth = ObserverFixtureFactory.make(.authFailedCached)
        let authOverview = ObserverProjectionBuilder.makeOverview(auth.snapshot)
        expect(authOverview.connectionIncident?.state == .authFailed, "auth failure separate connection state")
        expect(authOverview.connectionIncident?.detail?.contains("10m ago") == true, "auth cached freshness derived from snapshot")
        if case .focused(let run) = authOverview.focusMode {
            expect(run.status.rawValue == "RUNNING", "auth failure does not mutate execution truth")
        } else { expect(false, "auth cached retains focused run") }

        print("checks=\(checks) pass=\(checks-failures) fail=\(failures)")
        if failures > 0 { exit(1) }
    }
}
