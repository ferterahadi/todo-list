---
name: todo-refer
description: >-
  Use when the user invokes /todo-refer or wants one hub project's context — says "refer
  to project X", "pull in the context for X", "give me the plan for X to review against",
  or wants a project's plan/tasks loaded before another command — and equally for
  where-was-I on one project: "where was I", "pick up where we left off", "continue the
  migration project", "what happened last session", "what's the state of X", or a fresh
  session on a project with prior work. Also handles "what happened in R4"-style revision
  history questions. Replaces the former /todo-resume, which is now this skill's `resume`
  mode — treat that spelling as an invocation of this skill. Read-only, one project,
  active-or-archived, and cross-repo; the all-projects overview is todo-list, and
  changing or auditing recorded state is todo-state.
---

# Project Refer Skill

Load a hub project's context into the current session. Read-only and cross-repo: always
reach the hub by absolute path, and never edit `index.md`, `archive.md`, `tasks.md`,
`plan.md`, or repo code. Acting on what you load is the follow-on command's job.

Three modes, differing only in how far you dig and what the digest emphasizes:

| Mode | Question it answers | Extra work |
|---|---|---|
| **grounding** (default) | "what is this project about" | none — plan + current task state |
| **resume** | "what happened, what's in flight, what's next" | hub trail + repo/git state + a next-command recommendation |
| **revision** (`R<n>`) | "what happened in R4" | one anchored journal entry; skips everything else |

Run inline on at least the **balanced** tier from
[`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md). Resume mode is judgment
work — assembling the picture means deciding what matters — so keep it on the session
model rather than delegating it.

## Hub location and placeholder safety

Resolve every hub path against `$TODO_HUB`, and validate every `<placeholder>` before it
reaches a shell — [`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md)
§ Hub location and § Placeholder safety. This skill touches the widest set of values in
the hub (`<short-name>`, `<project-path>`, `<repo>`); on a failure, skip the command and
report the offending row rather than repairing it.

## Invocation

```text
/todo-refer service-auth              grounding digest
/todo-refer service-auth resume       where the work stopped + next command
/todo-refer service-auth R4           one revision's history
/todo-refer                           ask which project
/todo-refer resume                    resume the most recently touched in-progress project
```

Plain language selects the mode: "pull in the context for X" and "give me the plan for X"
mean grounding; "where did we leave the token rotation work", "continue where we stopped",
"what's the state of X" mean resume; "what happened in R4" means revision.

## Step 1 — Resolve the project

