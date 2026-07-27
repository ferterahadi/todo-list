# todo-list

**A project tracker that Claude Code or Codex works through for you.** Describe a project once;
the agent plans it, executes the checklist, verifies the result, and fixes the gaps — with
every plan and task list stored as plain markdown you can read and edit yourself.

When one project starts waiting on another, say so once. The agent then schedules around
it: what's ready, what's blocked and why, what finishing a thing would unlock.

It is a cross-platform Agent Skills package with native Claude Code and Codex plugin
manifests. No build step, runtime, or database — the graph compiler is Python 3 standard
library, the hooks are Bash.

## What it does

Most people scatter plans across notes apps, issue trackers, and each repo's own docs.
This plugin gives you **one hub** — a single folder (default `~/todo`) that tracks *all*
your projects:

```
~/todo/
  index.md                     ← the active registry: every live project, one row each
  archive.md                   ← the cold registry: completed rows, kept not deleted
  projects/
    work/api-rate-limiting/    ← one folder per project:
      plan.md                       goal, scope, decisions, relationships (source of truth)
      tasks.md                      the checklist the agent works through
      research/                     raw notes
      artifacts/                    outputs the agent produces
        journal.md                  closed revision detail, one anchor per revision
```

Each project folder **points at** wherever its real code lives. The hub tracks the work;
your actual repos stay untouched until you ask the agent to execute.

**It enhances your other skills, it doesn't replace them.** The `/todo-*` skills are the
organization layer — paths, formats, statuses, bookkeeping. When you have craft or
process skills installed (superpowers brainstorming / TDD / systematic-debugging,
code-review, dataviz, …), the todo skills invoke *those* for the thinking: `/todo-plan`
runs discovery through `superpowers:brainstorming` when it's there, `/todo-execute`
front-loads `test-driven-development` on code tasks, `/todo-review` drives your installed
`code-review`. No relevant skill installed? Every todo skill carries its own complete
fallback.

## The loop

Four skills form a `plan → do → check → revise` cycle:

```
        ┌──────────────────────────────────────────────────┐
        │                                                  │
   /todo-plan  ──▶  /todo-execute  ──▶  /todo-verify  ──▶  /todo-revise
     plan            do (build)         check (gate)       fix the gaps
        │                                  │                    │
        └── writes plan.md + tasks.md      └── ticks tasks,     └── loops back
                                               flips status,       until accepted
                                               opens Revisions
```

