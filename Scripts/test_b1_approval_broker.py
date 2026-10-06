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


# Contract/static checks.
check("contract depends on B0", "observer.backend.authority-time.v1" in contract["depends_on"])
check("owner is backend", contract["owner"] == "VCW_CONTROL_PLANE_BACKEND")
check("server clock authoritative", contract["clock_authority"] == "VCW_SERVER_CLOCK")
check("approval ttl has no invented default", contract["configuration"]["approval_ttl_seconds"]["default"] is None)
check("GPT wait is 30 seconds", contract["configuration"]["gpt_wait_window_seconds"]["value"] == 30)
check("GPT wait has no authority effect", contract["configuration"]["gpt_wait_window_seconds"]["authority_effect"] == "NONE")
check("consume is B2 internal only", contract["operations"]["consume_for_session"]["visibility"] == "INTERNAL_B2_ONLY")
check("legacy grant is fallback", contract["manual_fallback"]["legacy_grant"] == "MANUAL_EMERGENCY_OR_COMPATIBILITY_FALLBACK")
check("B1 state set matches B0 approval states",
      set(contract["state_machine"]["states"]) == set(b0["objects"]["approval"]["states"]))

matrix_ids = [case["id"] for case in matrix["cases"]]
check("test matrix ids unique", len(matrix_ids) == len(set(matrix_ids)))
check("test matrix has >= 30 cases", len(matrix_ids) >= 30)

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
]:
    check("invariant " + required, required in invariants)

# Runtime reference-model tests.
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

not_committed = broker.consume_for_session(
    approval_id=pending.approval_id,
    now=1035.0,
    mint_attempt_id="mint-1",
    session_ref="session-1",
    mint_commit_proven=False,
)
check("failed mint before commit leaves APPROVED", not_committed.state == "APPROVED")

ambiguous = broker.consume_for_session(
    approval_id=pending.approval_id,
    now=1036.0,
    mint_attempt_id="mint-amb",
    session_ref="session-amb",
    mint_commit_proven=None,
)
check("ambiguous mint -> OUTCOME_UNKNOWN", ambiguous.state == "OUTCOME_UNKNOWN")

same_ambiguous = broker.consume_for_session(
    approval_id=pending.approval_id,
    now=1037.0,
    mint_attempt_id="mint-amb",
    session_ref="session-amb",
    mint_commit_proven=None,
)
check("same ambiguous attempt is idempotent", same_ambiguous.state == "OUTCOME_UNKNOWN")

expect_error(
    "blind second mint blocked while unknown",
    StateConflict,
    lambda: broker.consume_for_session(
        approval_id=pending.approval_id,
        now=1038.0,
        mint_attempt_id="mint-2",
        session_ref="session-2",
        mint_commit_proven=True,
    ),
)

reconciled_not_committed = broker.reconcile_mint_outcome(
    approval_id=pending.approval_id,
    now=1039.0,
    mint_attempt_id="mint-amb",
    session_ref="session-amb",
    committed=False,
)
check("reconcile not committed -> APPROVED", reconciled_not_committed.state == "APPROVED")

consumed = broker.consume_for_session(
    approval_id=pending.approval_id,
    now=1040.0,
    mint_attempt_id="mint-final",
    session_ref="session-final",
    mint_commit_proven=True,
)
check("proven mint -> CONSUMED", consumed.state == "CONSUMED")
check("consumed binds session ref", consumed.consumed_session_ref == "session-final")

same_consumed = broker.consume_for_session(
    approval_id=pending.approval_id,
    now=1041.0,
    mint_attempt_id="mint-final",
    session_ref="session-final",
    mint_commit_proven=True,
)
check("same consumed mint idempotent", same_consumed == consumed)

expect_error(
    "second session mint rejected",
    DuplicateSessionMint,
    lambda: broker.consume_for_session(
        approval_id=pending.approval_id,
        now=1042.0,
        mint_attempt_id="mint-other",
        session_ref="session-other",
        mint_commit_proven=True,
    ),
)

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

invalidate_broker = new_broker()
inv_pending = create(invalidate_broker, key="inv-p")
invalidated = invalidate_broker.invalidate(
    approval_id=inv_pending.approval_id,
    now=1001.0,
    reason="PROJECT_BINDING_CHANGED",
)
check("pending can invalidate", invalidated.state == "INVALIDATED")
expect_error(
    "terminal invalidated cannot invalidate again",
    StateConflict,
    lambda: invalidate_broker.invalidate(
        approval_id=inv_pending.approval_id,
        now=1002.0,
        reason="AGAIN",
    ),
)

inv2 = create(invalidate_broker, key="inv-a", attempt="req-3")
inv2_approved = invalidate_broker.decide(
    approval_id=inv2.approval_id,
    now=1001.0,
    decision="ALLOW",
    decision_attempt_id="inv-allow",
    expected_state_version=1,
    decider_principal="user:owner",
)
inv2_final = invalidate_broker.invalidate(
    approval_id=inv2_approved.approval_id,
    now=1002.0,
    reason="AUTHORITY_REVOKED",
)
check("approved can invalidate", inv2_final.state == "INVALIDATED")

amb2_broker = new_broker(ttl=20)
amb2 = create(amb2_broker, key="amb2")
amb2 = amb2_broker.decide(
    approval_id=amb2.approval_id,
    now=1001.0,
    decision="ALLOW",
    decision_attempt_id="amb2-allow",
    expected_state_version=1,
    decider_principal="user:owner",
)
amb2 = amb2_broker.consume_for_session(
    approval_id=amb2.approval_id,
    now=1002.0,
    mint_attempt_id="amb2-mint",
    session_ref="amb2-session",
    mint_commit_proven=None,
)
amb2_reconciled = amb2_broker.reconcile_mint_outcome(
    approval_id=amb2.approval_id,
    now=1021.0,
    mint_attempt_id="amb2-mint",
    session_ref="amb2-session",
    committed=False,
)
check("reconcile noncommit after ttl -> EXPIRED", amb2_reconciled.state == "EXPIRED")

amb3_broker = new_broker()
amb3 = create(amb3_broker, key="amb3")
amb3 = amb3_broker.decide(
    approval_id=amb3.approval_id,
    now=1001.0,
    decision="ALLOW",
    decision_attempt_id="amb3-allow",
    expected_state_version=1,
    decider_principal="user:owner",
)
amb3 = amb3_broker.consume_for_session(
    approval_id=amb3.approval_id,
    now=1002.0,
    mint_attempt_id="amb3-mint",
    session_ref="amb3-session",
    mint_commit_proven=None,
)
amb3_reconciled = amb3_broker.reconcile_mint_outcome(
    approval_id=amb3.approval_id,
    now=1003.0,
    mint_attempt_id="amb3-mint",
    session_ref="amb3-session",
    committed=True,
)
check("reconcile commit -> CONSUMED", amb3_reconciled.state == "CONSUMED")

for name, ok in checks:
    print(("PASS" if ok else "FAIL") + " " + name)

print(f"B1_APPROVAL_CHECKS={len(checks)} PASS={len(checks)-len(failures)} FAIL={len(failures)}")
if failures:
    sys.exit(1)
