from __future__ import annotations
import json
import unittest
from observer_read_projection import ObserverReadProjection, SessionTruth, HeartbeatTruth, EventTruth, EffectTruth

class ProjectionTests(unittest.TestCase):
    def setUp(self):
        self.p=ObserverReadProjection(source_instance_id="vcw-store:test-lineage")
        self.now=1000.0

    def session(self, **kw):
        base=dict(session_id="s_1",project_id="p1",state="RUNNING",created_at=900.0,expires_at=1200.0,started_at=920.0,ended_at=None,last_model_activity=980.0,last_execution_activity=990.0,failure_reason=None,queue_position=None)
        base.update(kw); return SessionTruth(**base)

    def event(self, **kw):
        base=dict(event_id=7,event_type="progress_update",created_at=990.0,session_id="s_1",project_id="p1",source="sandbox",authoritative=False,payload={"summary":"working"})
        base.update(kw); return EventTruth(**base)

    def effect(self, **kw):
        base=dict(effect_id="effect-1234567890",task_id="task-1",project_id="p1",state="OUTCOME_UNKNOWN",generation=3,created_at="2026-10-05T00:00:00Z",updated_at="2026-10-05T00:01:00Z",receipt=None,last_error_code="VCW_EFFECT_READBACK_INCONCLUSIVE")
        base.update(kw); return EffectTruth(**base)

    def test_running_session_is_not_task_truth(self):
        s=self.p.project_session(self.session(),now=self.now)
        self.assertEqual(s["state"],"RUNNING"); self.assertNotIn("task_id",s); self.assertNotIn("outcome",s)

    def test_elapsed_uses_started_at_not_created_at(self):
        s=self.p.project_session(self.session(),now=self.now)
        self.assertEqual(s["session_age_seconds"],100.0); self.assertEqual(s["execution_elapsed_seconds"],80.0)

    def test_not_started_has_unknown_execution_elapsed(self):
        self.assertIsNone(self.p.project_session(self.session(state="QUEUED",started_at=None),now=self.now)["execution_elapsed_seconds"])

    def test_terminal_elapsed_stops_at_ended_at(self):
        s=self.p.project_session(self.session(state="FINISHED",ended_at=970.0),now=self.now)
        self.assertEqual(s["execution_elapsed_seconds"],50.0); self.assertEqual(s["state_class"],"TERMINAL")

    def test_unknown_session_state_is_preserved(self):
        s=self.p.project_session(self.session(state="FUTURE_STATE"),now=self.now)
        self.assertEqual(s["state"],"FUTURE_STATE"); self.assertEqual(s["state_class"],"UNKNOWN")

    def test_heartbeat_30s_boundary(self):
        self.assertEqual(self.p.project_heartbeat(HeartbeatTruth("runner","ONLINE",970.0,{}),now=self.now)["freshness"],"FRESH")
        self.assertEqual(self.p.project_heartbeat(HeartbeatTruth("runner","ONLINE",969.999,{}),now=self.now)["freshness"],"STALE")

    def test_stale_heartbeat_does_not_create_failed_state(self):
        h=self.p.project_heartbeat(HeartbeatTruth("runner","ONLINE",900.0,{}),now=self.now)
        self.assertEqual(h["freshness"],"STALE"); self.assertNotIn("execution_status",h); self.assertNotIn("failed",json.dumps(h).lower())

    def test_event_identity_is_source_plus_event_id(self):
        e=self.p.project_event(self.event())
        self.assertEqual(e["event_identity"],"vcw-store:test-lineage:7"); self.assertNotIn("epoch",e); self.assertNotIn("seq",e)

    def test_event_authority_is_preserved(self):
        self.assertFalse(self.p.project_event(self.event(authoritative=False))["authoritative"])

    def test_non_authoritative_effect_event_cannot_change_effect_truth(self):
        s=self.p.snapshot(observed_at=self.now,projects=[{"project_id":"p1"}],sessions=[self.session()],heartbeats=[],events=[self.event(event_type="effect_reconciling",authoritative=False)],effects=[self.effect(state="OUTCOME_UNKNOWN")])
        self.assertEqual(s["effects"][0]["state"],"OUTCOME_UNKNOWN")

    def test_effect_outcome_unknown_is_preserved(self):
        self.assertEqual(self.p.project_effect(self.effect())["state"],"OUTCOME_UNKNOWN")

    def test_effect_reconciling_is_preserved(self):
        self.assertEqual(self.p.project_effect(self.effect(state="RECONCILING"))["state"],"RECONCILING")

    def test_unknown_effect_state_is_preserved_but_not_treated_known(self):
        e=self.p.project_effect(self.effect(state="FUTURE_STATE"))
        self.assertEqual(e["state"],"FUTURE_STATE")
        self.assertFalse(e["state_known"])

    def test_no_authoritative_focus_is_invented(self):
        s=self.p.snapshot(observed_at=self.now,projects=[],sessions=[self.session(),self.session(session_id="s_2",project_id="p2")],heartbeats=[],events=[],effects=[])
        self.assertIsNone(s["authoritative_focus_task_id"])

    def test_missing_product_modules_remain_unavailable(self):
        s=self.p.snapshot(observed_at=self.now,projects=[],sessions=[],heartbeats=[],events=[],effects=[])
        self.assertEqual(s["availability"]["checkpoint"],"UNAVAILABLE")
        self.assertEqual(s["availability"]["artifact"],"UNAVAILABLE")
        self.assertEqual(s["availability"]["presentation"],"UNKNOWN")

    def test_project_filter_does_not_leak_other_project(self):
        s=self.p.snapshot(observed_at=self.now,projects=[{"project_id":"p1"},{"project_id":"p2"}],sessions=[self.session(),self.session(session_id="s2",project_id="p2")],heartbeats=[],events=[self.event(),self.event(event_id=8,project_id="p2")],effects=[self.effect(),self.effect(effect_id="effect-2222222222",project_id="p2")],project_id="p1")
        self.assertEqual([x["project_id"] for x in s["projects"]],["p1"])
        self.assertEqual([x["project_id"] for x in s["sessions"]],["p1"])
        self.assertEqual([x["project_id"] for x in s["events"]],["p1"])
        self.assertEqual([x["project_id"] for x in s["effects"]],["p1"])

    def test_cursor_is_max_event_id_in_filtered_view(self):
        s=self.p.snapshot(observed_at=self.now,projects=[],sessions=[],heartbeats=[],events=[self.event(event_id=4),self.event(event_id=11)],effects=[])
        self.assertEqual(s["event_cursor"],11)

    def test_empty_cursor_is_zero(self):
        self.assertEqual(self.p.snapshot(observed_at=self.now,projects=[],sessions=[],heartbeats=[],events=[],effects=[])["event_cursor"],0)

    def test_snapshot_revision_ignores_time_derived_fields(self):
        kw=dict(projects=[{"project_id":"p1"}],sessions=[self.session()],heartbeats=[HeartbeatTruth("runner","ONLINE",990.0,{})],events=[self.event()],effects=[self.effect()])
        self.assertEqual(self.p.snapshot(observed_at=1000,**kw)["snapshot_revision"],self.p.snapshot(observed_at=1100,**kw)["snapshot_revision"])

    def test_snapshot_revision_changes_with_truth(self):
        a=self.p.snapshot(observed_at=self.now,projects=[],sessions=[self.session()],heartbeats=[],events=[],effects=[])
        b=self.p.snapshot(observed_at=self.now,projects=[],sessions=[self.session(state="RECONCILE")],heartbeats=[],events=[],effects=[])
        self.assertNotEqual(a["snapshot_revision"],b["snapshot_revision"])

    def test_effect_receipt_is_minimized(self):
        receipt={"receipt_id":"r1","authorization_snapshot_ref":"secret-ish-ref","runner_generation_digest":"digest","request_fingerprint":"fp","disposition":"APPLIED","verified":True,"observed_at":"2026-10-05T00:02:00Z","evidence":{"verification":"FILE_CONTENT_SHA256"}}
        e=self.p.project_effect(self.effect(state="CONFIRMED_APPLIED",receipt=receipt))
        self.assertEqual(set(e["receipt"]),{"disposition","verified","observed_at","evidence"})
        self.assertNotIn("authorization_snapshot_ref",e["receipt"])

    def test_input_order_does_not_change_snapshot_revision(self):
        a=self.p.snapshot(observed_at=self.now,projects=[{"project_id":"p2"},{"project_id":"p1"}],sessions=[self.session(session_id="s2",project_id="p2"),self.session()],heartbeats=[HeartbeatTruth("runner","ONLINE",990,{})],events=[self.event(event_id=9),self.event(event_id=3)],effects=[self.effect(effect_id="effect-bbbbbbbbbbbb"),self.effect(effect_id="effect-aaaaaaaaaaaa")])
        b=self.p.snapshot(observed_at=self.now,projects=[{"project_id":"p1"},{"project_id":"p2"}],sessions=[self.session(),self.session(session_id="s2",project_id="p2")],heartbeats=[HeartbeatTruth("runner","ONLINE",990,{})],events=[self.event(event_id=3),self.event(event_id=9)],effects=[self.effect(effect_id="effect-aaaaaaaaaaaa"),self.effect(effect_id="effect-bbbbbbbbbbbb")])
        self.assertEqual(a["snapshot_revision"],b["snapshot_revision"])

    def test_source_instance_id_is_required(self):
        with self.assertRaises(ValueError): ObserverReadProjection(source_instance_id="")

    def test_event_id_zero_is_rejected(self):
        with self.assertRaises(ValueError): self.p.project_event(self.event(event_id=0))

if __name__=="__main__": unittest.main(verbosity=2)
