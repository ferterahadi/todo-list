---
name: todo-triage
description: Use when the user invokes /todo-triage, says "what's left", "tabulate remaining work", "which model should handle this", "triage my tasks", or wants a cross-project table of open tasks with a recommended model per task. Read-only — tabulates and recommends, never edits.
---

# Project Triage Skill

You tabulate **what's left** across the hub — open tasks and open Revisions — and
recommend a provider-neutral execution tier for each item: **frontier**, **deep**,
**balanced**, or **fast**. Resolve each tier to the current host through
[`../model-routing/SKILL.md`](../model-routing/SKILL.md). The output is a decision aid: the user
picks the session model or dispatch target per task instead of running everything on
the most expensive model by default.

This is **read-only**. Never edit `index.md`, `tasks.md`, `plan.md`, or any project
file. To change state use `/todo-update-state`; to do the work use `/todo-execute`.

## The model this runs on

Hybrid, matching the hub's house pattern:

- **Gathering is mechanical** — reading `index.md`, counting checkboxes, extracting open
  task lines. When triaging **3+ projects**, delegate gathering to a **fast**-tier
  subagent when dispatching is available. It returns, per project:
  status, `done/total`, the verbatim open task lines grouped by phase, open `## Revisions`
  headings, and any `artifacts/blockers.md` one-liners. For 1–2 projects just read inline.
- **The recommendation is judgment** — classifying each task against the routing rubric
  requires reading the plan's context. Do this **inline on the main model**; never
  delegate the tier-per-task decision to the gathering subagent.

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Resolve **every** path against this
absolute root — `index.md`, each project's `path`, `plan.md`, `tasks.md` — regardless of
the current working directory. This skill may be invoked from another repo; never assume
cwd is the hub. (Same convention as `todo-refer`.)

## How the user invokes this

```
/todo-triage                              ← every ready/in-progress project
/todo-triage rmq-vertical-scaler-quorum-queue   ← one project
/todo-triage work                         ← one section (work | self-initiative)
```

Plain language counts too: "what's left across my projects", "which model for these
tasks", "triage the quorum queue work".

## Step 1 — Resolve scope

Read `$TODO_HUB/index.md`.

- No argument → every project with status `ready` or `in-progress`. Mention `planning`
  projects only in a footer line ("N projects still in planning — no tasks to triage;
  run `/todo-plan`").
- Short name → that project only; not found → tell the user and stop.
- Section name (`work` / `self-initiative`) → all `ready`/`in-progress` rows in that table.
- `done` projects are skipped unless they have **open Revisions** — those still count as
  remaining work and get triaged.

## Step 2 — Gather remaining work

For each in-scope project (via the fast-tier gathering subagent when 3+, else inline):

- **Open tasks**: every `- [ ]` line in `tasks.md`, kept verbatim, grouped under its
  phase header. **Extract — never read a large tasks.md whole** (they run up to 115KB;
  the open items are usually a tiny fraction):
  ```bash
  grep -nE '^(#{2,3} |\s*- \[ \])' tasks.md    # phase headers + open items only
  ```
  Use the shared counting rules: **skip the `## Status` legend block** and
  **skip anything inside HTML comments** (same awk snippet as `todo-list` sort mode /
  `todo-update-state`).
- **Open Revisions**: every `### R<n> … [open]` heading with its `Gap:` line
  (`grep -A1 -E '^### R[0-9]+.*\[open\]' tasks.md`).
- **Completion**: `done/total` via the shared awk snippet.
- **Blockers**: if `artifacts/blockers.md` exists, one line per blocker — a blocked task
  gets flagged, not model-routed (no model fixes a missing credential).

Also read each project's `plan.md` (Goal, Constraints, Key Decisions) — you need it to
judge task complexity in Step 3. For a big sweep, the `## Goal` + `## Constraints`
sections are enough; don't load whole plans for 15 projects.

## Step 3 — Recommend a model per task

Classify each open task and open Revision against this rubric. **Default to the
cheapest model that can do the job safely; when torn between adjacent tiers, bump up
one tier — never two.**

**Deterministic routing — answer these in order, first YES wins.** This makes the
classification reproducible regardless of which model runs it; the rubric table below
is the reference, this list is the procedure:

1. Does the task touch auth/tokens/crypto/payments, migrate data, change concurrent
   behavior, or span 2+ repos? → **frontier**
2. Is there a "how" question about this task that plan.md doesn't answer? Apply the
   **quote test**: try to quote the plan sentence that answers it — no quotable sentence
   → that's a YES → **deep**. (Don't reason your way to an answer the plan never wrote
   down; inability to quote IS the signal.)
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

