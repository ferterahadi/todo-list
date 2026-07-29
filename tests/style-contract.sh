#!/usr/bin/env bash
# Contract for /todo-style: the response-style pack is installed only through a verified
# backup, and nothing the user already had is ever lost.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill_dir="$repo_root/skills/todo-style"
script="$skill_dir/scripts/agent-style.sh"
claude_asset="$skill_dir/assets/CLAUDE.md"
codex_asset="$skill_dir/assets/AGENTS.md"

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

expect_same_file() {
  cmp -s "$2" "$3" || fail "$1 ($2 != $3)"
}

expect_differ() {
  cmp -s "$2" "$3" && fail "$1 ($2 == $3)"
  return 0
}

expect_contains() {
  grep -Fq "$2" <<< "$1" || fail "$3"
}

backup_count() {
  local dir="$1" pattern="$2" file count=0
  for file in "$dir"/$pattern; do
    [ -e "$file" ] || continue
    count=$((count + 1))
  done
  printf '%s\n' "$count"
}

[ -f "$script" ] || fail "the style helper is missing"
[ -x "$script" ] || fail "the style helper is not executable"
[ -s "$claude_asset" ] || fail "the Claude Code style pack is missing or empty"
[ -s "$codex_asset" ] || fail "the Codex style pack is missing or empty"

# --- the two packs stay in step ---------------------------------------------
# The Codex pack is a harness port of the Claude one, not a fork. Same sections, in the
# same order, or a rule added to one silently goes missing from the other.
claude_sections="$(grep -E '^## ' "$claude_asset")"
codex_sections="$(grep -E '^## ' "$codex_asset")"
[ "$claude_sections" = "$codex_sections" ] ||
  fail "the Claude and Codex style packs have different '## ' sections"

for asset in "$claude_asset" "$codex_asset"; do
  grep -Fq 'CTO' "$asset" &&
    fail "style pack names a job title instead of describing the reader: ${asset#"$repo_root"/}"
  grep -Fq '## AUDIENCE' "$asset" ||
    fail "style pack has no AUDIENCE section: ${asset#"$repo_root"/}"
done

# Both packs put below-the-fold evidence behind the same rule and heading — one form, not
# a per-surface branch the agent has to guess at.
for asset in "$claude_asset" "$codex_asset"; do
  grep -Fq '### Technical detail' "$asset" ||
    fail "style pack lost its below-the-fold heading: ${asset#"$repo_root"/}"
  grep -Fq '<details><summary>' "$asset" &&
    fail "style pack still branches to an accordion: ${asset#"$repo_root"/}"
done
grep -Fq 'Never use `<details>`' "$codex_asset" ||
  fail "the Codex pack must forbid <details> outright"

# Harness-specific rules must actually differ — a copy-paste of the Claude pack into the
# Codex slot would tell Codex to emit artifact widgets and click-to-choose pickers a
# terminal cannot render.
grep -Fq 'artifact' "$claude_asset" ||
  fail "the Claude pack lost its artifact-widget rule"
grep -Fq 'artifact' "$codex_asset" &&
  fail "the Codex pack points at artifact widgets Codex cannot render"
grep -Fq 'no click-to-choose control' "$codex_asset" ||
  fail "the Codex pack must say the comparison table is the whole interface"

# --- the call-to-action stays one word, and one word only -------------------
# The banner is the landmark the reader scrolls for. Two spellings across the two packs,
# or a stray second arrow, and it stops being a landmark.
for asset in "$claude_asset" "$codex_asset"; do
  grep -Fq '## ➡️ CHOOSE' "$asset" ||
    fail "style pack lost the '## ➡️ CHOOSE' banner: ${asset#"$repo_root"/}"
  grep -Fq 'YOUR CALL' "$asset" &&
    fail "style pack still uses the old 'YOUR CALL' banner: ${asset#"$repo_root"/}"
  grep -Fq '**Action:**' "$asset" ||
    fail "style pack lost the 'Action:' option label: ${asset#"$repo_root"/}"
  grep -Fq '**Trade-off:**' "$asset" ||
    fail "style pack lost the 'Trade-off:' option label: ${asset#"$repo_root"/}"
  grep -Fq 'Bullets are the default shape for explanation' "$asset" ||
    fail "style pack lost the bullets-by-default rule: ${asset#"$repo_root"/}"
done

# --- sandbox ----------------------------------------------------------------
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

hub="$fixture_root/hub"
claude_home="$fixture_root/dot-claude"
codex_home="$fixture_root/dot-codex"
claude_target="$claude_home/CLAUDE.md"
codex_target="$codex_home/AGENTS.md"
backups="$hub/backups/agent-instructions"

run_style() {
  TODO_HUB="$hub" \
  CLAUDE_CONFIG_DIR="$claude_home" \
  CODEX_HOME="$codex_home" \
    bash "$script" "$@"
}

# --- fresh machine: no target file, so no backup ----------------------------
output="$(run_style install claude)"
expect_contains "$output" 'no previous file existed' \
  "install on a fresh machine must say no backup was needed"
