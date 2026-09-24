# Project: Example Feature — API rate limiting

> A sample project so the `/todo-*` skills have real content to resolve against.
> Copy this shape for your own projects (or run `/todo-add` + `/todo-plan`).

## Goal
Each authenticated API token gets a 100-token bucket refilling at 100 tokens/minute;
an exhausted bucket returns HTTP 429 with `Retry-After`, verifiable with a burst test.

## Context
`api-service` (a fictional example repo at `~/code/api-service`) exposes a public REST API
with no throttling today, so a single client can saturate it. This project adds a
token-bucket rate limiter at the gateway. There is no shared state store yet, so the limiter
needs one (Redis is assumed available).

This project exists mainly to demonstrate the hub workflow — the tasks below are illustrative.
The repo and design are fictional; a real `/todo-plan` must replace these assumptions with
source-backed findings before marking a project ready.

## Success Criteria
Observable, checkable outcomes — distinct from the tasks.
- [ ] A client sending 101 back-to-back requests receives 100 allowed responses and a 429 on the 101st.
- [ ] The 429 response includes a `Retry-After` header rounded up to the next available token.
- [ ] Limits are per-client (keyed by API token), not global.
- [ ] Requests under the limit are unaffected (no added error rate).
- [ ] Two gateway instances share the same per-client allowance under concurrent requests.
- [ ] If Redis is unavailable, the gateway returns 503 before running a protected handler.

## Constraints
- No breaking changes to existing 2xx response shapes.
- Limiter state must survive a single gateway restart (externalized, not in-process).

## Scope
**In:** token-bucket limiter middleware, per-token keying, 429 + `Retry-After`, config for the
rate.
**Out:** per-endpoint custom limits, quota billing, a client-facing usage dashboard.

## Implementation Approach
An authenticated request enters the gateway middleware. The middleware derives a stable
client key from the verified API-token identity and calls one atomic Redis operation to
refill and consume the token bucket. An allowed result continues to the handler. A denied
result returns 429 and rounds `Retry-After` up from the next available token time. The
middleware does not store raw API tokens in Redis keys.

All gateway instances use the same Redis bucket and rate configuration. If Redis times
out or is unavailable, the middleware returns 503 before the handler runs; recovery
resumes from the shared bucket state. A burst test checks the 101st response and header,
a concurrent two-instance test checks shared accounting, and an outage test checks 503.
These are illustrative contracts; a real plan would cite the gateway and Redis code in
`research/findings.md` and confirm the outage choice with the owner.

## Key Decisions
- **D1 — Token bucket.** Refill continuously at 100/minute rather than resetting a fixed window.
- **D2 — Atomic Redis operation.** Share and serialize bucket updates across gateway instances.
- **D3 — Fail closed on Redis outage.** Return 503 before the handler rather than bypassing the limit.

## Trade-offs
- **D1** — gain: controlled bursts · cost: more state and time arithmetic than a fixed window.
- **D2** — gain: consistent cross-instance limits · cost: a Redis dependency on every request.
- **D3** — gain: no unthrottled traffic during an outage · cost: valid clients may see 503.

**Forgone**
- Per-endpoint limits and billing quotas — separate product scope.

**Known gaps**
- The fictional example has no measured latency or production availability target.

## Relationships

| relation | target | reason |
|---|---|---|

## Verification
<!-- The "check" gate. Read by /todo-verify. Delete this section if the project has no
     verification MCP layer. This block is illustrative. -->
- **Feature:** api-rate-limiting
- **Run:** how to start the run (verification MCP tool + args, e.g. `start_run` with session reuse)
- **Gate covers:** Phase 3 tasks (integration / burst test)
- **Coverage source:** <optional; how to fetch coverage>
- **Task↔test map:**
  - "Add a burst integration test proving the 429 + Retry-After" ⟶ spec: rate-limit.spec

## Repo
`~/code/api-service` (fictional example — replace with your real repo)

## References
- Token-bucket algorithm overview
- Your gateway/middleware framework docs
