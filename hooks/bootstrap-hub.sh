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

# Existing hub: converge it on the shipped seed without ever destroying content.
#
# Three classes of hub file, and the difference matters:
#   registries  — index.md, archive.md hold the user's project rows. NEVER overwritten.
#                 index.md's format is migrated in place by migrate-registry-preamble.sh.
#   docs        — AGENTS.md, CLAUDE.md, REGISTRY.md, templates/. Added when missing.
#                 Users extend these, so a file that differs is reported, not replaced.
#   projects/   — never touched.
if [ -f "$HUB/index.md" ]; then
  add_if_missing() {
    local rel="$1" note="$2"
    [ -f "$SEED/$rel" ] || return 0
    [ -f "$HUB/$rel" ] && return 0
    mkdir -p "$(dirname "$HUB/$rel")"
    cp "$SEED/$rel" "$HUB/$rel"
    printf 'todo-list: added %s/%s%s\n' "$HUB" "$rel" "$note"
  }

  add_if_missing archive.md ' — the completed-project registry.'
  add_if_missing REGISTRY.md ' (registry columns, status lifecycle, date semantics).'
  add_if_missing AGENTS.md ' — the shared agent instructions.'
  add_if_missing CLAUDE.md ' — Claude Code entry point, defers to AGENTS.md.'
  if [ -d "$SEED/templates" ]; then
    for template in "$SEED/templates"/*; do
      [ -f "$template" ] && add_if_missing "templates/$(basename "$template")" ' — a project template.'
    done
  fi

  # Report doc drift; never resolve it by overwriting. A hub's own additions to AGENTS.md
  # or REGISTRY.md are the user's, and the seed has no way to tell an extension from a
  # stale copy.
  drifted=""
  for doc in AGENTS.md CLAUDE.md REGISTRY.md; do
    [ -f "$SEED/$doc" ] && [ -f "$HUB/$doc" ] || continue
    cmp -s "$SEED/$doc" "$HUB/$doc" || drifted="$drifted $doc"
  done
  if [ -n "$drifted" ]; then
    printf 'todo-list: hub docs differ from the shipped versions:%s. Yours are kept as-is — diff them against the plugin seed if you want the newer wording.\n' "$drifted"
  fi
  exit 0
fi

mkdir -p "$HUB"
# Copy seed contents (including dotfiles) without clobbering anything present.
cp -Rn "$SEED"/. "$HUB"/ 2>/dev/null || cp -R "$SEED"/. "$HUB"/

# One-time notice, surfaced as session context.
printf 'todo-list: created your project hub at %s (index.md, archive.md, templates, and an example project). It is the default location — set the TODO_HUB env var to move it.\n' "$HUB"
exit 0