expect_same_file "install must write the shipped pack" "$claude_target" "$claude_asset"
expect_equal "a fresh install must not create a backup" \
  "0" "$(backup_count "$backups" 'claude-CLAUDE-*.md')"

# --- already current: no-op, and no redundant backup ------------------------
output="$(run_style install claude)"
expect_contains "$output" 'already current' \
  "re-installing an unchanged file must be a no-op"
expect_equal "a no-op install must not create a backup" \
  "0" "$(backup_count "$backups" 'claude-CLAUDE-*.md')"

# --- existing hand-written file: backed up before it is replaced ------------
original="$fixture_root/original-CLAUDE.md"
printf '%s\n' '# my own rules' 'always run the linter' > "$original"
cp "$original" "$claude_target"

output="$(run_style install claude)"
expect_contains "$output" 'backed up to' "install must report where the backup landed"
expect_equal "replacing a file must create exactly one backup" \
  "1" "$(backup_count "$backups" 'claude-CLAUDE-*.md')"

backup_file="$(printf '%s\n' "$backups"/claude-CLAUDE-*.md | head -n 1)"
expect_same_file "the backup must hold the user's original file" "$backup_file" "$original"
expect_same_file "the target must now hold the shipped pack" "$claude_target" "$claude_asset"
[ -f "$backups/README.md" ] || fail "the backup folder must explain itself"

# The reported path must be the real one — the skill relays this line verbatim.
expect_contains "$output" "$backup_file" "the reported backup path must exist on disk"

# --- restore: original comes back, and restoring again is a no-op -----------
output="$(run_style restore claude)"
expect_same_file "restore must bring the user's original file back" \
  "$claude_target" "$original"
# The file restore replaced was the untouched shipped pack, which the plugin can hand back
# at any time — backing it up would only churn the folder.
expect_equal "restore must not back up a file that ships with the plugin" \
  "1" "$(backup_count "$backups" 'claude-CLAUDE-*.md')"

output="$(run_style restore claude)"
expect_contains "$output" 'already matches' "a redundant restore must change nothing"
expect_equal "a redundant restore must not create a backup" \
  "1" "$(backup_count "$backups" 'claude-CLAUDE-*.md')"

# A file the user edited after installing is their content, so restore must save it.
printf '%s\n' 'my own tweak' >> "$claude_target"
run_style restore claude >/dev/null
expect_equal "restore must back up a file the user edited" \
  "2" "$(backup_count "$backups" 'claude-CLAUDE-*.md')"
expect_same_file "the user's original file survived every round trip" \
  "$backup_file" "$original"

# --- nothing is ever deleted ------------------------------------------------
surviving="$(backup_count "$backups" 'claude-CLAUDE-*.md')"
[ "$surviving" -ge 2 ] || fail "backups were removed; this script must only ever add"

# --- codex side is independent and honors CODEX_HOME ------------------------
mkdir -p "$codex_home"
printf '%s\n' '# codex notes' > "$codex_target"
output="$(run_style install codex)"
expect_same_file "the Codex pack must install to CODEX_HOME/AGENTS.md" \
  "$codex_target" "$codex_asset"
expect_differ "the Codex pack must not be the Claude pack" "$codex_target" "$claude_asset"
expect_equal "installing Codex must not back up Claude's file" \
  "$surviving" "$(backup_count "$backups" 'claude-CLAUDE-*.md')"
expect_equal "installing Codex must back up the Codex file" \
  "1" "$(backup_count "$backups" 'codex-AGENTS-*.md')"

# --- restore with no backup at all reports and changes nothing --------------
empty_hub="$fixture_root/empty-hub"
empty_claude="$fixture_root/empty-dot-claude"
mkdir -p "$empty_claude"
printf '%s\n' 'untouched' > "$empty_claude/CLAUDE.md"
output="$(
  TODO_HUB="$empty_hub" CLAUDE_CONFIG_DIR="$empty_claude" CODEX_HOME="$codex_home" \
    bash "$script" restore claude
)"
expect_contains "$output" 'nothing to restore' \
  "restore without a backup must say so"
expect_equal "restore without a backup must leave the file alone" \
  "untouched" "$(cat "$empty_claude/CLAUDE.md")"

# --- status and hub resolution ----------------------------------------------
output="$(run_style status)"
expect_contains "$output" "$hub" "status must name the hub it resolved"
expect_contains "$output" "$claude_target" "status must name the Claude target"
expect_contains "$output" "$codex_target" "status must name the Codex target"
expect_contains "$output" 'current (already the shipped style pack)' \
  "status must recognize an installed pack"

# --- bad input fails closed --------------------------------------------------
run_style install nonsense >/dev/null 2>&1 &&
  fail "an unknown agent must be rejected"
run_style frobnicate >/dev/null 2>&1 &&
  fail "an unknown mode must be rejected"

# A named-backup restore needs one agent, not both.
run_style restore both "$backup_file" >/dev/null 2>&1 &&
  fail "restoring a named backup across both agents must be rejected"

printf 'ok - style contract\n'
