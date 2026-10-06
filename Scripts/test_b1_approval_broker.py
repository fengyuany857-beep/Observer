#!/usr/bin/env python3
import importlib.util
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REF = ROOT / "Reference"

spec = importlib.util.spec_from_file_location(
    "approval_broker_reference",
    REF / "B1" / "approval_broker_reference.py",
)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)

ApprovalBroker = module.ApprovalBroker
ApprovalError = module.ApprovalError
InvalidConfiguration = module.InvalidConfiguration
IdempotencyConflict = module.IdempotencyConflict
StateConflict = module.StateConflict
VersionConflict = module.VersionConflict
Expired = module.Expired
DuplicateSessionMint = module.DuplicateSessionMint

contract = json.loads((REF / "Observer_B1_Approval_Broker_Contract_v1.json").read_text())
matrix = json.loads((REF / "Observer_B1_Test_Matrix_v1.json").read_text())
b0 = json.loads((REF / "Observer_B0_Authority_Time_Contract_v1.json").read_text())

checks = []
failures = []


def check(name, condition):
    ok = bool(condition)
    checks.append((name, ok))
    if not ok:
        failures.append(name)


def expect_error(name, exc_type, fn):
    try:
        fn()
    except exc_type:
        check(name, True)
    except Exception as exc:
        check(name + f" wrong exception {type(exc).__name__}", False)
    else:
        check(name + " missing exception", False)


def new_broker(ttl=120):
    return ApprovalBroker(approval_ttl_seconds=ttl)


def create(broker, now=1000.0, key="key-1", scope="workspace:read", attempt="req-1"):
    return broker.create_request(
        now=now,
        request_attempt_id=attempt,
        requester_principal="gpt:chat",
        project_id="project-a",
        requested_scope=scope,
        action_class="READ_WORKSPACE",
        effect_class="READ_ONLY",
        idempotency_key=key,
    )


def approve(broker, item, now=1001.0, attempt="allow-1"):
    return broker.decide(
        approval_id=item.approval_id,
        now=now,
        decision="ALLOW",
        decision_attempt_id=attempt,
        expected_state_version=item.state_version,
        decider_principal="user:owner",
    )


# Static contract checks.
check("contract revision R2", contract["revision"] == "B1-2026-10-06-R2")
check("contract depends on B0", "observer.backend.authority-time.v1" in contract["depends_on"])
check("owner is backend", contract["owner"] == "VCW_CONTROL_PLANE_BACKEND")
check("server clock authoritative", contract["clock_authority"] == "VCW_SERVER_CLOCK")
check("approval ttl has no invented default", contract["configuration"]["approval_ttl_seconds"]["default"] is None)
check("GPT wait is 30 seconds", contract["configuration"]["gpt_wait_window_seconds"]["value"] == 30)
check("GPT wait has no authority effect", contract["configuration"]["gpt_wait_window_seconds"]["authority_effect"] == "NONE")
check("mint fence is B2 internal", contract["mint_fence"]["visibility"] == "INTERNAL_B2_ONLY")
check("fence acquire is B2 internal", contract["operations"]["acquire_mint_fence"]["visibility"] == "INTERNAL_B2_ONLY")
check("mint finalize is B2 internal", contract["operations"]["finalize_session_mint"]["visibility"] == "INTERNAL_B2_ONLY")
check("legacy grant is fallback", contract["manual_fallback"]["legacy_grant"] == "MANUAL_EMERGENCY_OR_COMPATIBILITY_FALLBACK")
check(
    "B1 state set matches B0 approval states",
    set(contract["state_machine"]["states"]) == set(b0["objects"]["approval"]["states"]),
)

matrix_ids = [case["id"] for case in matrix["cases"]]
check("test matrix ids unique", len(matrix_ids) == len(set(matrix_ids)))
check("test matrix has >= 40 cases", len(matrix_ids) >= 40)

