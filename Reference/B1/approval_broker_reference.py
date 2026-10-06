from __future__ import annotations

from dataclasses import dataclass, replace
from hashlib import sha256
from typing import Dict, Optional


class ApprovalError(Exception):
    code = "APPROVAL_ERROR"


class InvalidConfiguration(ApprovalError):
    code = "INVALID_CONFIGURATION"


class NotFound(ApprovalError):
    code = "NOT_FOUND"


class IdempotencyConflict(ApprovalError):
    code = "IDEMPOTENCY_CONFLICT"


class StateConflict(ApprovalError):
    code = "STATE_CONFLICT"


class VersionConflict(ApprovalError):
    code = "VERSION_CONFLICT"


class Expired(ApprovalError):
    code = "EXPIRED"


class DuplicateSessionMint(ApprovalError):
    code = "DUPLICATE_SESSION_MINT"


class LateMintCommit(ApprovalError):
    code = "MINT_COMMITTED_AFTER_APPROVAL_EXPIRY"


@dataclass(frozen=True)
class ApprovalRequest:
    approval_id: str
    request_attempt_id: str
    requester_principal: str
    project_id: str
    requested_scope: str
    action_class: str
    effect_class: str
    created_at: float
    expires_at: float
    state: str
    state_version: int
    request_fingerprint: str
    create_idempotency_key: str
    last_decision_attempt_id: Optional[str] = None
    last_decision: Optional[str] = None
    fence_mint_attempt_id: Optional[str] = None
    fence_session_ref: Optional[str] = None
    fence_acquired_at: Optional[float] = None
    consumed_session_ref: Optional[str] = None
    consumed_mint_attempt_id: Optional[str] = None
    reason: Optional[str] = None


