#!/usr/bin/env bash
# Contract test for hooks/sync-hub-seed.sh — the seed-to-existing-hub upgrade path.
#
# The hook exists because a rule added to seed/ used to reach new hubs only: bootstrap
# copies each file once and never looks again. It must close that gap without ever losing
# a byte of project data, so the invariants below are as much about what it refuses to do
# as about what it writes.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$repo_root/hooks/sync-hub-seed.sh"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

expect_equal() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" != "$expected" ]; then
    printf 'not ok - %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

expect_output_contains() {
  local label="$1" text="$2" output="$3"
  case "$output" in
    *"$text"*) ;;
    *) printf 'not ok - %s\nexpected output to contain: %s\nactual: %s\n' \
         "$label" "$text" "$output" >&2; exit 1 ;;
  esac
}

expect_file_contains() {
  grep -Fq "$2" "$1" || fail "$1 must contain: $2"
}

expect_file_lacks() {
  grep -Fq "$2" "$1" && fail "$1 must not contain: $2"
  return 0
}

file_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }
digest() { shasum -a 256 < "$1" 2>/dev/null | cut -d' ' -f1 || sha256sum < "$1" | cut -d' ' -f1; }

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

# --- fixtures ---------------------------------------------------------------------------
# A throwaway plugin whose seed/ has two published generations, so the hook's
# "did the plugin itself once ship this?" provenance check has real history to read.

TABLE_HEADER='| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |'
TABLE_RULE='|---|---|---|---|---|---|---|---|---|'
ROW='| alpha | projects/work/alpha | ~/code/alpha | in-progress | 2026-06-12 | - | - | - | - |'

write_old_seed() {
  local seed="$1"
  mkdir -p "$seed/templates"
  cat > "$seed/index.md" <<EOF
# Project Index

Old preamble sentence.

## Work

$TABLE_HEADER
$TABLE_RULE
EOF
  cat > "$seed/archive.md" <<EOF
# Completed Projects

Old archive preamble.

## Work

$TABLE_HEADER
$TABLE_RULE
EOF
  printf 'Old agent instructions.\n' > "$seed/AGENTS.md"
  printf 'Read AGENTS.md.\n' > "$seed/CLAUDE.md"
  printf '# Old registry reference\n' > "$seed/REGISTRY.md"
  printf '# Old task template\n' > "$seed/templates/tasks.md"
}

write_new_seed() {
  local seed="$1"
  cat > "$seed/index.md" <<EOF
# Project Index

> **Start here:** -

New preamble sentence.

This file is data, not a report.

## Work

$TABLE_HEADER
$TABLE_RULE
EOF
  cat > "$seed/archive.md" <<EOF
# Completed Projects

New archive preamble.

Like index.md, this file is data, not a report.

## Work

$TABLE_HEADER
$TABLE_RULE
EOF
  printf 'New agent instructions.\nRegistries are data, not reports.\n' > "$seed/AGENTS.md"
  printf 'Read AGENTS.md.\n' > "$seed/CLAUDE.md"
  printf '# Registry reference\n\nRegistries are data, not reports.\n' > "$seed/REGISTRY.md"
  printf '# Task template\n' > "$seed/templates/tasks.md"
}

plugin="$sandbox/plugin"
mkdir -p "$plugin"
git -C "$plugin" init -q
git -C "$plugin" config user.email test@example.com
git -C "$plugin" config user.name test
write_old_seed "$plugin/seed"
git -C "$plugin" add -A
git -C "$plugin" commit -qm 'seed v1'
old_agents_digest="$(digest "$plugin/seed/AGENTS.md")"
write_new_seed "$plugin/seed"
git -C "$plugin" add -A
git -C "$plugin" commit -qm 'seed v2'

# A hub as it existed before the sync hook: the old seed, plus the user's own rows.
make_stale_hub() {
  local hub="$1"
  rm -rf "$hub"
  mkdir -p "$hub"
  git -C "$plugin" show 'HEAD~1:seed/index.md' > "$hub/index.md"
  git -C "$plugin" show 'HEAD~1:seed/archive.md' > "$hub/archive.md"
  git -C "$plugin" show 'HEAD~1:seed/AGENTS.md' > "$hub/AGENTS.md"
  git -C "$plugin" show 'HEAD~1:seed/CLAUDE.md' > "$hub/CLAUDE.md"
  git -C "$plugin" show 'HEAD~1:seed/REGISTRY.md' > "$hub/REGISTRY.md"
  mkdir -p "$hub/templates"
  git -C "$plugin" show 'HEAD~1:seed/templates/tasks.md' > "$hub/templates/tasks.md"
  printf '%s\n' "$ROW" >> "$hub/index.md"
}

run_hook() {
  local hub="$1"
  shift
  env "$@" PLUGIN_ROOT="$plugin" TODO_HUB="$hub" bash "$hook" 2>&1
}

# --- no hub, no seed: both must be silent no-ops -----------------------------------------

expect_equal "a missing hub prints nothing" "" "$(run_hook "$sandbox/absent")"

