#!/usr/bin/env python3
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REF = ROOT / "Reference"

contract = json.loads((REF / "Observer_B0_Authority_Time_Contract_v1.json").read_text())
matrix = json.loads((REF / "Observer_B0_Test_Matrix_v1.json").read_text())
gate = json.loads((REF / "Observer_B0_A6_Compatibility_Gate_v1.json").read_text())
openapi = (ROOT / "Packages/ObserverReadAPI/Sources/ObserverReadAPI/openapi.yaml").read_text()

checks = []

def check(name, condition, detail=""):
    checks.append((name, bool(condition), detail))

objects = contract["objects"]
check("distinct approval/wait/session/daily concepts",
      set(["approval","gpt_wait_window","session_lease","daily_close_policy"]).issubset(objects))
check("GPT wait defaults 30s", objects["gpt_wait_window"]["default_seconds"] == 30)
check("GPT wait has no authority effect", objects["gpt_wait_window"]["authority_effect"] == "NONE")
check("Session hard TTL is 25 minutes", objects["session_lease"]["hard_ttl_seconds"] == 1500)
check("No silent session renewal", objects["session_lease"]["renewal"] == "NO_SILENT_RENEWAL")
check("Daily close reminder is 23:30", objects["daily_close_policy"]["local_time"] == "23:30")
check("Daily close timezone is explicit config", objects["daily_close_policy"]["timezone"] == "REQUIRED_CONFIGURATION")
check("Server clock authoritative", contract["clock"]["authority"] == "VCW_SERVER_CLOCK")
check("Client clock display-only", contract["clock"]["client_clock_role"] == "DISPLAY_ONLY")
check("Credential bounded by Session expiry",
      objects["credential"]["max_lifetime_rule"] == "credential_expires_at <= session_hard_expires_at")
check("Raw credential excluded from Observer",
      "NEVER_PROJECT_RAW_CREDENTIAL_TO_OBSERVER" in objects["credential"]["rules"])

rules = set(contract["cross_plane_invariants"])
for invariant in [
    "APPROVAL_TTL != GPT_WAIT_WINDOW",
    "GPT_WAIT_WINDOW != SESSION_TTL",
    "SESSION_TTL != DAILY_CLOSE_REMINDER",
    "SESSION_LIFETIME != JOB_LIFETIME",
    "SESSION_LIFETIME != OPERATION_LIFETIME",
    "APPROVED != SESSION_MINTED",
    "SESSION_MINTED != PROJECT_BOUND",
    "SESSION_REVOKED != RESOURCE_CLEANUP_VERIFIED",
]:
    check("invariant " + invariant, invariant in rules)

must_not = set(contract["a6_hard_boundaries"]["must_not"])
for invariant in [
    "SESSION_ACTIVE_SYNTHESIZES_CURRENT_OPERATION",
    "JOB_RUNNING_SYNTHESIZES_CURRENT_OPERATION",
    "CURRENT_OPERATION_DISAPPEARS_IMPLIES_JOB_FINISHED",
]:
    check("A6 hard boundary " + invariant, invariant in must_not)

case_ids = [c["id"] for c in matrix["cases"]]
check("B0 matrix ids unique", len(case_ids) == len(set(case_ids)))
check("B0 matrix has >= 20 cases", len(case_ids) >= 20)

for needle, label in [
    ("expires_at:", "A6 ObserverSession.expires_at"),
    ("remaining_seconds:", "A6 ObserverSession.remaining_seconds"),
    ("gateway_state:", "A6 ObserverJob.gateway_state"),
    ("currentness:", "A6 ObserverOperation.currentness"),
    ("Process-local Gateway operations that are currently in flight.", "A6 operation current semantics"),
    ("RUNNING is only last-observed active state.", "A6 job last-observed semantics"),
]:
    check(label, needle in openapi)

check("B0.5 baseline branch", gate["a6_baseline"]["branch"] == "observer-a6-openapi-ci-20261006")
check("B0.5 baseline commit pinned", gate["a6_baseline"]["commit"] == "04eebed2c2c6d673dd6d94251ae76860af7dda91")
check("B0.5 has no production effect", gate["production_effect"] == "NONE")

failed = [(n,d) for n,ok,d in checks if not ok]
for name, ok, detail in checks:
    print(("PASS" if ok else "FAIL") + " " + name + (f" :: {detail}" if detail else ""))

print(f"B0_CONTRACT_CHECKS={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}")
if failed:
    sys.exit(1)
