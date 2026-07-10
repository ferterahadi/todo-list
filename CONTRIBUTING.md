# Contributing to todo-list

Thanks for your interest. This project is a set of [Claude Code](https://claude.com/claude-code)
skills — plain markdown, no build system — so contributing is mostly writing and refining
prompts.

## How a skill works

Each skill lives in `skills/<name>/SKILL.md` and starts with YAML frontmatter:

```yaml
---
name: todo-example
description: Use when the user invokes /todo-example, says "...", or wants X. One or two
  sentences describing exactly when Claude should reach for this skill.
---
```

- **`name`** must match the folder name and is what the user types as `/name`.
- **`description`** is the trigger. Claude picks a skill by matching the user's intent
  against these — make it specific, list the phrasings that should fire it, and say what it
  does *not* do. This is the single most important line for the skill working at all.

The body is the instructions Claude follows when the skill runs. Write it as a clear,
ordered procedure. Look at the existing skills for the house style: numbered steps,
explicit invariants, terse examples.

## Conventions

- **Resolve hub paths against `$TODO_HUB`** (default `~/todo`) — never hardcode an absolute
  path. Skills may be invoked from inside another repo, so they can't assume the current
  working directory is the hub.
- **`tasks.md` is a checklist, not a journal** — one line per task (~150 chars). Detail goes
  to `research/` or `artifacts/` with a pointer.
- **`plan.md` stays the source of truth.** Derived views (the infographic, the index row)
  reflect it; they don't replace it.
- **Model pins are advisory.** Where a skill suggests a Claude model/effort, treat it as a
  cost/quality hint, not a hard dependency.
- **Keep skills self-contained.** A reader (human or model) should understand one SKILL.md
  without loading the others.

## Repo layout

This repo is a Claude Code plugin *and* its own marketplace:

- `.claude-plugin/plugin.json` — the manifest; bump `version` when you cut a release.
- `.claude-plugin/marketplace.json` — makes the repo installable.
- `skills/todo-*/SKILL.md` — the skills (auto-discovered).
- `hooks/` — `hooks.json` (auto-registered) plus `bootstrap-hub.sh` (SessionStart, seeds
  the hub) and `infographic-staleness.sh` (Stop).
- `seed/` — copied to `$TODO_HUB` on first run: `index.md`, `CLAUDE.md`, `templates/`, and
  the example project. Anything a fresh hub should contain goes here.

## Adding a skill

1. Create `skills/todo-<name>/SKILL.md` with the frontmatter above.
2. Add a row to the table in `skills/README.md` and, if user-facing, the one in the root
   `README.md`.
3. If it introduces a new convention, note it here.

## Testing a change

There's no automated suite — these are prompt files. To exercise a change:

1. Install the plugin from your local checkout, then reinstall after edits:

   ```bash
   claude plugin marketplace add /absolute/path/to/todo-list
   ```
   ```
   /plugin install todo-list@todo-list
   ```

2. Invoke the skill from Claude Code against the example project the hub seeds
   (`example-feature`), or a scratch project you scaffold with `/todo-add`.
3. Confirm it does what the description promises and touches only the files it should.

To test the bootstrap hook in isolation, run it against a throwaway hub:

```bash
CLAUDE_PLUGIN_ROOT="$(pwd)" TODO_HUB=/tmp/hub-test bash hooks/bootstrap-hub.sh
```

## Pull requests

- One focused change per PR. Explain what triggered it and what behavior changes.
- Don't include anything machine- or organization-specific (absolute personal paths, real
  project data, internal tool names). Use `$TODO_HUB` and neutral example names.
- Keep the diff readable — match the surrounding prose style.
