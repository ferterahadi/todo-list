# Changelog

All notable changes to this plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[semver](https://semver.org). Installed users only receive an update when the
`version` in `.claude-plugin/plugin.json` is bumped — see CONTRIBUTING.md § Releasing.

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
