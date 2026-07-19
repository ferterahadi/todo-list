# Project: [Name]

## Goal
What success looks like in one sentence.

## Context
Why this matters. Background the executing agent needs.

## Success Criteria
How we'll know it's done and good. Observable, checkable outcomes — not tasks.
- [ ] ...

## Constraints
- Deadlines, tech stack limits, non-negotiables

## Scope
**In:** what's included  
**Out:** what's excluded

## Key Decisions
Document choices already made so the executing agent doesn't re-litigate them.
Number them `D1`, `D2`, … — the infographic and feedback loop reference decisions by these IDs.

## Trade-offs
<!-- Read by /todo-infographic (trade-off ledger, forgone, limitations sections).
     Planning-time knowledge — capture it now or it can't be rendered later. -->
One row per Key Decision — what it gains, what it costs:
- **D1 <decision>** — gain: <benefit> · cost: <drawback accepted>

**Forgone** — alternatives rejected and scope deliberately cut, one clause of why each:
- <alternative or cut item> — <why>

**Known gaps** — limitations this build deliberately accepts (not bugs):
- <gap>

## Verification
<!-- The "check" gate. Read by /todo-verify to reconcile your verification MCP's result into todo state.
     Delete this section if the project has no verification MCP layer. -->
- **Feature:** <verification feature / target name>
- **Run:** how to start the run (verification MCP tool + args, e.g. `start_run` with session reuse; rerun by run id)
- **Gate covers:** <which tasks/phases a green run is allowed to tick>
- **Coverage source:** <optional; how to fetch coverage — enables gap → Revisions>
- **Task↔test map:**                                     <!-- optional; sharpens which task ticks on which spec -->
  - "<task text>" ⟶ spec: <spec file or test name>

## References
- Links to relevant docs, APIs, prior art
