# Tasks: Example Feature — API rate limiting

> Point your coding agent here to execute. Each task = one clear action, one line (~150 chars max).
> Detail and rationale go to `research/` or `artifacts/`, never inline here.

## Status
- [ ] Not started
- [x] Done

---

## Phase 1 — Limiter core
- [ ] Add a token-bucket limiter module: capacity 100, refill 100/min, keyed by API token
- [ ] Back the buckets with Redis so state survives a gateway restart
- [ ] Unit-test the bucket: consume, refill-over-time, and exhaustion boundaries

## Phase 2 — Wire into the gateway
- [ ] Add limiter middleware to the request pipeline, before the route handlers
- [ ] On limit exceeded, return HTTP 429 with a `Retry-After` header (seconds to reset)
- [ ] Make the rate configurable (env or config file), defaulting to 100/min

## Phase 3 — Verify end-to-end
- [ ] Add a burst integration test proving the 429 + `Retry-After` on the 101st request
- [ ] Confirm under-limit traffic is unaffected (no added errors on a 90-req/min run)

## Notes
- This is a sample project. The repo `~/code/api-service` is fictional — swap in a real one.

## Revisions
<!-- Managed by /todo-revise. One entry per gap found in completed work, backlinked to its source task. -->
<!-- ### R1 ⟵ Task N — what it touches        [open|done]
     - Gap: what's wrong
     - Expected: what the plan/user wanted
     - Actual: what was built instead
     - Fix: the concrete approach
     - [ ] implement + re-verify -->