class ApprovalBroker:
    TERMINAL = {"DENIED", "EXPIRED", "CONSUMED", "INVALIDATED", "FAILED"}
    REUSABLE = {"PENDING", "APPROVED"}

    def __init__(self, *, approval_ttl_seconds: Optional[int]):
        if approval_ttl_seconds is None or approval_ttl_seconds <= 0:
            raise InvalidConfiguration("approval_ttl_seconds must be configured and > 0")
        self.approval_ttl_seconds = int(approval_ttl_seconds)
        self._by_id: Dict[str, ApprovalRequest] = {}
        self._create_key_to_id: Dict[str, str] = {}
        self._next_id = 1

    @staticmethod
    def fingerprint(*, requester_principal: str, project_id: str, requested_scope: str,
                    action_class: str, effect_class: str) -> str:
        normalized = "\n".join([
            requester_principal.strip(),
            project_id.strip(),
            requested_scope.strip(),
            action_class.strip(),
            effect_class.strip(),
        ])
        return sha256(normalized.encode("utf-8")).hexdigest()

    def create_request(self, *, now: float, request_attempt_id: str, requester_principal: str,
                       project_id: str, requested_scope: str, action_class: str,
                       effect_class: str, idempotency_key: str) -> ApprovalRequest:
        fields = [request_attempt_id, requester_principal, project_id, requested_scope,
                  action_class, effect_class, idempotency_key]
        if any(not str(x).strip() for x in fields):
            raise ApprovalError("required field empty")

        fp = self.fingerprint(
            requester_principal=requester_principal,
            project_id=project_id,
            requested_scope=requested_scope,
            action_class=action_class,
            effect_class=effect_class,
        )
        existing_id = self._create_key_to_id.get(idempotency_key)
        if existing_id:
            existing = self._by_id[existing_id]
            if existing.request_fingerprint != fp:
                raise IdempotencyConflict("same key with different request fingerprint")
            return self.get_request(existing.approval_id, now=now)

        approval_id = f"apr-{self._next_id:06d}"
        self._next_id += 1
        item = ApprovalRequest(
            approval_id=approval_id,
            request_attempt_id=request_attempt_id,
            requester_principal=requester_principal,
            project_id=project_id,
            requested_scope=requested_scope,
            action_class=action_class,
            effect_class=effect_class,
            created_at=now,
            expires_at=now + self.approval_ttl_seconds,
            state="PENDING",
            state_version=1,
            request_fingerprint=fp,
            create_idempotency_key=idempotency_key,
        )
        self._by_id[approval_id] = item
        self._create_key_to_id[idempotency_key] = approval_id
        return item

    def _apply_expiry(self, item: ApprovalRequest, *, now: float) -> ApprovalRequest:
        if now < item.expires_at:
            return item
        if item.state == "PENDING":
            item = replace(
                item,
                state="EXPIRED",
                state_version=item.state_version + 1,
                reason="TTL_EXPIRED",
            )
            self._by_id[item.approval_id] = item
        elif item.state == "APPROVED":
            if item.fence_mint_attempt_id is not None:
                item = replace(
                    item,
                    state="OUTCOME_UNKNOWN",
                    state_version=item.state_version + 1,
                    reason="MINT_FENCE_REQUIRES_RECONCILIATION_AT_EXPIRY",
                )
            else:
                item = replace(
                    item,
                    state="EXPIRED",
                    state_version=item.state_version + 1,
                    reason="TTL_EXPIRED",
                )
            self._by_id[item.approval_id] = item
        return item

    def get_request(self, approval_id: str, *, now: float) -> ApprovalRequest:
        item = self._by_id.get(approval_id)
        if item is None:
            raise NotFound(approval_id)
        return self._apply_expiry(item, now=now)

    def list_pending(self, *, now: float) -> list[ApprovalRequest]:
        out = []
        for approval_id in list(self._by_id):
            item = self.get_request(approval_id, now=now)
            if item.state == "PENDING":
                out.append(item)
        return out

    def decide(self, *, approval_id: str, now: float, decision: str,
               decision_attempt_id: str, expected_state_version: int,
               decider_principal: str) -> ApprovalRequest:
        if decision not in {"ALLOW", "DENY"}:
            raise ApprovalError("decision must be ALLOW or DENY")
        if not decision_attempt_id.strip() or not decider_principal.strip():
            raise ApprovalError("decision identity required")

        item = self.get_request(approval_id, now=now)

        if item.last_decision_attempt_id == decision_attempt_id:
            if item.last_decision != decision:
                raise IdempotencyConflict("decision attempt reused with different decision")
            return item

        if item.state == "EXPIRED":
            raise Expired(approval_id)
        if item.state != "PENDING":
            raise StateConflict(f"cannot decide from {item.state}")
        if item.state_version != expected_state_version:
            raise VersionConflict(
                f"expected {expected_state_version}, actual {item.state_version}"
            )

        new_state = "APPROVED" if decision == "ALLOW" else "DENIED"
        item = replace(
            item,
            state=new_state,
            state_version=item.state_version + 1,
            last_decision_attempt_id=decision_attempt_id,
            last_decision=decision,
            reason=f"DECIDED_BY:{decider_principal}",
        )
        self._by_id[approval_id] = item
        return item

    def acquire_mint_fence(self, *, approval_id: str, now: float,
                           mint_attempt_id: str, session_ref: str,
                           expected_state_version: int) -> ApprovalRequest:
        if not mint_attempt_id.strip() or not session_ref.strip():
            raise ApprovalError("mint identity required")
        item = self.get_request(approval_id, now=now)

        if item.state == "EXPIRED":
            raise Expired(approval_id)
        if item.state != "APPROVED":
            raise StateConflict(f"cannot acquire mint fence from {item.state}")

        if item.fence_mint_attempt_id is not None:
            if (
                item.fence_mint_attempt_id == mint_attempt_id
                and item.fence_session_ref == session_ref
            ):
                return item
            raise DuplicateSessionMint("approval already fenced by another mint")

        if item.state_version != expected_state_version:
            raise VersionConflict(
                f"expected {expected_state_version}, actual {item.state_version}"
            )

        item = replace(
            item,
            fence_mint_attempt_id=mint_attempt_id,
            fence_session_ref=session_ref,
            fence_acquired_at=now,
            state_version=item.state_version + 1,
            reason="MINT_FENCE_ACQUIRED",
        )
        self._by_id[approval_id] = item
        return item

    def finalize_session_mint(self, *, approval_id: str, now: float,
                              mint_attempt_id: str, session_ref: str,
                              commit_state: Optional[bool],
                              committed_at: Optional[float] = None) -> ApprovalRequest:
        item = self.get_request(approval_id, now=now)

        if item.state == "CONSUMED":
            if (
                item.consumed_mint_attempt_id == mint_attempt_id
                and item.consumed_session_ref == session_ref
            ):
                return item
            raise DuplicateSessionMint("approval already consumed by another session")

        if (
            item.fence_mint_attempt_id != mint_attempt_id
            or item.fence_session_ref != session_ref
        ):
            raise StateConflict("mint fence identity mismatch")

        if item.state not in {"APPROVED", "OUTCOME_UNKNOWN"}:
            raise StateConflict(f"cannot finalize mint from {item.state}")

        if commit_state is None:
            if item.state == "OUTCOME_UNKNOWN":
                return item
            item = replace(
                item,
                state="OUTCOME_UNKNOWN",
                state_version=item.state_version + 1,
                reason="SESSION_MINT_OUTCOME_AMBIGUOUS",
            )
            self._by_id[approval_id] = item
            return item

        if commit_state is False:
            next_state = "EXPIRED" if now >= item.expires_at else "APPROVED"
            item = replace(
                item,
                state=next_state,
                state_version=item.state_version + 1,
                fence_mint_attempt_id=None,
                fence_session_ref=None,
                fence_acquired_at=None,
                reason="SESSION_MINT_NOT_COMMITTED",
            )
            self._by_id[approval_id] = item
            return item

        if committed_at is None:
            raise ApprovalError("committed_at required for proven commit")

        if committed_at >= item.expires_at:
            item = replace(
                item,
                state="FAILED",
                state_version=item.state_version + 1,
                reason="MINT_COMMITTED_AFTER_APPROVAL_EXPIRY",
            )
            self._by_id[approval_id] = item
            return item

        item = replace(
            item,
            state="CONSUMED",
            state_version=item.state_version + 1,
            consumed_session_ref=session_ref,
            consumed_mint_attempt_id=mint_attempt_id,
            reason="SESSION_MINT_COMMITTED",
        )
        self._by_id[approval_id] = item
        return item

    def invalidate(self, *, approval_id: str, now: float, reason: str) -> ApprovalRequest:
        item = self.get_request(approval_id, now=now)
        if item.state not in self.REUSABLE:
            raise StateConflict(f"cannot invalidate from {item.state}")
        if item.fence_mint_attempt_id is not None:
            raise StateConflict("cannot invalidate while mint fence requires resolution")
        item = replace(
            item,
            state="INVALIDATED",
            state_version=item.state_version + 1,
            reason=reason,
        )
        self._by_id[approval_id] = item
        return item
