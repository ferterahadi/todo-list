#!/usr/bin/env bash
# SessionStart hook (todo-list plugin): bootstrap the project hub on first run.
#
# Creates the hub at $TODO_HUB (default ~/todo) from the plugin's bundled seed/
# content — index.md, templates/, an example project, and the hub CLAUDE.md — if
# it doesn't exist yet. Idempotent and SILENT once the hub is present, so it adds
# no noise to normal sessions.
set -euo pipefail

# Resolve the hub root, expanding a leading ~ if the user set one.
HUB="${TODO_HUB:-$HOME/todo}"
case "$HUB" in "~"*) HUB="${HOME}${HUB#\~}" ;; esac

# Already bootstrapped? Do nothing, say nothing.
[ -f "$HUB/index.md" ] && exit 0

SEED="${CLAUDE_PLUGIN_ROOT:-}/seed"
[ -d "$SEED" ] || exit 0   # nothing to seed from — bail quietly

mkdir -p "$HUB"
# Copy seed contents (including dotfiles) without clobbering anything present.
cp -Rn "$SEED"/. "$HUB"/ 2>/dev/null || cp -R "$SEED"/. "$HUB"/

# One-time notice, surfaced as session context.
printf 'todo-list: created your project hub at %s (index.md, templates, and an example project). It is the default location — set the TODO_HUB env var to move it.\n' "$HUB"
exit 0
