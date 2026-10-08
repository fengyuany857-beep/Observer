#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
manifest_path = ROOT / "Reference" / "B8" / "observer-backend-contract-freeze-v1.json"
truth_path = ROOT / "Sources" / "Domain" / "ObserverB8Truth.swift"
source_path = ROOT / "Sources" / "Domain" / "ObserverB8LiveDataSource.swift"
shell_path = ROOT / "Sources" / "SwiftUI" / "ObserverLiveShell.swift"
transport_path = ROOT / "Sources" / "Domain" / "RealObserverDataSource.swift"
runner_path = ROOT / "Scripts" / "run_core_tests.sh"
package_path = ROOT / "Packages" / "ObserverReadAPI" / "Sources" / "ObserverReadAPI" / "ObserverReadAPI.swift"

manifest_bytes = manifest_path.read_bytes()
manifest = json.loads(manifest_bytes)
truth = truth_path.read_text()
source = source_path.read_text()
shell = shell_path.read_text()
transport = transport_path.read_text()
runner = runner_path.read_text()
package_source = package_path.read_text()

checks: list[tuple[str, bool]] = []

def check(name: str, condition: bool) -> None:
    checks.append((name, bool(condition)))

check(
    "frozen-manifest-sha256",
    hashlib.sha256(manifest_bytes).hexdigest()
    == "ff59dc0310701cb9790f0045a49dfb288f4fd44a579ee4aefe3f6265bdfd1968",
)
check("freeze-id", manifest.get("freeze_id") == "OBSERVER-BACKEND-FREEZE-20261007-R1")
check("freeze-state", manifest.get("status") == "FROZEN_CONTRACT")
check("read-token-prefix", manifest["auth"]["read_token_prefix"] == "obsr_")
check("owner-token-prefix", manifest["auth"]["owner_token_prefix"] == "obsw_")
check("session-handle-hidden", manifest["auth"]["session_handle_exposed_to_observer"] is False)
check("ttl-1500", manifest["session_deadline"]["hard_ttl_seconds"] == 1500)
check("reminder-90", manifest["session_deadline"]["close_reminder_seconds"] == 90)
check("close-required-1410", manifest["session_deadline"]["close_required_elapsed_seconds"] == 1410)
check(
    "cached-current-forbidden",
    manifest["currentness"]["cached_current_allowed_when_transport_offline"] is False,
)
check(
    "client-generation-owner",
    manifest["read_race"]["ordering_owner"] == "CLIENT_REQUEST_GENERATION",
)
check(
    "source-change-full-baseline",
    manifest["read_race"]["source_instance_change_requires_full_snapshot"] is True,
)
check(
    "cursor-regression-full-baseline",
    manifest["read_race"]["cursor_regression_requires_full_snapshot"] is True,
)

for literal in (
    'freezeID = "OBSERVER-BACKEND-FREEZE-20261007-R1"',
    'transport = "observer.transport.v1"',
    'readPlane = "observer.read-plane.v1"',
    'snapshot = "observer.snapshot.v1"',
    'authority = "observer.authority.v1"',
    'jobs = "observer.jobs.v1"',
    'operations = "observer.operations.v1"',
    'readTokenPrefix = "obsr_"',
    "hardTTLSeconds = 1500",
    "closeReminderSeconds = 90",
    "closeRequiredElapsedSeconds = 1410",
    'currentness == "CURRENT"',
    'authority == "GATEWAY_IN_FLIGHT_CALL"',
    'freshness == "CURRENT_PROCESS"',
):
    check("truth:" + literal, literal in truth)

for literal in (
    '"X-Observer-Request-Generation"',
    '"X-Observer-Read-Intent"',
    '"If-None-Match"',
    'let operationGeneration = issueGeneration()',
    'let jobGeneration = issueGeneration()',
    'private func fetchJobs(',
    'private func jobsRequest(',
    'public func refreshCurrentOperations(',
    'public func pollEvents(',
    'private func issueGeneration()',
    'currentOperationsBySession: [:]',
):
    target = truth if literal == 'currentOperationsBySession: [:]' else source
    check("datasource:" + literal, literal in target)

check(
    "read-role-enforced",
    "bearerToken.hasPrefix(ObserverB8Contract.readTokenPrefix)" in transport,
)
check(
    "package-read-role-enforced",
    'bearerToken.hasPrefix("obsr_")' in package_source,
)
check(
    "live-shell-b8-source",
    "private var dataSource: ObserverB8LiveDataSource?" in shell,
)
check(
    "initial-reconnect-baseline",
    "_ = await refresh(intent: .reconnectBaseline)" in shell,
)
check(
    "incremental-events-through-b8",
    "dataSource.pollEvents(afterID: afterID, intent: .poll)" in shell,
)
check(
    "operation-poll-through-b8",
    "dataSource.refreshCurrentOperations(intent: .poll)" in shell,
)
check(
    "active-generation-error-owner",
    "var activeGeneration = generation" in source
    and "activeGeneration = operationGeneration" in source
    and "activeGeneration = jobGeneration" in source,
)
check(
    "jobs-share-generation-gate",
    "let jobGeneration = issueGeneration()" in source
    and "expectedSourceInstanceID" in source
    and "payload.contractVersion == ObserverB8Contract.jobs" in source,
)
check(
    "304-read-chain-error-owner",
    "var activeGeneration = generation" in source
    and "if activeGeneration != latestIssuedGeneration" in source,
)
check(
    "job-truth-preserved-operation-only",
    "jobs: jobs ?? $0.jobs" in source,
)
check(
    "operation-only-requires-live-baseline",
    "previous.snapshot.provenance == .live" in source
    and "previous.backendTruth?.transportLive == true" in source,
)
check(
    "b8-tests-in-core-runner",
    "Tests/ObserverB8LiveDataSourceTests.swift" in runner,
)
check(
    "no-session-handle-in-b8-truth",
    "session_handle" not in truth.lower(),
)
check(
    "no-session-handle-in-b8-source",
    "session_handle" not in source.lower(),
)

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(("PASS " if ok else "FAIL ") + name)
print(f"checks={len(checks)} pass={len(checks)-len(failed)} fail={len(failed)}")
if failed:
    sys.exit(1)
