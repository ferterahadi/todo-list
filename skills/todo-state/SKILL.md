---
name: todo-state
description: >-
  Use when the user wants to change or audit a hub project's recorded state — invokes
  /todo-state, says "mark X as done", "tick off task Y", "uncheck that", "add a task to
  X", "reword task 2.3", "set this to in-progress", "reopen this archived project", "mark
  this project done", or wants to record progress without a full execution pass — and
  equally when they say "is the index accurate", "does the todo match reality", "audit my
  project statuses", "this says done but it never shipped", or suspect hub state has
  drifted from what actually happened in the repos. Edits tasks.md and the owning active
  or archived registry row in sync; `audit` only reports drift against tasks and git
  evidence, and `audit fix` applies it after one confirmation. Not for looking: the
  all-projects overview is todo-list, and one project's context or where-was-I is
  todo-refer. Replaces the former /todo-update-state (now the default mode) and
  /todo-sync (now `audit`) — treat either of those spellings as an invocation of this
  skill.
---

# Project State Skill

You own the hub's **recorded state** — task checkboxes and registry rows — in both
directions:

| Mode | Trigger | Writes |
|---|---|---|
| **set** (default) | the user tells you what changed | exactly the requested edit |
| **audit** | the user asks whether the record is honest | nothing, ever |
| **audit fix** | the user wants the drift corrected | the board's listed edits, after one confirmation |

Set mode is the lightweight write companion to `todo-execute`: use it when the user just
wants to *record* progress without the agent doing the work. Audit mode checks the record
against reality — a project marked `done` whose branch never merged, an `in-progress`
project whose PR landed weeks ago, ticked tasks with no commits anywhere. Each is drift,
and drift compounds: triage routes wrong, refer misleads, sort lies.

Both modes touch the same two surfaces:

- **`tasks.md`** in each project — task checkboxes: `- [ ]` (not done) and `- [x]` (done),
  plus single task lines added or reworded through set mode's `add` and `edit`
