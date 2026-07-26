#!/usr/bin/env bash
# SessionStart hook (todo-list plugin): bootstrap the project hub on first run.
#
# Creates the hub at $TODO_HUB (default ~/todo) from the plugin's bundled seed/
# content — index.md, archive.md, templates/, an example project, and shared agent
# instructions — if it doesn't exist yet. Existing hubs receive a missing archive.md
# once; otherwise the hook is silent.
set -euo pipefail

# Resolve the hub root, expanding a leading ~ if the user set one.
HUB="${TODO_HUB:-$HOME/todo}"
case "$HUB" in "~"*) HUB="${HOME}${HUB#\~}" ;; esac

PLUGIN="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
SEED="$PLUGIN/seed"
[ -d "$SEED" ] || exit 0   # nothing to seed from — bail quietly

# Existing hub: add only the new cold archive registry, never recopy the seed.
if [ -f "$HUB/index.md" ]; then
  if [ ! -f "$HUB/archive.md" ] && [ -f "$SEED/archive.md" ]; then
    cp "$SEED/archive.md" "$HUB/archive.md"
    printf 'todo-list: added the completed-project registry at %s/archive.md.\n' "$HUB"
  fi
  exit 0
fi

mkdir -p "$HUB"
# Copy seed contents (including dotfiles) without clobbering anything present.
cp -Rn "$SEED"/. "$HUB"/ 2>/dev/null || cp -R "$SEED"/. "$HUB"/

# One-time notice, surfaced as session context.
printf 'todo-list: created your project hub at %s (index.md, archive.md, templates, and an example project). It is the default location — set the TODO_HUB env var to move it.\n' "$HUB"
exit 0
