# Changelog

All notable changes to this plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[semver](https://semver.org). Installed users only receive an update when the
`version` in `.claude-plugin/plugin.json` is bumped — see CONTRIBUTING.md § Releasing.

## [1.2.0] — 2026-07-21

### Added
- Project date tracking: `started` / `completed` / `elapsed (days)` columns in `index.md`
  section tables, stamped on status flips per `todo-update-state` Step 3.5 (priority chain
  `in-progress` > `ready` > `planning` > `completed`; cleared on reopen).
- `hooks/migrate-index-dates.sh` SessionStart hook: automatically widens pre-2.0
  six-column `index.md` tables on the next session and backfills the dates from the hub's
  git history (first/last commit touching each project path); hubs without git get `-`.
  A backup is left at `index.md.pre-dates.bak`.

### Changed
- **Hub format (auto-migrated):** `index.md` section tables went from six to
  nine columns. `todo-add`/`todo-plan`/`todo-execute`/`todo-verify`/`todo-sync`/`todo-list`
  read and stamp the new columns; `todo-list` keeps them out of the default compact view.
  Existing hubs are upgraded in place by the SessionStart migration hook — no manual step.

## [1.1.0] — 2026-07-19

### Added
- Infographic feedback loop: stable section IDs (`W1`/`D#`/`F#`/`X#`/`L#`) on every
  reviewable element, quotable in chat and resolvable by `/todo-revise`.
- Infographic sections: What & why, git-derived file footprint tree (added/modified/removed),
  trade-off ledger (gain·cost per decision), forgone alternatives, known limitations.
- `plan.md` template: `## Trade-offs` section (gain·cost rows, forgone, known gaps);
  `/todo-plan` captures rejected alternatives during discovery.
- `session-handoff` and `infographic-scope` learned-convention skills.

### Changed
- Skills refactored for model routing (tier-first: frontier/deep/balanced/fast) and
  execution tiers per skill.
- `/todo-infographic` scoped to single-project by default; `all` is explicit opt-in.

### Fixed
- Global Codex skill installation.

## [1.0.0] — 2026-07-10

Initial release: 16 `/todo-*` skills plus `model-routing`, self-bootstrapping hub
(SessionStart hook seeds `~/todo`), infographic staleness Stop hook, Claude Code and
Codex plugin manifests, repo doubles as its own marketplace.