- **`index.md` / `archive.md`** in the hub root — active and completed project rows,
  including `status`, `started`, and `completed` columns (see
  [Date stamping](#date-stamping))

Tasks and their IDs follow
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Counting tasks and
§ Task IDs. Every list and count here comes from `graph-report.py` — never from reading
`tasks.md` into context or counting by hand.

## Execution tier

Hybrid, matching the hub's house pattern. The **edits are mechanical** — use the **fast**
tier from [`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md) when dispatching
is available, otherwise perform them inline. Audit mode's **evidence-gathering across 3+
projects** is mechanical too and delegates the same way; for 1–2 projects gather inline.
The drift *verdicts* are judgment — always yours, inline on the main model.

## Hub location

Resolve every hub path against `$TODO_HUB` — see
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Hub location. Pass that
absolute root to any edit subagent so it writes there, not into the cwd. Validate every
`<placeholder>` before it reaches a shell (§ Placeholder safety).

## How the user invokes this

```
/todo-state queue-migration                       ← show its status, then ask what to change
/todo-state queue-migration 2.1 2.3 done          ← tick tasks by ID
/todo-state queue-migration 2.3 undone            ← untick a task
/todo-state queue-migration add "Alert on DLQ depth" under 4   ← append one task to Phase 4
/todo-state queue-migration 2.3 edit "Retry with jittered backoff"   ← reword one task
/todo-state queue-migration in-progress           ← status only; reopens an archived row
/todo-state queue-migration done                  ← mark the whole project done
/todo-state                                       ← ask which project, or act on context
/todo-state audit [queue-migration]               ← report drift; writes nothing
/todo-state audit fix [queue-migration]           ← report, confirm once, apply
```

The user will usually say what they want in plain language. Set mode: "mark the migration
done", "tick off the first two tasks", "uncheck task 3", "add a task for the DLQ alert",
"set queue-migration back to ready". Audit mode: "does my registry match reality", "audit
the hub", "is the index accurate". Interpret that against the resolved project.

---

# Set mode

## Step S1 — Resolve the project

Resolve the project per
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Resolving a project,
recording the owning file and section with the full path and status. This skill writes to
that row, so getting the owner wrong writes state into the wrong registry.

## Step S2 — Show only what the edit touches

List the project's tasks with their canonical IDs:

```bash
python3 <todo-graph-skill-dir>/scripts/graph-report.py tasks "$TODO_HUB" "<short-name>" [--open]
```

Each row is `TASK\t<id>\t<open|done>\t<line>\t<text>`, then one
`SUMMARY\ttasks\tproject=…\tdone=<d>\ttotal=<t>\topen_revisions=<n>`. Pass `--open`
when the request only ticks open tasks.

Report the current `status`, whether the row is active or archived, `done/total`, and
**only the matched tasks** as `<id> · <open|done> · <text>` — never the whole checklist.
A request by ID matches that row. A request by description ("the migration task") matches
on `text`; when more than one row fits, print just those candidates and ask. A missing ID
or no match is reported, not guessed.

`ERROR\tMISSING_TASKS` or `total=0` means there is nothing to check off yet;
`/todo-plan <short-name>` creates tasks.

## Step S3 — Apply the requested change

Make exactly the edits the user asked for. Resolve every ID against the fresh Step S2
listing and confirm the file still holds that `text` at `<line>` before writing; a
mismatch means the file moved — re-list and re-match. The operations:

**Tick or untick tasks** (`<id…> done`, `<id…> undone`) — change only the box character:
`- [ ]` → `- [x]`, or `- [x]` / `- [X]` → `- [ ]`. The task text is never touched here.

**Add a task** (`add "<text>" [under <phase>]`):

- The text is one line of at most 150 characters, with no line break and no leading
  `- [`. Longer detail belongs in `research/` or `artifacts/` with a pointer — suggest
  that instead of writing an over-long line.
- `under <phase>` names a phase heading per § Task IDs (`4`, `6a`). Append the new
  `- [ ] <text>` after that phase's last real task — directly under the heading when it
  has none — matching its neighbours' indentation. An unknown phase is reported, never
  created.
- Without `under`: a file with no phase headings gets the task after its last real task
  outside `## Revisions`; a file with phases lists them and asks which one.
- Never add into `## Revisions` (entries belong to `/todo-revise`), `## Status`,
  `## Notes`, `## Context`, an HTML comment, or a fence.
- Write with the file-edit tool, never through a shell command — the text is free prose.
- Re-list and report the new task's ID. Appending at the end of a phase keeps every
  existing ID; if tasks outside phases follow the insertion point, name the IDs that shifted.

**Reword a task** (`<id> edit "<text>"`) — same text rules as `add`. Replace only the
text after the checkbox; keep indentation and box state. An `R<n>` ID is refused — a
revision entry's wording belongs to `/todo-revise <short-name> R<n>`. Report
`before → after`.

**Mark the whole project done** (`done`):

1. List with `--open`. If `open_revisions` is above zero or any open row has an `R` ID,
   refuse and write nothing. Read each such revision's heading tag
   (`grep -inE '^#{2,3} (R3|R4)([^A-Za-z0-9]|$)' tasks.md` with the listed IDs) and route
   it per [`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Revision tags:
   `[open…]` → `/todo-revise <short-name> R<n>`; `[fixed — awaiting verify]` →
   `/todo-verify <short-name>`, which ticks it. `[advisory]` entries carry no checkbox and
   never block `done`.
2. When `plan.md` has a `## Verification` block, `/todo-verify <short-name>` is the path
   to `done` — it runs the checks and sets `done` itself when they pass. Say so, and flip
   here only if the user confirms they are skipping it.
3. Run the status-flip gate (below). A refusal writes nothing.
4. Tick every listed open task, then set `status: done` in the owning row with its date
   stamps, in one pass.

**"Not done" / "reopen"** — the user will usually mean the status, not unchecking every
task; confirm whether they want tasks unchecked too before doing it, since that's
destructive to recorded progress.

**Change status only** (`<status>`) — update the owning row's `status` column to one of
`planning` / `ready` / `in-progress` / `done`; an archived row follows the reopen rule
below.

Before a flip to `in-progress` or `done`, run the gate from
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § The status-flip gate. A
direct state edit must not bypass the dependency check `/todo-execute` enforces — that
loophole is the whole reason the gate is repeated here.

**Reopen an archived project** — any status change on an `archive.md` row, including
`/todo-state <short-name> in-progress` handed off by `todo-archive` for an archived row
with open work or a non-`done` status, is also a registry move:

1. Gate first when the target is `in-progress`. A refusal moves nothing.
2. In one atomic two-file edit: remove the row verbatim from its section in `archive.md`,
   append it to the same section in `index.md`, set the new `status`, clear `completed`
   and `elapsed (days)` to `-`, and keep `started`. If the editing surface cannot do that
   in one edit, append and verify the destination first, then remove the source — a
   temporary duplicate is recoverable, a row missing from both registries is not.
3. Confirm the short-name now appears exactly once across both registries.

Preserve custom section names; if a legacy row's source section is unknown, ask before
moving it.

Do not touch anything the user didn't ask about. Leave `plan.md`, `research/`, and
`artifacts/` alone — this skill edits state, not content.

## Step S4 — Keep status and tasks in sync

After editing, re-run the Step S2 listing (`--open` is enough). The project's status in
its owning registry row and its task completion should tell the same story. When they'd
otherwise disagree, reconcile — and say what you did:

- All tasks now checked and no open revisions, but status isn't `done` → offer to set it
  `done` (or just set it and report, if the user already said "mark done").
- A task got unchecked or added on a project marked `done` → it's no longer truly done;
  flag it and offer `/todo-state <short-name> in-progress` (for an archived row, that
  reopens it).
- First task checked on a `planning`/`ready` project → work has started; suggest
  `in-progress`, stamping dates from the state before this edit.

Don't silently override the user's explicit instruction — if they said "set status to
ready" while tasks are all checked, do what they asked and just note the mismatch.

**Archive housekeeping:** if the `tasks.md` you touched exceeds 20,480 bytes, mention it
and offer `/todo-archive <short-name>`. When this skill itself flips a revision tag to a
case-insensitive `[done…]`, apply `todo-archive` Step 2 to that entry immediately — an
`<a id="revision-r<n>"></a>` anchor before the journal entry and
`[journal:R<n>](artifacts/journal.md#revision-r<n>)` in the two-line tombstone. Never
archive ordinary task checkboxes.

## Step S5 — Confirm what changed

Report the edits plainly: which task IDs flipped, were added, or were reworded, the new
`done/total` from the re-run listing, and the status before → after. If a status flip
stamped or cleared a `started`/`completed` date, say so in the same line. Keep it short.
If you reconciled a mismatch in Step S4, say so explicitly so the user knows state was
kept consistent.

---

# Audit mode

`/todo-state audit` detects and reports; it never writes. `/todo-state audit fix` runs the
same detection, shows the board with the exact edits it would make, asks **once**, and
applies them on a yes — or only the rows the user names. A "yes, fix them" reply after a
plain audit is `audit fix`: show the edits and ask that one question before writing.

## Step A1 — Resolve scope

Read every project's status and task counts in one call:

```bash
python3 <todo-graph-skill-dir>/scripts/graph-report.py export "$TODO_HUB"
```

Default scope is every `NODE` row with registry `active` and status `ready`,
`in-progress`, or `done`; `planning` has nothing to drift against. An explicit short-name
resolves per [`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Resolving a
project and may be archived. Take each in-scope row's `repo` cell from its registry row.
Read the rows, not the exit status.

## Step A2 — Gather evidence

Four sources, cross-checked:

1. **Recorded status** — the `NODE` row's `status`.
2. **Task state** — the same `NODE` row's `tasks=<done>/<total>` and `open_revisions`.
   Never re-count per project; a second count is how two numbers for one project appear.
3. **Repo evidence** — group the in-scope projects by `repo` cell (expand a leading `~`;
   two spellings of one path are one repo) and run the helper **once per distinct repo**,
   passing every short-name on it:
   ```bash
   bash <todo-state-skill-dir>/scripts/repo-evidence.sh "<repo>" <short-name>... \
     --fetch --hub "$TODO_HUB"
   ```
   It validates its inputs, derives owner/name from `origin`, the base from `origin/HEAD`,
   fetches once, and prints `BRANCH`, `WORKTREE`, and `PR` evidence rows plus one
   `SUMMARY` per project. A `repo` cell that is `-` has no repo (hub-only). A cell that
   fails § Placeholder safety — `multi-repo (see plan.md)` carries parentheses — is not
   passed on: skip it and report the row **as an audit finding**, since a cell carrying a
   metacharacter is exactly the kind of drift this audit exists to surface. Exit 2 is the
   helper refusing an input — report it the same way. Exit 3 is a repo that is not on
   disk; its `SUMMARY` rows are all `unknown`.

   Hub-only projects are checked on sources 1–2 plus artifacts: `done` with an empty
   `artifacts/` is suspicious; say so.

   **Return contract** — whether gathered inline or by the fast-tier subagent, evidence
   lands in this shape
   ([`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Subagent return
   contracts). The `repo` fields are the helper's `SUMMARY` values, copied as printed:

   ```json
   {
     "projects": [{
       "short_name": "<registry short-name>",
       "recorded_status": "planning | ready | in-progress | done",
       "done": 12,
       "total": 20,
       "open_revisions": 1,
       "repo": {
         "checked": true,
         "branch": "merged | open | empty | absent | unknown",
         "pr": "merged | open | none | unknown",
         "worktree": "present | absent | unknown",
         "unshipped": "3 | unknown",
         "uncommitted": "0 | unknown",
         "evidence": ["<BRANCH/WORKTREE/PR rows cited verbatim>"]
       }
     }]
   }
   ```

   **`unknown` is a value, never an omission.** A repo that isn't on disk, a failed fetch,
   no `gh`, a command skipped by placeholder validation — each yields `unknown` for that
   field, never `absent` or `none`. `absent` means checked and not there; `unknown` means
   not checked. Step A3 turns the first into drift and the second into *unverifiable*, and
   collapsing them is how a project nobody could check gets reported as a project that
   failed. For a hub-only project, `checked` is `false` and every other `repo` field is
   `unknown`.

4. **Project-graph evidence** — run one bounded audit for the hub, then associate its
   incident issues and hard blockers with each in-scope project:
   ```bash
   python3 <todo-graph-skill-dir>/scripts/graph-report.py audit "$TODO_HUB"
   ```
   An in-progress project with an unsettled prerequisite is **at risk**; a done project
   with one is graph drift. Context and lineage edges never count.

## Step A3 — Judge drift

Compare the sources. The canonical mismatches and their fixes:

| Recorded | Evidence | Drift | Suggested fix |
|---|---|---|---|
| `done` | `done < total` or `open_revisions` above zero | not actually done | status → `in-progress` |
| `done` | not shipped per [`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Shipped work — `unshipped` or `uncommitted` above zero, or `pr=open` | shipped on paper only | status → `in-progress`, point at `/todo-push` |
| `in-progress` | all tasks ticked, `branch=merged` or `pr=merged`, `uncommitted=0` | finished but never recorded | status → `done` (via `/todo-verify` if plan.md has a `## Verification` block — the gate flips `done`, not this skill) |
| `ready`/`in-progress` | `branch=absent`, `pr=none`, `worktree=absent`, `done=0` | stale — never started | status → `ready`, or ask if it's abandoned |
| any | ticked tasks but `branch=absent`, `pr=none`, and no artifacts | unbacked claims | flag the specific tasks; suggest `/todo-review <short-name>` for the audit-by-diff |
| any | `uncommitted` above zero | work at risk | surface it — `/todo-refer <short-name> resume` before anything else |
| `in-progress` | hard prerequisite is no longer settled | execution order at risk | stop execution; `/todo-graph why <short-name>` |
| `done` | hard prerequisite is unresolved or dishonest | completion graph is inconsistent | audit evidence; do not auto-reopen |

`branch=empty` — a branch with no commits of its own — is not drift by itself.

Any `unknown` in a project's `repo` block makes it **unverifiable**, not drifted — report
it in its own bucket, never guess a verdict from partial evidence. That is a field check,
not a judgment call: read the value, don't reason about what it probably was.

## Step A4 — Report the drift board

```
## 🔎 Hub audit — 14 projects checked

| project | recorded | evidence | verdict | fix |
|---|---|---|---|---|
| queue-migration | done | PR #42 still open | ❌ drifted | → in-progress, ship via /todo-push |
| api-token-rotation | in-progress | merged, 20/20 tasks | ❌ drifted | → done (verify gate first) |
| service-auth | ready | no repo locally | ⚠️ unverifiable | clone repo or fix repo column |
| 11 others | — | — | ✅ consistent | — |

2 drifted · 1 unverifiable · 11 consistent
```

Every drifted row cites its evidence (PR URL, branch, task IDs) — a verdict without the
evidence line is not reportable. A plain `audit` ends here, with
`/todo-state audit fix` as the act-now pointer when anything drifted.

## Step A5 — Apply fixes (`audit fix` only)

Under the board, list each edit `audit fix` would make — the project, the field, and
`before → after`, including any archive → active row move. Ask once. On a yes, apply
exactly those edits (or the subset the user named) through set mode's Step S3 and Step S4
rules, **including the status-flip gate and [Date stamping](#date-stamping) in full**
(delegate the mechanical edits to the fast tier when available). Re-run Step A1's export
and re-render the fixed rows.

Never fix silently, never fix beyond what was confirmed, and never flip a status to `done`
past an unrun `## Verification` gate — point at `/todo-verify` instead.

---

## Date stamping

**This section is the authority on `started` / `completed` / `elapsed (days)` for the
whole hub.** Other skills that flip a status — `todo-execute`, `todo-verify`,
`todo-revise`, `todo-archive` — apply these same rules.

`started` picks the earliest reliable signal, in priority order — **`in-progress` >
`ready` > `planning` > `completed`**. The tiers exist because the early signals only say
work is *intended* (project created, plan confirmed) while a real `ready`→`in-progress`
flip says work *began*: lower tiers stamp provisionally, higher tiers overwrite them, and
the real start is never overwritten. A `started` value is provisional only while no real
task is checked; after the first checked task it is final. Whenever an edit changes a
row's `status` cell, also update that row's `started` / `completed` cells, using today's
date (`YYYY-MM-DD`) and judging every condition on the state *before* the edit:

- **Flips to `planning`** (new project via `/todo-add`) — stamp `started` to today if it's
  currently `-`. This is the lowest-tier provisional stamp — see the overwrite rules below.
  A flip *back* to `planning` on an existing project (rare) leaves `started` unchanged —
  it's not a new project.
- **Flips to `ready`** from `planning` — stamp `started` to today, **overwriting** any
  tier-3 (`planning`) stamp already there. Still provisional — see next bullet. A flip to
  `ready` from any other status (a replan or demotion of started work) leaves `started`
  alone.
- **Flips to `in-progress`** — stamp `started` to today when `started` is `-`, or when the
  flip comes from `planning` or `ready` **and** no real task is checked yet (`done=0` in
  the `graph-report.py tasks` SUMMARY) — the value is still provisional, and a direct
  `planning`→`in-progress` jump is just as real a start. In every other case leave
  `started` alone: an `in-progress`→`ready`→`in-progress` round trip after work began, or
  a reopen from `done`, keeps the first real start.
- **Flips to `done`** — set `completed` to today. This one *does* overwrite — if the project
  was reopened and is completing again, the newer date is the honest one. Then, if `started`
  is *still* `-` at this point (none of tiers 1–3 ever fired — typically a row added
  directly as `done`, retroactively documenting work finished elsewhere), fall back to the
  last resort: set `started` to the same date as `completed`. Finally, compute
  `elapsed (days)` = `completed − started` in whole days (0 if same-day) and stamp it —
  computed at the moment `completed` is set (recomputed if the project re-completes),
  never live-recomputed afterwards.
- **Flips away from `done`** (reopened to any other status, including an archived row
  moving back to `index.md`) — clear `completed` back to `-`, and clear `elapsed (days)`
  back to `-` alongside it; it's no longer true that the project is finished, so neither a
  completion date nor a duration is honest anymore. `started` stays.

A status column edit and its date-column edit are the same logical change — make them in
one pass, not as a follow-up.

If a row's table predates these columns (header has no `started`), the plugin's
SessionStart hook (`hooks/migrate-index-dates.sh`) migrates and git-backfills it on the
next session. If you hit an unmigrated table mid-edit, widen it yourself first: insert
`started` / `completed` / `elapsed (days)` after `status` in the header and separator, and
`-` cells in every row, then apply the stamp.

## Notes

- `audit` is idempotent and safe to run weekly; only `audit fix` writes, after its one
  confirmation.
- This skill reconciles **state**; it never edits code or plans, and changes task text
  only through `add` and `edit` — one line each.
- `/todo-verify` proves behavior via a verification run; audit mode cross-checks
  bookkeeping against git. Verify is the gate, audit is the bookkeeping check.
- Registry status is not dependency readiness. "What can I start now?" belongs to
  `todo-graph`.
