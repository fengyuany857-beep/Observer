from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable, Protocol
import hashlib
import json

ACTIVE_SESSION_STATES = frozenset({"AUTHORIZED","QUEUED","STARTING","RUNNING","STOPPING","RECONCILE"})
TERMINAL_SESSION_STATES = frozenset({"EXPIRED","FINISHED","FAILED","STOPPED"})
EFFECT_STATES = frozenset({
    "PREPARED","DISPATCHING","CONFIRMED_APPLIED","CONFIRMED_NOT_APPLIED",
    "OUTCOME_UNKNOWN","RECONCILING","RECOVERY_BLOCKED",
})
HEARTBEAT_STALE_AFTER_SECONDS = 30.0

def _nonnegative(value: float) -> float:
    return max(0.0, float(value))

def canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)

@dataclass(frozen=True)
class SessionTruth:
    session_id: str
    project_id: str | None
    state: str
    created_at: float
    expires_at: float
    started_at: float | None = None
    ended_at: float | None = None
    last_model_activity: float | None = None
    last_execution_activity: float | None = None
    failure_reason: str | None = None
    queue_position: int | None = None

@dataclass(frozen=True)
class HeartbeatTruth:
    component: str
    status: str
    observed_at: float
    detail: dict[str, Any]

@dataclass(frozen=True)
class EventTruth:
    event_id: int
    event_type: str
    created_at: float
    session_id: str | None
    project_id: str | None
    source: str
    authoritative: bool
    payload: dict[str, Any]

@dataclass(frozen=True)
class EffectTruth:
    effect_id: str
    task_id: str
    project_id: str
    state: str
    generation: int
    created_at: str
    updated_at: str
    receipt: dict[str, Any] | None = None
    last_error_code: str | None = None

class EffectSummarySource(Protocol):
    def list_public_effects(self, *, project_id: str, task_id: str | None = None, limit: int = 100) -> list[EffectTruth]: ...

