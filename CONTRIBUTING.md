# Contributing to todo-list

Thanks for your interest. This project is a set of cross-platform Agent Skills for
Claude Code and Codex — plain markdown, no build system — so contributing is mostly
writing and refining prompts.

## How a skill works

Each skill lives in `skills/<name>/SKILL.md` and starts with YAML frontmatter:

```yaml
---
name: todo-example
description: Use when the user invokes /todo-example, says "...", or wants X. One or two
  sentences describing exactly when an agent should reach for this skill.
---
```

- **`name`** must match the folder name and is what the user types as `/name`.
- **`description`** is the trigger. The agent picks a skill by matching the user's intent
  against these — make it specific, list the phrasings that should fire it, and say what it
  does *not* do. This is the single most important line for the skill working at all.

The body is the instructions the agent follows when the skill runs. Write it as a clear,
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
- **Model routing is tier-first.** Use `frontier`, `deep`, `balanced`, or `fast` in skill
  instructions and keep provider names in `skills/model-routing/SKILL.md`.
- **Keep skills self-contained.** A reader (human or model) should understand one SKILL.md
  without loading the others.

## Repo layout

This repo packages the same skills for both agents:

- `.claude-plugin/plugin.json` — Claude Code manifest; bump `version` on release.
- `.claude-plugin/marketplace.json` — makes the repo installable.
- `.codex-plugin/plugin.json` — Codex manifest; keep its version aligned.
- `skills/todo-*/SKILL.md` — the skills (auto-discovered).
- `hooks/` — `hooks.json` (auto-registered) plus `bootstrap-hub.sh` (SessionStart, seeds
  the hub) and `infographic-staleness.sh` (Stop).
- `seed/` — copied to `$TODO_HUB` on first run: `index.md`, `AGENTS.md`, `CLAUDE.md`, `templates/`, and
  the example project. Anything a fresh hub should contain goes here.

## Adding a skill

1. Create `skills/todo-<name>/SKILL.md` with the frontmatter above.
2. Add a row to the table in `skills/README.md` and, if user-facing, the one in the root
   `README.md`.
3. If it introduces a new convention, note it here.

## Testing a change

There's no automated suite — these are prompt files. To exercise a change:

1. Install the skills from your local checkout for both agents:

   ```bash
   npx skills add . --skill model-routing todo-add todo-archive todo-execute \
     todo-infographic todo-learn todo-list todo-plan todo-push todo-refer \
     todo-resume todo-review todo-revise todo-sync todo-triage todo-update-state \
     todo-verify --agent claude-code --agent codex --global --yes
   ```

2. To test the Claude Code hooks and bootstrap path, install the full plugin:

   ```bash
   claude plugin marketplace add /absolute/path/to/todo-list
   ```
   ```
   /plugin install todo-list@todo-list
   ```

3. Invoke the skill from Claude Code or Codex against `example-feature`, or a scratch
   project scaffolded with `todo-add`.
4. Confirm it does what the description promises and touches only the files it should.

To test the bootstrap hook in isolation, run it against a throwaway hub:

```bash
CLAUDE_PLUGIN_ROOT="$(pwd)" TODO_HUB=/tmp/hub-test bash hooks/bootstrap-hub.sh
```

## Releasing

Pushing commits does **not** update installed users — Claude Code treats the `version`
string in `.claude-plugin/plugin.json` as the release key. A change ships when you:

1. **Bump `version`** in `.claude-plugin/plugin.json` (semver: MAJOR = breaking skill
   behavior or hub-format change, MINOR = new skill/section/capability, PATCH = prompt
   fixes and wording).
2. **Mirror the same version** in `.codex-plugin/plugin.json`.
3. **Move the `[Unreleased]` entries** in `CHANGELOG.md` under a new `## [x.y.z] — <date>`
   heading. Every user-visible change lands in `[Unreleased]` in the same PR that makes it.
4. Push. Users with auto-update enabled for the marketplace get a notification prompting
   `/reload-plugins`; others pick it up via `/plugin marketplace update todo-list`.

Unbumped commits are fine — they simply accumulate as the next release.

## Pull requests

- One focused change per PR. Explain what triggered it and what behavior changes.
- Don't include anything machine- or organization-specific (absolute personal paths, real
  project data, internal tool names). Use `$TODO_HUB` and neutral example names.
- Keep the diff readable — match the surrounding prose style.
