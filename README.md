# todo-list

A set of [Claude Code](https://claude.com/claude-code) skills for keeping track of projects.
Plans and checklists stay as plain markdown, and the `/todo-*` skills work through them in a
`plan → do → check → revise` cycle. It's prompt files — no build step, no runtime.

It works as one hub — a monorepo for all your projects — where every plan and checklist
lives together instead of being scattered across each project's own repo. Each `<project>/`
folder points at wherever its real code lives, so the hub tracks the work while your actual
repos stay untouched.

The skills reference Claude models by name (Haiku for the mechanical steps, Sonnet and Opus
for the judgment calls), so it's meant for Claude Code running Claude. It may work with
other setups; that isn't something I've tested.

It installs as a Claude Code plugin.

## The loop

```
        ┌─────────────────────────────────────────────────┐
        │                                                  │
   /todo-plan  ──▶  /todo-execute  ──▶  /todo-verify  ──▶  /todo-revise
     plan            do (build)         check (gate)       fix the gaps
        │                                  │                    │
        └── writes plan.md + tasks.md      └── ticks tasks,     └── loops back
                                               flips status,       until accepted
                                               opens Revisions
```

- **plan** — `/todo-plan` runs discovery and writes `plan.md` (goal, scope, decisions) and
  `tasks.md` (the checklist).
- **do** — `/todo-execute` works the checklist top to bottom, writing outputs to `artifacts/`.
  `/todo-execute-parallel` fans file-disjoint tasks out to worktree agents.
- **check** — `/todo-verify` drives an optional [verification MCP](#verification-mcp-optional)
  and reconciles the result into todo state.
- **revise** — `/todo-revise` reworks completed items against a captured gap, then re-verifies.

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
- creates a hub at `~/todo` from bundled seed content — `index.md`, `templates/`, and a
  small example project — via a SessionStart hook. It runs once, then stays quiet.

The hook creates a `~/todo` directory on first run; to put the hub elsewhere, set
`TODO_HUB` first (below).

### Removing it

```bash
claude plugin uninstall todo-list@todo-list      # remove the plugin (skills + hooks)
claude plugin marketplace remove todo-list       # remove the marketplace entry
```

(Both also work from the interactive `/plugin` menu.)

What's left on disk is the hub folder (`~/todo`, or wherever `TODO_HUB` points) — your own
plans and notes. Delete it whenever:

```bash
rm -rf ~/todo
```

### Optional config

- **Move the hub.** The hub defaults to `~/todo`. To put it elsewhere, set `TODO_HUB`
  (e.g. in `~/.claude/CLAUDE.md` or your shell profile) *before* first run:

  ```bash
  export TODO_HUB=~/my/hub/path
  ```

  Skills resolve every hub path against `TODO_HUB`, so they work even when invoked from
  inside another repo. See [`.env.example`](.env.example).
- **Version the hub.** The hub is a plain directory. `git init` it if you want history.

## Quickstart

The hub ships with an example project. In Claude Code:

```
/todo-list                              # see the project index
/todo-refer example-feature             # load its plan + tasks as context
/todo-execute example-feature           # work its checklist
/todo-infographic example-feature       # render a one-page visual of the plan
```

Start your own with `/todo-add "add rate limiting to the API"`, then `/todo-plan <name>`.

> Slash commands are namespaced by the plugin — `/todo-list:todo-plan` — but each skill's
> natural-language triggers ("plan this project", "what's on my list") fire without the
> prefix.

## Layout

The plugin repo:

```
.claude-plugin/
  plugin.json        the plugin manifest
  marketplace.json   makes this repo installable as a marketplace
skills/todo-*/       the 14 /todo-* skills (each a SKILL.md) + skills/README.md
hooks/
  hooks.json         registers the two hooks below (auto)
  bootstrap-hub.sh   SessionStart: seed the hub on first run
  infographic-staleness.sh   Stop: nudge stale infographics
seed/                copied to $TODO_HUB on first run ↓
```

The hub (created at `$TODO_HUB`, default `~/todo`) from `seed/`:

```
index.md             the registry: short-name → path / repo / status / infographic
CLAUDE.md            instructions Claude reads when working in the hub
templates/           plan.md · tasks.md · planning-prompt.md — copied for new projects
projects/
  work/              work projects
  self-initiative/   self-driven / research projects
```

Each project folder holds `plan.md` (source of truth), `tasks.md` (the checklist),
`research/` (raw notes), and `artifacts/` (outputs).

## The skills

| Skill | Purpose |
|---|---|
| `todo-add` | Scaffold a new project folder + register it in `index.md` |
| `todo-plan` | Discovery → write `plan.md` and `tasks.md` |
| `todo-execute` | Work `tasks.md`, write outputs to `artifacts/` |
| `todo-execute-parallel` | Fan file-disjoint tasks to worktree agents, land PRs via a serial merge queue |
| `todo-verify` | The check gate: drive a verification MCP, tick tasks / flip status, open Revisions |
| `todo-revise` | Gap-driven rework of completed items, then re-verify |
| `todo-update-state` | Mark tasks/projects done, move status |
| `todo-list` | Read-only overview of the index, grouped by status |
| `todo-sort` | Reorder `index.md` rows by task completion |
| `todo-triage` | Tabulate open work + recommend a model per item |
| `todo-refer` | Load a project's plan+tasks as grounding context (cross-repo) |
| `todo-infographic` | Turn a plan into a one-page HTML infographic |
| `todo-push` | General git shipping workflow: branch → commit → push → PR → merge |
| `todo-learn` | Capture a correction as a durable rule in a repo's own skill files |

Status lifecycle: `planning → ready → in-progress → done`.

Some skills note a suggested Claude model (e.g. mechanical steps on Haiku, judgment work on
Sonnet). Those are advisory conventions, not requirements — adjust to taste.

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
