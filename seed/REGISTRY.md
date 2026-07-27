# Registry Reference

Single home for how the two project registries work. [`index.md`](index.md) and
[`archive.md`](archive.md) hold the rows; this file explains them.

## Hot and cold

| file | holds | read when |
|---|---|---|
| [`index.md`](index.md) | active projects only | always — every hub-wide scan |
| [`archive.md`](archive.md) | `done` rows with no open Revisions | only on an exact-name miss in `index.md` |

Skills resolve an exact short-name in `index.md` first, then search the cold
`archive.md`. Completed rows keep their original section (`## Work` /
`## Self-initiative`) when `/todo-archive` moves them; reopening moves the row back to the
matching section. A row never exists in both files. Project folders never move.

The SessionStart archive-candidates check reports pending moves and compaction without
editing anything.

## Registries are data, not reports

`index.md` holds four things: the title, the fixed preamble, the optional `Start here`
line, and the section tables. `archive.md` holds the same minus the pointer, which is
active-work-only. Nothing else in either — no status banners, no release notes, no
revision narrative, no `##` heading that is not a section.

The rule exists because a registry is read constantly and edited narrowly. Every hub-wide
scan opens `index.md` first, so prose here is paid for on every read; and a paragraph
nobody re-opens before editing a row goes stale silently, while still looking current to
the next session. Status that matters belongs where the next reader is already going to
look for it:

| what you want to record | where it goes |
|---|---|
| what is next for a project | `<project>/artifacts/YYYY-MM-DD-handoff-<slug>.md` |
| what happened, with evidence | `<project>/artifacts/journal.md` |
| what is blocked and why | `<project>/artifacts/blockers.md` |
| a gap between result and expectation | `tasks.md` `## Revisions` |
| which project to open first | the `Start here` line below |

Answering "where was I" is `/todo-refer <short-name> resume`, which derives the answer
from live files and git rather than from a line someone remembered to update.

## The `Start here` line

One optional line directly under the title, naming the project a cold session should open
first:

```markdown
> **Start here:** [service-auth](projects/work/service-auth/artifacts/2026-07-28-handoff-cutover.md) — rollout paused before the flag flip.
```

Exactly one line, one project, one link, and at most a sentence after the dash. `-` — or
no line at all — means nothing is pinned. It is a **pointer, never a summary**: the link
target holds the state, and the sentence only says why you would open it.

`/todo-state` owns the line. A flip into `in-progress` repoints it at that project; the
flip that leaves no `in-progress` project anywhere resets it to `-`. `/todo-state audit`
reports a pointer whose link is dead or whose project is no longer `in-progress`. No other
skill writes it.

## Columns

Both registries carry the same columns.

| column | holds | written by |
|---|---|---|
| `short-name` | unique key used to resolve the project | `/todo-add` |
| `path` | hub-relative project folder | `/todo-add` |
| `repo` | local path to the codebase — fill it in as soon as you know it | you, `/todo-plan` |
| `status` | `planning` → `ready` → `in-progress` → `done` | any skill that flips state |
| `started` · `completed` · `elapsed (days)` | when the project actually ran | stamped alongside every `status` edit |
| `infographic` | link to the plan's one-pager, `-` if none | `/todo-infographic` + the Stop hook |
| `related` | legacy context hints, never blocking | hand edits only |

### `status`

`ready` means the project plan is ready. It is *runnable* only when `/todo-graph` confirms
every explicit `depends-on` target is settled — the registry itself encodes no scheduling.

The gate into `done` is `/todo-verify <project>`: it reads a project's result from its
verification MCP (per the `## Verification` block in its `plan.md`) and reconciles it into
todo state. A green run ticks `tasks.md` and flips `status`; failures and coverage gaps
open `## Revisions` entries for `/todo-revise` to fix. Detection only — it never edits
code. Projects with no verification layer simply omit the `## Verification` block.

### `started` · `completed` · `elapsed (days)`

Dates are `YYYY-MM-DD`; `-` means not yet or unknown.

`started` holds the earliest *reliable* signal, in priority order
**`in-progress` > `ready` > `planning` > `completed`**. The tiers exist because the early
signals are guesses about a start that may never happen: creating a project (`planning`)
or confirming its plan (`ready`) says work is *intended*, while a real
`ready`→`in-progress` flip says work *began*. So the lower tiers stamp provisionally and
the higher tier overwrites them, and once the real start lands it is never overwritten.
A row that appears directly as `done` — retroactive bookkeeping — falls back to
`started` = `completed`.

`completed` is stamped at the flip to `done` and cleared if the project is reopened.
`elapsed (days)` = `completed − started` in whole days, computed at that same flip and
cleared alongside `completed`.

**The mechanical rules — which flip stamps what, and what overwrites what — live in
`todo-state` § Date stamping.** That section is the authority; every skill that flips a
status follows it.

### `infographic`

A one-pager visual summary of the plan — open the HTML in a browser to review a plan at a
glance instead of reading the full `plan.md`. Generated by the `todo-infographic` skill and
kept fresh automatically by the plugin's Stop hook.

### `related`

A legacy, comma-separated list of other `short-name`s worth reading alongside this
project. Context-only; it never blocks execution. Canonical typed relationships live in
each project's `plan.md` `## Relationships` table, and `/todo-graph` derives the ready
frontier, blockers, paths, and impact from those explicit edges. `-` means no legacy hints.
