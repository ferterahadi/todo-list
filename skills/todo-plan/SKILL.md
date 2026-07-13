---
name: todo-plan
description: Use when the user invokes /todo-plan, says "plan this project", or names a project and wants a plan created. Runs discovery, verifies the target repo exists locally, then writes plan.md and tasks.md.
---

# Project Planning Skill

You plan projects stored in a hub repo. Each project has plan.md and tasks.md. Your job: fill them in through structured discovery.

This is judgment work (discovery questions, scoping, decisions) — run it inline on the main model; do not downgrade to Haiku.

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Resolve **every** path against this absolute root — `index.md`, each project's `path`, `plan.md`, `tasks.md` — regardless of the current working directory. This skill may be invoked from another repo; never assume cwd is the hub. (The `repo` column still points at the *target* codebase elsewhere — that's separate from the hub.) (Same convention as `todo-refer`.)

## How the user invokes this

```
/todo-plan queue-migration
/todo-plan projects/work/queue-migration   ← full path also works
```

## Step 1 — Resolve the project path

Read `$TODO_HUB/index.md`.

- Short name (e.g. `queue-migration`) → look up in index.md to get the full `path` and `repo`
- Not found in index.md → tell the user and stop
- Full path passed directly → use as-is, still read index.md for the `repo` column

## Step 2 — Ask questions first

Before reading or writing anything, gather answers to all six discovery questions.
**Use the `AskUserQuestion` tool for the enumerable ones** — clickable options beat
walls of prompt text for a visual reader — and plain text for the open-ended ones,
all in the same turn:

Via `AskUserQuestion` (options + the built-in "Other" for free text):
- **Repo path** — offer the `repo` value from index.md as the first option
  ("Confirmed: `~/code/…`") plus "Different path" (if index.md shows `-`, skip the
  widget and just ask).
- **Verification layer** — "Does this project have a verification MCP layer?" with
  options like "Yes — I'll name the feature/target" / "No — drop the Verification block".
- **Constraint categories** (multiSelect) — "Which constraints apply?" with options
  "Hard deadline" / "Tech stack locked" / "Team dependency" / "None of these"; follow
  up in text for specifics on whatever they pick.

As plain questions in the accompanying message:
1. What is this project? What problem does it solve?
2. What does done look like? What's the expected outcome? (push for observable, checkable signals — these become Success Criteria)
3. Any prior context to read? (docs, tickets, other repos or paths)

Wait for answers. Do not proceed until you have them.

## Step 3 — Verify the repo

Once the user confirms the repo path:

- Check the path exists on disk
- If it's a git repo, note the current branch
- If the path doesn't exist, tell the user and ask for the correct path before continuing

## Step 4 — Research (only if user points to something)

If the user references a local repo, doc, or path:
- Read the referenced files relevant to this project
- Extract what's useful for the plan
- Write a brief summary to `research/findings.md` inside the project folder

Regardless of references, check the confirmed repo for existing superpowers docs —
`<repo>/docs/superpowers/plans/` and `<repo>/docs/superpowers/specs/` (written by the
brainstorming / writing-plans skills in earlier target-repo sessions). Read any that touch
this project, list them as rows in `research/superpowers-docs.md` (a table: doc path +
source + one-line summary), and fold their decisions into the plan instead of re-deciding.

If no external reference is given and the repo has no superpowers docs, skip this step.

## Step 5 — Write plan.md

Fill in the project's `plan.md`:

- **Goal**: one sentence — what success looks like
- **Context**: background a future Claude session needs to execute without asking questions
- **Success Criteria**: observable, checkable outcomes (the expectation) — written as a `- [ ]` list, distinct from tasks. These are what `todo-revise` compares completed work against, so make them concrete and testable, not aspirational
- **Constraints**: deadlines, tech limits, non-negotiables
- **Scope**: what's in / what's out
- **Key Decisions**: choices already made so Claude doesn't re-litigate them. If the architecture/approach is still genuinely open (the user couldn't answer "how"), don't pad this section with guesses — check for an installed brainstorming/architecture skill (e.g. from superpowers) and offer to run it to converge on the decision first; otherwise record the open question explicitly as a decision-to-make task. If such a skill writes its output into the target repo (`docs/superpowers/…`), immediately record a pointer in `research/superpowers-docs.md` and under plan.md References — a doc that lives only in the target repo is lost to the hub
- **Verification**: the "check" gate binding for `/todo-verify`. If the project has a verification MCP layer, ask for the feature/target name and fill the `## Verification` block — `Feature`, `Gate covers` (which tasks/phases a green run may tick), and optionally `Coverage source` + a `Task↔test map`. If there's no verification layer, delete the section.
- **Repo**: absolute path to the local codebase (confirmed in Step 3)
- **References**: paths or links to relevant resources

