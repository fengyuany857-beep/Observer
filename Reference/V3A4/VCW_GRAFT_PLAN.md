# Observer V3-A4 VCW graft plan

State: CANDIDATE_ONLY / NOT_DEPLOYED

## Target
Current VCW V2 Gateway / schema 3 / Phase7 effect kernel, using the exact Production-bound identities observed during V3-A3.

## Minimal assembly
1. Add a pure observer_projection module beside the Gateway.
2. Add a persistent observer_source_instance_id to the VCW store metadata at deployment/bootstrap time.
   - generated once;
   - preserved across normal restarts;
   - changed only when the event-store lineage is intentionally replaced;
   - never generated or rotated by a read request.
3. Add a read-only effect listing primitive to the exact SQLiteEffectLedger:
   - exact project_id scope required;
   - optional task_id narrows, never broadens;
   - returns only EffectRecord.public_dict()-equivalent fields after Observer receipt minimization;
   - never returns effect access tokens or authorization internals.
4. Register read-only projection methods:
   - observer_snapshot(project_id: str | None = None)
   - observer_project(project_id: str)
   - observer_events(project_id: str, after_id: int = 0, limit: int = 200)
   - observer_effects(project_id: str, task_id: str | None = None, limit: int = 100)
5. Keep transport out of V3-A4. No public HTTP/WebSocket listener is added here.
6. Do not add checkpoint/artifact/presentation truth until an owning authority exists.

## Non-negotiable semantics
- session_id, task_id, effect_id, runner job_id stay separate namespaces.
- event_id is only a cursor inside source_instance_id.
- effect_* events are hint/invalidation data, not authoritative effect state.
- heartbeat freshness cannot terminalize a session.
- no server-side global focus is invented.
- missing modules remain UNKNOWN/UNAVAILABLE.
- unknown future raw states are preserved instead of coerced.

## Security
The projection must never expose grant/session credentials, effect access tokens, authorization_snapshot_ref, runner worker_ref/backend_port, nonce/grant hashes, or any command-plane mutation method.

## Required graft regression
- existing VCW V2 suite remains green;
- existing Phase7 effect suite remains green;
- observer projection 24-case baseline remains green;
- exact project-scope isolation;
- task filter monotonic narrowing;
- source_instance_id persistence across normal restart;
- source_instance_id changes on deliberate fresh-store lineage;
- read calls produce zero DB mutations after bootstrap;
- duplicate/out-of-order events cannot overwrite truth;
- unknown effect/session states do not become false terminal success/failure;
- projection failure does not affect Gateway command plane.

## Current blocker
The one-time VCW grant used for V3-A3 expired before this candidate build. Therefore the exact current SQLiteEffectLedger schema and graft points must be re-read with a fresh grant before any VPS candidate modification.

## Production boundary
No Production deployment, service restart, DB migration, systemd change, or cutover is authorized by this V3-A4 candidate.
