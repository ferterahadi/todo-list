---
name: todo-plan
description: Use when the user invokes /todo-plan, says "plan this project", "replan X", "update the plan", "break X into tasks", or names a hub project and wants its plan created or revised. Runs discovery, verifies the target repo exists locally, then writes the hub project's plan.md and tasks.md — not a writer for generic implementation plans outside the hub.
---

# Project Planning Skill

You plan projects stored in a hub repo. Each project has plan.md and tasks.md. Your job: fill them in through structured discovery.

This is judgment work involving discovery, scope, and decisions. Run it inline on the
current session model; use at least the **balanced** tier from
[`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md). Use its **deep** tier
when the design is ambiguous or crosses services; model choice does not replace repo
inspection.

## Compose with installed skills — organize, don't replace

This skill owns the **organization layer**: hub resolution, the plan.md/tasks.md format,
the quality gate, index bookkeeping. The **thinking** belongs to the best process skill the
user already has — see
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Composing with installed
skills. Here that means:

- **Discovery/design** — if `superpowers:brainstorming` is installed, run it first; it
  explores intent, requirements, and design better than a question list. Step 2's seven
  questions then become the *coverage checklist*: after brainstorming, ask only what it
  didn't surface. Not installed → run Step 2 yourself.
- **Task breakdown** — if `superpowers:writing-plans` is installed and the work is a
  multi-step code change, let it draft the implementation plan, then translate the result
  into the hub format (Steps 5–6). Any doc it writes into the target repo
  (`docs/superpowers/…`) gets an immediate pointer row in `research/superpowers-docs.md`.

Delegation changes who thinks, not what ships: the output always lands in the hub's
plan.md/tasks.md shape, and the Step 6.5 gate runs on the final files regardless of
which skill produced the content.

## Hub location

Resolve every hub path against `$TODO_HUB` — see
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Hub location. The `repo`
column points at the target codebase elsewhere and is not resolved against the hub.

## How the user invokes this

```
/todo-plan queue-migration
/todo-plan projects/work/queue-migration   ← full path also works
```

Running it on a project that already has a plan is a replan — same steps, asking only what
should change.

## Step 1 — Resolve the project path

Resolve the project per
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Resolving a project,
recording the `path`, `repo`, owning registry, and section.

A short-name in neither registry is not a dead end here: offer to scaffold it with
`todo-add` now — its single prompt covers short-name and work vs self-initiative — then
continue planning the new row in the same run.

## Step 2 — Establish the starting point

Read the current plan, tasks, registry row, and any user-supplied context. A `planning`
row may contain only the scaffold from `todo-add`; treat placeholder text as missing, not
as an answer. On a replan, preserve accepted decisions and completed work, but verify
current-state claims against the repo before carrying them forward.

If the row's `repo` is `-` or the path does not exist, ask for the target repo path now.
If the outcome itself is unclear, ask what observable result the user wants. Ask for any
specific docs, tickets, or other repos they want considered. Defer detailed design
questions that source inspection can answer. Use structured choices for enumerable
questions when available, and ask the missing basics in one turn.

## Step 3 — Verify the repo

Once the repo path is settled — confirmed by the user, or a row `repo` Step 2 skipped:

- Check the path exists on disk
- If it's a git repo, note the current branch
- If the path doesn't exist, tell the user and ask for the correct path before continuing

## Step 4 — Inspect the current system

Inspect the confirmed repo even when the user named no source file. Search the relevant
entry points, callers, data models, tests, configuration, and nearby docs; follow the
current request or data path far enough to explain the behavior being changed. Read
user-supplied references and any related repos as needed. Keep the search proportional:
a small change needs a focused trace; a cross-service or data-integrity change needs the
contracts and failure paths across its boundaries. Do not invent file paths or APIs.

Record a concise evidence map in `research/findings.md`: source baseline/branch, current
behavior with file paths, the affected components, existing tests and constraints,
material unknowns, and any external claim that still needs confirmation. Label proposed
behavior as proposed. This file supports the plan; it is not a substitute for the
implementation approach in `plan.md`.

Also check the confirmed repo for existing superpowers docs —
`<repo>/docs/superpowers/plans/` and `<repo>/docs/superpowers/specs/` (written by the
brainstorming / writing-plans skills in earlier target-repo sessions). Read any that touch
this project, list them as rows in `research/superpowers-docs.md` (a table: doc path ·
source · one-line summary), and fold their decisions into the plan instead of re-deciding.

After inspection, ask only for material choices the repo cannot settle: outcome and scope,
external constraints (such as deadlines or locked technology), whether a verification MCP
layer exists and its feature/target if so, and exact tracked-project relationships with
a reason. Present the observed baseline and a recommendation beside each choice; batch
open questions. Wait for answers to decisions that change the design.
If an answer can safely be deferred, state the unknown and make its investigation an
explicit task that gates dependent implementation. Do not turn an unknown into a guessed
decision.

## Step 5 — Write plan.md

Fill in the project's `plan.md`:

- **Goal**: one sentence — what success looks like
- **Context**: background a future agent session needs to execute without asking questions
- **Success Criteria**: observable, checkable outcomes (the expectation) — written as a `- [ ]` list, distinct from tasks. These are what `todo-revise` compares completed work against, so make them concrete and testable, not aspirational
- **Constraints**: deadlines, tech limits, non-negotiables
- **Scope**: what's in / what's out
- **Implementation Approach**: explain the current path → proposed path in terms of the
  actual components and interfaces. Include the data/API contract, important edge and
  failure behavior, compatibility or migration, and rollout/recovery when they matter.
  Link the evidence map and any larger design artifact. Scale detail to complexity: a
  small change may need one paragraph; a multi-service change needs the boundary and
  sequence an executor would otherwise have to rediscover. Keep agreed design here,
  not solely in a distant artifact.
- **Key Decisions**: choices already made so the next agent doesn't re-litigate them. Number them `D1`, `D2`, … — `todo-infographic` and the feedback loop reference decisions by ID. If the architecture/approach is still genuinely open (the user couldn't answer "how"), don't pad this section with guesses — check for an installed brainstorming/architecture skill (e.g. from superpowers) and offer to run it to converge on the decision first; otherwise record the open question explicitly as a decision-to-make task. If such a skill writes its output into the target repo (`docs/superpowers/…`), immediately record a pointer in `research/superpowers-docs.md` and under plan.md References — a doc that lives only in the target repo is lost to the hub
- **Key Decisions**: choices already made so the next agent doesn't re-litigate them. Number them `D1`, `D2`, … — `todo-infographic` and the feedback loop reference decisions by ID. If the approach is open, use an installed brainstorming/architecture skill when applicable to develop a recommendation; ask the user only for a material choice they own. Otherwise make the unresolved choice a decision task that gates implementation. Do not pad this section with guesses. If another skill writes into the target repo (`docs/superpowers/…`), immediately record a pointer in `research/superpowers-docs.md` and under plan.md References — a doc that lives only in the target repo is lost to the hub
- **Trade-offs**: planning-time knowledge the infographic renders later — capture it now or it's lost. Three parts, per the template: one `**D<n>** — gain: … · cost: …` row per Key Decision; **Forgone** — alternatives you and the user considered and rejected (plus scope deliberately cut), one clause of why each; **Known gaps** — limitations the build deliberately accepts. Record rejected alternatives *as they're rejected* during discovery, not reconstructed afterwards. If a part is genuinely empty, delete its stub line rather than padding it.
- **Relationships**: the canonical typed project graph. Write one row per explicit
  relationship: `depends-on` for a hard prerequisite, `related-to` for context, or
  `supersedes` for lineage. Resolve every target by exact short-name active-first, then
  archive. Record why the edge exists. Never store `blocks` (it is derived), promote a
  legacy registry `related` hint into a dependency, or infer an edge from name similarity.
  Keep the three-column table empty when there are no relationships. If an older plan has
  no section, insert the canonical table before `## Verification` or `## References`.
- **Verification**: the "check" gate binding for `/todo-verify`. If the project has a verification MCP layer, ask for the feature/target name and fill the `## Verification` block — `Feature`, `Run` (the start tool and its arguments, and how to rerun by id), `Gate covers` (which tasks/phases a green run may tick), and optionally `Coverage source` + a `Task↔test map`. If there's no verification layer, delete the section.
- **Repo**: absolute path to the local codebase (confirmed in Step 3)
- **References**: paths or links to relevant resources

Replace every scaffold placeholder and the scaffold marker. Write with enough detail that
a cold agent session can pick this up without talking to the user.

## Step 6 — Write tasks.md

Break the work into a concrete checklist:

- Each task must be specific and actionable — "implement X" not "think about X"
- A future agent session should be able to execute each task without asking questions
- Order by dependency (prerequisites first)
- When the project has distinct phases, write each as `### Phase N — title` under
  `## Tasks` (`N` is a number with an optional letter, e.g. `6a`); a single-phase project
  lists its tasks straight under `## Tasks`. Task IDs are positional — `2.3` is the third
  task under Phase 2 ([`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md)
  § Task IDs and phases) — so never hand-number task lines. On a replan, add tasks at the end of their
  phase or in a new phase when order allows: inserting mid-phase renumbers every later task
  in it, and existing `⟵ Task <id>` backlinks would point at the wrong work.
- **One line per task (~150 chars max).** Supporting detail, mechanics, and rationale go
  to `plan.md` for agreed behavior or `research/findings.md` for source evidence, with a
  pointer when the link is not obvious. Every task needs a concrete output and a check
  that proves it works; those may live in the plan rather than on the checklist line.
  `tasks.md` is read whole by several skills; it must stay a checklist, not a journal.

## Step 6.5 — Quality gate, before anything is shown

A failed check means fix the file and re-run the gate; a plan that fails a check is not
shown:

- [ ] **Goal test**: one sentence, and it names an observable outcome (a number, a state
  someone can check, or a named artifact). If it contains "improve", "support",
  "enhance", or "better" without a measurable object → rewrite until a stranger could
  say yes/no to "did this happen?".
- [ ] **Scaffold test**: no template instructions, placeholder tasks, or scaffold marker
  remain in the plan or task checklist.
- [ ] **Success Criteria test**: for each criterion, write down (mentally) the exact
  command, test, or observation that would check it. Can't name one → the criterion is
  aspirational; rewrite it or move it to Context.
- [ ] **Evidence and design test**: the plan identifies the source baseline and explains
  the affected current path → proposed path. Current-state claims have repo or
  user-supplied evidence; assumptions and proposed behavior are labelled. For a material
  interface or data change, the plan states the contract and failure/compatibility path.
- [ ] **Task test**: every task line starts with a verb, names its target (file, system,
  endpoint), and fits on one line. "Think about X" / "handle Y properly" fail.
- [ ] **Execution test**: each implementation task has an output and a checkable proof
  in the task or plan. Every Success Criterion is covered by a task and verification
  method; every necessary migration, rollback, or operational gate has an owner/task.
  An unresolved design choice has a decision/spike task before dependent work.
- [ ] **Dependency walk**: read tasks.md top to bottom once; if any task needs an output
  produced by a later task, reorder now.
- [ ] **Project-graph test**: after writing Relationships, check this project only —
  `python3 <todo-graph-skill-dir>/scripts/graph-report.py context "$TODO_HUB" <short-name>`
  (validate `<short-name>` first; `todo-conventions` § Placeholder safety). An `ERROR` line
  about this project's edges fails the plan: a missing or ambiguous target, an unknown
  relation, a self-edge, a duplicate edge, a malformed table, or a cycle through this
  project. Fix the table before continuing; do not reinterpret a broken edge. Expected, and
  not failures: a `BLOCKERS` line for an unsettled prerequisite (it gates execution, not
  planning), `DONE_OPEN_WORK` on a `done` project you are replanning (Step 8 reopens it),
  and any issue elsewhere in the hub. If the helper is unavailable and the table contains a
  `depends-on` row, stop instead of publishing an unvalidated hard dependency.
- [ ] **Cold-session test**: for each task ask "would a fresh session need to ask the
  user anything to do this?" If yes, the answer belongs in plan.md Context — add it.
- [ ] **Repo check**: the Repo path in plan.md was verified on disk this session (you
  saw the `ls`/git output in Step 3, not remembered it).

## Step 7 — Review the actual plan

Render a compact, decision-quality preview and link the full `plan.md` and `tasks.md` by
their verified absolute paths. Include the current → proposed path, one representative
implementation task with its proof, and the main unresolved choice or risk. The preview
helps scanning; it must not hide the design the user is being asked to accept. If the user
asked for a detailed plan in the conversation, show the relevant design and task detail
directly rather than offering to reveal it later.

For example:

```
## 📋 rmq-dlq-support — plan at a glance

🎯 **Goal** — Dead-lettered messages are retried 3× then parked with alerting.

| ✅ In scope | 🚫 Out of scope |
|---|---|
| DLQ topology + retry policy | Consumer-side dedup |
| Parking-lot queue + alert | Multi-cluster federation |

**Phases**   Phase 1 · setup (3) ─▶ Phase 2 · retry policy (5) ─▶ Phase 3 · alerting (4)   — 12 tasks

**Decisions** ① quorum queues, not classic ② retry via per-queue TTL, not delayed-exchange plugin

**Change** Consumer failure → bounded retry queues → parking lot + alert; broker restart is not required.

**Proof** Force retries to exhaust in a test run; inspect the parked message and alert.

**Graph** auth-foundation ─▶ rmq-dlq-support · token-rotation (context)

**Constraints** ⛔ no broker restart in prod · ⚠️ ship before the 4.1 upgrade

**Verification** 🔬 `rmq-dlq` gates Phase 3   (or: — none)

**Full files** [plan.md](<absolute path>) · [tasks.md](<absolute path>)
```

Rules for the render:
- Goal = one line, key noun bolded. Scope = two-column table, top items only.
- Phases = a `─▶` pipeline with per-phase task counts — this is the tasks.md summary;
  don't paste the checklist.
- Decisions numbered ①②③, one clause each. Constraints as chips: ⛔ hard, ⚠️ soft.
- Graph = hard prerequisites first, then context/lineage; omit the line when empty.
- Change and Proof = the most important design path and a concrete check; mention an
  unresolved decision or risk when one remains. Link full files using paths that exist.

Then ask via the host's structured choice prompt when available: "Does this plan look
right?" with options
"Looks right — lock it in" / "Adjust something" / "Show me the full plan.md".
Apply changes and re-run the Step 6.5 gate on any file you edited. Nothing touches the
registry until the user confirms.

## Step 8 — Update the registry, once confirmed

- Set `repo` to the confirmed absolute local path.
- `planning` → set `ready` and stamp `started` = today, overwriting the creation stamp
  `/todo-add` left (`todo-state` § Date stamping).
- `ready` or `in-progress` → leave `status` and `started` alone; a replan never demotes
  work that has begun, and never clobbers a real start date.
- `done`, active or archived → a replan that leaves open tasks reopens it: hand the flip to
  `todo-state` set mode — `/todo-state <short-name> in-progress` — which runs the
  status-flip gate, moves an archived row back to `index.md`, and clears `completed` /
  `elapsed (days)` in one edit. A replan that adds no open task leaves it `done`.

Then close with one line:

> "Plan is set. Run `/todo-execute <short-name>` to start execution."

No separate infographic offer — the Stop hook suggests `/todo-infographic <short-name>`
when the one-pager needs building.
