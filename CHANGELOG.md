# Changelog

All notable changes to this plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[semver](https://semver.org). Installed users only receive an update when the
`version` in `.claude-plugin/plugin.json` is bumped — see CONTRIBUTING.md § Releasing.

Entries are one line per user-visible change. Why a change was made lives in its pull
request; how it works lives in the diff.

## [Unreleased]

### Changed
- **`/todo-push` checks the active GitHub account can write to the repo.** Preflight reads
  the account's permission and stops — naming the account and repo — instead of branching,
  committing and pushing only for `gh pr create` to fail on access.

## [1.10.0] — 2026-08-04

### Changed
- **`/todo-push` runs its git sequence from two scripts.** `preflight.sh` reports repo facts
  read-only and fails before anything mutates; `land.sh` owns branch-through-merge, commits
  only files named explicitly, and hands control back on a blocked merge or a real conflict.
- **`/todo-push` matches the merge style a repo actually uses**, not just what it permits —
  a squash-only history no longer gets a merge commit.
- **The `frontier` tier routes to Fable 5.0 at high effort** on Claude Code, replacing
  Opus 5.0 at max effort.

## [1.9.1] — 2026-08-03

### Added
- **README: why the installer shows risk warnings.** Explains the amber badges printed by
  `npx skills add`, in the scanners' own words, and names what each flagged capability is for.
- **README: `## Update`.** Gives the two commands needed to move onto a new release.

### Changed
- **Six skills validate placeholders before they reach a shell command line.** Short-names
  must be lowercase kebab-case, relation words come from an allowlist, and repo paths and
  branch names carry no shell metacharacters; a failing value stops the command.
- **`/todo-push` no longer trusts handed-down commands.** A prepended branch name or test
  command is checked against the repo's own files before it runs.
- **README reworded in the plainer house voice**, with the skill catalog grouped by purpose.

## [1.9.0] — 2026-08-03

### Added
- **`/todo-style`: new `WRITING STYLE` section.** Both packs now ask for conversational
  English with technical terms only where they are the correct name, and carry a good/bad pair.

### Changed
- **Four duplicated rule statements collapsed to one each** in `AUDIENCE`, `GROUND RULES`
  and `VISUAL FIRST` — first-use naming, plain wording and the bullets trigger each appear once.

## [1.8.x] — 2026-07-28 → 2026-07-30

### Added
- **`/todo-review-handoff` — package a review so someone else can rule on it.** Each finding
  is a numbered falsifiable claim with a confidence grade and a verification method, ending in
  a ruling sheet whose columns include *the reviewer is wrong*. Hub-optional; never fixes code.
- **`bootstrap-hub.sh` backfills every missing hub doc and template,** and
  `hooks/migrate-registry-preamble.sh` strips prose preambles from an existing `index.md`
  behind a `.pre-preamble.bak`. Registries are reported, never overwritten.

### Changed
- **`/todo-style`: sixteen invented terms replaced with plain words** — `➡️ YOUR CALL` →
  `➡️ CHOOSE`, `Does:`/`Trade:` → `Action:`/`Trade-off:`, `CORE` → `GROUND RULES`,
  `SOLUTION SPINE` → `PROPOSING A FIX`, and no metaphor where a plain word exists.
- **Bullets are the stated default shape** — they trigger at two sentences in a row, a
  `**label:**` line is capped at one line, and below-the-fold evidence is always a `---` rule
  plus `### Technical detail` (the `<details>` accordion is gone).
- **A `CHOOSE` block must be answerable** — required `What this is about:` line, no
  invented code names before the last option, length caps on options and table cells, and a
  fixed `Suggestion:`/`Reason:` recommendation that may argue against the alternatives.
- **The packs govern replies, not what you write into a repo.** Commit messages, changelogs,
  docs and code comments follow that repo's own conventions; release notes are one bullet per
  change, two lines at most (CONTRIBUTING.md § Releasing).
- **Both packs cut by about a sixth** — 8,460 → 7,010 tokens, every rule and worked example
  kept. `seed/index.md`, `seed/AGENTS.md`, `seed/REGISTRY.md` and `seed/archive.md` are data
  only, carrying the registries-are-data routing table. Existing hubs untouched.

### Fixed
- `tests/style-contract.sh` still required the `<details>` rule these releases deleted and had
  been failing on `main`; `.codex-plugin/plugin.json` was stuck at `1.7.0` against `1.7.1`.

## [1.7.0] — 2026-07-27

### Added
- **`/todo-style` — an opt-in response-style pack for both agents.** 16 skills → 17. Installs
  one pack per harness: `~/.claude/CLAUDE.md` or `~/.codex/AGENTS.md`.
  - The existing file is byte-verified into `$TODO_HUB/backups/agent-instructions/` before
    anything is overwritten; a failed backup aborts without writing, and backups are never deleted.
  - `status`, `diff`, `install`, `restore` and `list-backups` run through
    `skills/todo-style/scripts/agent-style.sh`. No hook fires it; an explicit yes is required.
  - Covered by `tests/style-contract.sh`, sandboxed so it never touches real instruction files.

### Note
- `skills/todo-style/assets/CLAUDE.md` is user-scoped and is **not** `seed/CLAUDE.md`, which
  is hub-scoped. Same filename, different destination.

## [1.6.0] — 2026-07-27

### Fixed
- `hooks/infographic-staleness.sh` resolves the hub from `$TODO_HUB` like every other hook,
  so the staleness nudge reaches cross-repo and worktree sessions. Covered by the new
  `tests/infographic-hook-contract.sh`.
- The task-counting snippet in `todo-state`, `todo-list` and `todo-infographic` skips
  `## Notes` / `## Context` and fenced code blocks, so completion ratios agree everywhere.

### Changed
- Hub self-description corrected in ten skills: `$TODO_HUB` is your hub folder, not a clone
  of this repo.
- Provider model names retreat behind the tier layer in `todo-push` and `todo-triage`.
- `templates/plan.md` gains the `## Repo` section every skill already expected.

### Removed
- `seed/templates/planning-prompt.md` — orphaned, and it disagreed with `/todo-plan`.

### Upgrade note
- Global skill installs made before 1.5.0 still carry the removed `todo-resume`, `todo-sync`
  and `todo-update-state` skills. Delete those folders from your global skills directory.
  Native plugin installs are unaffected.

## [1.5.0] — 2026-07-27

### Removed
- `/todo-resume`, `/todo-sync` and `/todo-update-state` as standalone skills. 18 → 16. The old
  names still route correctly via the surviving skills' descriptions.

### Changed
- **`/todo-resume` merged into `/todo-refer` as `resume` mode.**
- **`/todo-update-state` + `/todo-sync` merged into `/todo-state`,** with `audit` and
  `audit fix` modes. Date stamping moved to `todo-state` § Date stamping, now the hub-wide
  authority.
- The documented `npx skills add` command drops `--skill`; installer discovery replaces the
  hand-maintained name list.
- Repo-local convention skills are marked `metadata: internal: true` so they never ship, and
  `/todo-learn` writes that flag into every topic skill it creates.
- `tests/package-contract.sh` asserts the no-`--skill` command, internal marking,
  byte-identical `.claude/skills/` mirrors, and the `todo-` prefix on every public skill.

## [1.4.0] — 2026-07-27

### Added
- **`/todo-graph`** compiles `plan.md` relationships into a ready frontier, blocker chains,
  impact, dependency paths, integrity audits, validated edge edits, and TSV / JSON exports.
- Plans carry an optional typed `## Relationships` table — `depends-on` schedules,
  `related-to` and `supersedes` are context only.
- A read-only SessionStart archive-candidates report, which never blocks or edits.
- `/todo-refer <project> R<n>` history lookup via a stable journal anchor.

### Changed
- Six skills consume bounded graph queries instead of guessing cross-project order from prose.
- Graph queries fail closed on corruption and invalid hard prerequisites; cycle detection,
  bounded search and symlink containment cover deep or adversarial hubs.
- `index.md` is the active registry; completed rows move losslessly to cold `archive.md`.
- Revision-state matching is case-insensitive and supports suffixed IDs.

## [1.3.0] — 2026-07-25

### Changed
- **Breaking (skill rename):** `model-routing` → `todo-llm-routing`. Re-run `npx skills add`
  with the new name and delete the stale skill.
- **Claude Code routing collapsed onto Opus at all four tiers,** with reasoning effort as the
  only lever: `frontier` = max, `deep` = high, `balanced` = medium, `fast` = low, per
  [CursorBench 3.2](https://cursor.com/cursorbench). Every tier now draws on the same Opus
  allowance, so `fast`-tier work no longer relieves usage limits. Codex mappings unchanged.

## [1.2.0] — 2026-07-21

### Added
- Project date tracking: `started` / `completed` / `elapsed (days)` columns in `index.md`.
- `hooks/migrate-index-dates.sh` widens pre-2.0 six-column tables on the next session and
  backfills dates from the hub's git history, leaving an `index.md.pre-dates.bak`.

### Changed
- **Hub format (auto-migrated):** `index.md` section tables went six → nine columns. Existing
  hubs upgrade in place, with no manual step.

## [1.1.0] — 2026-07-19

### Added
- Infographic feedback loop: stable section IDs (`W1`/`D#`/`F#`/`X#`/`L#`), quotable in chat
  and resolvable by `/todo-revise`.
- Infographic sections: what & why, git-derived file footprint, trade-off ledger, forgone
  alternatives, known limitations.
- `plan.md` gains `## Trade-offs`; `/todo-plan` captures rejected alternatives.
- `session-handoff` and `infographic-scope` learned-convention skills.

### Changed
- Skills refactored for tier-first model routing (frontier / deep / balanced / fast).
- `/todo-infographic` scoped to single-project by default; `all` is opt-in.

### Fixed
- Global Codex skill installation.

## [1.0.0] — 2026-07-10

Initial release: 16 `/todo-*` skills plus `model-routing`, self-bootstrapping hub
(SessionStart hook seeds `~/todo`), infographic staleness Stop hook, Claude Code and
Codex plugin manifests, repo doubles as its own marketplace.
