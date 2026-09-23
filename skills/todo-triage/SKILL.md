---
name: todo-triage
description: Use when the user invokes /todo-triage, says "what's left", "tabulate remaining work", "which model should handle this", "triage my tasks", or wants a cross-project table of open tasks with a recommended model per task. Read-only — tabulates and recommends, never edits.
---

# Project Triage Skill

You tabulate **what's left** across the hub — open tasks and open Revisions — and
recommend a provider-neutral execution tier for each item: **frontier**, **deep**,
**balanced**, or **fast**. Resolve each tier to the current host through
[`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md). The output is a decision aid: the user
picks the session model or dispatch target per task instead of running everything on
the most expensive model by default.

This is **read-only**. Never edit `index.md`, `tasks.md`, `plan.md`, or any project
file. To change state use `/todo-state`; to do the work use `/todo-execute`.

## The model this runs on

Hybrid, matching the hub's house pattern:

- **Gathering is mechanical** — deterministic helper output: one hub-wide count plus one
  open-task listing per project. When triaging **3+ projects**, delegate gathering to a
  **fast**-tier subagent when dispatching is available; for 1–2 projects run it inline. The
  subagent returns the object declared in [Step 2](#step-2--gather-remaining-work) and
  nothing else.
- **The recommendation is judgment** — classifying each task against the routing rubric
  requires reading the plan's context. Do this **inline on the main model**; never
  delegate the tier-per-task decision to the gathering subagent.

## Hub location

Resolve every hub path against `$TODO_HUB` — see
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Hub location.

## Placeholder safety

Validate every `<placeholder>` before it reaches a shell:
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Placeholder safety. Here
that means `<short-name>`, `<project>`, and `<project-path>`. On a failure, skip the
command and report the offending row. Every command this skill prints carries the
registry short-name in full — a shortened name resolves to nothing.

## How the user invokes this

```
/todo-triage                              ← every ready/in-progress project
/todo-triage rmq-vertical-scaler-quorum-queue   ← one project
/todo-triage work                         ← one section (work | self-initiative)
```

Plain language counts too: "what's left across my projects", "which model for these
tasks", "triage the quorum queue work".

## Step 1 — Resolve scope

Read active `$TODO_HUB/index.md` for default and section scopes.

- No argument → every project with status `ready` or `in-progress`. Mention `planning`
  projects only in a footer line ("N projects still in planning — no tasks to triage;
  run `/todo-plan <short-name>`", naming each).
- Short name → resolve per
  [`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Resolving a project. An
  archived project with no open work produces an empty result.
- Section name (`work` / `self-initiative`) → all `ready`/`in-progress` rows in that table.
- `done` projects are skipped unless their export row shows remaining work
  (`open_revisions` above zero or `done < total`) — an open or awaiting-verify revision
  still counts and gets triaged.

## Step 1.5 — Filter through the ready frontier

Run the deterministic graph helper before opening any project plans or task files:

```bash
python3 <todo-graph-skill-dir>/scripts/graph-report.py frontier "$TODO_HUB"
```

- Gather and model-route full task detail only for in-scope `IN_FLIGHT` and `READY`
  projects.
- Keep graph-blocked projects on the board as one project-level blocked row with the
  exact unsatisfied prerequisites. Do not spend tokens reading or routing their tasks;
  no model choice can satisfy another project's unfinished dependency.
- Keep `PLANNING` projects in the existing footer.
- Any graph identity/cycle error makes the affected component unactionable. Surface
  `/todo-graph audit` instead of guessing an order.
- Legacy registry `related` hints and canonical `related-to` / `supersedes` edges are
  context only and never remove a project from the frontier.

If the helper is unavailable, report that dependency-aware triage cannot run; do not
fall back to treating untyped relationships as blockers.

## Step 2 — Gather remaining work

Never read a large `tasks.md` whole (they run past 100 KB; the open items are usually a
tiny fraction). The helpers apply the canonical rule in
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Counting tasks and
§ Task IDs — the Status legend, commented templates, fences, and Notes/Context never
surface as tasks.

1. **Completion, once for the whole hub** — reuse the `NODE` rows from one call:
   ```bash
   python3 <todo-graph-skill-dir>/scripts/graph-report.py export "$TODO_HUB"
   ```
   `tasks=<done>/<total>` and `open_revisions=<n>` per project. Read the rows, not the exit
   status.
2. **Open tasks, per in-scope project** — uncapped, with canonical IDs:
   ```bash
   python3 <todo-graph-skill-dir>/scripts/graph-report.py tasks "$TODO_HUB" "<short-name>" --open
   ```
   Each `TASK\t<id>\topen\t<line>\t<text>` row is one open task; its `<id>` is the
   handle every command below uses. A row whose ID starts with `R` is a Revisions
   checkbox — route it as part of that revision, not as a separate task.
3. **Live Revisions** — extract each live revision heading and its `Gap:` line; the
   terminal tag decides the route, per
   [`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Revision tags:
   ```bash
   grep -inE -A4 '^#{2,3} R[0-9]+[A-Za-z]*([^A-Za-z0-9].*)?\[(open|fixed[^]]*awaiting verify|advisory)[^]]*\][[:space:]]*$' tasks.md
   ```
   Keep the heading and the first `Gap:` line of each match.
   - `[open]`, `[OPEN]`, `[open — note]` → an **open revision**, fixed by
     `/todo-revise <short-name> R<n>`. These headings must number exactly `open_revisions`;
     a mismatch means a heading the grep cannot see (an unusual tag or a commented block)
     — report it rather than guessing.
   - `[fixed — awaiting verify]` → **verify work**. Its `R` checkbox stays open until a
     green `/todo-verify <short-name>` ticks it; route it there, never to revise or execute.
   - `[advisory]` → an **optional** coverage gap with no checkbox. List it; never count it
     as remaining work. `/todo-revise <short-name> R<n>` promotes it to `[open]`.
4. **Blockers**: if `artifacts/blockers.md` exists, one line per blocker — a blocked task
   gets flagged, not model-routed (no model fixes a missing credential).

**Return contract** — whether gathered inline or by subagent, the result takes this shape
([`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Subagent return
contracts):

```json
{
  "projects": [{
    "short_name": "<registry short-name>",
    "status": "planning | ready | in-progress | done",
    "done": 14,
    "total": 20,
    "open_tasks": [{"id": "5.2", "phase": "<phase from the ID, e.g. 5 or 6a; - outside phases>", "text": "<verbatim TASK text>"}],
    "open_revisions": [{"id": "R3", "source_task": "4.1", "gap": "<the Gap: line>"}],
    "awaiting_verify": [{"id": "R4", "source_task": "5.2", "gap": "<the Gap: line>"}],
    "advisory": [{"id": "R8", "source_task": "5.3", "gap": "<the Gap: line>"}],
    "blockers": ["<one line each, or [] when blockers.md is absent>"]
  }]
}
```

`id` and `text` are copied **verbatim** from the helper — the board renders them and
`/todo-execute` targets the `id`, so a helpfully reworded task or a renumbered ID is a
broken handle. The open `TASK` rows (including `R` rows) must number exactly
`total − done`; any other count means truncated or re-derived output — say so rather than
routing a project as finished.

Also read each project's `plan.md` (Goal, Constraints, Key Decisions) — you need it to
judge task complexity in Step 3. For a big sweep, the `## Goal` + `## Constraints`
sections are enough; don't load whole plans for 15 projects.

## Step 3 — Recommend a model per task

Classify each open task and open Revision against this rubric (awaiting-verify rows skip
it — they run on `todo-verify`'s tier). **Default to the
cheapest model that can do the job safely; when torn between adjacent tiers, bump up
one tier — never two.**

**Routing — answer these in order; the first yes wins.** The rubric table below is the
reference; this list is the procedure:

1. Does the task touch auth/tokens/crypto/payments, migrate data, change concurrent
   behavior, or span 2+ repos? → **frontier**
2. Is there a "how" question about this task that plan.md doesn't answer? Apply the
   **quote test**: try to quote the plan sentence that answers it — no quotable sentence
   → that's a yes → **deep**. (Don't reason your way to an answer the plan never wrote
   down; inability to quote is the signal.)
3. Does it change code or system behavior at all? → **balanced**
4. Otherwise (text/state/config edits whose exact content is already specified) → **fast**

Then apply the modifiers below — **at most one bump total**, and record which modifier
fired in the "why" cell.

| Tier | Route here when | Typical signals |
|---|---|---|
| **fast** | Purely mechanical, zero design decisions | state flips, renames, doc formatting, config/version bumps, template scaffolds, moving files, regenerating from a spec that already exists |
| **balanced** | Well-scoped implementation the plan fully specifies | single-feature code + unit tests, HTML/infographic generation, wiring a spec'd integration, writing tests for existing behavior, contained bug with known cause |
| **deep** | Judgment the plan doesn't fully resolve, one-repo blast radius | cross-file refactors, debugging with unknown cause, performance work, API design within one service, ambiguous requirements needing interpretation |
| **frontier** | Wrong decision is expensive or dangerous | security/auth/token/crypto work, multi-repo migrations, concurrency/data-integrity changes, architecture decisions that constrain later phases, orchestrating parallel execution waves |

Modifiers that bump a task **up** one tier:
- The plan flags it as the riskiest phase, or a Revision exists because a cheaper pass
  already got it wrong once (rework of drifted work goes up a tier, not the same one).
- It touches anything in `## Constraints` marked non-negotiable.
- Its output gates other tasks (a wrong foundation multiplies cost downstream).

Modifiers that keep a task **down**:
- A `Task↔test map` / verification gate covers it — cheap model + hard verification beats an
  expensive model with no gate.
- `research/findings.md` already answers the open questions.

Each recommendation carries a short **why** that fits its table cell ("auth token
exchange — security-sensitive", "mechanical checkbox sync").

### Effort (the second dial)

Model and reasoning effort are independent levers. Start from the effort
`todo-llm-routing/SKILL.md` lists for the tier **on the current host**, and write only
values that skill lists:

- Take the tier's listed effort as-is for routine work.
- Raise it to **high** for debugging an unknown cause, security-sensitive reasoning, or
  anything a Revision already proved subtle. House precedent: `todo-verify` and
  `todo-infographic` run the balanced tier at **high** effort.
- Where the routing skill says the model takes no effort setting (the Claude Code fast
  model), the cell reads `default` and never gets raised; route up a tier instead.
- `xhigh` / `max` appear only on the routing skill's own terms. Never invent a level.

Render the tier, resolved host model, and effort in the model cell, for example
`balanced · <resolved host model> · medium` or `balanced · <resolved host model> · high`.

### Skill pairing (procedure beats raw intelligence)

For each item, also recommend a **skill to invoke** during execution — see
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Composing with installed
skills. Check `.agents/skills/`, `.claude/skills/`, and installed plugins alongside the
session listing; when nothing installed fits, the cell is `—`.

| Task smells like | Pair with (if installed) |
|---|---|
| code change that must be correct | `code-review` (effort matched to the task's tier) |
| working code that needs cleanup | `simplify` |
| chart / dashboard / metrics UI | `dataviz` |
| HTML one-pager, visual artifact | `artifact-design` (+ `dataviz` if it has charts) |
| UI/UX build or "looks wrong" gap | frontend-design / design-critique skills |
| architecture or approach not yet decided | brainstorming/architecture skills (e.g. superpowers) |
| open question needing sources | `deep-research` |
| proving a change works end-to-end | `verify` (or the project's verification gate) |

## Step 4 — Render the triage board

Per project, a card — status icon, progress bar, then the table. Progress bars are 10
cells of `▓`/`░` (`round(done/total*10)`):

```
### 🔄 rmq-vertical-scaler-quorum-queue   ▓▓▓▓▓▓▓░░░ 14/20 · 1 open revision · 1 awaiting verify

| # | remaining task | phase | tier · model · effort | skill | why |
|---|---|---|---|---|---|
| 5.2 | Failover drill under quorum loss | Phase 5 | **frontier · resolved model · high** | verify | data-integrity, gates 5.3–5.5 |
| 5.3 | Grafana panel for quorum lag | Phase 5 | balanced · resolved model · medium | dataviz | spec'd in plan, contained |
| R3 | Re-verify scaler after fix ⟵ Task 4.1 | Revisions | deep · resolved model · high | code-review | rework of drifted work |
| R4 | Consumer backoff ⟵ Task 4.3 · awaiting verify | Revisions | balanced · resolved model · high | verify | fix accepted — `/todo-verify` closes it |
| 6.1 | Bump version + changelog | Phase 6 | fast · resolved model · default | — | mechanical version bump |

Optional: R8 advisory — no e2e covers the rotate endpoint (`/todo-revise rmq-vertical-scaler-quorum-queue R8` promotes it)
```

The fast row shows the effort the routing skill lists for the host running the triage —
`default` where that model takes no effort setting.

- Number rows by the helper's IDs so commands target them directly:
  `/todo-execute <short-name> tasks <id,id,…>` for tasks,
  `/todo-revise <short-name> R<n>` for an open revision — the `R` is part of the handle —
  and `/todo-verify <short-name>` for awaiting-verify rows; one verify run covers them all.
  A verify row takes `todo-verify`'s own tier (balanced · high), not a rubric pick.
- `[advisory]` entries go on one `Optional:` line under the table, never in it; they are
  not counted in the card's total or the totals line.
- Blocked tasks get a `⛔ blocked` model cell with the blocker one-liner as the why.
- Order cards most-complete first (same instinct as `/todo-list sort`), but don't edit
  `index.md` order — this is display only.

## Step 5 — Summarize and point at execution

End with:

1. **Totals line**, e.g.
   `31 items left — 3 frontier · 7 deep · 14 balanced · 5 fast · 2 blocked · 1 verify`
   Follow with a one-line token read: how many expensive-tier items exist and whether a
   skill pairing lets any of them drop a tier (e.g. "2 of 3 frontier items are gated by
   verification — could run deep · high instead").
2. **Fan-out candidates**: if one project has 2+ file-disjoint balanced/fast tasks, name
   them as a `/todo-execute <short-name> parallel tasks <id,id,…>` group (the biggest
   efficiency win this skill can surface).
3. **Batch hint**: if fast-tier items span projects (state syncs, doc fixes), suggest
   clearing them in one cheap sweep before starting expensive work.
4. **Session plan** — turn the tiers into commands the user can run as-is. Group the
   board's items by recommended model, then emit one line per group; a task's model is
   set by the *session* it runs in, so this is the actionable form of the whole board:

   ```
   ## ▶ Session plan

   now (this session)       dispatch the 5 fast items — say "go" and I'll sweep them
   <balanced host model>    → /todo-execute rmq-vertical-scaler-quorum-queue tasks 5.3
   <balanced host model>    → /todo-verify rmq-vertical-scaler-quorum-queue
   <deep host model>        → /todo-revise rmq-vertical-scaler-quorum-queue R3
   <frontier host model>    → /todo-execute rmq-vertical-scaler-quorum-queue tasks 5.2
   ```

   Resolve placeholders from `todo-llm-routing/SKILL.md` and show commands only for the current
   host. For example, Claude Code uses `claude --model <name>`; Codex uses
   `codex --model <model-id> -c model_reasoning_effort=<effort>`. Fast items never need
   a new session when they can be dispatched inline. Emit one line per
   model × project pair, carrying the full short-name and the exact IDs from the board
   (`tasks <id,id,…>` for tasks, `R<n>` for a revision, one revision per `/todo-revise`
   line, one `/todo-verify <short-name>` line per project with awaiting-verify rows); if the session is already on the right model for a group, say so instead of
   telling the user to relaunch. Use the host's model picker when available.

## Notes

- Recommendations are **advisory routing**, not overrides. Execution skills keep their
  own rules (`todo-execute` runs inline on the session model; `todo-verify` uses balanced
  at high effort; `todo-execute` parallel mode inherits the session model). The triage tells
  the user which session model to *pick* before invoking those skills, or which tasks
  are safe to hand to a cheap dispatch.
- Model names live only in `todo-llm-routing/SKILL.md`; keep this skill's decision logic in tiers.
- Idempotent and read-only: run it as often as you like; nothing changes on disk.
- If every in-scope project has zero open items, say so and celebrate briefly — don't
  invent work.