invariants = set(contract["hard_invariants"])
for required in [
    "GPT_WAIT_TIMEOUT_DOES_NOT_EXPIRE_APPROVAL",
    "GPT_CANNOT_SELF_APPROVE",
    "APPROVAL_APPROVED_DOES_NOT_EQUAL_SESSION_MINTED",
    "APPROVAL_CONSUME_AT_MOST_ONCE",
    "APPROVAL_ID_IS_NOT_A_CREDENTIAL",
    "STALE_EXPECTED_STATE_VERSION_CANNOT_MUTATE",
    "CACHED_APPROVAL_CANNOT_AUTHORIZE_SESSION",
    "SESSION_MINT_FAILURE_DOES_NOT_SILENTLY_CONSUME_APPROVAL",
    "AMBIGUOUS_MINT_RESULT_MUST_RECONCILE_BEFORE_RETRY",
    "MINT_FENCE_DOES_NOT_EQUAL_CONSUMED",
    "MINT_COMMIT_MUST_PRECEDE_APPROVAL_EXPIRY",
    "FINALIZE_AFTER_EXPIRY_MAY_CONSUME_ONLY_IF_SAME_FENCED_COMMIT_OCCURRED_BEFORE_EXPIRY",
]:
    check("invariant " + required, required in invariants)

# Configuration and create/idempotency.
expect_error(
    "missing ttl rejected",
    InvalidConfiguration,
    lambda: ApprovalBroker(approval_ttl_seconds=None),
)

broker = new_broker()
pending = create(broker)
check("create -> PENDING", pending.state == "PENDING")
check("create version=1", pending.state_version == 1)
check("server expiry computed from ttl", pending.expires_at == 1120.0)

same = create(broker, now=1005.0)
check("same create idempotency returns same id", same.approval_id == pending.approval_id)
expect_error(
    "same key changed scope conflicts",
    IdempotencyConflict,
    lambda: create(broker, now=1006.0, scope="workspace:write"),
)

still_pending = broker.get_request(pending.approval_id, now=1030.0)
check("30s wait does not expire approval", still_pending.state == "PENDING")

expect_error(
    "stale decision version rejected",
    VersionConflict,
    lambda: broker.decide(
        approval_id=pending.approval_id,
        now=1031.0,
        decision="ALLOW",
        decision_attempt_id="dec-stale",
        expected_state_version=999,
        decider_principal="user:owner",
    ),
)

approved = broker.decide(
    approval_id=pending.approval_id,
    now=1032.0,
    decision="ALLOW",
    decision_attempt_id="dec-allow-1",
    expected_state_version=1,
    decider_principal="user:owner",
)
check("allow -> APPROVED", approved.state == "APPROVED")
check("allow increments version", approved.state_version == 2)

same_decision = broker.decide(
    approval_id=pending.approval_id,
    now=1033.0,
    decision="ALLOW",
    decision_attempt_id="dec-allow-1",
    expected_state_version=1,
    decider_principal="user:owner",
)
check("same decision attempt idempotent", same_decision == approved)

expect_error(
    "different decision after approved rejected",
    StateConflict,
    lambda: broker.decide(
        approval_id=pending.approval_id,
        now=1034.0,
        decision="DENY",
        decision_attempt_id="dec-deny-late",
        expected_state_version=2,
        decider_principal="user:owner",
    ),
)

# Mint fence mechanics.
fenced = broker.acquire_mint_fence(
    approval_id=approved.approval_id,
    now=1035.0,
    mint_attempt_id="mint-1",
    session_ref="session-1",
    expected_state_version=approved.state_version,
)
check("fence leaves approval APPROVED", fenced.state == "APPROVED")
check("fence binds mint identity", fenced.fence_mint_attempt_id == "mint-1")
check("fence increments version", fenced.state_version == approved.state_version + 1)

same_fence = broker.acquire_mint_fence(
    approval_id=approved.approval_id,
    now=1036.0,
    mint_attempt_id="mint-1",
    session_ref="session-1",
    expected_state_version=approved.state_version,
)
check("same fence idempotent", same_fence == fenced)

expect_error(
    "different session cannot steal fence",
    DuplicateSessionMint,
    lambda: broker.acquire_mint_fence(
        approval_id=approved.approval_id,
        now=1037.0,
        mint_attempt_id="mint-2",
        session_ref="session-2",
        expected_state_version=fenced.state_version,
    ),
)

not_committed = broker.finalize_session_mint(
    approval_id=approved.approval_id,
    now=1038.0,
    mint_attempt_id="mint-1",
    session_ref="session-1",
    commit_state=False,
)
check("no commit before expiry -> APPROVED", not_committed.state == "APPROVED")
check("no commit releases fence", not_committed.fence_mint_attempt_id is None)

