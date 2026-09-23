---
name: todo-verify
description: Use when the user invokes /todo-verify, says "verify this project", "did the e2e pass", "run the verification layer", or names a project and wants its verification result reconciled into the todo. Detection only — reads results, ticks tasks, flips status, opens Revisions on failures and records coverage gaps as advisory; never edits code.
---

# Project Verify Skill

You are the **check** gate in the hub's `plan → do → check → revise` loop. `todo-execute`
*builds*; you *verify* — reading the project's result from its **verification MCP** (the
user's verification layer) and reconciling it into todo state. You **detect and record**;
you never edit code, never run repair. Run failures become `[open]` `## Revisions` entries
that `todo-revise` then consumes and fixes; coverage gaps become `[advisory]` entries that
inform but never block.

Division of labor: **the verification MCP attests; you transcribe its verdict into
`tasks.md` plus the owning registry row.** The run is the only signal that ticks tasks or
flips status; coverage never does either.

This involves real judgment — driving the run, handling collisions, and interpreting the
result. Use the **balanced** tier at **high** effort from
[`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md). The `tasks.md` and registry
edits are a few lines — make them inline; a dispatch costs more than it saves.

## The verification MCP (pluggable)

This skill is **not tied to any specific test harness**. It assumes a verification MCP
server that exposes, in some form, this small contract:

- **start a run** against a named feature/target (returns a run id)
- **wait for / poll** until the run reaches a terminal verdict (`passed` / `failed`), and
  ideally streams progress rather than requiring a busy-poll
- **read the result** — which tests/specs passed, which failed
- **(optional) read coverage** — a gap list + a grounded coverage %

The tool names used below (`start_run`, `wait_for_result`, `get_result`, `get_coverage`)
are placeholders for that contract — map them to your server's actual tools. If a project
has no verification MCP, it simply omits the `## Verification` block in `plan.md` and this
skill is a no-op for it; the `plan → do → revise` loop still runs without the check gate.

**Pointing it at a concrete server:** register the server with the host as an MCP server,
list its tools, and pick the one that fills each contract verb above. Record the choice in
the project's `## Verification` block (Step 2): `Feature` is the server's name for the
target, `Run` names the start tool and its arguments (and how to rerun by id), and
`Coverage source` names the coverage tool. That block is the whole binding.

## Hub location

Resolve every hub path against `$TODO_HUB` — see
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Hub location.

## How the user invokes this

```
/todo-verify api-token-mgmt          ← drive the run + coverage, reconcile state
/todo-verify api-token-mgmt 7cvh     ← rerun an existing run by its id instead of a fresh run
/todo-verify                         ← ask which project, or act on context
```

Plain language counts too: "verify the token feature", "did the lifecycle spec pass",
"run the verification layer on this".

## Step 1 — Resolve the project

Resolve the project per
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Resolving a project,
recording the owning registry, section, full path, and status.

## Step 2 — Read the `## Verification` block

Extract the `## Verification` section from `plan.md` — **don't ingest the whole plan**
(hub plans can run large; the binding block is all this skill needs, plus the `## Goal`
line for the report):

```bash
awk '/^## Verification/{f=1} f&&/^## /&&!/^## Verification/{exit} f' plan.md
grep -m1 -A1 '^## Goal' plan.md
```

This is the binding to the verification MCP:

```markdown
## Verification
- **Feature:** api-token-mgmt
- **Run:** start_run (session reuse); rerun by run id
- **Gate covers:** Phase 5 tasks (e2e / integration / deploy-smoke)
- **Coverage source:** get_coverage(api-token-mgmt)                 # optional
- **Task↔test map:**                                                # optional
  - "Deploy + smoke-test full lifecycle" ⟶ spec: token-lifecycle.spec.ts
```

- **No `## Verification` block, or `Feature` unfilled** → stop and report:
  "<project> has no verification binding — add a `## Verification` block to plan.md
  (feature name + gate-covered tasks) before running /todo-verify." Do not guess a feature.
- Note the **`Gate covers`** set — the *only* tasks you may ever auto-tick. Anything outside
  it is never ticked by this skill.
- Note whether **`Coverage source`** is set (enables the coverage-gap → advisory path).
- Read the **`Task↔test map`** if present — it sharpens which task ticks on which passing
  spec and which task a failure backlinks to. Absent → map coarsely (see Step 5).

## Step 3 — Drive the gate run (record-only)

Drive the verification MCP in **record-only** mode — you observe, you do not repair. If the
server has an auto-repair / "heal" mode, turn it off:

1. Start the run for the feature, reusing a stable session/conversation handle if the
   server supports it. For a rerun (a run id was passed, e.g. `7cvh`), start from that id.
2. If starting the run reports a **collision** (another run is using the same repo/app) →
   **ask the user** whether to run isolated (a per-run worktree, if the server offers it)
   or to queue behind the other run, then retry. Do not guess.
3. Wait for the terminal verdict using the server's wait/stream tool; if it returns a
   "still running" signal, call it again — loop until terminal (`passed` / `failed`).
   Prefer the wait/stream tool over busy-polling a status endpoint.
4. Pull the verdict from the result tool: which tests passed (ids / names) and which failed.

**Degradation rule:** if the app can't boot — no creds, blocked deploy, health-check
timeout — don't hard-fail. Set the run result to `blocked`, capture the
blocker reason verbatim, and continue to Step 4 (coverage-only). Report the blocker
prominently in Step 7.

## Step 4 — Read coverage (if `Coverage source` is set)

Call the coverage tool for the feature. Collect the gap list (e.g. `untested`,
`unverified`, `shallow-verified`, `path-incomplete`) plus the grounded coverage %. These
never tick a task or flip status — they only become `[advisory]` entries in Step 5.

If `Coverage source` is not set, skip this step.

## Step 5 — Reconcile tasks and Revisions

Edit `tasks.md` inline; the interpretation is yours. Resolve task IDs with the graph
helper rather than by counting:

```bash
python3 <todo-graph-skill-dir>/scripts/graph-report.py tasks "$TODO_HUB" <short-name>
```

It prints `TASK\t<id>\t<open|done>\t<line>\t<text>` per real task, using the positional IDs
from [`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Task IDs and phases (`5.7`,
`R3`). Anchor each tick on its printed line and backlink with its ID. Validate
`<short-name>` first (§ Placeholder safety).

| Verification result | tasks.md | Revisions |
|---|---|---|
| Run green, all gate-covered tasks pass | tick covered `[ ]`→`[x]` | close every `[fixed — awaiting verify]` entry: tick its `- [ ]`, tag `[done]`, archive it |
| Run fails | no tick | one `[open]` entry per failing area, backlinked `⟵ Task <id>`; a `[fixed — awaiting verify]` entry for a failing area goes back to `[open]` with the new Actual |
| Coverage gap (even if run green) | no change | one `[advisory]` entry per gap (gap type named), no checkbox |
| Run blocked (boot/creds) | no tick | none — report the blocker; coverage path still runs |
| No verification block | — | (handled in Step 2 — stop) |

**Mapping tasks ↔ tests:**
- With a `Task↔test map`: tick the mapped task only when its mapped spec/test passes;
  backlink a failure to the mapped task. On a partial pass, close only the
  `[fixed — awaiting verify]` entries whose mapped spec now passes.
- Without a map (coarse fallback): an **all-green** run ticks the entire `Gate covers` set
  at once; a **partial** pass ticks and closes nothing (you can't tell which task each test
  proves) — open a Revision noting which tests failed and that a `Task↔test map` would
  sharpen this.

**Revisions format** — reuse the exact `## Revisions` schema `todo-revise` consumes, so the
two skills interlock. Append to (or create) the `## Revisions` block at the bottom of
`tasks.md`, numbering `R<n>` continuing from any existing entries (never reuse a number).
A run failure is a full, fixable entry; a coverage gap is advisory — no checkbox, so it
never counts as open work:

```markdown
### R7 ⟵ Task 5.7 — beta deploy + lifecycle smoke        [open]
- Gap: token-lifecycle.spec.ts failed at the exchange step
- Expected: full lifecycle green (author → exchange → resolve-scoped → rotate → revoke)
- Actual: exchange returned 401 — run 7cvh, exchange step
- Fix: (leave for /todo-revise unless the cause is obvious)
- Source: verification run 7cvh / feature api-token-mgmt
- [ ] implement + re-verify

### R8 ⟵ Task 5.3 — rotate endpoint        [advisory]
- Gap: untested — no spec exercises rotate with an expired token
- Source: coverage get_coverage(api-token-mgmt), run 7cvh, 82% grounded
```

**Invariants:**
- Never tick a task outside `Gate covers` — the one exception is the checkbox of a
  revision this run closes. Never edit code. Never run repair.
- The **run** is the only signal that ticks tasks or flips status. **Coverage** writes
  `[advisory]` entries only: no `[open]` tag and no checkbox, so task counts and the graph
  ignore them and they can never hold back `done`. `/todo-revise <short-name> R<n>`
  promotes one to `[open]` when the user decides to close that gap.
- **Idempotent:** before appending a Revision, scan existing entries — if one already
  covers the same failing area/test or coverage gap, update it rather than adding a
  duplicate. An `[advisory]` gap that a later coverage read no longer reports is tagged
  `[done]`. Scan by extraction, not a full read:
  `grep -niA1 '^### R[0-9]\+[A-Za-z]*' tasks.md` gives every entry's heading + Gap line;
  read a specific entry's body by line range only if you need it.
- **Closing a revision archives it** — apply `todo-archive` Step 2 to that entry at once
  ([`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Archiving completed
  revisions).
- Leave `plan.md` and `research/` untouched — this skill edits `tasks.md`, the owning
  registry row, and `artifacts/journal.md` only when it archives a closed revision.

## Step 6 — Set the project status

Decide status once, here, from `tasks.md` as Step 5 left it. `done` requires all four:

1. **Green run** — not failed, not blocked.
2. **No open work** — every real task is `[x]` (count per
   [`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Counting tasks;
   Revisions checkboxes count) and no case-insensitive `[open]` Revision remains.
   `[advisory]` entries have neither, so coverage never blocks.
3. **Shipped** — the shipping check below passes.
4. **Graph gate** — § The status-flip gate passes, run now rather than reused from earlier.

All four hold → set `done` without asking; this run is the gate the other skills defer to.
Stamp `completed` = today and `elapsed (days)` per `todo-state` § Date stamping, never
overwriting a real `started`. An archived project that stays `done` keeps its `archive.md`
row, updated in place. Any check fails → the project is not `done`; report which check held
it. A refused gate holds the *status*, never the ticks Step 5 wrote.

**Reopening:** a project recorded as `done` that now has open work (check 2 — a failed run
lands there through its `[open]` entries) is not done. Hand the flip to `todo-state` set
mode — `/todo-state <short-name> in-progress` — which runs the status-flip gate, moves an
archived row back to `index.md`, and clears `completed` / `elapsed (days)` in one edit. If
that gate refuses, leave the row and report both the open work and the blocker. A blocked
run or an `[advisory]` entry never reopens a project.

**Shipping check** — proof that the project's code reached `<base>`, as defined in
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Shipped work. A hub-only
project (repo `-`, or execution skipped the worktree) passes. Otherwise run `todo-state`'s
evidence helper once:

```bash
bash <todo-state-skill-dir>/scripts/repo-evidence.sh "<repo>" "<short-name>" \
  --fetch --hub "$TODO_HUB"
```

It validates both values, fetches once, and closes with one `SUMMARY` row. Shipped means
`unshipped=0`, `uncommitted=0`, and `pr` is not `open`; merge, rebase, and squash merges
all count, and an absent branch and worktree pass. Exit 2 (refused input), exit 3 (repo
not on disk), or any `unknown` field (failed fetch, `gh` unauthenticated) makes shipping
**unknown**, which holds `done` exactly like unshipped work — report it, never guess.

## Step 7 — Report

Status-first, terse:
- ✅ / ❌ / ⚠️ run verdict (or ⚠️ blocked + the blocker reason).
- Grounded coverage % and gap counts, if coverage ran — advisory, never a status input.
- Exactly what was written: which tasks ticked, which `R<n>` opened, closed, or recorded as
  advisory, status before → after (plus any `started`/`completed`/`elapsed (days)` stamped
  or cleared).
- What held `done`, if anything: open work, a refused gate, or unshipped/unknown shipping —
  for unshipped work, `/todo-push` from `<repo>-wt/<short-name>`, then `/todo-verify` again
  so the run attests the merged code rather than the branch.
- `[open]` Revisions: `/todo-revise <short-name> R<n>` to fix now (the entry is fully
  specified, so revise goes straight to the fix), or `/todo-refer <short-name> resume` for
  a later session — see [`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md)
  § Session handoff.

## Notes
- This is the producer half of the Revisions loop; `todo-revise` is the consumer. Keep the
  schema identical so they interlock — same `### R<n> ⟵ Task <id> — … [open]` + `- [ ]`
  shape. Tags: `[open]` → `[fixed — awaiting verify]` (revise, once the user accepts a fix)
  → `[done]` (this skill, on a green run); `[advisory]` is coverage-only.
- Reconciled state feeds the infographic: the Stop hook (`infographic-staleness.sh`)
  applies count and status refreshes to `artifacts/infographic.html` itself and only
  suggests `/todo-infographic <short-name>` when the page needs a structural rebuild. It
  skips `done` projects.
- If a run keeps blocking on the same missing prerequisite (e.g. a deploy that never
  happened), say so plainly — that's a project blocker for `/todo-revise` or the user, not
  something verify can clear.
