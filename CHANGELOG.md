# Changelog

All notable changes to this plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[semver](https://semver.org). Installed users only receive an update when the
`version` in `.claude-plugin/plugin.json` is bumped — see CONTRIBUTING.md § Releasing.

## [1.3.0] — 2026-07-25

### Changed
- **Breaking (skill rename):** `model-routing` → `todo-llm-routing`. Every `/todo-*` skill,
  `README.md`, `skills/README.md`, and `CONTRIBUTING.md` now point at the new path. Anyone who
  installed by name must re-run `npx skills add` with `todo-llm-routing` in place of
  `model-routing`, and remove the stale `model-routing` skill.
- **Claude Code routing collapsed onto Opus at all four tiers**, with reasoning effort as the
  only lever: `frontier` = max, `deep` = high, `balanced` = medium, `fast` = low. Per
  [CursorBench 3.2](https://cursor.com/cursorbench), the Opus 5 effort sweep Pareto-dominates
  the rest of the Claude lineup — Sonnet 5 at max effort (60.5% @ ~$6.6) scores below Opus 5 at
  low effort (62.3% @ ~$2.8), and Opus 5 max (69.6% @ ~$8.2) beats the previous `frontier`
  default of Fable 5 high (65.5% @ ~$8.6) on both accuracy and cost. Sonnet and Haiku are no
  longer defaults at any tier; Fable is worth hand-picking only at max effort.
  Codex tier mappings are unchanged — CursorBench does not plot Terra or Luna.

  Note that the quota profile shifts: all tiers now draw on the same Opus allowance, so
  `fast`-tier work no longer relieves usage limits.

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