seedless="$sandbox/seedless"
mkdir -p "$seedless"
printf '# Project Index\n' > "$seedless/index.md"
expect_equal "a plugin with no seed/ prints nothing" "" \
  "$(env PLUGIN_ROOT="$sandbox/not-a-plugin" TODO_HUB="$seedless" bash "$hook" 2>&1)"
expect_equal "a seedless run leaves the hub alone" "# Project Index" "$(cat "$seedless/index.md")"

printf 'ok - silent no-op without a hub or a seed\n'

# --- a hub already current: silent, and it starts tracking hashes -------------------------

current="$sandbox/hub-current"
mkdir -p "$current/templates"
cp "$plugin/seed/index.md" "$current/index.md"
cp "$plugin/seed/archive.md" "$current/archive.md"
cp "$plugin/seed/AGENTS.md" "$current/AGENTS.md"
cp "$plugin/seed/CLAUDE.md" "$current/CLAUDE.md"
cp "$plugin/seed/REGISTRY.md" "$current/REGISTRY.md"
cp "$plugin/seed/templates/tasks.md" "$current/templates/tasks.md"
printf '%s\n' "$ROW" >> "$current/index.md"

expect_equal "an up-to-date hub prints nothing" "" "$(run_hook "$current")"
expect_equal "an up-to-date hub gets no backups" "0" \
  "$(find "$current" -name '*.pre-seed-sync.bak' | wc -l | tr -d ' ')"
[ -f "$current/.todo-list-seed" ] || fail "an up-to-date hub must still record hashes"
expect_equal "every managed file is recorded" "4" \
  "$(wc -l < "$current/.todo-list-seed" | tr -d ' ')"
expect_equal "a second run stays silent" "" "$(run_hook "$current")"

printf 'ok - current hub is a silent, idempotent no-op\n'

# --- the upgrade the hook exists for -----------------------------------------------------

stale="$sandbox/hub-stale"
make_stale_hub "$stale"
index_mode_before="$(file_mode "$stale/index.md")"
output="$(run_hook "$stale")"

expect_output_contains "the refresh names REGISTRY.md" "REGISTRY.md" "$output"
expect_output_contains "the refresh names the index preamble" "index.md preamble" "$output"
expect_output_contains "the refresh names the archive preamble" "archive.md preamble" "$output"

# Pure-reference files take the new version outright.
cmp -s "$stale/REGISTRY.md" "$plugin/seed/REGISTRY.md" ||
  fail "REGISTRY.md must be refreshed — it holds no user content"

# An untouched-but-old AGENTS.md is provably the plugin's own earlier release, so it
# upgrades without asking. This is the case a manifest alone cannot resolve.
cmp -s "$stale/AGENTS.md" "$plugin/seed/AGENTS.md" ||
  fail "an unmodified old AGENTS.md must be recognised as published and refreshed"
expect_equal "the old AGENTS.md digest was the published one" \
  "$old_agents_digest" "$(digest "$stale/AGENTS.md.pre-seed-sync.bak")"

# The preamble is replaced; the rows below it are not.
expect_file_contains "$stale/index.md" 'This file is data, not a report.'
expect_file_lacks "$stale/index.md" 'Old preamble sentence.'
expect_equal "the user's row survives the preamble refresh" "1" \
  "$(grep -c "^| alpha " "$stale/index.md")"
expect_file_contains "$stale/index.md" '> **Start here:** -'
expect_file_contains "$stale/archive.md" 'Like index.md, this file is data, not a report.'
expect_equal "file modes are preserved" "$index_mode_before" "$(file_mode "$stale/index.md")"
[ -f "$stale/index.md.pre-seed-sync.bak" ] || fail "every write must leave a backup"
expect_equal "a second pass over the upgraded hub is silent" "" "$(run_hook "$stale")"

printf 'ok - a stale hub upgrades, keeping rows, modes, and a backup\n'

# --- a live Start here pointer is data, and survives verbatim -----------------------------

pointed="$sandbox/hub-pointed"
make_stale_hub "$pointed"
pointer='> **Start here:** [alpha](projects/work/alpha/artifacts/2026-07-27-handoff-cutover.md) — mid-cutover.'
# An old hub has no pointer slot at all; the refresh must install one and, where the hub
# already has a pointer, keep the hub's value rather than the seed's placeholder.
run_hook "$pointed" >/dev/null
awk -v ptr="$pointer" '/^> \*\*Start here:\*\*/ { print ptr; next } { print }' \
  "$pointed/index.md" > "$sandbox/pointed-index"
cp "$sandbox/pointed-index" "$pointed/index.md"
# Make the preamble stale again so the hook has a reason to rewrite it.
printf '# Registry reference\n' > "$pointed/REGISTRY.md"
run_hook "$pointed" >/dev/null
expect_file_contains "$pointed/index.md" "$pointer"
expect_equal "exactly one pointer line remains" "1" \
  "$(grep -c '^> \*\*Start here:\*\*' "$pointed/index.md")"

