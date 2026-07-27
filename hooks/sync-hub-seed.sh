#!/usr/bin/env bash
# SessionStart hook (todo-list plugin): keep an existing hub's plugin-owned instruction
# files current with the bundled seed/.
#
# Skills upgrade with the plugin; the hub's own instruction files were copied once at
# creation and never refreshed, so a rule added to seed/ reached new hubs only.
# This hook closes that gap without ever touching project data.
#
# Three policies, by how likely a user edit is:
#
#   pure reference  REGISTRY.md, CLAUDE.md      refreshed whenever they differ
#   preamble only   index.md, archive.md        block above the first `## ` heading;
#                                               the section tables and a live
#                                               `Start here` pointer are preserved
#   edit-tracked    AGENTS.md, templates/*      refreshed when the hub copy still matches
#                                               the hash recorded at install, or matches
#                                               any version the plugin once published;
#                                               a locally edited file is reported, never
#                                               overwritten
#
# Every write leaves a <file>.pre-seed-sync.bak. Nothing to do prints nothing.
# Recorded hashes live in $TODO_HUB/.todo-list-seed.
#
# TODO_SEED_ADOPT=<rel-path>[,<rel-path>...] forces an edit-tracked file to take the
# seed version anyway (still backed up first). TODO_SEED_ADOPT=all covers every one.
set -euo pipefail

HUB="${TODO_HUB:-$HOME/todo}"
case "$HUB" in "~"*) HUB="${HOME}${HUB#\~}" ;; esac

PLUGIN="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
SEED="$PLUGIN/seed"
[ -d "$SEED" ] || exit 0          # nothing to sync from — bail quietly
[ -f "$HUB/index.md" ] || exit 0  # no hub yet — bootstrap-hub.sh owns creation

MANIFEST="$HUB/.todo-list-seed"
ADOPT="${TODO_SEED_ADOPT:-}"

refreshed=()
added=()
drifted=()      # edit-tracked files the user has customised
needs_audit=()  # registries carrying prose where only a preamble belongs

if command -v shasum >/dev/null 2>&1; then
  sha() { shasum -a 256 | cut -d' ' -f1; }
else
  sha() { sha256sum | cut -d' ' -f1; }
fi
sha_file() { sha < "$1"; }

file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || printf '644\n'
}

# The hub is data. Never lose a byte of it without leaving a copy behind.
backup() { cp "$1" "$1.pre-seed-sync.bak"; }

manifest_get() {
  [ -f "$MANIFEST" ] || return 0
  awk -v key="$1" '$2 == key { print $1; exit }' "$MANIFEST"
}

manifest_set() {
  local key="$1" value="$2" temp_file
  temp_file="$(mktemp)"
  if [ -f "$MANIFEST" ]; then
    awk -v key="$key" '$2 != key' "$MANIFEST" > "$temp_file"
  fi
  printf '%s  %s\n' "$value" "$key" >> "$temp_file"
  LC_ALL=C sort -k2,2 -o "$temp_file" "$temp_file"
  mv "$temp_file" "$MANIFEST"
}

adopt_requested() {
  case ",$ADOPT," in
    ,all,) return 0 ;;
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

install_seed() {
  local rel="$1" temp_file
  temp_file="$(mktemp)"
  cat "$SEED/$rel" > "$temp_file"
  chmod "$(file_mode "$HUB/$rel")" "$temp_file"
  mv "$temp_file" "$HUB/$rel"
}

add_missing() {
  local rel="$1"
  mkdir -p "$(dirname "$HUB/$rel")"
  cp "$SEED/$rel" "$HUB/$rel"
  manifest_set "$rel" "$(sha_file "$SEED/$rel")"
  added+=("$rel")
}

# Pure reference: plugin prose with no user content, so a difference is always staleness.
refresh_reference() {
  local rel="$1"
  [ -f "$SEED/$rel" ] || return 0
  if [ ! -f "$HUB/$rel" ]; then
    add_missing "$rel"
    return 0
  fi
  if cmp -s "$SEED/$rel" "$HUB/$rel"; then
    manifest_set "$rel" "$(sha_file "$SEED/$rel")"
    return 0
  fi
  backup "$HUB/$rel"
  install_seed "$rel"
  manifest_set "$rel" "$(sha_file "$SEED/$rel")"
  refreshed+=("$rel")
}

# A hub predating the manifest has no recorded hash, so "untouched but old" and "edited by
# hand" look identical. They are still distinguishable: if the hub's copy matches a version
# the plugin itself once published, it was installed and never touched — just stale. The
# plugin checkout is a git repo on both the marketplace and local-dev paths; where it is
# not, this returns false and the file is reported instead of written.
matches_published_version() {
  local rel="$1" live_hash="$2" commit blob
  git -C "$PLUGIN" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  while IFS= read -r commit; do
    [ -n "$commit" ] || continue
    blob="$(git -C "$PLUGIN" rev-parse "$commit:seed/$rel" 2>/dev/null)" || continue
    if [ "$(git -C "$PLUGIN" cat-file blob "$blob" 2>/dev/null | sha)" = "$live_hash" ]; then
      return 0
    fi
  done < <(git -C "$PLUGIN" log -n 50 --format=%H -- "seed/$rel" 2>/dev/null)
  return 1
}

