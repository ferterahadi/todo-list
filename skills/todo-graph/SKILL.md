---
name: todo-graph
description: Use when the user invokes /todo-graph, asks "what can I start?", "what's blocked and why?", "what does finishing X unlock?", how tracked projects depend on each other, requests a dependency path or graph audit/export, or wants to add/remove a typed project relationship. Also lists one project's real tasks with their IDs for other skills. Answers from a deterministic project graph and never guesses dependencies from prose. For "what's left and which model should do it", use todo-triage instead.
---

# Todo Graph

Treat every tracked project as one execution loop and the hub as a graph of those loops.
Use the bundled compiler for graph truth; do not load every plan or infer scheduling from
names, prose, or legacy `related` cells.

Run every query inline: the compiler answers in about 50 ms, so dispatching a subagent
costs more than the query. Relationship edits require judgment about intent, so make them
on at least the **balanced** tier from
[`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md).

## Hub and compiler

Resolve every hub path against `$TODO_HUB` — see
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Hub location. The
deterministic compiler is:

```bash
python3 <todo-graph-skill-dir>/scripts/graph-report.py <mode> "$TODO_HUB" [args]
```

The compiler scans Markdown outside model context and emits bounded Tab-Separated Values
(TSV). Only explicit `export` and one project's `tasks` listing are unbounded. If Python 3
or the helper is unavailable,
report that blocker; never approximate a ready frontier by interpreting prose.

## Relationship contract

Canonical relationships live in each project's `plan.md`:

```markdown
## Relationships

| relation | target | reason |
|---|---|---|
| depends-on | `auth-foundation` | D2 consumes its token contract |
| related-to | `token-rotation` | shares gateway context |
```

|Relation|Meaning|Scheduling|
|-|-|-|
|`depends-on`|The source requires the target|Target must be settled before source is runnable|
|`related-to`|Useful neighboring context|Never blocks|
|`supersedes`|Source replaces or continues target|Never blocks|

`B blocks A` is the derived inverse of `A depends-on B`; never store `blocks`. A target is
settled only when its exact registry row is `done`, `tasks.md` exists with no open tasks,
and it has no open Revision.

The registry's historical `related` cell remains a compatibility hint. Every bare name
there is a non-blocking `related-to` edge. Never promote it to `depends-on`, rewrite it,
or use it to determine readiness.

## Choose the mode

```text
/todo-graph
/todo-graph frontier
/todo-graph service-release
/todo-graph why service-release
/todo-graph impact auth-foundation
/todo-graph path auth-foundation service-release
/todo-graph audit
/todo-graph export
/todo-graph tasks service-release
/todo-graph link service-release depends-on auth-foundation "needs token contract"
/todo-graph unlink service-release depends-on auth-foundation
```

- No argument, “what can I start?”, or “ready frontier” → `frontier`.
- A project name or “what is connected to X?” → `context`.
- “Why is X blocked?” → `why`.
- “What will finishing X unlock?” → `impact`.
- “Show the route from X to Y” → `path`.
- “Find cycles/broken links” → `audit`.
- “Export the graph” → `export`.
- “List X's tasks” / “which task is 6a.3?” → `tasks`.
- “Make X depend on Y” / “remove that relationship” → `link` / `unlink`.

## Read-only queries

Run exactly one bounded query first:

```bash
python3 <skill-dir>/scripts/graph-report.py frontier "$TODO_HUB"
python3 <skill-dir>/scripts/graph-report.py context "$TODO_HUB" "<project>"
python3 <skill-dir>/scripts/graph-report.py why "$TODO_HUB" "<project>"
python3 <skill-dir>/scripts/graph-report.py impact "$TODO_HUB" "<project>"
python3 <skill-dir>/scripts/graph-report.py path "$TODO_HUB" "<from>" "<to>"
python3 <skill-dir>/scripts/graph-report.py audit "$TODO_HUB"
python3 <skill-dir>/scripts/graph-report.py tasks "$TODO_HUB" "<project>" [--open]
```

**Validate before running any of these** —
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Placeholder safety.
`<project>`, `<from>`, and `<to>` come from the user's prose or a registry cell and must
match `^[a-z0-9][a-z0-9-]*$`; `<skill-dir>` resolves from the installed skill location. On
a failure, stop and report that name.

Trust the helper's exact-name resolution and issue rows. Do not open all project plans,
tasks, or journals afterwards. Read one named `plan.md` only when the user asks for its
reasoning or the query result makes that project the chosen next action.

Render the result compactly:

- `frontier` — in-flight work, ready work, blocked work, then complete counts.
- `context` — the node, hard prerequisites, derived blockers, and context/lineage edges.
- `why` — shortest blocking chains first.
- `impact` — projects immediately unlocked first, then transitively affected projects.
  `ALREADY_SETTLED` means describe current dependents without claiming a future unlock.
- `path` — one shortest prerequisite-to-dependent path; say when none exists. The helper
  tries both argument orders. `PATH` names the prerequisite first; `direction=reverse`
  means the user named the dependent first, so say the route runs the other way.
- `audit` — group errors by code and cite the source plan/line. An empty audit is one
  confirmed line, not a raw TSV dump.
- `tasks` — see Task listing below.

**Exit codes.** `0` means a complete answer with no relevant `ERROR` row. `1` still carries a
valid answer to parse: it has at least one relevant `ERROR` row, or the answer is negative
(`NO_PATH`, an unresolved project, a refused `can-link`, a missing `tasks.md`). `2` is a
usage error or unknown export format with nothing to parse. Never treat exit 1 as an empty
result.

When `SUMMARY legacy_edges` is nonzero, state once that those registry hints are
non-blocking and have not been classified as dependencies. Offer explicit `link`
commands for any edge the user confirms; never migrate them automatically.

Never call a longest dependency chain a “critical path”: without duration estimates it
does not predict elapsed time.

## Task listing

`tasks` lists one project's real tasks in file order, resolving the name active-first and
then archived. Counting and IDs follow
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Counting tasks and
§ Task IDs and phases. Output is TSV and unbounded for that one project:

```text
TASK	<id>	<open|done>	<tasks.md line>	<task text after the checkbox>
SUMMARY	tasks	project=<short-name>	done=<d>	total=<t>	open_revisions=<n>
```

`--open` prints only open tasks; `SUMMARY` still carries the full counts. An unresolved
name, an unsafe project path, or a missing `tasks.md` prints one `ERROR` row and exits 1.

## Add a relationship

Syntax:

```text
/todo-graph link <source> <depends-on|related-to|supersedes> <target> "<reason>"
```

1. Require an exact source, relation, and target. Ask only for a missing identity or
   relation; do not ask for a reason yet. Both names must match `^[a-z0-9][a-z0-9-]*$` and
   the relation must be exactly `depends-on`, `supersedes`, or `related-to` — these go
   onto a shell command line in the next step. Reject anything else and say which value
   failed; never interpolate it anyway, never rewrite it into something that passes.
2. Validate without editing:

   ```bash
   python3 <skill-dir>/scripts/graph-report.py can-link \
     "$TODO_HUB" "<source>" "<relation>" "<target>"
   ```

3. Stop on `ERROR`. A dependency cycle, ambiguous identity, missing target, self-edge,
   archived source, or unknown relation must leave every file unchanged. `EXISTS` is an
   idempotent success; do not add a duplicate row.
4. On `OK`, ask for a short reason only if the user did not provide one. Then edit only
   the source project's `plan.md`. Add the row to its visible
   `## Relationships` table. If the section is absent, insert the canonical three-column
   table before `## Verification`, or before `## References` when Verification is absent.
   Preserve other rows and the user's wording; collapse reason newlines to spaces and
   escape a literal `|` as `\|` so the Markdown row stays parseable.
5. Re-run `audit`, then `context <source>`. If either reports a new error, fix only the
   row just added or restore it; do not mutate registry state.

Do not edit the registry's `related` cell. It is a legacy context hint, not a graph cache.

## Remove a relationship

Syntax:

```text
/todo-graph unlink <source> <relation> <target>
```

1. Resolve the source with `context`.
2. Find exactly one canonical row in the source `plan.md` matching the normalized relation
   and exact target.
3. Zero matches → report no change. Multiple matches → stop and run `audit`; do not guess.
4. Remove only that row. Keep the header and separator even when the table becomes empty.
5. Re-run `audit` and `context <source>`.

Never remove or rewrite a legacy registry hint through this command.

## Export

Export is explicit because it is intentionally unbounded:

```bash
python3 <skill-dir>/scripts/graph-report.py export "$TODO_HUB" tsv
python3 <skill-dir>/scripts/graph-report.py export "$TODO_HUB" json
```

TSV is the stable compact interchange. JavaScript Object Notation (JSON) includes a
schema version for future tools. Write an export to an artifact only when the user asks;
otherwise return the requested slice in chat.

## Safety and accuracy

- Exact names only; active registry is checked before the archive, and a duplicate across
  either registry invalidates that identity.
- Missing targets, unknown relation types, self-edges, duplicate canonical edges, cycles,
  and dishonest completion state fail closed.
- Valid context and lineage edges never influence readiness. A malformed canonical row
  fails its source project without contaminating the target.
- An unknown status makes only that project unusable; it blocks the projects that depend
  on it and no others. A missing or malformed registry table and a duplicated identity
  are registry-wide and block every project.
- Read-only modes never edit. Link validation happens before the single plan-row edit.
- Do not auto-change status when a dependency regresses. Report an in-progress dependent
  as at risk and let `todo-state audit` reconcile state deliberately.