fenced2 = broker.acquire_mint_fence(
    approval_id=approved.approval_id,
    now=1039.0,
    mint_attempt_id="mint-amb",
    session_ref="session-amb",
    expected_state_version=not_committed.state_version,
)
ambiguous = broker.finalize_session_mint(
    approval_id=approved.approval_id,
    now=1040.0,
    mint_attempt_id="mint-amb",
    session_ref="session-amb",
    commit_state=None,
)
check("ambiguous mint -> OUTCOME_UNKNOWN", ambiguous.state == "OUTCOME_UNKNOWN")
check("unknown retains fence", ambiguous.fence_session_ref == "session-amb")

same_unknown = broker.finalize_session_mint(
    approval_id=approved.approval_id,
    now=1041.0,
    mint_attempt_id="mint-amb",
    session_ref="session-amb",
    commit_state=None,
)
check("same unknown finalize idempotent", same_unknown == ambiguous)

expect_error(
    "blind second fence blocked while outcome unknown",
    StateConflict,
    lambda: broker.acquire_mint_fence(
        approval_id=approved.approval_id,
        now=1042.0,
        mint_attempt_id="mint-other",
        session_ref="session-other",
        expected_state_version=ambiguous.state_version,
    ),
)

reconciled_not_committed = broker.finalize_session_mint(
    approval_id=approved.approval_id,
    now=1043.0,
    mint_attempt_id="mint-amb",
    session_ref="session-amb",
    commit_state=False,
)
check("reconcile no commit before ttl -> APPROVED", reconciled_not_committed.state == "APPROVED")
check("reconcile clears fence", reconciled_not_committed.fence_mint_attempt_id is None)

# Pending/expired cannot acquire fence.
pending_broker = new_broker()
p = create(pending_broker, key="pending-fence")
expect_error(
    "pending cannot acquire mint fence",
    StateConflict,
    lambda: pending_broker.acquire_mint_fence(
        approval_id=p.approval_id,
        now=1001.0,
        mint_attempt_id="m",
        session_ref="s",
        expected_state_version=p.state_version,
    ),
)

expired_broker = new_broker(ttl=10)
e = create(expired_broker, key="expired-fence")
e = approve(expired_broker, e, now=1001.0, attempt="e-allow")
expect_error(
    "expired approval cannot acquire fence",
    Expired,
    lambda: expired_broker.acquire_mint_fence(
        approval_id=e.approval_id,
        now=1010.0,
        mint_attempt_id="late",
        session_ref="late-session",
        expected_state_version=e.state_version,
    ),
)

# Critical TTL race: fenced commit before expiry, finalize after expiry.
race_broker = new_broker(ttl=20)
race = create(race_broker, key="race")
race = approve(race_broker, race, now=1001.0, attempt="race-allow")
race = race_broker.acquire_mint_fence(
    approval_id=race.approval_id,
    now=1018.0,
    mint_attempt_id="race-mint",
    session_ref="race-session",
    expected_state_version=race.state_version,
)
race_consumed = race_broker.finalize_session_mint(
    approval_id=race.approval_id,
    now=1022.0,
    mint_attempt_id="race-mint",
    session_ref="race-session",
    commit_state=True,
    committed_at=1019.5,
)
check("pre-expiry commit finalized after ttl -> CONSUMED", race_consumed.state == "CONSUMED")

same_consumed = race_broker.finalize_session_mint(
    approval_id=race.approval_id,
    now=1023.0,
    mint_attempt_id="race-mint",
    session_ref="race-session",
    commit_state=True,
    committed_at=1019.5,
)
check("same consumed finalize idempotent", same_consumed == race_consumed)

expect_error(
    "second session after consumed rejected",
    DuplicateSessionMint,
    lambda: race_broker.finalize_session_mint(
        approval_id=race.approval_id,
        now=1024.0,
        mint_attempt_id="other-mint",
        session_ref="other-session",
        commit_state=True,
        committed_at=1019.0,
    ),
)

# Expiry with active fence must not silently become EXPIRED.
unknown_broker = new_broker(ttl=20)
u = create(unknown_broker, key="unknown")
u = approve(unknown_broker, u, now=1001.0, attempt="u-allow")
u = unknown_broker.acquire_mint_fence(
    approval_id=u.approval_id,
    now=1018.0,
    mint_attempt_id="u-mint",
    session_ref="u-session",
    expected_state_version=u.state_version,
)
u_at_expiry = unknown_broker.get_request(u.approval_id, now=1020.0)
check("fenced approval at ttl -> OUTCOME_UNKNOWN", u_at_expiry.state == "OUTCOME_UNKNOWN")
u_no_commit = unknown_broker.finalize_session_mint(
    approval_id=u.approval_id,
    now=1021.0,
    mint_attempt_id="u-mint",
    session_ref="u-session",
    commit_state=False,
)
check("reconciled no-commit after ttl -> EXPIRED", u_no_commit.state == "EXPIRED")