# Edit-tracked: refresh only what we can prove the user never touched.
sync_tracked() {
  local rel="$1" seed_hash live_hash recorded
  [ -f "$SEED/$rel" ] || return 0
  if [ ! -f "$HUB/$rel" ]; then
    add_missing "$rel"
    return 0
  fi
  seed_hash="$(sha_file "$SEED/$rel")"
  live_hash="$(sha_file "$HUB/$rel")"
  if [ "$live_hash" = "$seed_hash" ]; then
    manifest_set "$rel" "$seed_hash"   # already current — start tracking it
    return 0
  fi
  recorded="$(manifest_get "$rel")"
  if { [ -n "$recorded" ] && [ "$live_hash" = "$recorded" ]; } ||
     { [ -z "$recorded" ] && matches_published_version "$rel" "$live_hash"; } ||
     adopt_requested "$rel"; then
    backup "$HUB/$rel"
    install_seed "$rel"
    manifest_set "$rel" "$seed_hash"
    refreshed+=("$rel")
  else
    drifted+=("$rel")
  fi
}

# Preamble only. The rows below the first section table are the user's data, and the
# `Start here` pointer inside the preamble is data too — /todo-state owns that line.
#
# The preamble is anchored on the first `## ` heading that actually opens a registry
# table, not on the first `## ` of any kind: a pasted status banner is often itself a
# `## ` heading, and anchoring on that would splice the new preamble in above it and
# duplicate the old one.
section_start_line() {
  awk '
    /^## / { heading = NR; next }
    heading && /^\|/ && /short-name/ { print heading; exit }
  ' "$1"
}

lines_above() { awk -v stop="$2" 'NR < stop { print }' "$1"; }

sync_preamble() {
  # Separate statements: a single `local` expands every value before assigning any of them.
  local rel="$1"
  local hub_file="$HUB/$rel"
  local seed_file="$SEED/$rel"
  [ -f "$seed_file" ] || return 0
  [ -f "$hub_file" ] || return 0

  local hub_start seed_start
  hub_start="$(section_start_line "$hub_file")"
  seed_start="$(section_start_line "$seed_file")"
  # No recognisable section table means we cannot tell preamble from content.
  if [ -z "$hub_start" ] || [ -z "$seed_start" ]; then
    needs_audit+=("$rel")
    return 0
  fi

  local current_preamble new_preamble live_pointer
  current_preamble="$(lines_above "$hub_file" "$hub_start")"
  new_preamble="$(lines_above "$seed_file" "$seed_start")"

  # Refuse rather than delete. Extra headings or pasted paragraphs in the preamble are a
  # registry-hygiene violation whose text belongs in the project's artifacts/ — relocating
  # it is /todo-state audit's job, and it asks first. A hook must never silently drop it.
  local heading_count current_lines allowed_lines
  heading_count="$(printf '%s\n' "$current_preamble" | grep -c '^#' || true)"
  current_lines="$(printf '%s\n' "$current_preamble" | wc -l | tr -d ' ')"
  allowed_lines=$(( $(printf '%s\n' "$new_preamble" | wc -l | tr -d ' ') + 4 ))
  if [ "$heading_count" -gt 1 ] || [ "$current_lines" -gt "$allowed_lines" ]; then
    needs_audit+=("$rel")
    return 0
  fi

  live_pointer="$(grep -m1 '^> \*\*Start here:\*\*' "$hub_file" || true)"
  if [ -n "$live_pointer" ]; then
    new_preamble="$(
      printf '%s\n' "$new_preamble" |
        awk -v pointer="$live_pointer" \
          '/^> \*\*Start here:\*\*/ { print pointer; next } { print }'
    )"
  fi

  [ "$current_preamble" = "$new_preamble" ] && return 0

  backup "$hub_file"
  local temp_file
  temp_file="$(mktemp)"
  printf '%s\n' "$new_preamble" > "$temp_file"
  awk -v start="$hub_start" 'NR >= start { print }' "$hub_file" >> "$temp_file"
  chmod "$(file_mode "$hub_file")" "$temp_file"
  mv "$temp_file" "$hub_file"
  refreshed+=("$rel preamble")
}

refresh_reference REGISTRY.md
refresh_reference CLAUDE.md
sync_tracked AGENTS.md
sync_preamble index.md
sync_preamble archive.md

if [ -d "$SEED/templates" ]; then
  while IFS= read -r template; do
    sync_tracked "templates/${template#"$SEED/templates/"}"
  done < <(find "$SEED/templates" -type f | LC_ALL=C sort)
fi

# $* joins on the first character of IFS only, so build the separator explicitly.
join_list() {
  local joined="$1" item
  shift
  for item in "$@"; do joined="$joined, $item"; done
  printf '%s' "$joined"
}

join_commas() {
  local joined="$1" item
  shift
  for item in "$@"; do joined="$joined,$item"; done
  printf '%s' "$joined"
}

if [ "${#added[@]}" -gt 0 ]; then
  printf 'todo-list: added missing hub files from the plugin seed — %s.\n' \
    "$(join_list "${added[@]}")"
fi

if [ "${#refreshed[@]}" -gt 0 ]; then
  printf 'todo-list: refreshed hub instruction files from the plugin seed — %s. Project rows and the Start here pointer are untouched; backups at *.pre-seed-sync.bak.\n' \
    "$(join_list "${refreshed[@]}")"
fi

if [ "${#drifted[@]}" -gt 0 ]; then
  printf 'todo-list: these hub files carry local edits, so the plugin seed update was left unapplied — %s. Keep your version, or take the seed with TODO_SEED_ADOPT=%s (a backup is written first).\n' \
    "$(join_list "${drifted[@]}")" "$(join_commas "${drifted[@]}")"
fi

if [ "${#needs_audit[@]}" -gt 0 ]; then
  printf 'todo-list: %s carries prose above its section tables, so the preamble was left as is — the registries are data, not reports. Run /todo-state audit to relocate that text into the owning project artifacts/; it asks before editing and never deletes.\n' \
    "$(join_list "${needs_audit[@]}")"
fi

exit 0
