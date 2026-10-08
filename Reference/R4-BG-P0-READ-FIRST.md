# Observer R4-BG P0 isolated candidate

**Status:** ISOLATED_CANDIDATE / IOS_BUILD_PENDING / APNS_DEVICE_GATE_BLOCKED / NOT_PRODUCTION

Branch: observer-r4-bg-p0-isolated-20261008
Frozen base: observer-b4-close-ci-20261008 @ 5ada8694d2f623007a090f984bc41f45df910e3a.

This is not a change to Production, Backend Authority, or UI V2 branch. There is no APNs provider installed and no app delegate connected.

## Included
- SQLite-based durable approval attempt journal, with exclusive first-submit authorization.
- Background action engine: scoped hint -> fresh Owner GET -> 30s advisory -> atomic attempt -> CAS -> durable result.
- Adapter for current Owner Control protocol.
- **Unwired** iOS notification delegate candidate, not enabled until signed APNs entitlement and cold-launch iOS E2E.
- Isolated Swift 6 contract tests; the Linux test uses a local SQLite3 modulemap, not an iOS dependency.

## Blocking integration gates
1. Published signing_report.py declares push_notifications=false and unsigned CI IPA. Inspect the *real signed* distributable Profile/entitlement/device APNs registration.
2. Swift iOS/macOS compile the notification handler before it is enabled; fix SDK concurrency / completion handling based on real compiler output.
3. Wire in-app Approvals through the SAME journal and coordinator; otherwise two user entrypoints can produce unrelated decision_attempt_id values.
4. Durable reconcile: after an uncertain POST, GET the authoritative status and keep operation attribution uncertainty. APPROVED on GET doesn't prove this tap caused it.
5. Handle expiration cancel safely; do not send another POST under a new attempt ID.
6. Ensure data-protection behavior for SQLite in the background and keep Owner Approval / Session Close bearers separately scoped.
7. Only after APNs gate, add authenticated device-token registration and server APNs provider. Do not introduce silent-push continuous polling.

The notification delegate remains deliberately unregistered and the effective feature is OFF.
