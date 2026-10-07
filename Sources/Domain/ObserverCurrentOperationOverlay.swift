import Foundation

public enum ObserverCurrentOperationOverlay {
    public static func applying(
        _ operationsByRunID: [String: OperationSnapshot],
        to snapshot: ObserverSnapshot
    ) -> ObserverSnapshot {
        ObserverSnapshot(
            connectionState: snapshot.connectionState,
            authoritativeFocusRunID: snapshot.authoritativeFocusRunID,
            runs: snapshot.runs.map { run in
                let operation: OperationSnapshot?
                if run.isTerminalObservation || run.endedAt != nil {
                    operation = nil
                } else {
                    operation = operationsByRunID[run.runID]
                }

                return RunStatusSnapshot(
                    runID: run.runID,
                    projectID: run.projectID,
                    projectName: run.projectName,
                    executionStatus: run.executionStatus,
                    directorTruth: run.directorTruth,
                    runtimeHealth: run.runtimeHealth,
                    runtimePhase: run.runtimePhase,
                    stage: run.stage,
                    currentOperation: operation,
                    elapsedMS: run.elapsedMS,
                    startedAt: run.startedAt,
                    endedAt: run.endedAt,
                    heartbeats: run.heartbeats,
                    tests: run.tests,
                    checkpoint: run.checkpoint,
                    bundle: run.bundle,
                    presentationStatus: run.presentationStatus,
                    lastEvent: run.lastEvent,
                    updatedAt: run.updatedAt
                )
            },
            observedAt: snapshot.observedAt,
            lastSyncAt: snapshot.lastSyncAt,
            provenance: snapshot.provenance
        )
    }

    public static func clearing(_ snapshot: ObserverSnapshot) -> ObserverSnapshot {
        applying([:], to: snapshot)
    }
}
