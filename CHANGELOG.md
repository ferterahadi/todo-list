# Changelog

All notable changes to this plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[semver](https://semver.org). Installed users only receive an update when the
`version` in `.claude-plugin/plugin.json` is bumped — see CONTRIBUTING.md § Releasing.

## [Unreleased]

## [1.8.3] — 2026-07-28

### Added
- **`/todo-review-handoff` — package a review so someone else can rule on it.** A review
  handed over raw is a pile of opinions: the recipient can only trust it or ignore it, and
  a non-engineer cannot judge it at all. The skill converts each finding into a numbered
  **falsifiable claim** with a confidence grade and a verification method, specifies a
  script that prints plain-English evidence per claim, and emits a ruling sheet whose
  columns include *the reviewer is wrong*. Only accepted rows get fixed, by a second agent,
  from the same document.
  - It never reviews code itself and never applies a fix. Findings come from whatever is
    already available, in order: findings from the current session → `todo-review` (which
    adds plan compliance — scope drift, violated constraints, ticked tasks with no
    evidence) → the installed `code-review` skill → a self-run pass as fallback.
  - **Hub-optional.** A handoff is often about a pull request in a repo with no hub project
    — another team's, another product's. With a hub project, accepted rows feed
    `todo-revise`; without one, the output is a standalone brief for a second agent.
  - Judgment work, so it runs inline on the session model at the **deep** tier
    (`balanced` floor) rather than being farmed out.
  - Slots into the loop as the escape hatch on `todo-review`: `plan → do → check → revise`
    with `todo-review` as the optional intent check, and this skill for when the person who
    must rule on the findings isn't the person who ran the review. Listed in `README.md` and
    `skills/README.md`.

### Changed
- **`/todo-style`: below-the-fold evidence now has one form, not two.** The pack used to
  branch on surface — `<details>` accordion for Claude Desktop / artifacts / HTML, a
  `---` rule plus `### Technical detail` heading for the terminal — which meant the agent
  had to guess where its output would be read — and a wrong guess renders raw `<details>`
  markup at the reader. It is now the rule and heading, always, in every reply. Two
  coordinated edits in `skills/todo-style/assets/CLAUDE.md`
  (`CODE PLACEMENT`, and the `STUCK` block's below-the-fold line), plus the now-redundant
  *Below-the-fold evidence* row dropped from the surface-differences table in
  `skills/todo-style/SKILL.md`. This brings the Claude pack in line with
  `assets/AGENTS.md`, which already stated the single form — below the fold is no longer a
  surface difference between the two packs.

## [1.8.2] — 2026-07-28

### Added
- **Existing hubs now converge on the shipped seed, without ever losing content.**
  `bootstrap-hub.sh` used to add a missing `archive.md` or `REGISTRY.md` and then stop, so a
  hub created before a given release stayed behind it forever. It now backfills every
  missing doc and template — `AGENTS.md`, `CLAUDE.md`, `REGISTRY.md`, `templates/*` — and
  reports docs that differ from the shipped versions instead of replacing them. The seed's
  example project is still never recopied into an established hub.
  - The split that makes this safe: registries (`index.md`, `archive.md`) hold the user's
    project rows and are **never** overwritten; docs are added when missing and only
    *reported* when they differ, because the seed cannot tell a hub's own extension from a
    stale copy; `projects/` is never touched.
- **`hooks/migrate-registry-preamble.sh`** — a SessionStart migration that removes prose
  preambles from `index.md`, so an existing hub picks up the data-only format from 1.8.1
  rather than keeping the old eight-line header. Modelled on `migrate-index-dates.sh`:
  writes a `.pre-preamble.bak` first, is a no-op on an already-clean registry, and preserves
  the file mode.
  - It refuses to run if the rewrite would change the project-row count, and reports the
    number of rows kept. A blockquote directly under the title is preserved, so a hub that
    pins a pointer line there keeps it.
  - `archive.md` keeps its preamble by design — the rule for what may live there (only
    `done` projects with no open Revisions) is stated nowhere else.

### Changed
- **`seed/AGENTS.md`, `seed/REGISTRY.md` and `seed/archive.md` now carry the
  registries-are-data rule.** A registry is read on every hub-wide scan and edited narrowly,
  so prose there is paid for on every read and goes stale silently while still looking
  current. `REGISTRY.md` gains a *Registries are data, not reports* section with the routing
  table for what to record where — handoff, `journal.md`, `blockers.md`, `## Revisions` —
  and `AGENTS.md` states the rule at the entry point.

## [1.8.1] — 2026-07-28

### Changed
- **`/todo-style`: a recommendation may now argue against the alternatives.** The pack used
  to cap this at "one decisive sentence… expand only if asked", which compressed the whole
  case for a pick into a one-line `**Trade:**` field. In a live incident session four
  candidate fixes were weighed, two shipped, and the reader still had to ask outright for
  the pros and cons — because the distinction that decided it (one fix converts a data loss
  into a delay; another can only reduce how often the loss happens) had nowhere to go.
  Six coordinated edits per pack, in both `skills/todo-style/assets/CLAUDE.md` and
  `skills/todo-style/assets/AGENTS.md`:
  - `BEHAVIOR` now *requires* the expansion whenever the options differ in kind rather than
    degree — a different mechanism, a different failure closed, a different thing left
    broken. Options differing only in scope or speed still need none.
  - A new **`Why this, not that`** paragraph in the `CHOICES` block, sitting with the ladder
    and before the option blocks: what each rejected option cannot do, and what the pick
    still leaves broken. Placed there so the existing rule "the last option block ends the
    prose" keeps holding.
  - The `CHOICES` ladder table is no longer gated on the options differing by something
    *countable*. Categorical outcomes count too — does it close the hole? is the loss
    recoverable? what stays broken? A yes/no column is a legitimate column. In the Codex
    pack, where the ladder is always present, this opens the columns instead of the gate.
  - `SOLUTION SPINE` item 4 no longer caps "why this fix" at one line.
  - `CORE` and `VISUAL FIRST` gained matching carve-outs, so the argument is not deleted as
    recap prose or converted into a table that keeps the *what* and strips the *because*.
- **`seed/index.md` is data only — title and section tables, nothing else.** The eight-line
  preamble restated two facts every agent already reads from the hub's `AGENTS.md`: resolve
  a short-name here before `archive.md`, and `REGISTRY.md` is the reference for the columns.
  Existing hubs are untouched — `hooks/bootstrap-hub.sh` never overwrites an `index.md` that
  is already there.

### Fixed
- `.codex-plugin/plugin.json` was left at `1.7.0` when the Claude manifest went to `1.7.1`.
  Both manifests now carry the same version, as CONTRIBUTING.md § Releasing requires.

## [1.7.0] — 2026-07-27

### Added
- **`/todo-style` — an opt-in response-style pack for both agents.** 16 skills → 17. Every
  other skill organizes work; this one changes how the agent *talks*. The pack is a
  formatting and briefing contract for a reader who is technical but short on time:
  meaning before evidence, visuals instead of prose, an explicit `➡️ YOUR CALL` block
  whenever something is the reader's to decide, and a closing verdict that names what is
  still open.
  - Two files ship, one per harness, and they carry the same rules —
    `skills/todo-style/assets/CLAUDE.md` installs to `~/.claude/CLAUDE.md`,
    `skills/todo-style/assets/AGENTS.md` to `~/.codex/AGENTS.md`. Only harness-specific
    lines differ: the Claude pack uses `<details>` accordions and artifact widgets, the
    Codex pack uses a `### Technical detail` heading and written-to-disk HTML, because a
    terminal renders neither accordions nor mermaid.
  - **The current file is backed up into the hub and byte-verified before anything is
    overwritten**, at `$TODO_HUB/backups/agent-instructions/<agent>-<file>-<UTC>-<run>.md`.
    A failed backup aborts without writing. Nothing in that folder is ever deleted, and it
    contains only the user's own content — the shipped pack is skipped, since the plugin
    can hand that back at any time.
  - `status`, `diff`, `install`, `restore`, and `list-backups` run through
    `skills/todo-style/scripts/agent-style.sh`; the skill never hand-copies a file. An
    already-current install and a redundant restore are both no-ops.
  - Entirely opt-in: no hook fires it, no other `/todo-*` skill calls it, and it requires
    an explicit yes in conversation. The rest of the plugin behaves identically without it.
  - Covered by the new `tests/style-contract.sh`, which sandboxes `CLAUDE_CONFIG_DIR` and
    `CODEX_HOME` so it never touches the machine's real instruction files.

### Note
- `skills/todo-style/assets/CLAUDE.md` is **not** `seed/CLAUDE.md`. The seed pair is
  hub-scoped and describes how `$TODO_HUB` works; the asset pair is user-scoped and
  describes how the agent should answer. Same filenames, different destinations.

## [1.6.0] — 2026-07-27

### Fixed
- `hooks/infographic-staleness.sh` resolves the hub from `$TODO_HUB` (default `~/todo`)
  like every other hook, instead of only ever firing when the session's working
  directory happened to be the hub. The staleness nudge now reaches cross-repo sessions:
  a stale `ready`/`in-progress` project is reported from the hub itself or from a
  session inside that project's target repo (including its `<repo>-wt/*` worktrees),
  and unrelated repos stay quiet. Covered by the new `tests/infographic-hook-contract.sh`
  — the hook previously had no tests.
- The shared task-counting awk snippet embedded in `todo-state`, `todo-list`, and
  `todo-infographic` now skips `## Notes` / `## Context` sections and fenced code
  blocks, matching the deterministic helpers (`graph-report.py`, `archive-report.sh`),
  so completion ratios agree across every reader.

### Changed
- Hub self-description corrected in ten skills: `$TODO_HUB` points at "your hub
  folder", not "your clone of this repo" — the hub is seeded by the plugin, not a
  clone of it. The seeded `AGENTS.md` no longer lists a `skills/` directory the hub
  doesn't contain.
- Provider model names retreat behind the tier layer (per CONTRIBUTING, names live
  only in `todo-llm-routing`): `todo-push` now says "the fast tier's resolved host
  model" instead of naming Opus / GPT-5.6 Luna, and `todo-triage`'s example render
  uses `<resolved host model>`.
- `templates/plan.md` gains the `## Repo` section every skill already expected;
  `todo-infographic`'s Note section names its fallback when a plan has no `## Notes`.

### Removed
- `seed/templates/planning-prompt.md` — an orphaned pre-`/todo-plan` copy-paste prompt
  nothing referenced; it duplicated (and disagreed with) `/todo-plan`'s discovery
  questions.

### Upgrade note
- Global skill installs made before 1.5.0 (`npx skills add … --global`) still carry
  the removed `todo-resume` / `todo-sync` / `todo-update-state` skills, and possibly
  stale pre-`internal` copies of the repo's own `session-handoff` /
  `infographic-scope` conventions. Delete those folders from your global skills
  directory (e.g. `~/.claude/skills/`) so stale descriptions stop competing with the
  merged skills. Native plugin installs are unaffected.

## [1.5.0] — 2026-07-27

### Removed
- `/todo-resume` and `/todo-sync` as standalone skills, and `/todo-update-state` under
  that name. 18 skills → 16. See the two merges below for where each one went; both old
  names are called out in the surviving skills' descriptions so a stale invocation still
  routes correctly.

### Changed
- **`/todo-resume` merged into `/todo-refer` as `resume` mode.** Both skills resolved a
  project the same way and extracted `tasks.md` the same way — resume's own instructions
  said "use `todo-refer`'s resolution" and "the `todo-refer` extraction snippets", so the
  duplication was already load-bearing. `/todo-refer <name>` still gives the grounding
  digest, `/todo-refer <name> R<n>` still gives one revision, and
  `/todo-refer <name> resume` gives the where-you-stopped digest plus the evidence →
  next-command routing table.
- **`/todo-update-state` + `/todo-sync` merged into `/todo-state`.** Sync could not write
  a correct status flip without following update-state's Step 3.5 date-stamping rules
  from another file. Neither old name described the merged skill honestly, so both were
  retired: `/todo-state` records what the user says, `/todo-state audit` checks the record
  against tasks and git evidence, and `/todo-state audit fix` applies confirmed
  corrections through the same edit path.
- Date-stamping rules moved from `todo-update-state` "Step 3.5" to a named
  `todo-state` § Date stamping section, and are now explicitly the hub-wide authority.
  `todo-execute`, `todo-verify`, `todo-revise`, and `seed/index.md` point at the section
  instead of a step number.
- The documented `npx skills add` command no longer passes `--skill`. Every publicly
  installable skill lives in `skills/` and is named `todo-*`, so the installer's own
  discovery is now the source of truth instead of an 18-name list kept in sync by hand
  across `README.md`, `skills/README.md`, and `CONTRIBUTING.md`.
- The repo's own learned-convention skills (`.agents/skills/infographic-scope`,
  `.agents/skills/session-handoff`, and their `.claude/skills/` mirrors) are marked
  `metadata: internal: true`, which is what makes the unfiltered command safe —
  `npx skills` skips them during discovery.
- `/todo-learn` now writes `metadata: internal: true` into every topic skill it creates,
  so a repo's private corrections never ship to people installing that repo's skills.
- `tests/package-contract.sh` swapped its name-list assertion for the two invariants that
  now matter: the documented install command carries no `--skill` filter, and every
  repo-local skill is marked internal and mirrored byte-identically into
  `.claude/skills/`. It also asserts the `todo-` prefix on every public skill.

## [1.4.0] — 2026-07-27

### Added
- `/todo-graph` compiles canonical `plan.md` relationships into a deterministic ready
  frontier, blocker chains, impact, dependency paths, integrity audits, validated edge
  edits, and stable Tab-Separated Values / JavaScript Object Notation exports.
- Project plans now carry an optional typed `## Relationships` table. `depends-on` is a
  hard scheduling edge; `related-to` and `supersedes` are context-only.
- A read-only SessionStart archive-candidates report identifies detailed closed
  revisions, legacy tombstone links, oversized task files, and completed active rows
  without blocking or editing.
- Targeted `/todo-refer <project> R<n>` history lookup follows a stable
  `artifacts/journal.md#revision-r<n>` anchor instead of loading the full journal.

### Changed
- `/todo-execute`, `/todo-triage`, `/todo-refer`, `/todo-resume`,
  `/todo-update-state`, and `/todo-sync` now consume bounded graph queries instead of
  guessing cross-project order from prose. Legacy registry `related` values remain
  non-blocking compatibility hints.
- Graph queries fail closed on global corruption and invalid hard prerequisites while
  keeping incoming context hints diagnostic-only. Iterative cycle detection, bounded
  blocker search, fenced-comment handling, and symlink containment cover deep or
  adversarial hubs without expanding model context.
- `index.md` is now the active registry; completed rows move losslessly to cold
  `archive.md` under their original section. Exact name lookup checks the index first
  and the archive only on a miss.
- Revision-state matching is case-insensitive, suffixed IDs are supported, and closed
  entries collapse to direct journal links.

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
