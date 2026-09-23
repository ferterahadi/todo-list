#!/usr/bin/env bash
# bootstrap-hub.sh never replaces a file that already exists — on a fresh hub or an
# established one, with BSD or GNU tools — backfills missing docs once, and reports
# customised hub docs once per shipped-doc revision.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/bootstrap-hub.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/todo-bootstrap-contract.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

expect_equal() {
  [ "$3" = "$2" ] || fail "$1"$'\n'"expected: $2"$'\n'"actual:   $3"
}

# A private plugin root, so a test can change the shipped seed without touching the repo.
PLUGIN="$TMP/plugin"
mkdir -p "$PLUGIN"
cp -R "$ROOT/seed" "$PLUGIN/seed"
run_hook() {
  PLUGIN_ROOT="$PLUGIN" TODO_HUB="$1" bash "$HOOK"
}

# No `cp` no-clobber flag is trusted: BSD `cp -n` fails on an existing file and GNU
# changed its meaning, which is how a fallback `cp -R` once overwrote hub files.
if grep -Ev '^[[:space:]]*#' "$HOOK" | grep -Eq 'cp[[:space:]]+-[A-Za-z]*n'; then
  fail "bootstrap-hub.sh must not depend on cp -n semantics"
fi

# Fresh hub: every seed file lands, dotfiles included.
fresh="$TMP/fresh hub"
fresh_output="$(run_hook "$fresh")"
case "$fresh_output" in
  "todo-list: created your project hub at $fresh "*) ;;
  *) fail "fresh bootstrap must announce itself once: $fresh_output" ;;
esac
(cd "$PLUGIN/seed" && find . -type f -print) | while IFS= read -r rel; do
  cmp -s "$PLUGIN/seed/$rel" "$fresh/$rel" || fail "fresh bootstrap missed $rel"
done
[ -f "$fresh/projects/work/example-feature/artifacts/.gitkeep" ] ||
  fail "fresh bootstrap must copy .gitkeep files"
expect_equal "a seeded hub is silent on the next session" "" "$(run_hook "$fresh")"
printf 'ok - fresh hub gets the whole seed\n'

# A folder that exists without index.md takes the fresh path; it must keep what is there,
# including a symlink, and must not write through it.
partial="$TMP/partial"
mkdir -p "$partial/templates"
printf 'MY AGENTS\n' > "$partial/AGENTS.md"
printf 'MY PLAN TEMPLATE\n' > "$partial/templates/plan.md"
printf 'LINK TARGET\n' > "$TMP/claude-target.md"
ln -s "$TMP/claude-target.md" "$partial/CLAUDE.md"
run_hook "$partial" > /dev/null
expect_equal "custom AGENTS.md survives" "MY AGENTS" "$(cat "$partial/AGENTS.md")"
expect_equal "custom template survives" "MY PLAN TEMPLATE" "$(cat "$partial/templates/plan.md")"
[ -L "$partial/CLAUDE.md" ] || fail "an existing symlink must not be replaced"
expect_equal "a symlink target is never written" "LINK TARGET" "$(cat "$TMP/claude-target.md")"
[ -f "$partial/index.md" ] || fail "the missing index.md must still be seeded"
[ -f "$partial/templates/tasks.md" ] || fail "missing templates must still be seeded"
printf 'ok - fresh path never overwrites\n'

# Established hub: a missing doc or template is backfilled once; registries are never
# replaced; the example project is never recopied.
established="$TMP/established"
mkdir -p "$established"
printf '# Project Index\n\nMY ROWS\n' > "$established/index.md"
backfill_output="$(run_hook "$established")"
case "$backfill_output" in
  *"added $established/AGENTS.md"*"added $established/templates/"*) ;;
  *) fail "backfill must announce each added doc and template: $backfill_output" ;;
esac
expect_equal "registry content is never replaced" \
  "$(printf '# Project Index\n\nMY ROWS')" "$(cat "$established/index.md")"
[ ! -d "$established/projects" ] || fail "backfill must not recopy the example project"
expect_equal "backfill is idempotent" "" "$(run_hook "$established")"
rm "$established/templates/tasks.md"
readd_output="$(run_hook "$established")"
case "$readd_output" in
  *"added $established/templates/tasks.md"*) ;;
  *) fail "a deleted template must be backfilled again: $readd_output" ;;
esac
printf 'ok - established hub backfills once\n'

# Drift: reported once per shipped-doc revision, never resolved by overwriting.
printf '\nMY OWN HUB RULE\n' >> "$established/AGENTS.md"
first_drift="$(run_hook "$established")"
case "$first_drift" in
  *'differ from the shipped versions: AGENTS.md.'*) ;;
  *) fail "doc drift must be reported: $first_drift" ;;
esac
grep -q 'MY OWN HUB RULE' "$established/AGENTS.md" || fail "a customised doc must be kept"
[ -f "$established/.todo-list/doc-drift-notice" ] || fail "the drift marker must be written"
expect_equal "the same shipped revision is not reported twice" "" "$(run_hook "$established")"
printf '\nA NEWER SHIPPED LINE\n' >> "$PLUGIN/seed/REGISTRY.md"
second_drift="$(run_hook "$established")"
case "$second_drift" in
  *'differ from the shipped versions: AGENTS.md REGISTRY.md.'*) ;;
  *) fail "a new shipped-doc revision must report drift again: $second_drift" ;;
esac
expect_equal "the new revision is reported once" "" "$(run_hook "$established")"
cp "$PLUGIN/seed/AGENTS.md" "$established/AGENTS.md"
cp "$PLUGIN/seed/REGISTRY.md" "$established/REGISTRY.md"
expect_equal "matching docs are silent" "" "$(run_hook "$established")"
printf 'ok - drift is reported once per shipped-doc revision\n'

printf 'bootstrap contract tests passed\n'
