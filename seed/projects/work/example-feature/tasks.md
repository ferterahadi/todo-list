# Tasks: Example Feature — API rate limiting

> Point your coding agent here to execute. Each task = one clear action, one line (~150 chars max).
> Agreed behavior lives in `plan.md`; source evidence lives in `research/`.

## Status
- [ ] Not started
- [x] Done

---

## Tasks

### Phase 1 — Limiter core
- [ ] Add a token-bucket limiter module: capacity 100, refill 100/min, keyed by verified token identity
- [ ] Add an atomic Redis refill-and-consume operation shared by all gateway instances
- [ ] Unit-test the bucket: consume, refill-over-time, and exhaustion boundaries

### Phase 2 — Wire into the gateway
- [ ] Add limiter middleware to the request pipeline, before the route handlers
- [ ] On limit exceeded, return HTTP 429 with `Retry-After` rounded up to the next token
- [ ] Return 503 before handler execution when Redis is unavailable
- [ ] Make the rate configurable (env or config file), defaulting to 100/min

### Phase 3 — Verify end-to-end
- [ ] Add a burst integration test proving the 429 + `Retry-After` on the 101st request
- [ ] Test concurrent requests across two gateway instances and a Redis outage
- [ ] Confirm under-limit traffic is unaffected (no added errors on a 90-req/min run)

## Notes
- This is a sample project. The repo `~/code/api-service` is fictional — swap in a real one.

## Revisions
<!-- Managed by /todo-revise and /todo-verify. One gap per entry. Canonical tags are lowercase, while
     readers accept historical case variants: [open] the gap stands · [fixed — awaiting verify] fix
     accepted, waiting for a green /todo-verify run · [done] closed and archived · [advisory] a
     coverage gap from /todo-verify, with no checkbox, that never blocks done. -->
<!-- ### R1 ⟵ Task <id> — what it touches        [open]
     - Gap: what's wrong
     - Expected: what the plan/user wanted
     - Actual: what was built instead
     - Fix: the concrete approach
     - [ ] implement + re-verify -->
<!-- Closed entries collapse to:
### R1 ⟵ Task <id> — what it touches        [done]
- archived → [journal:R1](artifacts/journal.md#revision-r1) (YYYY-MM-DD) -->