Write with enough detail that a cold Claude session can pick this up without talking to the user.

## Step 6 — Write tasks.md

Break the work into a concrete checklist:

- Each task must be specific and actionable — "implement X" not "think about X"
- A future Claude session should be able to execute each task without asking questions
- Order by dependency (prerequisites first)
- Group under headers if the project has distinct phases
- **One line per task (~150 chars max).** Supporting detail, mechanics, and rationale go
  to `research/findings.md` with a pointer (`— see research/findings.md § Token exchange`),
  never inline in the task line. `tasks.md` is read whole by six skills; it must stay a
  checklist, not a journal.

## Step 6.5 — Quality gate (mandatory, before anything is shown)

This gate exists so the plan's quality does not depend on the model running this skill.
Walk every check literally; a failed check means **fix the file, then re-run the gate** —
never present a plan that fails one:

- [ ] **Goal test**: one sentence, and it names an observable outcome (a number, a state
  someone can check, or a named artifact). If it contains "improve", "support",
  "enhance", or "better" without a measurable object → rewrite until a stranger could
  say yes/no to "did this happen?".
- [ ] **Success Criteria test**: for each criterion, write down (mentally) the exact
  command, test, or observation that would check it. Can't name one → the criterion is
  aspirational; rewrite it or move it to Context.
- [ ] **Task test**: every task line starts with a verb, names its target (file, system,
  endpoint), and fits on one line. "Think about X" / "handle Y properly" fail.
- [ ] **Dependency walk**: read tasks.md top to bottom once; if any task needs an output
  produced by a LATER task, reorder now.
- [ ] **Cold-session test**: for each task ask "would a fresh session need to ask the
  user anything to do this?" If yes, the answer belongs in plan.md Context — add it.
- [ ] **Repo check**: the Repo path in plan.md was verified on disk THIS session (you
  saw the `ls`/git output in Step 3, not remembered it).

## Step 7 — Update index.md

- Set `status` to `ready`
- Set `repo` to the confirmed absolute local path

## Step 8 — Confirm with a plan-at-a-glance render

**Do not dump the raw plan.md/tasks.md** — the user is a visual reader; render the plan
as a compact widget block and offer the full files only on request:

```
## 📋 rmq-dlq-support — plan at a glance

🎯 **Goal** — Dead-lettered messages are retried 3× then parked with alerting.

| ✅ In scope | 🚫 Out of scope |
|---|---|
| DLQ topology + retry policy | Consumer-side dedup |
| Parking-lot queue + alert | Multi-cluster federation |

**Phases**   Phase 1 · setup (3) ─▶ Phase 2 · retry policy (5) ─▶ Phase 3 · alerting (4)   — 12 tasks

**Decisions** ① quorum queues, not classic ② retry via per-queue TTL, not delayed-exchange plugin

**Constraints** ⛔ no broker restart in prod · ⚠️ ship before the 4.1 upgrade

**Verification** 🔬 `rmq-dlq` gates Phase 3   (or: — none)
```

Rules for the render:
- Goal = one line, key noun bolded. Scope = two-column table, top items only.
- Phases = a `─▶` pipeline with per-phase task counts — this is the tasks.md summary;
  don't paste the checklist.
- Decisions numbered ①②③, one clause each. Constraints as chips: ⛔ hard, ⚠️ soft.

Then ask via `AskUserQuestion`: "Does this plan look right?" with options
"Looks right — lock it in" / "Adjust something" / "Show me the full plan.md".
Apply changes. Once confirmed:

> "Plan is set. Run `/todo-execute <short-name>` to start execution."

**Offer the visual next.** The plan is fresh — offer to run `/todo-infographic
<short-name>` now so the one-pager exists from day one instead of waiting for the
staleness hook.
