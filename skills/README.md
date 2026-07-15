# todo-* skills

The `/todo-*` skills that drive the hub. They follow the shared Agent Skills format and
ship in both the Claude Code and Codex packages — see the [root README](../README.md) for
installation. Claude Code slash commands are plugin-namespaced, for example
`/todo-list:todo-plan`; natural-language triggers and Codex `$skill` mentions use each
skill's `description`.

House rule: these skills **enhance installed skills, never replace them** — they own the
organization (hub paths, file formats, statuses) and delegate the craft to whatever
process skills the session has (superpowers brainstorming / TDD / systematic-debugging /
finishing-a-development-branch, code-review, dataviz, …), each with a complete built-in
fallback when nothing relevant is installed.

| Skill | Purpose |
|-------|---------|
| `todo-list` | Show the project index — at-a-glance view of all tracked projects, grouped by status (read-only); `sort` mode reorders `index.md` rows by task completion, most-done first (fast tier) |
| `todo-triage` | Tabulate what's left across projects and recommend frontier/deep/balanced/fast tier · effort · skill pairing per item (read-only; fast-tier gathering, routing judgment inline) |
| `todo-refer` | Load a project's `plan.md`+`tasks.md` into the current session as grounding context, plus a one-line goal digest for each project listed in its `related` column — cross-repo, read-only (run before `/code-review` etc. from another codebase) |
| `todo-resume` | Reconstruct where a project's work stopped — open tasks, last journal entry, blockers, worktree/branch/PR state — and recommend the next command (read-only, cross-repo) |
| `todo-add` | Scaffold a new project folder + register it in `index.md` (fast tier) |
| `todo-plan` | Write `plan.md` and `tasks.md` for a project |
| `todo-execute` | Work through `tasks.md`, write outputs to `artifacts/`; `parallel` mode fans file-disjoint tasks out to agents in git worktrees of the target repo (no model pin — both implement and review waves inherit the session model), then lands PRs via a serial merge queue |
| `todo-review` | Review a repo's diff against the project's plan — scope drift, violated constraints, ticked tasks with no evidence — then a correctness pass via the installed `code-review` skill (report-only) |
| `todo-update-state` | Mark tasks/projects done, move status (fast tier) |
| `todo-verify` | The "check" gate: drive a record-only verification run, tick tasks / flip status on green, open Revisions entries on failures or coverage gaps (balanced tier, high effort) |
| `todo-revise` | Gap-driven rework: review done items, capture feedback per item, plan + run fixes, verify |
| `todo-sync` | Audit recorded state vs reality: cross-check `index.md` status against `tasks.md` and target-repo git/PR evidence, report drift, fix only on confirmation (fast-tier gathering; verdicts inline) |
| `todo-archive` | Batch housekeeping: move `[done]` revision detail from `tasks.md` to `artifacts/journal.md` tombstones, retire done projects to an `## Archive` index section — lossless (fast tier) |
| `todo-learn` | Capture a correction as one shared repo skill under `.agents/skills/` and `.claude/skills/` (balanced tier, high effort) |
| `todo-infographic` | Turn a plan into a one-page HTML infographic, fresh theme each time (+ staleness hook). Generation uses balanced tier, high effort |
| `todo-push` | General-purpose git shipping workflow (any repo): branch off main, commit, push, PR, merge, land back on main (fast tier) |

Status lifecycle: `planning → ready → in-progress → done`. The `plan → do → check → revise`
loop is `todo-plan` → `todo-execute` → `todo-verify` → `todo-revise`, with `todo-review`
as an optional intent check between do and check, and `todo-resume` / `todo-sync` /
`todo-archive` keeping multi-session work continuable, honest, and compact.

## Install

Install all skills in both agents from the repo root:

```bash
npx skills add . --skill model-routing todo-add todo-archive todo-execute \
  todo-infographic todo-learn todo-list todo-plan todo-push todo-refer \
  todo-resume todo-review todo-revise todo-sync todo-triage todo-update-state \
  todo-verify --agent claude-code --agent codex --global --yes
```

See the [root README](../README.md) for native plugin installation when lifecycle hooks
and hub bootstrapping are also required.

## Bundled hooks (auto-registered)

The plugin ships three hooks in [`../hooks/`](../hooks/), registered automatically via
`hooks/hooks.json` on install:

- **`bootstrap-hub.sh`** (SessionStart) — creates the hub at `$TODO_HUB` (default `~/todo`)
  from the plugin's `seed/` on first run; silent thereafter.
- **`infographic-staleness.sh`** (Stop) — when a `ready`/`in-progress` project has a
  missing or stale `artifacts/infographic.html`, nudges the agent to regenerate it via
  `todo-infographic` before the turn ends. It self-scopes: it only acts when the current
  project has an `index.md` (i.e. you're working in the hub), so it's quiet everywhere else.
- **`superpowers-doc-sync.sh`** (Stop) — ensures superpowers plans/specs written into a
  target repo get a pointer row in the project's `research/superpowers-docs.md`.

## Editing a skill

These files are the source. Edit them here and reinstall/refresh the plugin to pick up
changes. See [CONTRIBUTING.md](../CONTRIBUTING.md) for the local-development loop.
