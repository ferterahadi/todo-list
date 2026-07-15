# todo-list

**A project tracker that Claude Code or Codex works through for you.** Describe a project once;
the agent plans it, executes the checklist, verifies the result, and fixes the gaps — with
every plan and task list stored as plain markdown you can read and edit yourself.

It is a cross-platform Agent Skills package with native Claude Code and Codex plugin
manifests. No build step, runtime, or database.

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
      tasks.md                      the checklist the agent works through
      artifacts/                    outputs the agent produces
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

## Install skills in Claude Code and Codex

One command installs all skills for both agents from the same source:

```bash
npx skills add ferterahadi/todo-list \
  --skill model-routing todo-add todo-archive todo-execute todo-infographic \
    todo-learn todo-list todo-plan todo-push todo-refer todo-resume todo-review \
    todo-revise todo-sync todo-triage todo-update-state todo-verify \
  --agent claude-code \
  --agent codex \
  --global \
  --yes
```

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
- creates the hub at `~/todo` from bundled seed content — `index.md`, `templates/`, and a
  small example project — via a SessionStart hook. It runs once, then stays quiet.

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

## Model routing

Skills route work by capability tier, then resolve the tier for the active provider:

|Tier|Claude Code|Codex preferred|Codex fallback|
|-|-|-|-|
|frontier|Fable 5, high|GPT-5.6 Sol, max|GPT-5.5, xhigh|
|deep|Opus latest, high|GPT-5.6 Sol, high|GPT-5.5, high|
|balanced|Sonnet latest, medium/high|GPT-5.6 Terra, medium/high|GPT-5.4, medium/high|
|fast|Haiku latest, low|GPT-5.6 Luna, low|GPT-5.4 Mini, low|

Use the preferred Codex model when it appears in the local model picker or
`codex debug models`; otherwise use the fallback. Fable and Opus both map to the
flagship Codex model, with reasoning effort separating highest-risk work from normal
deep work. The mapping is advisory and centralized in
[`skills/model-routing/SKILL.md`](skills/model-routing/SKILL.md).

## Repo layout

```
.claude-plugin/
  plugin.json        Claude Code plugin manifest
  marketplace.json   makes this repo installable as a marketplace
.codex-plugin/
  plugin.json        Codex plugin manifest
skills/todo-*/       the 16 shared skills (each a SKILL.md)
skills/model-routing/  shared provider model mapping skill
hooks/
  hooks.json         registers the three hooks below (auto)
  bootstrap-hub.sh   SessionStart: seed the hub on first run
  infographic-staleness.sh   Stop: nudge stale infographics
  superpowers-doc-sync.sh    Stop: ensure superpowers plans/specs are tracked in the hub
seed/                copied to $TODO_HUB on first run
```

The seeded hub adds `AGENTS.md` as the shared instructions and a small `CLAUDE.md`
pointer for Claude Code,
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
