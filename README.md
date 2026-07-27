# todo-list

**A project tracker that Claude Code or Codex works through for you.** Describe a project
once; the agent plans it, works the checklist, checks the result, and fixes the gaps.
Everything is plain markdown you can read and edit yourself — no build step, no runtime,
no database.

## The concept

One hub — a single folder (default `~/todo`) that tracks *all* your projects, separate
from the repos where the real code lives:

```
~/todo/
  index.md                     ← active projects, one row each
  archive.md                   ← completed rows, kept not deleted
  REGISTRY.md                  ← what each registry column means
  projects/
    work/api-rate-limiting/
      plan.md                       goal, scope, decisions
      tasks.md                      the checklist the agent works through
      artifacts/                    outputs the agent produces
```

Each project folder *points at* wherever its code lives. Your repos stay untouched until
you ask the agent to execute.

Four skills form a `plan → do → check → revise` loop:

```
/todo-plan  ──▶  /todo-execute  ──▶  /todo-verify  ──▶  /todo-revise
  plan             do (build)         check (gate)       fix the gaps
                                                              │
                                          loops back until accepted
```

A typical project, end to end:

```
/todo-add "add rate limiting to the API"   # scaffold + register it
/todo-plan api-rate-limiting               # research and write the plan
/todo-execute api-rate-limiting            # work the checklist
/todo-verify api-rate-limiting             # did it actually pass?
/todo-revise api-rate-limiting             # fix whatever the check caught
```

Stopped halfway? `/todo-refer api-rate-limiting resume` rebuilds where you left off.

When one project waits on another, say so once and the agent schedules around it:

```
/todo-graph link api-migration depends-on auth-foundation "consumes its token contract"
/todo-graph                                # what's ready to start right now
```

## Install

**Claude Code** — two commands; this repo is its own marketplace:

```bash
claude plugin marketplace add ferterahadi/todo-list
```
```
/plugin install todo-list@todo-list
```

On the next session it registers the `/todo-*` skills and creates the hub at `~/todo`
with an example project. It never overwrites an existing hub.

**Skills only, Claude Code + Codex** — one command, no hooks and no hub bootstrap:

```bash
npx skills add ferterahadi/todo-list --agent claude-code --agent codex --global --yes
```

**Move the hub** — set `TODO_HUB` in your shell profile *before* the first run:

```bash
export TODO_HUB=~/my/hub/path
```

### Try it

```
/todo-list                              # see the project index
/todo-refer example-feature             # load its plan + tasks
/todo-execute example-feature           # work its checklist
```

> In Claude Code, slash commands are namespaced by the plugin: `/todo-list:todo-plan`.
> In Codex, mention `$todo-plan` or just describe what you want.

## The 17 skills

**Track** — get projects in, see where they stand

|Skill|Purpose|
|-|-|
|`todo-add`|Scaffold a new project folder + register it|
|`todo-list`|Overview of the index by status; also `archive` and `sort`|
|`todo-triage`|Tabulate open work across projects + recommend a model per task|
|`todo-state`|Tick tasks / flip status by hand; `audit` cross-checks against git reality|

**Work** — the loop, and the graph over the loops

|Skill|Purpose|
|-|-|
|`todo-plan`|Discovery → write `plan.md` and `tasks.md`|
|`todo-execute`|Work the checklist; `parallel` fans tasks out to git-worktree agents|
|`todo-graph`|Declare which projects block which; ask what's ready, what's blocked, why|
|`todo-review`|Audit a diff against the plan — scope drift, missing evidence|
|`todo-verify`|The check gate: run the tests, tick tasks, open Revisions on failures|
|`todo-revise`|Rework what the gate caught, then re-verify|

**Bridge** — connect the hub to real repos

|Skill|Purpose|
|-|-|
|`todo-refer`|Load project context from any repo; `resume` reconstructs where work stopped|
|`todo-push`|Full git shipping workflow: branch → commit → push → PR → merge|
|`todo-infographic`|Turn a plan into a one-page HTML infographic|
|`todo-learn`|Capture a correction as a durable rule in a repo's own skill files|

**Hygiene and support**

|Skill|Purpose|
|-|-|
|`todo-archive`|Retire done rows to `archive.md` — lossless, nothing is deleted|
|`todo-style`|Swap in the bundled response-style pack for Claude Code and Codex, backing up your current file first|
|`todo-llm-routing`|Shared config: which model each skill asks for|

Status lifecycle: `planning → ready → in-progress → done`. Each skill's full contract
lives in [`skills/`](skills/).

**It enhances your other skills, it doesn't replace them.** When you have craft skills
installed (superpowers brainstorming / test-driven-development, code-review, dataviz, …),
the todo skills call *those* for the thinking. If none are installed, every todo skill
carries its own fallback.

## Optional: the response-style pack

Every other skill organizes *work*. `/todo-style` is the one that changes how the agent
*talks* — a formatting and briefing pack for readers who are technical but short on time:
meaning before evidence, visuals over prose, an explicit decision block whenever something
is yours to call, and a closing verdict that names what's still open.

```
/todo-style            # what's installed now vs what ships
/todo-style diff       # exactly which lines would change
/todo-style install    # back up, then swap in
/todo-style restore    # put your old file back
```

It writes to your **global** agent instruction file — `~/.claude/CLAUDE.md` for Claude
Code, `~/.codex/AGENTS.md` for Codex (same rules, ported per harness). Three guardrails,
because that file is usually hand-tuned:

- It replaces the file wholesale; it never merges. `/todo-style diff` shows you that first.
- Your current file is copied to `$TODO_HUB/backups/agent-instructions/` and byte-verified
  **before** anything is overwritten. A failed backup aborts the install.
- Nothing in that folder is ever deleted, and `restore` puts the newest one back.

Entirely opt-in — no hook runs it, no other skill calls it, and the rest of the plugin
behaves identically whether or not you install it.

## Remove it

```bash
claude plugin uninstall todo-list@todo-list      # remove the plugin (skills + hooks)
claude plugin marketplace remove todo-list       # remove the marketplace entry
```

What's left on disk is the hub — your own plans and notes. Delete it whenever:

```bash
rm -rf ~/todo    # or wherever TODO_HUB points
```

## More

- [CHANGELOG.md](CHANGELOG.md) — releases. Third-party marketplaces have auto-update off
  by default; enable it via `/plugin` → Marketplaces → todo-list, or pull manually with
  `/plugin marketplace update todo-list`.
- [`skills/todo-verify/SKILL.md`](skills/todo-verify/SKILL.md) — `/todo-verify` drives any
  MCP (Model Context Protocol) test server matching a small contract. No server? Omit the
  `## Verification` block from `plan.md`; the rest of the loop still runs.
- [CONTRIBUTING.md](CONTRIBUTING.md) — issues and pull requests welcome.

MIT licensed — see [LICENSE](LICENSE).
