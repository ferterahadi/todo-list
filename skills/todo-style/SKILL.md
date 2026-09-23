---
name: todo-style
description: Use when the user invokes /todo-style, says "install the briefing style", "make the agent answer like an executive briefing", "swap my CLAUDE.md", "back up my CLAUDE.md before changing it", "use the todo-list response style", "restore my old CLAUDE.md", "undo the style pack", "uninstall the style pack", or "which style pack version do I have". Backs the current global agent instruction file up into the hub, then installs the bundled response-style pack for Claude Code and Codex. Never runs unprompted and never overwrites without a verified backup.
---

# Response Style Skill

You install a **response-style pack** — a shared set of formatting and briefing rules — into
the user's *global* agent instruction file, keeping their previous file safe in the hub.

Two files, one per agent:

| Agent | Global file replaced | Bundled source |
|-------|----------------------|----------------|
| Claude Code | `$CLAUDE_CONFIG_DIR/CLAUDE.md` (default `~/.claude/CLAUDE.md`) | `assets/CLAUDE.md` |
| Codex | `$CODEX_HOME/AGENTS.md` (default `~/.codex/AGENTS.md`) | `assets/AGENTS.md` |

The two packs carry the same rules; only harness-specific lines differ, because the two
surfaces render and accept different things:

| | Claude Code | Codex |
|-|-|-|
| Complex diagrams | artifact widget | written-to-disk HTML (never mermaid) |
| Decision surface | interactive picker only | comparison table only |

The decision split is the one to remember: Claude Code puts the options in its interactive
picker, while Codex puts them in one compact table. Neither pack repeats the same options in
a comparison, cards, and a closing picker.