Each recommendation carries a **why** of at most ~6 words ("auth token exchange —
security-sensitive", "mechanical checkbox sync"). No paragraphs.

### Effort tier (the second dial)

Model and reasoning effort are independent levers. Recommend one effort per item and
resolve the tier to the current host using `model-routing/SKILL.md`:

- **low** — mechanical or fully spec'd work; thinking longer can't change the answer.
- **medium** — default for routine implementation.
- **high** — debugging unknown causes, security-sensitive reasoning, anything a
  Revision already proved subtle. House precedent: `todo-verify` and `todo-infographic`
  run the balanced tier at **high** effort.

Render the tier and resolved host model in the model cell, for example
`balanced · Sonnet · high` or `balanced · <resolved Codex model> · high`.

### Skill pairing (procedure beats raw intelligence)

For each item, also recommend a **skill to invoke** during execution. A skill is a
distilled procedure — pairing the right one lets a *cheaper* model succeed where a
bare expensive model would flail and retry, which is the real token win.

**Only recommend skills that actually exist** — check the session's available-skills
listing plus `.agents/skills/`, `.claude/skills/`, and installed plugins first. Never
invent a skill name; if no installed skill fits, the cell is `—`.

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
### 🔄 rmq-vertical-scaler-quorum-queue   ▓▓▓▓▓▓▓░░░ 14/20 · 2 open revisions

| # | remaining task | phase | tier · model · effort | skill | why |
|---|---|---|---|---|---|
| 5.2 | Failover drill under quorum loss | Phase 5 | **frontier · resolved model · highest** | verify | data-integrity, gates 5.3–5.5 |
| 5.3 | Grafana panel for quorum lag | Phase 5 | balanced · resolved model · medium | dataviz | spec'd in plan, contained |
| R3 | Re-verify scaler after fix ⟵ Task 4.1 | Revisions | deep · resolved model · high | code-review | rework of drifted work |
| 6.1 | Bump version + changelog | Phase 6 | fast · resolved model · low | — | mechanical version bump |
```

- Number rows by their task/revision identifiers so `/todo-execute <name>` and
  `/todo-revise <name> <n>` can target them directly.
- Blocked tasks get a `⛔ blocked` model cell with the blocker one-liner as the why.
- Order cards most-complete first (same instinct as `/todo-list sort`), but don't edit
  `index.md` order — this is display only.

## Step 5 — Summarize and point at execution

End with:

1. **Totals line**, e.g.
   `31 items left — 3 frontier · 7 deep · 14 balanced · 5 fast · 2 blocked`
   Follow with a one-line token read: how many expensive-tier items exist and whether a
   skill pairing lets any of them drop a tier (e.g. "2 of 3 frontier items are gated by
   verification — could run deep · high instead").
2. **Fan-out candidates**: if one project has 2+ file-disjoint balanced/fast tasks, name
   them as a `/todo-execute <name> parallel` group (the biggest efficiency win this skill can
   surface).
3. **Batch hint**: if fast-tier items span projects (state syncs, doc fixes), suggest
   clearing them in one cheap sweep before starting expensive work.
4. **Session plan** — turn the tiers into commands the user can run as-is. Group the
   board's items by recommended model, then emit one line per group; a task's model is
   set by the *session* it runs in, so this is the actionable form of the whole board:

   ```
   ## ▶ Session plan

   now (this session)       dispatch the 5 fast items — say "go" and I'll sweep them
   <balanced host model>    → /todo-execute rmq-vertical-scaler tasks 5.3,6.1
   <deep host model>        → /todo-revise api-token-rotation 3
   <frontier host model>    → /todo-execute payments-retry tasks 2.1
   ```

   Resolve placeholders from `model-routing/SKILL.md` and show commands only for the current
   host. For example, Claude Code uses `claude --model <name>`; Codex uses
   `codex --model <model-id> -c model_reasoning_effort=<effort>`. Fast items never need
   a new session when they can be dispatched inline. Emit one line per
   model × project pair, carrying the exact task/revision numbers from the board; if the
   session is already on the right model for a group, say so instead of telling the user
   to relaunch. Use the host's model picker when available.

## Notes

- Recommendations are **advisory routing**, not overrides. Execution skills keep their
  own rules (`todo-execute` runs inline on the session model; `todo-verify` uses balanced
  at high effort; `todo-execute` parallel mode inherits the session model). The triage tells
  the user which session model to *pick* before invoking those skills, or which tasks
  are safe to hand to a cheap dispatch.
- Model names live only in `model-routing/SKILL.md`; keep this skill's decision logic in tiers.
- Idempotent and read-only: run it as often as you like; nothing changes on disk.
- If every in-scope project has zero open items, say so and celebrate briefly — don't
  invent work.
