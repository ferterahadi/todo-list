# todo-list

**A project tracker that Claude Code works through for you.** You describe a project once;
Claude plans it, executes the checklist, verifies the result, and fixes the gaps — with
every plan and task list stored as plain markdown you can read and edit yourself.

It's a [Claude Code](https://claude.com/claude-code) plugin made of prompt files (skills).
No build step, no runtime, no database.

## What it does

Most people scatter plans across notes apps, issue trackers, and each repo's own docs.
This plugin gives you **one hub** — a single folder (default `~/todo`) that tracks *all*
your projects:

```
~/todo/
  index.md                     ← the registry: every project, one row each
  projects/
    work/api-rate-limiting/    ← one folder per project:
      plan.md                       goal, scope, decisions   (source of truth)
      tasks.md                      the checklist Claude works through
      artifacts/                    outputs Claude produces
```

Each project folder **points at** wherever its real code lives. The hub tracks the work;
your actual repos stay untouched (until you ask Claude to execute).

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
/todo-plan api-rate-limiting               # Claude researches and writes the plan
/todo-execute api-rate-limiting            # Claude works the checklist
/todo-verify api-rate-limiting             # check gate: did it actually pass?
/todo-revise api-rate-limiting             # fix whatever the gate caught
```

## Install

Two commands — this repo doubles as its own marketplace:

```bash
claude plugin marketplace add ferterahadi/todo-list
```
```
/plugin install todo-list@todo-list
```

On your next session it:

- registers the `/todo-*` skills (auto-discovered), and
- creates the hub at `~/todo` from bundled seed content — `index.md`, `templates/`, and a
  small example project — via a SessionStart hook. It runs once, then stays quiet.

To put the hub somewhere other than `~/todo`, set `TODO_HUB` *before* first run
([optional config](#optional-config) below).

### Try it

The hub ships with an example project:

```
/todo-list                              # see the project index
/todo-refer example-feature             # load its plan + tasks as context
/todo-execute example-feature           # work its checklist
/todo-infographic example-feature       # render a one-page visual of the plan
```

> Slash commands are namespaced by the plugin — `/todo-list:todo-plan` — but each skill's
> natural-language triggers ("plan this project", "what's on my list") fire without the
> prefix.

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

The loop skills above, plus support skills grouped by role:

**Track** — get projects in, see where they stand

|Skill|Purpose|
|-|-|
|`todo-add`|Scaffold a new project folder + register it in `index.md`|
|`todo-list`|Overview of the index grouped by status; `sort` mode reorders rows by task completion|
|`todo-triage`|Tabulate open work across projects + recommend a model per task|
|`todo-update-state`|Tick tasks / flip status by hand, without an execution pass|

**Work** — the loop

|Skill|Purpose|
|-|-|
|`todo-plan`|Discovery → write `plan.md` and `tasks.md`|
|`todo-execute`|Work `tasks.md` top to bottom; `parallel` mode fans tasks to git-worktree agents, lands PRs via a serial merge queue|
|`todo-review`|Audit a diff against the plan (scope, constraints, evidence), then a correctness pass|
|`todo-verify`|The check gate: drive a verification MCP, tick tasks / flip status, open Revisions|
|`todo-revise`|Gap-driven rework of completed items, then re-verify|

**Bridge** — connect the hub to real repos

|Skill|Purpose|
|-|-|
|`todo-refer`|Load a project's plan+tasks as grounding context from any repo|
|`todo-resume`|Reconstruct where work stopped (tasks, blockers, worktree/PR state) + name the next command|
|`todo-push`|Full git shipping workflow: branch → commit → push → PR → merge|
|`todo-infographic`|Turn a plan into a one-page HTML infographic|
|`todo-learn`|Capture a correction as a durable rule in a repo's own skill files|

**Hygiene** — keep the hub honest and small

|Skill|Purpose|
|-|-|
|`todo-sync`|Audit recorded status vs tasks + git/PR reality; fix drift on confirmation|
|`todo-archive`|Compact closed detail out of `tasks.md`, retire done projects to an Archive section — lossless|

Status lifecycle: `planning → ready → in-progress → done`.

Some skills note a suggested Claude model (Haiku for mechanical steps, Sonnet/Opus for
judgment calls) — advisory conventions, not requirements. Because of those model names,
this is built for Claude Code running Claude; other setups are untested.

## Repo layout

```
.claude-plugin/
  plugin.json        the plugin manifest
  marketplace.json   makes this repo installable as a marketplace
skills/todo-*/       the 16 /todo-* skills (each a SKILL.md) + skills/README.md
hooks/
  hooks.json         registers the three hooks below (auto)
  bootstrap-hub.sh   SessionStart: seed the hub on first run
  infographic-staleness.sh   Stop: nudge stale infographics
  superpowers-doc-sync.sh    Stop: ensure superpowers plans/specs are tracked in the hub
seed/                copied to $TODO_HUB on first run
```

The seeded hub adds `CLAUDE.md` (instructions Claude reads when working in the hub),
`templates/` (copied for new projects), and `projects/work/` + `projects/self-initiative/`
sections. Each project folder holds `plan.md`, `tasks.md`, `research/` (raw notes), and
`artifacts/` (outputs).

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
