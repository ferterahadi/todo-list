---
name: todo-style
description: Use when the user invokes /todo-style, says "install the briefing style", "make the agent answer like an executive briefing", "swap my CLAUDE.md", "back up my CLAUDE.md before changing it", "use the todo-list response style", "restore my old CLAUDE.md", or "undo the style pack". Backs the current global agent instruction file up into the hub, then installs the bundled response-style pack for Claude Code and Codex. Never runs unprompted and never overwrites without a verified backup.
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
| Below-the-fold evidence | `<details>` accordion | `### Technical detail` heading |
| Diagrams | artifact widget | written-to-disk HTML (never mermaid) |
| Decision picker | interactive picker tool, fired last | tag table at the top of the block |

The picker split is the one to remember: Claude Code has a click-to-choose control, so its
pack drops the closing `### ➡️ Choose` table and lets the tool be the click surface. A
terminal has no such control, so Codex's pack keeps a tag table — moved to the top of the
CHOICES block, where it is read before the option detail rather than after it.

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
/todo-style restore          ← put the newest backup back
/todo-style backups          ← list every backup in the hub
```

Plain language counts: "make it brief like a briefing", "swap my global CLAUDE.md",
"put my old CLAUDE.md back".

## Step 1 — Report the current state

Always start here, whatever the user asked for:

```bash
bash <todo-style-skill-dir>/scripts/agent-style.sh status
```

It prints, per agent: the target path, whether the file is absent / already the shipped
pack / different from it, and the newest backup. Relay it as a short table. If both agents
already report `current`, say so and stop — there is nothing to do.

## Step 2 — Show what would change

Before any install, run the diff for the agents in scope:

```bash
bash <todo-style-skill-dir>/scripts/agent-style.sh diff both
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

Ask in one line — what gets replaced, and where the backup lands. On an explicit yes:

```bash
bash <todo-style-skill-dir>/scripts/agent-style.sh install both
```

The script backs up first, verifies the backup byte-for-byte, and only then writes. It
prints one line per agent naming the backup path. If a file is already current it is
skipped without a redundant backup.

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

```bash
bash <todo-style-skill-dir>/scripts/agent-style.sh restore both
bash <todo-style-skill-dir>/scripts/agent-style.sh restore claude <backup-path>
```

`restore` puts the newest backup back, saving whatever it replaces first — unless that is
the untouched pack, which the plugin can always hand back. So the backup folder stays made
of the user's own content, and running `restore` twice is a no-op rather than a toggle.
With no backup for an agent it reports that and changes nothing. To pick an older backup,
list them first:

```bash
bash <todo-style-skill-dir>/scripts/agent-style.sh list-backups
```

## Notes

- **Global, not per-project.** This writes to the user-level file both agents read in
  every repo. A repo's own `CLAUDE.md` / `AGENTS.md` is untouched and still wins for
  project-specific rules.
- **Editing after install is fine and expected.** The pack is a starting point; the user's
  edits are backed up on the next install, so tuning it costs nothing.
- **Not the hub's own instructions.** `$TODO_HUB/CLAUDE.md` and `$TODO_HUB/AGENTS.md` come
  from the plugin's `seed/` and describe how the hub works. This skill never touches them.
- **Nothing here is required to use the plugin.** Every `/todo-*` skill works the same
  whether or not the pack is installed.