|Stage|Skill|What happens|
|-|-|-|
|plan|`/todo-plan`|Discovery, then writes `plan.md` (goal, scope, decisions) + `tasks.md` (checklist)|
|do|`/todo-execute`|Works the checklist top to bottom; outputs land in `artifacts/`. Add `parallel` to fan file-disjoint tasks out to worktree agents|
|check|`/todo-verify`|Runs an optional [verification MCP](#verification-mcp-optional), reconciles pass/fail into todo state|
|revise|`/todo-revise`|Captures each gap as a Revision entry, reworks it, re-verifies|

Between do and check, `/todo-review` optionally audits the diff *against the plan* —
scope drift, violated constraints, ticked tasks with no evidence — before the
verification gate runs.

A typical project, end to end:

```
/todo-add "add rate limiting to the API"   # scaffold + register it
/todo-plan api-rate-limiting               # research and write the plan
/todo-execute api-rate-limiting            # work the checklist
/todo-verify api-rate-limiting             # check gate: did it actually pass?
/todo-revise api-rate-limiting             # fix whatever the gate caught
```

Stopped halfway? `/todo-refer api-rate-limiting resume` rebuilds the open tasks, Revisions,
blockers, and git/worktree state, then names the next command.

## The graph

One project is a loop. Several projects that wait on each other are a graph — and
`/todo-graph` is the only thing that reads it. Relationships are declared, never guessed
from names or prose:

```
/todo-graph link api-migration depends-on auth-foundation "consumes its token contract"
```

That validates both project identities and cycle risk, then writes a visible table into
`api-migration/plan.md` — the graph lives in the same markdown as everything else:

```markdown
## Relationships

| relation | target | reason |
|---|---|---|
| depends-on | `auth-foundation` | consumes its token contract |
```

Three relations exist; only one of them changes what runs next:

```
  partner-rollout ──depends-on──▶ api-migration ──depends-on──▶ auth-foundation
      blocked                        blocked                      in-progress
                                        │                              ▲
                                   related-to                          │
                                        ▼                       the ready frontier:
                                  gateway-notes                 the only project
                            (context — never blocks)            work can start on
```

|Relation|Meaning|Scheduling effect|
|-|-|-|
|`depends-on`|Source requires target|Target must settle before source is runnable|
|`related-to`|Useful neighboring context|None|
|`supersedes`|Source replaces or continues target|None|

Once edges exist, the graph answers the scheduling questions directly:

```
/todo-graph                                     # the ready frontier
/todo-graph api-migration                       # one project's graph context
/todo-graph why api-migration                   # shortest blocker chains
/todo-graph impact auth-foundation              # direct + transitive dependents
/todo-graph path auth-foundation api-migration  # prerequisite-to-dependent route
/todo-graph audit                               # cycles, broken links, status conflicts
/todo-graph export [json]                       # TSV by default, JSON on request
```

Remove an edge with `/todo-graph unlink api-migration depends-on auth-foundation`.

What keeps it honest:

- A prerequisite counts as **settled** only when its row says `done`, `tasks.md` exists
  with every task checked, and no Revision is still open.
- Queries are read-only and bounded. Only `link` / `unlink` write, and only to the source
  project's `plan.md`. Explicit `export` is the one unbounded output.
- The compiler scans the markdown outside the model's context, so a large hub costs
  tokens for the answer, not for the corpus.
- A dependency path is not a critical path — the graph stores no durations.

## Install skills in Claude Code and Codex

One command installs all skills for both agents from the same source:

```bash
npx skills add ferterahadi/todo-list --agent claude-code --agent codex --global --yes
```

No `--skill` filter is needed. Every publicly installable skill in this repo lives under
`skills/` and is named `todo-*`; the repo's own learned-convention skills under
`.agents/skills/` are marked `metadata.internal: true`, so the installer skips them. Run
`npx skills add ferterahadi/todo-list --list` to see the exact set before installing.

For a local checkout, replace `ferterahadi/todo-list` with `.`. The installer uses
symlinks by default so both agents share one copy. This path installs skills only; use a
native plugin install when you also want lifecycle hooks and automatic hub bootstrapping.

### Full Claude Code plugin

Two commands — this repo doubles as its own marketplace:

```bash
claude plugin marketplace add ferterahadi/todo-list
```
```
/plugin install todo-list@todo-list
```

On the next Claude Code session it:

- registers the `/todo-*` skills (auto-discovered), and
- creates the hub at `~/todo` from bundled seed content — `index.md`, `archive.md`,
  `templates/`, and a small example project — via a SessionStart hook. It runs once, then
  stays quiet.

Already have a hub from an earlier version? Nothing is overwritten: bootstrap only adds a
missing `archive.md`, and a separate migration hook widens pre-1.2 registry tables to the
dated format, backfilling `started` / `completed` from the hub's git history and leaving
an `index.md.pre-dates.bak` backup.

**Staying up to date:** releases are versioned (see [CHANGELOG.md](CHANGELOG.md)).
Third-party marketplaces have auto-update **off** by default — enable it once via
`/plugin` → Marketplaces → todo-list → enable auto-update, and new releases will prompt
`/reload-plugins` as they land. Or pull manually with `/plugin marketplace update todo-list`.

### Codex plugin package

The repository includes `.codex-plugin/plugin.json`. Its `skills/` and `hooks/hooks.json`
use Codex's native plugin layout. Install through a Codex marketplace when publishing the
full package; use the cross-agent command above during local development.

To put the hub somewhere other than `~/todo`, set `TODO_HUB` *before* the first hook run
([optional config](#optional-config) below).

### Try it

The hub ships with an example project:

```
/todo-list                              # see the project index
/todo-refer example-feature             # load its plan + tasks as context
/todo-execute example-feature           # work its checklist
/todo-infographic example-feature       # render a one-page visual of the plan
```

> Claude Code slash commands are namespaced by the plugin, for example
> `/todo-list:todo-plan`. In Codex, mention `$todo-plan` explicitly or use the skill's
> natural-language trigger.

### Removing it

```bash
claude plugin uninstall todo-list@todo-list      # remove the plugin (skills + hooks)
claude plugin marketplace remove todo-list       # remove the marketplace entry
```

(Both also work from the interactive `/plugin` menu.)

What's left on disk is the hub folder — your own plans and notes. Delete it whenever:

```bash
rm -rf ~/todo    # or wherever TODO_HUB points
```

### Optional config

- **Move the hub.** Set `TODO_HUB` (e.g. in your shell profile) before first run:

  ```bash
  export TODO_HUB=~/my/hub/path
  ```

  Skills resolve every hub path against `TODO_HUB`, so they work even when invoked from
  inside another repo. See [`.env.example`](.env.example).
- **Version the hub.** The hub is a plain directory. `git init` it if you want history.

## All 16 skills

The loop and graph skills above, plus support skills grouped by role:

**Track** — get projects in, see where they stand

|Skill|Purpose|
|-|-|
|`todo-add`|Scaffold a new project folder + register it in `index.md`|
|`todo-list`|Overview of the index grouped by status; `archive` reads the cold registry, `sort` reorders rows by task completion|
|`todo-triage`|Tabulate open work across projects + recommend a model per task|
|`todo-state`|Record and reconcile state. Default: tick tasks / flip status by hand. `audit`: cross-check the registry against tasks + git/PR reality and fix drift on confirmation|

**Work** — the loop, and the graph over the loops

|Skill|Purpose|
|-|-|
|`todo-plan`|Discovery → write `plan.md` and `tasks.md`|
|`todo-execute`|Work `tasks.md` top to bottom; `parallel` mode fans tasks to git-worktree agents, lands PRs via a serial merge queue|
|`todo-graph`|Compile the typed relationships into ready frontier, blocker chains, impact, paths, audits, validated edits, and exports|
|`todo-review`|Audit a diff against the plan (scope, constraints, evidence), then a correctness pass|
|`todo-verify`|The check gate: drive a verification MCP, tick tasks / flip status, open Revisions|
|`todo-revise`|Gap-driven rework of completed items, then re-verify|

**Bridge** — connect the hub to real repos

|Skill|Purpose|
|-|-|
|`todo-refer`|Load project context from any repo. Default: plan+tasks as grounding. `resume`: reconstruct where work stopped (tasks, blockers, worktree/PR state) + name the next command. `R<n>`: one past Revision|
|`todo-push`|Full git shipping workflow: branch → commit → push → PR → merge|
|`todo-infographic`|Turn a plan into a one-page HTML infographic|
|`todo-learn`|Capture a correction as a durable rule in a repo's own skill files|

**Hygiene** — keep the hub honest and small

|Skill|Purpose|
|-|-|
|`todo-archive`|Move closed revision detail to the journal, retire done rows to `archive.md` — lossless|

**Support** — shared configuration the others read

|Skill|Purpose|
|-|-|
|`todo-llm-routing`|Map the frontier/deep/balanced/fast tiers to the active provider's model — see [Model routing](#model-routing)|

Status lifecycle: `planning → ready → in-progress → done`. Each skill's full contract
lives in [`skills/`](skills/).

## Done doesn't mean deleted

Archiving compacts the hub; it never discards work.

- **Projects.** `/todo-archive` previews the eligible completed rows and waits for your
  confirmation before moving them from `index.md` to `archive.md`. The project folder
  stays exactly where it was.
- **Revisions.** Once a Revision carries a terminal `[done…]` tag, its detail moves to an
  anchored entry in `artifacts/journal.md`, and `tasks.md` keeps the heading plus a direct
  link to that entry. Ordinary task checkboxes never move.
- **The SessionStart check** only reports what a sweep would compact. It never archives
  anything on its own.

## Model routing

Skills route work by capability tier, then resolve the tier for the active provider:

|Tier|Claude Code|Codex preferred|Codex fallback|
|-|-|-|-|
|frontier|Opus latest, max|GPT-5.6 Sol, max|GPT-5.5, xhigh|
|deep|Opus latest, high|GPT-5.6 Sol, high|GPT-5.5, high|
|balanced|Opus latest, medium|GPT-5.6 Terra, medium/high|GPT-5.4, medium/high|
|fast|Opus latest, low|GPT-5.6 Luna, low|GPT-5.4 Mini, low|

Use the preferred Codex model when it appears in the local model picker or
`codex debug models`; otherwise use the fallback. On Claude Code every tier resolves to
Opus and reasoning effort is the only lever — per [CursorBench 3.2](https://cursor.com/cursorbench)
the Opus 5 effort sweep is both more accurate and cheaper per task than Sonnet at any
effort, and than Fable below max. The mapping is advisory and centralized in
[`skills/todo-llm-routing/SKILL.md`](skills/todo-llm-routing/SKILL.md).

## Repo layout

```
.claude-plugin/
  plugin.json        Claude Code plugin manifest
  marketplace.json   makes this repo installable as a marketplace
.codex-plugin/
  plugin.json        Codex plugin manifest
skills/todo-*/       the 16 shared skills (each a SKILL.md)
  todo-graph/scripts/graph-report.py   the deterministic graph compiler (stdlib only)
hooks/
  hooks.json                 registers the five hooks below (auto)
  bootstrap-hub.sh           SessionStart: seed the hub on first run
  migrate-index-dates.sh     SessionStart: widen legacy index tables, backfill dates
  archive-candidates.sh      SessionStart: report what a /todo-archive sweep would compact
  infographic-staleness.sh   Stop: nudge stale infographics
  superpowers-doc-sync.sh    Stop: ensure superpowers plans/specs are tracked in the hub
seed/                copied to $TODO_HUB on first run
tests/               contract checks for the package, archive rules, graph compiler, and hooks
```

The seeded hub adds `AGENTS.md` as the shared instructions and a small `CLAUDE.md`
pointer for Claude Code, `index.md` + `archive.md` as the active and cold registries,
`templates/` (copied for new projects), and `projects/work/` +
`projects/self-initiative/` sections.

## Verification MCP (optional)

`/todo-verify` is the "check" gate, and it's **pluggable**. It drives any MCP server that
can:

- start a run against a named feature/target,
- wait for / report a terminal pass/fail verdict per test, and
- *(optionally)* report coverage gaps.

The contract (`start_run` / `wait_for_result` / `get_result` / `get_coverage`) is documented
in [`skills/todo-verify/SKILL.md`](skills/todo-verify/SKILL.md) — map those names to your own
harness's tools. Any server matching that contract works (for example, one that runs your
e2e/integration suite and reports per-test results plus coverage).

**No verification MCP?** Leave the `## Verification` block out of a project's `plan.md`. The
`plan → do → revise` loop still runs; you just don't get an automated check gate.

## License

MIT — see [LICENSE](LICENSE). Issues and pull requests are welcome; see
[CONTRIBUTING.md](CONTRIBUTING.md).