# A known late commit is invalid and must not become CONSUMED.
late_broker = new_broker(ttl=20)
late = create(late_broker, key="late")
late = approve(late_broker, late, now=1001.0, attempt="late-allow")
late = late_broker.acquire_mint_fence(
    approval_id=late.approval_id,
    now=1018.0,
    mint_attempt_id="late-mint",
    session_ref="late-session",
    expected_state_version=late.state_version,
)
late_result = late_broker.finalize_session_mint(
    approval_id=late.approval_id,
    now=1021.0,
    mint_attempt_id="late-mint",
    session_ref="late-session",
    commit_state=True,
    committed_at=1020.0,
)
check("commit at expiry -> FAILED", late_result.state == "FAILED")
check("late commit never becomes CONSUMED", late_result.state != "CONSUMED")

# Deny / expiry / list behavior.
deny_broker = new_broker()
deny_req = create(deny_broker, key="deny-key")
denied = deny_broker.decide(
    approval_id=deny_req.approval_id,
    now=1001.0,
    decision="DENY",
    decision_attempt_id="deny-1",
    expected_state_version=1,
    decider_principal="user:owner",
)
check("deny -> DENIED", denied.state == "DENIED")
expect_error(
    "denied cannot be approved later",
    StateConflict,
    lambda: deny_broker.decide(
        approval_id=deny_req.approval_id,
        now=1002.0,
        decision="ALLOW",
        decision_attempt_id="allow-after-deny",
        expected_state_version=2,
        decider_principal="user:owner",
    ),
)

expire_broker = new_broker(ttl=60)
expire_req = create(expire_broker, key="expire-key")
expired = expire_broker.get_request(expire_req.approval_id, now=1060.0)
check("ttl -> EXPIRED", expired.state == "EXPIRED")
expect_error(
    "decision after expiry rejected",
    Expired,
    lambda: expire_broker.decide(
        approval_id=expire_req.approval_id,
        now=1061.0,
        decision="ALLOW",
        decision_attempt_id="late-allow",
        expected_state_version=2,
        decider_principal="user:owner",
    ),
)

list_broker = new_broker(ttl=50)
list_a = create(list_broker, now=1000.0, key="list-a")
list_b = create(list_broker, now=1040.0, key="list-b", attempt="req-2")
pending_list = list_broker.list_pending(now=1051.0)
check("expired omitted from pending list", list_a.approval_id not in {x.approval_id for x in pending_list})
check("unexpired remains in pending list", list_b.approval_id in {x.approval_id for x in pending_list})

# Invalidation.
invalidate_broker = new_broker()
inv_pending = create(invalidate_broker, key="inv-p")
invalidated = invalidate_broker.invalidate(
    approval_id=inv_pending.approval_id,
    now=1001.0,
    reason="PROJECT_BINDING_CHANGED",
)
check("pending can invalidate", invalidated.state == "INVALIDATED")

inv2 = create(invalidate_broker, key="inv-a", attempt="req-3")
inv2 = approve(invalidate_broker, inv2, now=1001.0, attempt="inv-allow")
inv2_final = invalidate_broker.invalidate(
    approval_id=inv2.approval_id,
    now=1002.0,
    reason="AUTHORITY_REVOKED",
)
check("unfenced approved can invalidate", inv2_final.state == "INVALIDATED")

inv3 = create(invalidate_broker, key="inv-f", attempt="req-4")
inv3 = approve(invalidate_broker, inv3, now=1001.0, attempt="invf-allow")
inv3 = invalidate_broker.acquire_mint_fence(
    approval_id=inv3.approval_id,
    now=1002.0,
    mint_attempt_id="invf-mint",
    session_ref="invf-session",
    expected_state_version=inv3.state_version,
)
expect_error(
    "fenced approved cannot invalidate before reconciliation",
    StateConflict,
    lambda: invalidate_broker.invalidate(
        approval_id=inv3.approval_id,
        now=1003.0,
        reason="AUTHORITY_REVOKED",
    ),
)

for name, ok in checks:
    print(("PASS" if ok else "FAIL") + " " + name)

print(f"B1_APPROVAL_CHECKS={len(checks)} PASS={len(checks)-len(failures)} FAIL={len(failures)}")
if failures:
    sys.exit(1)