class ObserverReadProjection:
    """Pure read projection over authoritative VCW inputs."""

    def __init__(self, *, source_instance_id: str, heartbeat_stale_after: float = HEARTBEAT_STALE_AFTER_SECONDS):
        source_instance_id = str(source_instance_id).strip()
        if not source_instance_id:
            raise ValueError("source_instance_id is required")
        if heartbeat_stale_after <= 0:
            raise ValueError("heartbeat_stale_after must be positive")
        self.source_instance_id = source_instance_id
        self.heartbeat_stale_after = float(heartbeat_stale_after)

    def project_session(self, row: SessionTruth, *, now: float) -> dict[str, Any]:
        if not row.session_id:
            raise ValueError("session_id is required")
        if not row.state:
            raise ValueError("session state is required")
        execution_elapsed = None
        if row.started_at is not None:
            stop = row.ended_at if row.ended_at is not None else now
            execution_elapsed = _nonnegative(stop - row.started_at)
        return {
            "session_id": row.session_id,
            "project_id": row.project_id,
            "state": row.state,
            "state_class": "ACTIVE" if row.state in ACTIVE_SESSION_STATES else "TERMINAL" if row.state in TERMINAL_SESSION_STATES else "UNKNOWN",
            "created_at": row.created_at,
            "started_at": row.started_at,
            "ended_at": row.ended_at,
            "expires_at": row.expires_at,
            "last_model_activity": row.last_model_activity,
            "last_execution_activity": row.last_execution_activity,
            "failure_reason": row.failure_reason,
            "queue_position": row.queue_position,
            "session_age_seconds": _nonnegative(now - row.created_at),
            "execution_elapsed_seconds": execution_elapsed,
            "remaining_seconds": _nonnegative(row.expires_at - now),
        }

    def project_heartbeat(self, row: HeartbeatTruth, *, now: float) -> dict[str, Any]:
        age = _nonnegative(now - row.observed_at)
        return {
            "component": row.component,
            "status": row.status,
            "observed_at": row.observed_at,
            "age_seconds": age,
            "freshness": "STALE" if age > self.heartbeat_stale_after else "FRESH",
            "detail": dict(row.detail),
        }

    def project_event(self, row: EventTruth) -> dict[str, Any]:
        if row.event_id < 1:
            raise ValueError("event_id must be >= 1")
        return {
            "source_instance_id": self.source_instance_id,
            "event_id": row.event_id,
            "event_identity": f"{self.source_instance_id}:{row.event_id}",
            "event_type": row.event_type,
            "created_at": row.created_at,
            "session_id": row.session_id,
            "project_id": row.project_id,
            "source": row.source,
            "authoritative": bool(row.authoritative),
            "payload": dict(row.payload),
        }

    def project_effect(self, row: EffectTruth) -> dict[str, Any]:
        known = row.state in EFFECT_STATES
        result: dict[str, Any] = {
            "effect_id": row.effect_id,
            "task_id": row.task_id,
            "project_id": row.project_id,
            "state": row.state,
            "state_known": known,
            "generation": int(row.generation),
            "created_at": row.created_at,
            "updated_at": row.updated_at,
        }
        if row.receipt is not None:
            allowed = {"disposition", "verified", "observed_at", "evidence"}
            result["receipt"] = {k: v for k, v in row.receipt.items() if k in allowed}
        if row.last_error_code is not None:
            result["last_error_code"] = row.last_error_code
        return result

    def snapshot(self, *, observed_at: float, projects: Iterable[dict[str, Any]], sessions: Iterable[SessionTruth], heartbeats: Iterable[HeartbeatTruth], events: Iterable[EventTruth], effects: Iterable[EffectTruth], project_id: str | None = None) -> dict[str, Any]:
        projects = list(projects)
        sessions = list(sessions)
        heartbeats = list(heartbeats)
        events = list(events)
        effects = list(effects)
        if project_id is not None:
            projects = [x for x in projects if x.get("project_id") == project_id]
            sessions = [x for x in sessions if x.project_id == project_id]
            events = [x for x in events if x.project_id == project_id]
            effects = [x for x in effects if x.project_id == project_id]
        projects = sorted(projects, key=lambda x: (str(x.get("project_id", "")), canonical_json(x)))
        sessions = sorted(sessions, key=lambda x: x.session_id)
        heartbeats = sorted(heartbeats, key=lambda x: x.component)
        events = sorted(events, key=lambda x: x.event_id)
        effects = sorted(effects, key=lambda x: (x.project_id, x.task_id, x.updated_at, x.effect_id))
        event_cursor = max((x.event_id for x in events), default=0)

        projected_projects = projects
        projected_sessions = [self.project_session(x, now=observed_at) for x in sessions]
        projected_heartbeats = [self.project_heartbeat(x, now=observed_at) for x in heartbeats]
        projected_effects = [self.project_effect(x) for x in effects]
        projected_events = [self.project_event(x) for x in events]

        revision_basis = {
            "contract_version": "observer.snapshot.v1",
            "source_instance_id": self.source_instance_id,
            "projects": projected_projects,
            "sessions": [
                {
                    "session_id": x.session_id, "project_id": x.project_id, "state": x.state,
                    "created_at": x.created_at, "started_at": x.started_at, "ended_at": x.ended_at,
                    "expires_at": x.expires_at, "last_model_activity": x.last_model_activity,
                    "last_execution_activity": x.last_execution_activity, "failure_reason": x.failure_reason,
                    "queue_position": x.queue_position,
                } for x in sessions
            ],
            "heartbeats": [
                {"component": x.component, "status": x.status, "observed_at": x.observed_at, "detail": x.detail}
                for x in heartbeats
            ],
            "effects": projected_effects,
            "events": projected_events,
            "event_cursor": event_cursor,
        }
        snapshot_revision = hashlib.sha256(canonical_json(revision_basis).encode("utf-8")).hexdigest()

        return {
            "contract_version": "observer.snapshot.v1",
            "source_instance_id": self.source_instance_id,
            "snapshot_revision": snapshot_revision,
            "observed_at": float(observed_at),
            "authoritative_focus_task_id": None,
            "projects": projected_projects,
            "sessions": projected_sessions,
            "heartbeats": projected_heartbeats,
            "effects": projected_effects,
            "events": projected_events,
            "event_cursor": event_cursor,
            "availability": {
                "tests_summary": "UNAVAILABLE_AGGREGATE",
                "checkpoint": "UNAVAILABLE",
                "artifact": "UNAVAILABLE",
                "presentation": "UNKNOWN",
                "logs": "SESSION_JOB_TAIL_ONLY",
            },
        }