Resolve per [`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Resolving a
project, using **bounded exact-name checks** against both registry tables rather than
loading either file into model context. Three fallbacks are this skill's own:

- Exact lookup fails → fuzzy-match names from both files and ask for confirmation.
- No name, grounding mode → list active names from `index.md` only and ask which project.
- No name, resume mode → pick the active `in-progress` project whose `tasks.md` changed
  most recently (`ls -t`), say which one you picked, and offer the others. No
  `in-progress` projects at all → show the index the way `/todo-list` does and ask.

Record the owning registry, section, path, repo, status, and related names. Resolve the
project folder as `$TODO_HUB/<path>`.

For an archived row, always run Step 2's task listing—even on the revision-only fast
path. `done < total` or `open_revisions` above zero means the registry is stale. Keep
this read-only, flag the mismatch, and direct the user to
`/todo-state <short-name> in-progress`.

## Step 2 — Read current context economically

For a revision-only question such as "what happened in R4?", take the fast path: read
only the `## Goal` paragraph from `plan.md`, skip current task counts and related-project
expansion, then jump to Step 3. Every other mode uses the full path below.

Read `plan.md` because it is the grounding — in full for grounding mode; in resume mode
the `## Goal` paragraph and whether a `## Verification` block exists are usually enough,
with a full read only when the file is small. Extract current task state with the graph
helper rather than loading `tasks.md`:

```bash
python3 <todo-graph-skill-dir>/scripts/graph-report.py tasks "$TODO_HUB" "<short-name>" --open
grep -inE '^#{2,3} R[0-9]+[A-Za-z]*([^A-Za-z0-9].*)?\[(open|fixed[^]]*awaiting verify|advisory)[^]]*\][[:space:]]*$' \
  "$TODO_HUB/<project-path>/tasks.md"
```

Each `TASK\t<id>\topen\t<line>\t<text>` row is one open task with its canonical ID,
uncapped. The closing `SUMMARY\ttasks\tproject=…\tdone=<d>\ttotal=<t>\topen_revisions=<n>`
is the project's one Done number — the canonical rule in
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Counting tasks. Print
it and no other count. `ERROR\tMISSING_TASKS` means there is no `tasks.md` yet.

The `grep` lists live revision headings; route each by its tag per
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Revision tags — `[open…]`
is open work, `[fixed — awaiting verify]` waits on `/todo-verify`, `[advisory]` is
optional and never blocks.

Read all of `tasks.md` only when it is below about 15 kilobytes or the follow-on command
explicitly needs completed-task detail.

**Resume mode adds the rest of the hub trail** — extract, don't ingest whole files:

1. `artifacts/blockers.md` — every unresolved blocker, one line each.
2. `artifacts/journal.md` — the **last dated section only** (tail the file); it records
   the most recent closed work. If the user also named a revision, use Step 3's exact
   anchored lookup instead of the tail.
3. `artifacts/README.md` — the newest 2–3 rows (most recent outputs).

## Step 3 — Resolve requested revision history

When the user names a revision ID or explicitly asks about revision history, read only
that entry. Prefer the bundled read-only helper when `todo-archive` is installed:

```bash
bash <todo-archive-skill-dir>/scripts/archive-report.sh lookup \
  "$TODO_HUB" "<project-path>" "R4"
```

The helper returns a live or not-yet-tombstoned entry directly from `tasks.md`. For a
tombstone it resolves the stable `<a id="revision-r4"></a>` journal anchor and stops at
the next entry. It also supports legacy exact `## R4` / `### R4` headings, with a strict
boundary so `R1` never matches `R10`.

If the helper is unavailable:

1. Read the named revision block in `tasks.md`.
2. Follow its `artifacts/journal.md#revision-r<n>` link.
3. Read from that exact anchor until the next revision anchor or heading.
4. For a legacy unlinked pointer, search `journal.md` for exactly one case-insensitive
   `^#{2,3} R<n>(space-or-end)` heading and read only that block.

Zero or multiple journal matches are a broken tombstone. Report the ambiguity and do not
guess from nearby dated or aggregate sections.

## Step 4 — Load one bounded graph neighborhood

Skip this step on the revision-only fast path. Otherwise run:

```bash
python3 <todo-graph-skill-dir>/scripts/graph-report.py context \
  "$TODO_HUB" "<short-name>"
```

Use its exact one-hop `depends-on`, derived blocker, `related-to`, `supersedes`, and
legacy-context rows; its task count is Step 2's number, so don't print it twice. Read only each named neighbor's `## Goal` paragraph when the
follow-on request needs that context; never load neighboring tasks or journals.

Record unsatisfied hard prerequisites as graph blockers. Canonical `related-to`,
`supersedes`, and legacy registry hints are context only. In resume mode, an in-progress
project whose dependency regressed is **at risk**: say so, prioritize
`/todo-graph why <short-name>`, and do not recommend more execution until the graph is
honest.

Graph issues are not stale names to skip: surface them and point at `/todo-graph audit`.
If the helper is unavailable, fall back to the owning registry row's legacy `related`
names as non-blocking context only. Never infer a dependency from the fallback.

## Step 5 — Gather the repo trail (resume mode only)

If the owning registry row names a target repo (not `-`), run `todo-state`'s read-only
evidence helper once:

```bash
bash <todo-state-skill-dir>/scripts/repo-evidence.sh "<repo>" "<short-name>" --hub "$TODO_HUB"
```

It validates both values, derives the GitHub slug and base branch from `origin`, and
attributes only this project's branches and worktrees — `todo/<short-name>`, the
`<repo>-wt/<short-name>` worktree, and parallel-mode `feat/…` branches that name the
project — never every `feat/*`. `BRANCH`, `WORKTREE`, and `PR` rows carry the detail;
the closing `SUMMARY` gives `branch`, `pr`, `worktree`, `unshipped`, and `uncommitted`.

No `--fetch`: resume stays read-only on the repo too, so remote refs are as of the last
fetch; PR state from `gh` is live. Exit 2 is a refused input — report the row. Exit 3 or
an `unknown` field (repo not on disk, no `gh`) is a gap to note, not an error. The point
is to know whether work is **uncommitted, committed-but-unshipped, in an open PR, or
merged** — shipped as defined in
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Shipped work.

## Step 6 — Emit the digest

**Grounding mode** — a compact digest plus related projects:

```text
Loaded context: service-auth ($TODO_HUB/projects/work/service-auth)
Registry: active
Goal: <one line>
Status: in-progress
Open tasks: <first 3–5, then count>
Done: 12/20 tasks          (Step 2 SUMMARY)
Depends on: token-foundation — <goal> (done, archived)
Context: token-rotation — <goal> (in-progress)
```

**Revision mode** — the exact heading plus a compact Expected / Actual / Fix digest from
the extracted entry, together with the one-line goal and registry state. That is the
whole response; do not dump unrelated journal history.

**Resume mode** — one compact briefing, newest signal first:

```
## ⏪ queue-migration — where you left off

Goal: move order events from Redis pub/sub to RabbitMQ quorum queues
Status: in-progress · ▓▓▓▓▓▓░░░░ 12/20 tasks · 1 open revision

Last recorded work: R3 closed 2026-07-08 — consumer retry backoff (journal.md)
In flight:
- 🔄 worktree <repo>-wt/queue-migration exists · branch todo/queue-migration
- 🔄 3 commits unshipped (ahead of origin/main) · no open PR
- ⚠️ uncommitted changes in src/consumers/ (2 files)
Blockers:
- ❌ staging RabbitMQ creds missing (blockers.md, 2026-07-05)
Next open task: 4.2 dead-letter exchange for poison messages

▶ Next: /todo-push from <repo>-wt/queue-migration to ship the 3 commits   (then /todo-execute queue-migration)
```

The `▶ Next` line is resume mode's deliverable — the first matching row is the primary
recommendation, with at most one alternative:

| Evidence | Recommend |
|---|---|
| Unsatisfied project dependency | `/todo-graph why <short-name>` |
| Status `planning`, `total=0`, or no `tasks.md` | `/todo-plan <short-name>` |
| `unshipped` above zero or `pr=open` | `/todo-push` (from the worktree) |
| An `[open…]` revision | `/todo-revise <short-name> R<n>` |
| A `[fixed — awaiting verify]` revision | `/todo-verify <short-name>` |
| Only blocked tasks remain | name the blocker — no command unblocks a missing credential |
| Open tasks | `/todo-execute <short-name>` |
| All tasks done, `## Verification` block in plan.md | `/todo-verify <short-name>` |
| All tasks done, no `## Verification` block, shipped | `/todo-state <short-name> done` |

An `unknown` repo field leaves shipping unproven: name the gap instead of recommending
`done`. `[advisory]` entries are optional — mention them, never as the primary line.

Grounding and revision modes end with one next-command nudge instead; do not run that
command or edit hub files.

## Notes

- Read-only and idempotent in every mode — safe to run at the start of any session.
- Missing files are reported, not scaffolded.
- Artifact bodies remain cold by default. A named revision lookup is the deliberate
  exception; arbitrary artifact requests list filenames unless the user asks for content.
- Uncommitted changes in a worktree are the highest-priority resume signal: surface them
  first, they're the easiest thing to lose.
- If hub state and repo state disagree (tasks ticked but no commits anywhere, or merged
  PRs for unticked tasks), say so in the digest and point at `/todo-state audit` — don't
  reconcile here.
- To change state use `todo-state`; to execute use `todo-execute`.
