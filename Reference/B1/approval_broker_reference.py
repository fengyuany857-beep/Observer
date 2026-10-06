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
        self._mint_owner: Dict[str, str] = {}
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
        if item.state in {"PENDING", "APPROVED"} and now >= item.expires_at:
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

    def consume_for_session(self, *, approval_id: str, now: float,
                            mint_attempt_id: str, session_ref: str,
                            mint_commit_proven: bool) -> ApprovalRequest:
        if not mint_attempt_id.strip() or not session_ref.strip():
            raise ApprovalError("mint identity required")

        item = self.get_request(approval_id, now=now)

        if item.state == "CONSUMED":
            if item.consumed_mint_attempt_id == mint_attempt_id and item.consumed_session_ref == session_ref:
                return item
            raise DuplicateSessionMint("approval already consumed by another session mint")
        if item.state == "EXPIRED":
            raise Expired(approval_id)
        if item.state != "APPROVED":
            raise StateConflict(f"cannot consume from {item.state}")

        existing_owner = self._mint_owner.get(approval_id)
        if existing_owner and existing_owner != session_ref:
            raise DuplicateSessionMint("approval already reserved by another session")

        if not mint_commit_proven:
            return item

        self._mint_owner[approval_id] = session_ref
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
        item = replace(
            item,
            state="INVALIDATED",
            state_version=item.state_version + 1,
            reason=reason,
        )
        self._by_id[approval_id] = item
        return item
