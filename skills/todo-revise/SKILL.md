---
name: todo-revise
description: Use when the user invokes /todo-revise, says "this drifted", "give feedback on what's done", "the result isn't what I expected", "revise this", "what's the gap on X", or names a project and wants completed work corrected against expectation. Captures gaps as Revisions entries, then fixes and verifies.
---

# Project Revision Skill

You run the **Review → Gap → Revise → Verify** loop. This is the rework companion to `todo-execute`: execute *builds* tasks, revise *corrects* already-built ones against the user's expectation. The user reviews finished work, tells you the gap per item, and you turn each gap into a tracked revision task, fix it, and re-verify — looping until they accept.

The point is that feedback is **per-item and structured**: every gap is tied to the original task, with expected-vs-actual captured, so the rework is never free-floating and the *why* is preserved.

This involves real judgment and code work. Run it inline on the current session model,
like `todo-execute`, using at least the **balanced** tier from
[`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md). Do not delegate the core revision judgment
to the fast tier.

## Hub location

Resolve every hub path against `$TODO_HUB` — see
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Hub location. The `repo`
column points at the target codebase elsewhere — that's where the fixes land.

## How the user invokes this

```
/todo-revise api-token-rotation        ← review done items, take feedback, plan + run fixes
/todo-revise api-token-rotation 4.5    ← jump straight to one task
/todo-revise api-token-rotation F3     ← jump straight to an infographic section ID
/todo-revise                              ← ask which project, or act on context
```

Plain language counts too: "this isn't what I expected", "the picker drifted", "give me feedback on phase 4", "what's the gap here" — and infographic IDs quoted in chat: "F3 shouldn't be removed", "D2 is wrong because…".

### Infographic IDs as feedback handles

`artifacts/infographic.html` stamps every reviewable element with a stable ID (see `todo-infographic` § Section IDs). When the user quotes one, resolve it by opening the infographic HTML and reading the element it labels, then route:

|ID|Points at|Route|
|-|-|-|
|`F<n>`|a file in the footprint|find the task(s) that touched that file → normal gap on that task (Step 3)|
|`D<n>`|a decision / trade-off card|implementation diverged from the decision → normal gap; the user disputes the decision itself → plan-level, point to `/todo-plan` (see Notes)|
|`X<n>`|a forgone item|user wants it back in → scope change, `/todo-plan`, not a revision|
|`L<n>`|a known limitation|user rejects the accepted gap → either a new revision (handle it now) or `/todo-plan` if it reshapes scope — ask which|
|`W1`|what & why|narrative mismatch is almost always plan-level|
|`4.5` etc.|a task|normal Step 3 gap|

Record the ID in the revision entry's Gap line (e.g. `Gap (⟵ F3): …`) so the trail from infographic to fix survives.

## Step 1 — Resolve the project

Resolve the project per
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Resolving a project,
recording the owning registry and section with the full `path` and `status`.

## Step 2 — Orient and show what's reviewable

Read `plan.md` (goal, constraints, repo path) in full — it's the expectation baseline that revisions are measured against. For `tasks.md`, **extract rather than ingest** when the file is large (> ~15KB): the review board needs only completed items, phase headers, counts, and revision headings —

```bash
grep -nE '^(#{2,3} |\s*- \[x\])' tasks.md     # phase headers + done items
grep -niE '^### R[0-9]+[A-Za-z]*' tasks.md     # existing revision headings (for numbering + flags)
```

Read the specific revision entry bodies you're working on by line range, not the whole file.

Show the user the **completed** (`[x]`) tasks as a **review board**, not a flat list —
per phase: a 10-cell `▓░` progress bar with `done/total`, then the numbered done items
(these are the feedback candidates), with any existing revision flagged inline:

```
## 🔍 api-token-rotation — review board

**Phase 4 · token exchange**   ▓▓▓▓▓▓▓▓░░ 8/10
| # | done item | prior revisions |
|---|---|---|
| 4.3 | Exchange endpoint returns scoped PAT | — |
| 4.5 | ResourceScopePicker tree | 🔴 R1 open |

**Phase 5 · lifecycle**   ▓▓▓▓▓▓▓▓▓▓ 6/6
| 5.1 | Rotate flow | ✅ R2 done |
…
```

(Open `[ ]` tasks belong to `todo-execute`, not here — building unbuilt work is not
revision.) If a task number was passed, focus there but still render the board so the
user can point elsewhere.

If `tasks.md` is missing or has no completed tasks, say so — there's nothing to revise yet.

## Step 3 — Capture the gap (per item)

For each item the user flags, record the gap **structured**, never as a loose note. Pull what the user gives you into this shape, inferring `Expected` from plan.md when they don't spell it out:

- **Gap** — one line: what's wrong.
- **Expected** — what the plan / the user wanted.
- **Actual** — what was built instead.
- **Fix** — the concrete approach you'll take.

**Echo it back visually before writing anything** — a side-by-side table makes the
delta legible in a way four prose lines don't:

```
### Gap on Task 4.5 — ResourceScopePicker

| | Expected 🎯 | Actual ⚠️ |
|---|---|---|
| selection | persists per account | resets on account switch |

🔧 Fix: lift selection to a wizard-level map keyed by accountId
```

If the gap is ambiguous or you can't tell expected from actual, ask before writing it down. Don't guess at the user's intent on a correction.

## Step 4 — Plan the revision into tasks.md

Append (or update) a `## Revisions` section at the bottom of `tasks.md`. One entry per gap, each backlinked to its source task with `⟵ Task N` so the gap is anchored to the original item:

```markdown
## Revisions

### R1 ⟵ Task 4.5 ResourceScopePicker        [open]
- Gap: tree selection lost when switching account
- Expected: selections persist per account
- Actual: state resets on account change
- Fix: lift selection to a wizard-level map keyed by accountId
- [ ] implement + re-verify
```

Rules:
- Number revisions `R1`, `R2`, … continuing from any existing entries (never reuse a number).
- Status tag on the heading: `[open]` → `[done]` (set `[done]` only after Step 6 verify passes).
- Each revision carries its own `- [ ]` checkbox — that's the executable unit.
- If a completed source task no longer holds, leave its original `[x]` as-is but note in the revision that the source is being corrected; the project status reconcile (Step 7) handles the rest.
- If the project row came from `archive.md`, opening the first revision also reopens the
  project: move the row verbatim back to the same section in `index.md`, set status to
  `in-progress`, and clear `completed` / `elapsed (days)` per `todo-state` § Date
  stamping. Treat the row move and status edit as one atomic change.

## Step 5 — Execute the fix

Work each open revision like `todo-execute` does: complete it fully, write outputs to `artifacts/` (following the artifact conventions — dated `YYYY-MM-DD-<kind>-<slug>.md` name, backlink header blockquote, and a row in `artifacts/README.md`), drop notes in `research/` if useful.

**Match the fix to an installed skill** ([`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Composing with installed skills) — a revision exists because the first pass drifted, so front-load procedure instead of retrying bare: a code-correctness gap → run `code-review` on the fix diff before presenting it; a UI/"looks wrong" gap → a frontend-design or design-critique skill; a chart/visual gap → `dataviz`. Hit a credential/service/API blocker → record it in `artifacts/blockers.md` and move on; never silently skip. Check the revision's `- [ ]` → `- [x]` when the code/work is done (not yet verified).

## Step 6 — Verify and loop

Present the result of each revision back to the user against the gap's `Expected` —
reuse the Step 3 side-by-side table with a third column showing what the fix now does,
so accept/reject is a visual comparison, not a re-read. Then collect the verdict through
the host's structured choice prompt when available: "Does R<n> now match what you
expected?" with options
"Accepted" / "Still off — here's the gap" / "Park it for now".

- **Accepted** → flip the revision heading to `[done]`, and re-confirm the source task's state via the same checkbox logic `todo-state` uses (re-check it if it had been reopened). Then **archive the entry's detail** (see "Archival rule" below). Report it. If the project's `plan.md` has a `## Verification` block, suggest `/todo-verify <short-name>` to re-run the verification gate against the reworked code.
- **Rejected / still off** → the user gives a new gap. Return to Step 3 with it (a fresh revision entry, or refine the existing one). This is the loop — repeat until accepted or the user stops.

Never claim a revision is fixed without the user accepting it or you having run real verification. Evidence before assertions.

## Step 7 — Reconcile status, then offer to persist the lesson

**Status honesty** (mirror `todo-state` Step S4): case-insensitive open revisions
on a project marked `done` mean it is not truly done. Flag it and offer to move an
archived row back to `index.md` when needed, then set `in-progress`. All revisions whose
tags start with `[done` and all tasks `[x]` → run the gate from
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § The status-flip gate, and
offer `done` only if it passes.

**Recurring-gap memory.** If a gap repeats a pattern you've seen before (same class of drift across items or sessions — e.g. "marked done before e2e", "ignored the plan's scope boundary"), *offer* to persist the *why* as a `feedback` memory, and write it only on the user's OK. Follow the memory format: `feedback` type, with `**Why:**` and `**How to apply:**` lines, linked to related memories like `[[definition-of-done]]`. Do not auto-write without asking; do not nag if they decline.

## Step 8 — Confirm with a revisions dashboard

Close with a compact dashboard instead of prose — one bar for revision completion, one
row per revision touched this session, and the status transition:

```
## 📈 Revisions — api-token-rotation   ▓▓▓▓▓▓░░░░ 3/5 done

| R# | ⟵ source | gap (one line) | state |
|---|---|---|---|
| R1 | 4.5 | selection lost on account switch | ✅ done |
| R4 | 5.2 | rotate skips audit log | ✅ done (this session) |
| R5 | 5.7 | exchange 401 on beta | 🔴 open |

Status: done → in-progress   ·   memory written: [[definition-of-done]]
```

Add one line for any memory you wrote, or omit the line. Keep it to the dashboard —
the `## Revisions` block in tasks.md speaks for itself.

## Archival rule — done revisions leave the hot file

`tasks.md` is read repeatedly; closed history must not tax every future read. The moment a
revision tag starts with `[done` in any letter case, apply `todo-archive` Step 2 to that
one entry: its detail moves under an `<a id="revision-r4"></a>` anchor in
`artifacts/journal.md`, and the entry collapses to a two-line tombstone under its verbatim
heading:

```markdown
### R4 ⟵ Task 5.2 — rotate audit log   [DONE 2026-07-10]
- archived → [journal:R4](artifacts/journal.md#revision-r4) (2026-07-10)
```

Read the procedure and its safety rules there rather than from memory — the anchor format,
the legacy-link repair, and the interrupted-run conflict handling all live in that one
place, and a second copy here is how the two drift apart. If 3+ completed entries still
carry detail, offer `/todo-archive <short-name>` for the sweep.

## Notes
- **Session handoff:** open revisions left at the end of a session hand off through
  `/todo-refer <short-name> resume`; `/todo-revise <short-name> R<n>` is an act-now pointer
  only. See [`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Session handoff.
- This skill edits `tasks.md` (the `## Revisions` block) and project code/artifacts — it does not rewrite `plan.md`. If a gap reveals the *plan itself* was wrong, say so and point to `/todo-plan` rather than silently editing the plan.
- Revisions feed the infographic: the Stop hook (`infographic-staleness.sh`) will regenerate `artifacts/infographic.html` after rework lands.
