# Contributing to todo-list

Thanks for your interest. This project is a set of cross-platform Agent Skills for
Claude Code and Codex — plain Markdown, no build system or service. Most behavior lives
in skill instructions; deterministic shell/Python helpers compile state outside model
context where accuracy or token cost matters.

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
- **Keep the hot/cold registries separate.** `index.md` contains active rows;
  `archive.md` contains completed rows under their original section. Resolve an exact
  short-name in the index first and search the archive only on a miss. A reopened row
  moves back atomically; it never exists in both files. Registry column semantics live in
  `seed/REGISTRY.md` — the registries themselves stay data, not manuals.
- **Registries are data, not reports.** `index.md` and `archive.md` hold the title, the
  preamble, the optional one-line `Start here` pointer, and the section tables — never a
  status banner, release note, or narrative paragraph. A skill that writes a registry
  writes a *row*; the one exception is `/todo-state`, which owns the `Start here` line.
  Status output belongs in the owning project's `artifacts/`. Full rule:
  `seed/REGISTRY.md` § *Registries are data, not reports*.
- **`tasks.md` is a checklist, not a journal** — one line per task (~150 chars). Detail goes
  to `research/` or `artifacts/` with a pointer.
- **Use stable revision anchors.** Journal entry `R4` gets
  `<a id="revision-r4"></a>` and its tombstone links to
  `artifacts/journal.md#revision-r4`. Readers accept historical level-two or level-three
  revision headings and case-insensitive status tags.
- **`plan.md` stays the source of truth.** Derived views (the infographic, the index row)
  reflect it; they don't replace it.
- **Project relationships are typed.** Canonical `depends-on`, `related-to`, and
  `supersedes` rows live in `plan.md` `## Relationships`. Only `depends-on` gates work;
  `blocks` is derived and never stored. The registry's legacy `related` values remain
  context-only.
- **Model routing is tier-first.** Use `frontier`, `deep`, `balanced`, or `fast` in skill
  instructions and keep provider names in `skills/todo-llm-routing/SKILL.md`.
- **Keep skills self-contained.** A reader (human or model) should understand one SKILL.md
  without loading the others.

## Repo layout

This repo packages the same skills for both agents:

- `.claude-plugin/plugin.json` — Claude Code manifest; bump `version` on release.
- `.claude-plugin/marketplace.json` — makes the repo installable.
- `.codex-plugin/plugin.json` — Codex manifest; keep its version aligned.
- `skills/todo-*/SKILL.md` — the skills (auto-discovered).
- `hooks/` — `hooks.json` plus SessionStart bootstrap, date migration, and
  archive-candidate reporting; Stop hooks handle infographic and external-doc drift.
- `seed/` — copied to `$TODO_HUB` on first run: `index.md`, `archive.md`, `REGISTRY.md`,
  `AGENTS.md`, `CLAUDE.md`, templates, and the example project. Anything a fresh hub should
  contain goes here.
- `skills/todo-style/assets/` — the response-style pack: `CLAUDE.md` and `AGENTS.md`, one
  per harness. These are *not* seed files. `seed/CLAUDE.md` and `seed/AGENTS.md` are
  hub-scoped and land in `$TODO_HUB`; these are user-scoped and land in
  `~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md`, and only when the user asks. Same
  filenames, different scope — keep the two straight when editing.

## Adding a skill

1. Create `skills/todo-<name>/SKILL.md` with the frontmatter above.
2. Add a row to the table in `skills/README.md` and, if user-facing, the one in the root
   `README.md`.
3. If it introduces a new convention, note it here.

## Testing a change

Most behavior lives in skill instructions, with contract tests for deterministic helpers
and packaging. To exercise a change:

1. Install the skills from your local checkout for both agents:

   ```bash
   npx skills add . --agent claude-code --agent codex --global --yes
   ```

   The command carries no `--skill` filter, so anything the installer discovers ships.
   Keep that safe: public skills live in `skills/todo-*/`, and any repo-local skill under
   `.agents/skills/` (or its `.claude/skills/` mirror) must set `metadata.internal: true`
   in its frontmatter so the installer skips it. `tests/package-contract.sh` enforces
   both rules.

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

Run `hooks/archive-candidates.sh` against throwaway fixtures as well. A clean or missing
hub must print nothing and exit zero. A candidate hub emits one deterministic line and
still exits zero. Cover `[done]` and `[DONE …]`, suffixed IDs such as `R72b`, unique
level-two and level-three journal targets, missing/duplicate targets, and an already
linked tombstone.

Run `tests/graph-contract.sh` for graph changes. It must prove that legacy `related`
hints never block, archived completion is checked against live task/revision evidence,
cycles and missing targets fail closed, exact names do not collapse (`api` ≠ `api-v2`),
and rejected link validation leaves the hub byte-for-byte unchanged.

Run `tests/style-contract.sh` for any change to `/todo-style` or its packs. It must prove
the two packs keep identical `## ` sections (the Codex file is a harness port, not a fork),
that an existing instruction file is byte-verified into `$TODO_HUB/backups/agent-instructions/`
before it is overwritten, that an already-current install and a redundant restore both
no-op without churning backups, that a user-edited file *is* backed up on restore, that
backups are only ever added, and that a bad agent or mode fails closed. It sandboxes
`CLAUDE_CONFIG_DIR` and `CODEX_HOME`, so it never touches the machine's real files.

Run `tests/infographic-hook-contract.sh` for staleness-hook changes. It must prove the
hub resolves from `TODO_HUB`, hub sessions report every stale `ready`/`in-progress`
project, target-repo and `<repo>-wt/*` worktree sessions report only their own project,
unrelated sessions stay silent, and stub plans, fresh infographics, and stop-hook
continuations never fire.

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
