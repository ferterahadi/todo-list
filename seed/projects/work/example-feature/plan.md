# Project: Example Feature — API rate limiting

> A sample project so the `/todo-*` skills have real content to resolve against.
> Copy this shape for your own projects (or run `/todo-add` + `/todo-plan`).

## Goal
Every authenticated client is capped at 100 requests/minute, and a client that exceeds it
gets an HTTP 429 with a `Retry-After` header — verifiable with a burst test.

## Context
`api-service` (a fictional example repo at `~/code/api-service`) exposes a public REST API
with no throttling today, so a single client can saturate it. This project adds a
token-bucket rate limiter at the gateway. There is no shared state store yet, so the limiter
needs one (Redis is assumed available).

This project exists mainly to demonstrate the hub workflow — the tasks below are illustrative.

## Success Criteria
Observable, checkable outcomes — distinct from the tasks.
- [ ] A client sending 101 requests in one minute receives exactly one 429.
- [ ] The 429 response includes a `Retry-After` header with the seconds until reset.
- [ ] Limits are per-client (keyed by API token), not global.
- [ ] Requests under the limit are unaffected (no added error rate).

## Constraints
- No breaking changes to existing 2xx response shapes.
- Limiter state must survive a single gateway restart (externalized, not in-process).

## Scope
**In:** token-bucket limiter middleware, per-token keying, 429 + `Retry-After`, config for the
rate.
**Out:** per-endpoint custom limits, quota billing, a client-facing usage dashboard.

## Key Decisions
1. **Token bucket, not fixed window** — smoother bursts, standard `Retry-After` semantics.
2. **Redis for shared state** — already available; survives a gateway restart.

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