printf 'ok - the Start here pointer is preserved, never overwritten by the seed\n'

# --- a locally edited file is reported, never overwritten ---------------------------------

edited="$sandbox/hub-edited"
make_stale_hub "$edited"
printf 'My own local note. Do not lose this.\n' >> "$edited/AGENTS.md"
edited_digest="$(digest "$edited/AGENTS.md")"
output="$(run_hook "$edited")"

expect_output_contains "an edited file is reported" "AGENTS.md" "$output"
expect_output_contains "the report offers the adopt override" "TODO_SEED_ADOPT=AGENTS.md" "$output"
expect_equal "an edited file is left byte-for-byte alone" \
  "$edited_digest" "$(digest "$edited/AGENTS.md")"
expect_file_contains "$edited/AGENTS.md" 'Do not lose this.'

# The override takes the seed version, but only after the edit is recoverable.
output="$(run_hook "$edited" TODO_SEED_ADOPT=AGENTS.md)"
expect_output_contains "the override reports a refresh" "AGENTS.md" "$output"
cmp -s "$edited/AGENTS.md" "$plugin/seed/AGENTS.md" ||
  fail "TODO_SEED_ADOPT must install the seed version"
expect_file_contains "$edited/AGENTS.md.pre-seed-sync.bak" 'Do not lose this.'

printf 'ok - local edits are reported and preserved; the override backs them up first\n'

# --- prose in a registry is refused, not deleted ------------------------------------------
# The bug that prompted all of this was a pasted release report sitting above the section
# tables. Relocating that text is /todo-state audit's job, and it asks first — so the hook
# must leave such a file completely untouched rather than quietly dropping the paragraph.

polluted="$sandbox/hub-polluted"
make_stale_hub "$polluted"
{
  printf '# Project Index\n\n'
  printf '## 2.18.0 IS IN PRODUCTION\n\n'
  printf 'Deployed today on 15/15 deployments. Every producer flag is false.\n\n'
  printf 'Old preamble sentence.\n\n'
  printf '## Work\n\n%s\n%s\n%s\n' "$TABLE_HEADER" "$TABLE_RULE" "$ROW"
} > "$polluted/index.md"
polluted_digest="$(digest "$polluted/index.md")"
output="$(run_hook "$polluted")"

expect_equal "a polluted registry is left byte-for-byte unchanged" \
  "$polluted_digest" "$(digest "$polluted/index.md")"
expect_file_contains "$polluted/index.md" '2.18.0 IS IN PRODUCTION'
expect_output_contains "the report routes prose to the audit" "/todo-state audit" "$output"
expect_output_contains "the report names the file" "index.md" "$output"
case "$output" in
  *"index.md preamble"*) fail "a polluted registry must not be reported as refreshed" ;;
esac
# A registry with no recognisable section table is equally untouchable.
printf '# Project Index\n\nJust prose, no table.\n' > "$polluted/archive.md"
archive_digest="$(digest "$polluted/archive.md")"
run_hook "$polluted" >/dev/null
expect_equal "a tableless registry is left alone" \
  "$archive_digest" "$(digest "$polluted/archive.md")"

printf 'ok - prose in a registry is refused and routed to /todo-state audit\n'

# --- missing managed files are added, and templates are covered ---------------------------

partial="$sandbox/hub-partial"
make_stale_hub "$partial"
rm -f "$partial/REGISTRY.md" "$partial/templates/tasks.md"
output="$(run_hook "$partial")"
expect_output_contains "a missing file is reported as added" "added missing hub files" "$output"
[ -f "$partial/REGISTRY.md" ] || fail "a missing REGISTRY.md must be added"
cmp -s "$partial/templates/tasks.md" "$plugin/seed/templates/tasks.md" ||
  fail "a missing template must be added from the seed"

# An old template that the plugin once published upgrades like any tracked file.
tmpl="$sandbox/hub-template"
make_stale_hub "$tmpl"
run_hook "$tmpl" >/dev/null
cmp -s "$tmpl/templates/tasks.md" "$plugin/seed/templates/tasks.md" ||
  fail "an unmodified old template must be refreshed"

printf 'ok - missing files are added and templates follow the tracked policy\n'

# --- the hook is registered ---------------------------------------------------------------

grep -Fq 'hooks/sync-hub-seed.sh' "$repo_root/hooks/hooks.json" ||
  fail "sync-hub-seed.sh must be registered as a SessionStart hook"
python3 - "$repo_root/hooks/hooks.json" <<'PY'
import json, sys
hooks = json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]["hooks"]
commands = [h["command"] for h in hooks]
def index_of(name):
    return next(i for i, c in enumerate(commands) if name in c)
assert index_of("bootstrap-hub.sh") < index_of("sync-hub-seed.sh"), \
    "bootstrap must create the hub before the sync refreshes it"
assert index_of("sync-hub-seed.sh") < index_of("archive-candidates.sh"), \
    "the sync must run before the reporting hooks"
PY

printf 'ok - hook registration and ordering\n'
printf 'seed sync contract tests passed\n'