This is deterministic file work — the script does it all. Use the **fast** tier from
[`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md). Your judgment is spent on
the confirmation gate, not the copying.

## Non-negotiables

These exist because this skill writes outside the hub, to a file the user may have spent
a long time tuning.

1. **Never install without an explicit yes in this conversation.** Showing the diff is not
   consent. "Set up todo-list" is not consent.
2. **Never hand-copy the files.** Always go through `scripts/agent-style.sh`; it backs up
   and byte-verifies before it writes, and it aborts rather than overwrite on a failed
   backup.
3. **Never delete a backup**, and never edit one.
4. **This is the only skill that touches global instruction files.** No hook fires it, and
   no other `/todo-*` skill calls it.

## How the user invokes this

```
/todo-style                  ← status: what's installed vs what ships
/todo-style diff             ← unified diff, current file → shipped pack
/todo-style install          ← back up both files, then install both packs
/todo-style install claude   ← Claude Code only
/todo-style install codex    ← Codex only
/todo-style restore          ← undo the pack: back to the file before it, or to no file
/todo-style backups          ← list every backup in the hub
```

`uninstall` is another name for `restore`; `list-backups` is another name for `backups`.
Every mode except `status` and `backups` takes `claude`, `codex`, or `both` (the default).
Pass the agent the user named; a Claude-only request never touches the Codex file.

Plain language counts: "make it brief like a briefing", "swap my global CLAUDE.md",
"put my old CLAUDE.md back".

## Step 1 — Report the current state

Always start here, whatever the user asked for:

```bash
bash <todo-style-skill-dir>/scripts/agent-style.sh status
```

It prints, per agent: the target path, what the file holds, the pack it compared against
(path and version — the installed plugin's copy, which can lag the repo), the restore
point, and the newest backup. What the file holds is one of:

- `absent` — no file.
- `current` — the shipped pack for this agent.
- `holds the <other> pack` — the other harness's pack, e.g. the Codex pack in
  `CLAUDE.md`. Install replaces it.
- `an older todo-list pack (vX)` — a shipped version, recognised by hash from
  `pack-versions.tsv`. Install updates it.
- `a todo-list pack edited by hand` — pack-shaped, but no shipped version.
- `your own file` — not a pack at all.

Relay it as a short table. **For an install only:** if every agent in scope already reports
`current`, say so and stop — there is nothing to install. Restore, diff, and backups go on
from any state.

## Step 2 — Show what would change

Before any install, run the diff for the agents in scope — `claude`, `codex`, or `both`,
whichever the user asked for:

```bash
bash <todo-style-skill-dir>/scripts/agent-style.sh diff <agent>
```

Summarize it — how many lines are being replaced, and what the user loses. If their
current file holds real content (project conventions, tool preferences, personal rules),
**say so explicitly and name a few of those rules.** The pack replaces the file wholesale;
it does not merge. A user who forgot what was in their `CLAUDE.md` must not learn it from
the backup afterwards.

If they want to keep parts of their existing file, the right answer is: install the pack,
then append their kept rules to the installed file by hand. Offer that, don't do it
silently.

## Step 3 — Confirm, then install

Ask in one line — what gets replaced, and where the backup lands. On an explicit yes, for
the same agent scope:

```bash
bash <todo-style-skill-dir>/scripts/agent-style.sh install <agent>
```

The script backs up first, verifies the backup byte-for-byte, and only then writes. It
prints one line per agent naming the backup path. If a file is already current it is
skipped without a redundant backup, and content already backed up is never copied twice.

Install also records a **restore point** — what `restore` returns to: the backup of the
user's own file, or `absent` when there was no file. Installing a newer pack over an older
one keeps the earlier restore point, so restore goes back to the state before any pack.

Backups live at `$TODO_HUB/backups/agent-instructions/`, named
`<agent>-<file>-<UTC timestamp>-<nn>.md`, newest last. A `README.md` in that folder
explains itself to a cold reader.

## Step 4 — Report

Give the user, in this order:

- One line per agent: installed / already current / skipped.
- The backup path for each file that was replaced — this is the most important line in the
  report, and it must appear even when the user seems unconcerned.
- The restore command, verbatim.
- **When to expect it:** the global file is read at session start, so Claude Code and Codex
  pick the new style up on their *next* session, not this one.

## Restore

Run status first (Step 1). When a restore point reads `no file`, restore removes the live
file — say so in one line and get an explicit yes before running it.

```bash
bash <todo-style-skill-dir>/scripts/agent-style.sh restore <agent>
bash <todo-style-skill-dir>/scripts/agent-style.sh restore claude <backup-path>
```

`restore` returns each file to its restore point: the user's pre-pack file, or **no file**
when there was none — then it removes the pack. It saves whatever it replaces or removes
first, unless that is the untouched pack, which the plugin can always hand back. So an
edited pack is backed up once, the backup folder stays made of the user's own content, and
a second `restore` is a no-op rather than a toggle. An install from before restore points
existed has no record; restore then infers one (the newest backup that isn't a pack) and
status marks it `inferred`. With neither a record nor a usable backup it reports that and
changes nothing.

To put back a specific older backup, list them first — the restore point is marked:

```bash
bash <todo-style-skill-dir>/scripts/agent-style.sh backups
```

## Notes

- **Global, not per-project.** This writes to the user-level file both agents read in
  every repo. A repo's own `CLAUDE.md` / `AGENTS.md` is untouched and still wins for
  project-specific rules.
- **Editing after install is fine and expected.** The pack is a starting point; the user's
  edits are backed up on the next install or restore, so tuning it costs nothing.
- **New pack version → new `pack-versions.tsv` row.** Status recognises versions by hash;
  `tests/style-contract.sh` fails until the shipped packs are listed.
- **Not the hub's own instructions.** `$TODO_HUB/CLAUDE.md` and `$TODO_HUB/AGENTS.md` come
  from the plugin's `seed/` and describe how the hub works. This skill never touches them.
- **Nothing here is required to use the plugin.** Every `/todo-*` skill works the same
  whether or not the pack is installed.
