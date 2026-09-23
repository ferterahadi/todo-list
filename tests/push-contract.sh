#!/usr/bin/env bash
# Contract test for /todo-push's deterministic helpers.
# Proves preflight.sh reports repo facts without mutating anything, and that land.sh
# commits only what it was told to, refuses unsafe arguments, is re-entrant, and never
# runs the checkout/delete-branch commands git rejects inside a linked worktree. Also
# covers the recovery paths: rebase conflicts, dirty trees, a re-run after a hand-resolved
# rebase, a failed `gh pr create`, and --merge-existing for a merge queue.
# `gh` is stubbed on PATH — nothing here talks to GitHub.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
preflight="$repo_root/skills/todo-push/scripts/preflight.sh"
land="$repo_root/skills/todo-push/scripts/land.sh"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

expect_equal() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" != "$expected" ]; then
    printf 'not ok - %s\nexpected: %s\nactual:   %s\n' \
      "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

expect_text_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  case "$haystack" in
    *"$needle"*) ;;
    *)
      printf 'not ok - %s\nexpected to contain: %s\nactual: %s\n' \
        "$label" "$needle" "$haystack" >&2
      exit 1
      ;;
  esac
}

expect_text_lacks() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  case "$haystack" in
    *"$needle"*)
      printf 'not ok - %s\nmust not contain: %s\nactual: %s\n' \
        "$label" "$needle" "$haystack" >&2
      exit 1
      ;;
  esac
}

# Read one dotted field out of a JSON object on stdin.
field() {
  python3 -c '
import json, sys
value = json.load(sys.stdin)
keys = sys.argv[1].split(".", 1) if "/" in sys.argv[1] else sys.argv[1].split(".")
for key in keys:
    if not isinstance(value, dict) or key not in value:
        print("<missing>")
        raise SystemExit(0)
    value = value[key]
print(value if isinstance(value, str) else json.dumps(value))
' "$1"
}

# stdout must be exactly one JSON object — git noise on stdout would corrupt the handoff.
expect_json() {
  local label="$1"
  local text="$2"
  python3 -c 'import json, sys; json.loads(sys.argv[1])' "$text" 2> /dev/null ||
    { printf 'not ok - %s\nstdout is not one JSON object:\n%s\n' "$label" "$text" >&2; exit 1; }
}

[ -f "$preflight" ] || fail "preflight helper is missing"
[ -f "$land" ] || fail "land helper is missing"

# Physical path — git reports resolved paths, so the fixtures must not sit behind a symlink
# (macOS puts mktemp dirs under /var, a link to /private/var).
work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$work"' EXIT

# Runs a command, leaving its status in $run_code and its output in $run_out / $run_err.
# Not a command substitution: the callers need the captured output too.
run() {
  run_code=0
  "$@" > "$work/run.out" 2> "$work/run.err" || run_code=$?
  run_out="$(cat "$work/run.out")"
  run_err="$(cat "$work/run.err")"
}

# ---------------------------------------------------------------------------
# gh stub. Records every invocation so tests can assert on the flags used.
# ---------------------------------------------------------------------------
stub_bin="$work/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${GH_STUB_LOG:?GH_STUB_LOG unset}"
case "${1:-} ${2:-}" in
  "auth status")
    [ "${GH_STUB_AUTH:-ok}" = ok ] || { echo "not logged in" >&2; exit 1; }
    printf '  - Logged in to github.com account %s (keyring)\n' "${GH_STUB_ACCOUNT:-stub-user}"
    ;;
  "repo view")
    printf '{"nameWithOwner":"acme/demo","viewerPermission":"%s",%s}\n' \
      "${GH_STUB_VIEWER_PERMISSION:-WRITE}" \
      "${GH_STUB_MERGE_SETTINGS:-"\"mergeCommitAllowed\":true,\"squashMergeAllowed\":false,\"rebaseMergeAllowed\":false"}"
    ;;
  "pr list")
    printf '%s\n' "${GH_STUB_PR_LIST:-[]}"
    ;;
  "pr create")
    if [ "${GH_STUB_PR_CREATE:-ok}" = fail ]; then
      echo "pull request create failed: GraphQL: must be a collaborator" >&2
      exit 1
    fi
    printf '%s\n' "${GH_STUB_PR_URL:-https://github.com/acme/demo/pull/1}"
    ;;
  "pr view")
    printf '%s\n' "${GH_STUB_MERGE_STATE:-CLEAN}"
    ;;
  "pr merge")
    case "${GH_STUB_MERGE:-ok}" in
      blocked)
        echo "GraphQL: Changes must be reviewed by a code owner" >&2
        exit 1
        ;;
      dirty)
        echo "Pull request is not mergeable" >&2
        exit 1
        ;;
      dirty-once)
        # Refused the first time — base moved underneath the PR — accepted after the sync.
        if [ ! -e "${GH_STUB_ONCE:?GH_STUB_ONCE unset}" ]; then
          : > "$GH_STUB_ONCE"
          echo "Pull request is not mergeable: the base branch was modified" >&2
          exit 1
        fi
        ;;
    esac
    # Emulate the server-side merge so the local ff-only pull has something to take.
    git push -q origin "HEAD:${GH_STUB_BASE:-main}"
    ;;
  *)
    echo "gh stub: unhandled: $*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$stub_bin/gh"
PATH="$stub_bin:$PATH"
export PATH
export GH_STUB_LOG="$work/gh.log"
export GH_STUB_ONCE="$work/merge-refused-once"
: > "$GH_STUB_LOG"

# Keep the machine's real git identity and hooks out of the scratch repos.
export GIT_CONFIG_GLOBAL="$work/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
: > "$GIT_CONFIG_GLOBAL"
# A rebase --continue in a fixture must not wait on an editor.
export GIT_EDITOR=true

new_repo() {
  local name="$1"
  local root="$work/$name"
  local remote="$work/$name-remote.git"
  mkdir -p "$root"
  git init -q -b main "$root"
  git -C "$root" config user.email test@example.com
  git -C "$root" config user.name "Contract Test"
  printf 'test:\n\t@echo ok\n' > "$root/Makefile"
  printf 'seed\n' > "$root/README.md"
  git -C "$root" add Makefile README.md
  git -C "$root" commit -q -m 'seed'
  git init -q --bare "$remote"
  git -C "$root" remote add origin "$remote"
  git -C "$root" push -q -u origin main
  git -C "$root" remote set-head origin main
  printf '%s\n' "$root"
}

# Another session lands a commit on origin/main while this one is mid-ship.
land_upstream() {
  local name="$1"
  local path="$2"
  local content="$3"
  local other="$work/$name-other"
  if [ ! -d "$other" ]; then
    git clone -q "$work/$name-remote.git" "$other"
    git -C "$other" config user.email other@example.com
    git -C "$other" config user.name "Other Session"
  fi
  git -C "$other" pull -q --ff-only origin main
  printf '%s\n' "$content" > "$other/$path"
  git -C "$other" add -- "$path"
  git -C "$other" commit -q -m "upstream: $path"
  git -C "$other" push -q origin HEAD:main
}

remote_tip() {
  git -C "$1" ls-remote --heads origin "refs/heads/$2" | awk '{print $1}'
}

rebase_in_progress() {
  [ -d "$(git -C "$1" rev-parse --git-path rebase-merge)" ] ||
    [ -d "$(git -C "$1" rev-parse --git-path rebase-apply)" ]
}

printf 'seed message: why this change exists\n' > "$work/msg.txt"
printf '## Summary\n\n- adds a feature\n\n## Test plan\n\n- [x] make test\n' > "$work/body.txt"

# ---------------------------------------------------------------------------
# preflight.sh
# ---------------------------------------------------------------------------
alpha="$(new_repo alpha)"
printf 'changed\n' >> "$alpha/README.md"
printf 'junk\n' > "$alpha/.DS_Store"
printf 'plan\n' > "$alpha/local.tfplan"
mkdir -p "$alpha/newdir"
printf 'nested\n' > "$alpha/newdir/nested.txt"

cd "$alpha"
run bash "$preflight"
expect_equal "preflight exits zero on a dirty repo" 0 "$run_code"
report="$run_out"

expect_equal "preflight reports base" main "$(field base <<< "$report")"
expect_equal "preflight reports current branch" main "$(field current_branch <<< "$report")"
expect_equal "preflight reports a dirty tree" true "$(field dirty <<< "$report")"
expect_equal "preflight reports non-worktree" false "$(field is_worktree <<< "$report")"
expect_equal "preflight confirms gh auth" true "$(field gh_auth <<< "$report")"
expect_equal "preflight confirms origin" true "$(field has_origin <<< "$report")"
expect_equal "preflight reports repo root" "$alpha" "$(field repo_root <<< "$report")"
changed="$(field changed_files <<< "$report")"
expect_text_contains "changed files list README.md" "$changed" "README.md"
# Untracked files are listed individually — a collapsed "newdir/" can't be passed to --file.
expect_text_contains "changed files name files inside a new directory" \
  "$changed" "newdir/nested.txt"
suspicious="$(field untracked_suspicious <<< "$report")"
expect_text_contains "suspicious files flag .DS_Store" "$suspicious" ".DS_Store"
expect_text_contains "suspicious files flag .tfplan output" "$suspicious" "local.tfplan"
expect_equal "allowed strategies come from the repo" '["merge"]' \
  "$(field allowed_merge_strategies <<< "$report")"
expect_equal "makefile test target is a candidate" "make test" \
  "$(field test_cmd_candidates.makefile <<< "$report")"
# A doc candidate points the caller at untrusted repo prose, so it is only offered when the
# doc really declares how to run tests. Prose that merely says "test" must not manufacture one.
printf 'This project is well tested.\n' > "$alpha/CLAUDE.md"
run bash "$preflight"
expect_equal "prose mentioning tests is not a command pointer" "<missing>" \
  "$(field test_cmd_candidates.CLAUDE_md <<< "$run_out")"
printf 'Test command: `make test`\n' > "$alpha/CLAUDE.md"
run bash "$preflight"
expect_equal "a declared test command is a doc candidate" "see CLAUDE.md" \
  "$(field test_cmd_candidates.CLAUDE_md <<< "$run_out")"
rm -f "$alpha/CLAUDE.md"
# Allowed is not the same as used: a linear history means the repo squashes or rebases,
# whatever gh reports as permitted.
expect_equal "a linear history reads as linear" linear \
  "$(field observed_merge_pattern <<< "$report")"
expect_equal "a linear history counts no merge commits" 0 \
  "$(field recent_merge_commits <<< "$report")"
expect_equal "a linear, merge-only repo is handed the merge strategy" merge \
  "$(field recommended_strategy <<< "$report")"
expect_equal "a clean base counts nothing ahead" 0 "$(field ahead_of_base <<< "$report")"
expect_equal "ahead is measured against the remote-tracking base" origin/main \
  "$(field compare_ref <<< "$report")"

# Two gh calls, no more: one auth status, one repo view that answers permission and strategy.
: > "$GH_STUB_LOG"
run bash "$preflight"
expect_equal "preflight makes exactly two gh calls" 2 "$(wc -l < "$GH_STUB_LOG" | tr -d ' ')"
expect_equal "preflight asks gh auth once" 1 "$(grep -c '^auth status' "$GH_STUB_LOG")"
expect_equal "preflight asks gh repo view once" 1 "$(grep -c '^repo view' "$GH_STUB_LOG")"

# A linear history on a repo that allows squash is handed squash, not the first allowed.
run env GH_STUB_MERGE_SETTINGS='"mergeCommitAllowed":true,"squashMergeAllowed":true,"rebaseMergeAllowed":false' \
  bash "$preflight"
expect_equal "a linear history that may squash is handed squash" squash \
  "$(field recommended_strategy <<< "$run_out")"

# Shell test scripts are one candidate each: `bash tests/*.sh` would run only the first.
mkdir -p "$alpha/tests"
printf 'exit 0\n' > "$alpha/tests/one.sh"
printf 'exit 0\n' > "$alpha/tests/two.sh"
run bash "$preflight"
expect_equal "each shell test script is its own candidate" "bash tests/two.sh" \
  "$(field 'test_cmd_candidates.shell_tests/two.sh' <<< "$run_out")"
expect_text_lacks "no candidate globs the tests directory" "$run_out" 'tests/*.sh'
rm -rf "$alpha/tests"

# Read-only: the suspicious files it reported are still on disk, nothing staged.
[ -f "$alpha/.DS_Store" ] || fail "preflight removed an untracked file"
expect_equal "preflight stages nothing" "" "$(git -C "$alpha" diff --cached --name-only)"

# origin/HEAD missing — base still resolves via the remote.
git -C "$alpha" update-ref -d refs/remotes/origin/HEAD
run bash "$preflight"
expect_equal "preflight survives a missing origin/HEAD" 0 "$run_code"
expect_equal "base falls back to the remote's default" main "$(field base <<< "$run_out")"

# Clean tree — nothing to ship is an error, before anything mutates.
beta="$(new_repo beta)"
cd "$beta"
run bash "$preflight"
expect_equal "preflight fails on a clean tree" 1 "$run_code"
expect_text_contains "clean tree names the reason" "$run_out$run_err" "nothing to ship"

# A history made of merge commits reads the other way.
iota="$(new_repo iota)"
for n in 1 2; do
  git -C "$iota" checkout -q -b "side-$n" main
  printf 'side %s\n' "$n" > "$iota/side-$n.txt"
  git -C "$iota" add "side-$n.txt"
  git -C "$iota" commit -q -m "side $n"
  git -C "$iota" checkout -q main
  git -C "$iota" merge -q --no-ff --no-edit "side-$n"
done
printf 'changed\n' >> "$iota/README.md"
cd "$iota"
run bash "$preflight"
expect_equal "preflight reads a merge-commit history" 0 "$run_code"
expect_equal "a merge history reads as merge" merge \
  "$(field observed_merge_pattern <<< "$run_out")"
expect_equal "a merge history counts its merge commits" 2 \
  "$(field recent_merge_commits <<< "$run_out")"
expect_equal "a merge history is handed the merge strategy" merge \
  "$(field recommended_strategy <<< "$run_out")"

# No origin remote.
gamma="$(new_repo gamma)"
git -C "$gamma" remote remove origin
printf 'changed\n' >> "$gamma/README.md"
cd "$gamma"
run bash "$preflight"
expect_equal "preflight fails without origin" 1 "$run_code"
expect_text_contains "missing origin names the reason" "$run_out$run_err" "origin"

# gh not authenticated.
cd "$alpha"
run env GH_STUB_AUTH=fail bash "$preflight"
expect_equal "preflight fails when gh is unauthenticated" 1 "$run_code"
expect_text_contains "unauthenticated gh names the reason" "$run_out$run_err" "gh auth"

# Logged in is not the same as able to open a PR: an account with read-only access fails
# here, before land.sh branches and pushes, and the message names the account to switch off.
run env GH_STUB_VIEWER_PERMISSION=READ GH_STUB_ACCOUNT=work-account bash "$preflight"
expect_equal "preflight fails on read-only access" 1 "$run_code"
expect_text_contains "read-only access names the active account" \
  "$run_out$run_err" "work-account"
expect_text_contains "read-only access names the permission" "$run_out$run_err" "READ"
expect_text_contains "read-only access names the repo" "$run_out$run_err" "acme/demo"
expect_text_contains "read-only access points at the fix" "$run_out$run_err" "gh auth switch"

run env GH_STUB_VIEWER_PERMISSION=NONE GH_STUB_ACCOUNT=work-account bash "$preflight"
expect_equal "preflight fails when the account has no access" 1 "$run_code"
expect_text_contains "no access names the active account" "$run_out$run_err" "work-account"

for permission in WRITE ADMIN; do
  run env GH_STUB_VIEWER_PERMISSION="$permission" GH_STUB_ACCOUNT=personal bash "$preflight"
  expect_equal "preflight passes on $permission access" 0 "$run_code"
  expect_equal "preflight reports $permission" "$permission" \
    "$(field viewer_permission <<< "$run_out")"
  expect_equal "preflight reports the active account" personal \
    "$(field gh_account <<< "$run_out")"
done

# ---------------------------------------------------------------------------
# land.sh — argument validation fails closed before touching the repo
# ---------------------------------------------------------------------------
delta="$(new_repo delta)"
printf 'feature\n' > "$delta/feature.txt"
cd "$delta"

run bash "$land" --branch 'feat/x;rm -rf /' --message-file "$work/msg.txt" \
  --title 'bad' --body-file "$work/body.txt" --file feature.txt --base main
expect_equal "land rejects a branch name with shell metacharacters" 12 "$run_code"
expect_json "a precondition failure still prints one JSON object" "$run_out"
expect_text_contains "the precondition JSON names the problem" \
  "$(field error <<< "$run_out")" "--branch"
expect_equal "a precondition failure reports nothing done" "[]" "$(field done <<< "$run_out")"

run bash "$land" --branch --admin --message-file "$work/msg.txt" \
  --title 'flag as branch' --body-file "$work/body.txt" --file feature.txt --base main
expect_equal "land rejects a branch name that reads as a flag" 12 "$run_code"

run bash "$land" --branch feat/ok --message-file "$work/msg.txt" \
  --title 'outside' --body-file "$work/body.txt" --file ../elsewhere.txt --base main
expect_equal "land rejects a path outside the repo" 12 "$run_code"

run bash "$land" --branch feat/ok --message-file "$work/msg.txt" \
  --title 'dangling' --body-file "$work/body.txt" --file feature.txt --base
expect_equal "land rejects a flag missing its value" 12 "$run_code"
expect_equal "rejected branch created no branch" main "$(git -C "$delta" branch --show-current)"

run bash "$land" --branch feat/ok --message-file "$work/nope.txt" \
  --title 'missing message' --body-file "$work/body.txt" --file feature.txt --base main
expect_equal "land rejects a missing message file" 12 "$run_code"

run bash "$land" --branch feat/ok --message-file "$work/msg.txt" \
  --title 'missing file' --body-file "$work/body.txt" --file ghost.txt --base main
expect_equal "land rejects a named file that does not exist" 12 "$run_code"

run bash "$land" --branch feat/ok --message-file "$work/msg.txt" \
  --title 'no files' --body-file "$work/body.txt" --base main
expect_equal "land needs a --file when no commits sit ahead of base" 12 "$run_code"
expect_text_contains "no files and no commits names the reason" \
  "$(field error <<< "$run_out")" "nothing to ship"

run bash "$land" --branch feat/ok --message-file "$work/msg.txt" \
  --title 'bad strategy' --body-file "$work/body.txt" --file feature.txt \
  --base main --strategy octopus
expect_equal "land rejects an unknown merge strategy" 12 "$run_code"

run bash "$land" --branch feat/ok --message-file "$work/msg.txt" \
  --title 'bad base' --body-file "$work/body.txt" --file feature.txt --base 'main;id'
expect_equal "land rejects a base name with shell metacharacters" 12 "$run_code"

expect_equal "no failed validation left a commit behind" main \
  "$(git -C "$delta" branch --show-current)"

# ---------------------------------------------------------------------------
# land.sh — happy path stages only what it was told to
# ---------------------------------------------------------------------------
printf 'scratch\n' > "$delta/scratch.tfplan"
: > "$GH_STUB_LOG"
run bash "$land" --branch feat/adds-feature --message-file "$work/msg.txt" \
  --title 'Add feature' --body-file "$work/body.txt" --file feature.txt --base main
expect_equal "land ships the happy path" 0 "$run_code"
result="$run_out"
expect_equal "result reports the PR url" "https://github.com/acme/demo/pull/1" \
  "$(field pr_url <<< "$result")"
expect_equal "result reports the merge" true "$(field merged <<< "$result")"
expect_equal "result reports the branch" feat/adds-feature "$(field branch <<< "$result")"
expect_equal "result reports the strategy" merge "$(field strategy <<< "$result")"

committed="$(git -C "$delta" show --stat --name-only --format= feat/adds-feature)"
expect_text_contains "the named file was committed" "$committed" "feature.txt"
expect_text_lacks "the unnamed scratch file was not committed" "$committed" "scratch.tfplan"
[ -f "$delta/scratch.tfplan" ] || fail "land deleted an untracked file it should have left alone"
expect_text_contains "result names what it left out" \
  "$(field unstaged_reported <<< "$result")" "scratch.tfplan"

expect_equal "land ends on the base branch" main "$(git -C "$delta" branch --show-current)"
expect_equal "local base took the merge" \
  "$(git -C "$delta" rev-parse origin/main)" "$(git -C "$delta" rev-parse main)"
expect_equal "result reports base synced" true "$(field base_synced <<< "$result")"

gh_calls="$(cat "$GH_STUB_LOG")"
expect_text_contains "land opened the PR" "$gh_calls" "pr create"
expect_text_contains "land passed the base to gh" "$gh_calls" "--base main"

# ---------------------------------------------------------------------------
# land.sh — re-entrancy: a second identical run is a no-op, not a second PR
# ---------------------------------------------------------------------------
epsilon="$(new_repo epsilon)"
printf 'feature\n' > "$epsilon/feature.txt"
cd "$epsilon"
: > "$GH_STUB_LOG"
run bash "$land" --branch feat/twice --message-file "$work/msg.txt" \
  --title 'Twice' --body-file "$work/body.txt" --file feature.txt --base main --no-merge
expect_equal "land stops at the PR with --no-merge" 0 "$run_code"
expect_equal "--no-merge reports no merge" false "$(field merged <<< "$run_out")"
expect_text_lacks "--no-merge never called gh pr merge" "$(cat "$GH_STUB_LOG")" "pr merge"
first_commit="$(git -C "$epsilon" rev-parse feat/twice)"

: > "$GH_STUB_LOG"
run env GH_STUB_PR_LIST='[{"number":1,"url":"https://github.com/acme/demo/pull/1"}]' \
  bash "$land" --branch feat/twice --message-file "$work/msg.txt" \
  --title 'Twice' --body-file "$work/body.txt" --file feature.txt --base main --no-merge
expect_equal "a repeat run succeeds" 0 "$run_code"
expect_equal "a repeat run adds no commit" "$first_commit" \
  "$(git -C "$epsilon" rev-parse feat/twice)"
expect_text_lacks "a repeat run opens no second PR" "$(cat "$GH_STUB_LOG")" "pr create"
expect_equal "a repeat run reuses the open PR" "https://github.com/acme/demo/pull/1" \
  "$(field pr_url <<< "$run_out")"

# ---------------------------------------------------------------------------
# land.sh — a blocked merge reports the PR and stops, never force-merges
# ---------------------------------------------------------------------------
zeta="$(new_repo zeta)"
printf 'feature\n' > "$zeta/feature.txt"
cd "$zeta"
: > "$GH_STUB_LOG"
run env GH_STUB_MERGE=blocked bash "$land" --branch feat/blocked \
  --message-file "$work/msg.txt" --title 'Blocked' --body-file "$work/body.txt" \
  --file feature.txt --base main
expect_equal "a blocked merge exits 10" 10 "$run_code"
expect_equal "a blocked merge still reports the PR" "https://github.com/acme/demo/pull/1" \
  "$(field pr_url <<< "$run_out")"
expect_equal "a blocked merge reports no merge" false "$(field merged <<< "$run_out")"
expect_text_lacks "a blocked merge never passes --admin" "$(cat "$GH_STUB_LOG")" "--admin"
expect_text_lacks "a blocked merge never force-pushes" "$(cat "$GH_STUB_LOG")" "--force"

# ---------------------------------------------------------------------------
# land.sh — linked worktree: no checkout of base, no --delete-branch
# ---------------------------------------------------------------------------
eta="$(new_repo eta)"
wt="$work/eta-wt"
git -C "$eta" worktree add -q -b feat/in-worktree "$wt" main
printf 'from the worktree\n' > "$wt/wt.txt"
cd "$wt"
: > "$GH_STUB_LOG"
run bash "$land" --branch feat/in-worktree --message-file "$work/msg.txt" \
  --title 'Worktree' --body-file "$work/body.txt" --file wt.txt --base main
expect_equal "land ships from a linked worktree" 0 "$run_code"
result="$run_out"
expect_equal "result flags worktree mode" true "$(field is_worktree <<< "$result")"
expect_text_lacks "worktree merge never passes --delete-branch" \
  "$(cat "$GH_STUB_LOG")" "--delete-branch"
expect_equal "the worktree stays on its own branch" feat/in-worktree \
  "$(git -C "$wt" branch --show-current)"
[ -d "$wt" ] || fail "land removed the worktree it was standing in"
expect_equal "the primary copy stays on base" main "$(git -C "$eta" branch --show-current)"
expect_equal "the primary copy took the merge" \
  "$(git -C "$eta" rev-parse origin/main)" "$(git -C "$eta" rev-parse main)"
expect_text_contains "result hands back the worktree cleanup commands" \
  "$(field cleanup_hint <<< "$result")" "worktree remove"
expect_text_contains "a merge-commit landing keeps the safe branch delete" \
  "$(field cleanup_hint <<< "$result")" "git branch -d feat/in-worktree"

# ---------------------------------------------------------------------------
# land.sh — base detection when --base is omitted
# ---------------------------------------------------------------------------
theta="$(new_repo theta)"
printf 'feature\n' > "$theta/feature.txt"
cd "$theta"
run bash "$land" --branch feat/detects-base --message-file "$work/msg.txt" \
  --title 'Detects base' --body-file "$work/body.txt" --file feature.txt
expect_equal "land detects the base when not given one" 0 "$run_code"
expect_equal "detected base is main" main "$(field base <<< "$run_out")"

# ---------------------------------------------------------------------------
# land.sh — a path staged earlier but not named is never committed
# ---------------------------------------------------------------------------
kappa="$(new_repo kappa)"
printf 'secret\n' > "$kappa/secret.txt"
git -C "$kappa" add secret.txt
printf 'feature\n' > "$kappa/feature.txt"
cd "$kappa"
: > "$GH_STUB_LOG"
run bash "$land" --branch feat/prestaged --message-file "$work/msg.txt" \
  --title 'Prestaged' --body-file "$work/body.txt" --file feature.txt --base main \
  --strategy merge
expect_equal "land ships around a pre-staged file" 0 "$run_code"
expect_json "the happy path prints one JSON object" "$run_out"
committed="$(git -C "$kappa" show --name-only --format= feat/prestaged)"
expect_text_contains "the named file was committed" "$committed" "feature.txt"
expect_text_lacks "a pre-staged, unnamed file was not committed" "$committed" "secret.txt"
expect_text_lacks "a pre-staged file never reached the base" \
  "$(git -C "$kappa" ls-tree -r --name-only origin/main)" "secret.txt"
expect_text_contains "the pre-staged file is reported as not named" \
  "$(field staged_not_named <<< "$run_out")" "secret.txt"
expect_text_contains "the pre-staged file is reported as left out" \
  "$(field unstaged_reported <<< "$run_out")" "secret.txt"
expect_text_contains "the pre-staged file is still staged" \
  "$(git -C "$kappa" diff --cached --name-only)" "secret.txt"
expect_text_lacks "a passed --strategy costs no repo view" "$(cat "$GH_STUB_LOG")" "repo view"

# ---------------------------------------------------------------------------
# land.sh — commits already on the current branch ship under a new branch name
# ---------------------------------------------------------------------------
lambda="$(new_repo lambda)"
git -C "$lambda" checkout -q -b feat/earlier
printf 'earlier\n' > "$lambda/earlier.txt"
git -C "$lambda" add earlier.txt
git -C "$lambda" commit -q -m 'earlier work'
printf 'later\n' > "$lambda/later.txt"
cd "$lambda"
run bash "$preflight"
expect_equal "preflight counts the commit already on the branch" 1 \
  "$(field ahead_of_base <<< "$run_out")"
run bash "$land" --branch feat/renamed --message-file "$work/msg.txt" \
  --title 'Carries' --body-file "$work/body.txt" --file later.txt --base main
expect_equal "land ships a branch that was already ahead" 0 "$run_code"
expect_equal "result counts the carried commit" 1 "$(field carried_commits <<< "$run_out")"
shipped_tree="$(git -C "$lambda" ls-tree -r --name-only origin/main)"
expect_text_contains "the carried commit reached the base" "$shipped_tree" "earlier.txt"
expect_text_contains "the new commit reached the base" "$shipped_tree" "later.txt"

# Clean tree, commits ahead: no --file at all ships the existing commits on their own.
mu="$(new_repo mu)"
git -C "$mu" checkout -q -b feat/committed
printf 'done\n' > "$mu/done.txt"
git -C "$mu" add done.txt
git -C "$mu" commit -q -m 'already committed'
tip="$(git -C "$mu" rev-parse HEAD)"
cd "$mu"
run bash "$preflight"
expect_equal "preflight accepts a clean branch with commits ahead" 0 "$run_code"
run bash "$land" --branch feat/committed --title 'Committed' --body-file "$work/body.txt" \
  --base main
expect_equal "land ships commits with no --file" 0 "$run_code"
expect_equal "shipping existing commits adds none" "$tip" \
  "$(git -C "$mu" rev-parse feat/committed)"
expect_text_contains "the existing commit reached the base" \
  "$(git -C "$mu" ls-tree -r --name-only origin/main)" "done.txt"

# An existing branch that lacks the current HEAD would strand commits — refused up front.
git -C "$mu" checkout -q -b feat/stale "$tip~1"
git -C "$mu" checkout -q feat/committed
printf 'more\n' > "$mu/more.txt"
run bash "$land" --branch feat/stale --message-file "$work/msg.txt" \
  --title 'Stale' --body-file "$work/body.txt" --file more.txt --base main
expect_equal "land refuses a branch that would strand commits" 12 "$run_code"
expect_equal "the refused switch left the checkout alone" feat/committed \
  "$(git -C "$mu" branch --show-current)"
rm -f "$mu/more.txt"

# ---------------------------------------------------------------------------
# land.sh — a staged rename ships as its two paths
# ---------------------------------------------------------------------------
rho="$(new_repo rho)"
git -C "$rho" mv README.md DOCS.md
cd "$rho"
run bash "$preflight"
expect_equal "preflight reads a staged rename" 0 "$run_code"
changed="$(field changed_files <<< "$run_out")"
expect_text_contains "the rename's old side is a changed path" "$changed" '"README.md"'
expect_text_contains "the rename's new side is a changed path" "$changed" '"DOCS.md"'
expect_text_lacks "no path carries an arrow" "$changed" "->"
expect_equal "the rename is reported as a pair" '[{"from": "README.md", "to": "DOCS.md"}]' \
  "$(field renames <<< "$run_out")"
expect_text_contains "a staged rename is a staged path" \
  "$(field staged_files <<< "$run_out")" "DOCS.md"
run bash "$land" --branch chore/rename --message-file "$work/msg.txt" \
  --title 'Rename' --body-file "$work/body.txt" --file README.md --file DOCS.md --base main
expect_equal "land ships a staged rename" 0 "$run_code"
expect_text_contains "the commit records a rename" \
  "$(git -C "$rho" show --name-status -M --format= chore/rename)" "R100"

# ---------------------------------------------------------------------------
# land.sh — gh pr create failing is its own outcome, with the branch already pushed
# ---------------------------------------------------------------------------
pi="$(new_repo pi)"
printf 'feature\n' > "$pi/feature.txt"
cd "$pi"
run env GH_STUB_PR_CREATE=fail bash "$land" --branch feat/no-pr \
  --message-file "$work/msg.txt" --title 'No PR' --body-file "$work/body.txt" \
  --file feature.txt --base main
expect_equal "a failed PR create exits 13" 13 "$run_code"
expect_json "a failed PR create prints one JSON object" "$run_out"
expect_equal "a failed PR create reports no PR" "" "$(field pr_url <<< "$run_out")"
expect_equal "a failed PR create says how far it got" '["branch", "commit", "push"]' \
  "$(field done <<< "$run_out")"
expect_equal "a failed PR create names the step" pr "$(field failed_step <<< "$run_out")"
expect_text_contains "a failed PR create carries gh's reason" \
  "$(field error <<< "$run_out")" "must be a collaborator"
expect_equal "the branch really is pushed" "$(git -C "$pi" rev-parse HEAD)" \
  "$(remote_tip "$pi" feat/no-pr)"
: > "$GH_STUB_LOG"
run bash "$land" --branch feat/no-pr --message-file "$work/msg.txt" --title 'No PR' \
  --body-file "$work/body.txt" --file feature.txt --base main
expect_equal "a re-run after the PR create is fixed ships" 0 "$run_code"
expect_text_contains "the re-run opens the PR" "$(cat "$GH_STUB_LOG")" "pr create"

# ---------------------------------------------------------------------------
# land.sh — a rebase conflict stays parseable, names its files, and a re-run after the
# user resolves it pushes the rebased branch with a lease
# ---------------------------------------------------------------------------
nu="$(new_repo nu)"
printf 'mine\n' > "$nu/README.md"
cd "$nu"
land_upstream nu README.md theirs
: > "$GH_STUB_LOG"
run env GH_STUB_MERGE=dirty GH_STUB_MERGE_STATE=DIRTY bash "$land" --branch feat/clash \
  --message-file "$work/msg.txt" --title 'Clash' --body-file "$work/body.txt" \
  --file README.md --base main --strategy merge
expect_equal "a rebase conflict exits 11" 11 "$run_code"
expect_json "a rebase conflict prints one JSON object" "$run_out"
expect_text_lacks "git's CONFLICT line stays off stdout" "$run_out" "CONFLICT ("
expect_equal "a rebase conflict names the file" '["README.md"]' \
  "$(field conflict_files <<< "$run_out")"
expect_equal "a rebase conflict is not a dirty tree" "[]" "$(field dirty_files <<< "$run_out")"
expect_text_contains "a rebase conflict hands the user the resolution steps" \
  "$(field cleanup_hint <<< "$run_out")" "rebase --continue"
rebase_in_progress "$nu" && fail "the conflicted rebase was left in progress"
clash_tip="$(field commit <<< "$run_out")"
expect_equal "the aborted rebase left the branch where it was" "$clash_tip" \
  "$(git -C "$nu" rev-parse HEAD)"
expect_text_lacks "a conflict never passes --admin" "$(cat "$GH_STUB_LOG")" "--admin"

# The user resolves it by hand. A half-done rebase is refused, not stepped on.
git -C "$nu" rebase -q origin/main > /dev/null 2>&1 || true
rebase_in_progress "$nu" || fail "fixture: the hand rebase did not stop on the conflict"
run bash "$land" --branch feat/clash --message-file "$work/msg.txt" --title 'Clash' \
  --body-file "$work/body.txt" --file README.md --base main --strategy merge
expect_equal "land refuses to run over a rebase in progress" 12 "$run_code"
expect_text_contains "the refusal names the rebase" "$(field error <<< "$run_out")" "rebase"
printf 'resolved\n' > "$nu/README.md"
git -C "$nu" add README.md
git -C "$nu" rebase --continue > /dev/null 2>&1
: > "$GH_STUB_LOG"
run env GH_STUB_PR_LIST='[{"number":1,"url":"https://github.com/acme/demo/pull/1"}]' \
  bash "$land" --branch feat/clash --message-file "$work/msg.txt" --title 'Clash' \
  --body-file "$work/body.txt" --file README.md --base main --strategy merge
expect_equal "a re-run after a hand-resolved rebase ships" 0 "$run_code"
expect_equal "the re-run replaced the old tip with a lease" true \
  "$(field force_pushed <<< "$run_out")"
expect_equal "the resolution reached the base" resolved \
  "$(git -C "$nu" show origin/main:README.md)"
expect_text_lacks "the re-run opened no second PR" "$(cat "$GH_STUB_LOG")" "pr create"

# ---------------------------------------------------------------------------
# land.sh — a dirty tree: unrelated changes ride through the rebase, overlapping ones stop it
# ---------------------------------------------------------------------------
xi="$(new_repo xi)"
printf 'feature\n' > "$xi/feature.txt"
printf 'work in progress\n' >> "$xi/README.md"
cd "$xi"
land_upstream xi upstream.txt landed-first
rm -f "$GH_STUB_ONCE"
run env GH_STUB_MERGE=dirty-once GH_STUB_MERGE_STATE=BEHIND bash "$land" \
  --branch feat/dirty-ok --message-file "$work/msg.txt" --title 'Dirty ok' \
  --body-file "$work/body.txt" --file feature.txt --base main --strategy merge
expect_equal "an unrelated dirty file does not block the rebase" 0 "$run_code"
expect_equal "the rebased branch merged" true "$(field merged <<< "$run_out")"
expect_equal "the rebase replaced the pushed tip with a lease" true \
  "$(field force_pushed <<< "$run_out")"
expect_text_contains "the rebase is reported done" "$(field done <<< "$run_out")" '"rebase"'
expect_text_contains "the left-out change survived the rebase" \
  "$(cat "$xi/README.md")" "work in progress"
expect_text_lacks "the left-out change never reached the base" \
  "$(git -C "$xi" show origin/main:README.md)" "work in progress"
expect_text_contains "the upstream commit is in the merged base" \
  "$(git -C "$xi" ls-tree -r --name-only origin/main)" "upstream.txt"

omicron="$(new_repo omicron)"
printf 'feature\n' > "$omicron/feature.txt"
printf 'work in progress\n' >> "$omicron/README.md"
cd "$omicron"
land_upstream omicron README.md 'rewritten upstream'
run env GH_STUB_MERGE=dirty GH_STUB_MERGE_STATE=BEHIND bash "$land" \
  --branch feat/dirty-clash --message-file "$work/msg.txt" --title 'Dirty clash' \
  --body-file "$work/body.txt" --file feature.txt --base main --strategy merge
expect_equal "an overlapping dirty file stops before the rebase" 14 "$run_code"
expect_json "a dirty-tree stop prints one JSON object" "$run_out"
expect_equal "the dirty-tree stop names the file" '["README.md"]' \
  "$(field dirty_files <<< "$run_out")"
expect_equal "a dirty tree is not a conflict" "[]" "$(field conflict_files <<< "$run_out")"
expect_equal "the dirty-tree stop names the step" rebase "$(field failed_step <<< "$run_out")"
expect_equal "the dirty-tree stop says the PR exists" '["branch", "commit", "push", "pr"]' \
  "$(field done <<< "$run_out")"
expect_text_contains "the dirty file was not touched" \
  "$(cat "$omicron/README.md")" "work in progress"
rebase_in_progress "$omicron" && fail "the dirty-tree stop left a rebase in progress"

# ---------------------------------------------------------------------------
# land.sh — commits someone else pushed to the branch are never overwritten
# ---------------------------------------------------------------------------
upsilon="$(new_repo upsilon)"
printf 'feature\n' > "$upsilon/feature.txt"
cd "$upsilon"
run bash "$land" --branch feat/shared --message-file "$work/msg.txt" --title 'Shared' \
  --body-file "$work/body.txt" --file feature.txt --base main --no-merge
expect_equal "fixture: the shared branch is open" 0 "$run_code"
git clone -q "$work/upsilon-remote.git" "$work/upsilon-other"
git -C "$work/upsilon-other" config user.email other@example.com
git -C "$work/upsilon-other" config user.name "Other Session"
git -C "$work/upsilon-other" checkout -q feat/shared
printf 'theirs\n' > "$work/upsilon-other/theirs.txt"
git -C "$work/upsilon-other" add theirs.txt
git -C "$work/upsilon-other" commit -q -m 'a collaborator commit'
git -C "$work/upsilon-other" push -q origin feat/shared
foreign_tip="$(remote_tip "$upsilon" feat/shared)"
run bash "$land" --branch feat/shared --message-file "$work/msg.txt" --title 'Shared' \
  --body-file "$work/body.txt" --file feature.txt --base main --no-merge
expect_equal "a foreign remote commit stops the push" 14 "$run_code"
expect_equal "the stop names the push" push "$(field failed_step <<< "$run_out")"
expect_equal "the foreign commit is still the remote tip" "$foreign_tip" \
  "$(remote_tip "$upsilon" feat/shared)"

# ---------------------------------------------------------------------------
# land.sh --merge-existing — the merge queue's entry point
# ---------------------------------------------------------------------------
sigma="$(new_repo sigma)"
sigma_wt="$work/sigma-wt"
git -C "$sigma" worktree add -q -b feat/queued "$sigma_wt" main
printf 'queued\n' > "$sigma_wt/queued.txt"
cd "$sigma_wt"
run bash "$land" --branch feat/queued --message-file "$work/msg.txt" --title 'Queued' \
  --body-file "$work/body.txt" --file queued.txt --base main --no-merge
expect_equal "fixture: the queued PR is open" 0 "$run_code"
queued_tip="$(git -C "$sigma_wt" rev-parse HEAD)"
land_upstream sigma upstream.txt landed-first
printf 'local edit\n' >> "$sigma_wt/README.md"

run bash "$land" --merge-existing --branch feat/queued --base main --file queued.txt
expect_equal "--merge-existing rejects ship-only arguments" 12 "$run_code"
run bash "$land" --merge-existing --branch feat/queued --base main
expect_equal "--merge-existing needs an open PR" 12 "$run_code"
expect_text_contains "no open PR names the reason" "$(field error <<< "$run_out")" "no open PR"
run bash "$land" --merge-existing --branch feat/elsewhere --base main
expect_equal "--merge-existing runs only on the branch's own checkout" 12 "$run_code"

: > "$GH_STUB_LOG"
run env GH_STUB_PR_LIST='[{"number":7,"url":"https://github.com/acme/demo/pull/7"}]' \
  bash "$land" --merge-existing --branch feat/queued --base main
expect_equal "--merge-existing merges the open PR" 0 "$run_code"
expect_json "--merge-existing prints one JSON object" "$run_out"
expect_equal "--merge-existing reports its mode" merge-existing "$(field mode <<< "$run_out")"
expect_equal "--merge-existing reports the PR" "https://github.com/acme/demo/pull/7" \
  "$(field pr_url <<< "$run_out")"
expect_equal "--merge-existing reports the merge" true "$(field merged <<< "$run_out")"
expect_equal "--merge-existing detects the strategy like preflight" merge \
  "$(field strategy <<< "$run_out")"
gh_calls="$(cat "$GH_STUB_LOG")"
expect_text_contains "--merge-existing merged the branch's PR" "$gh_calls" \
  "pr merge feat/queued --merge"
expect_text_lacks "--merge-existing never deletes the branch" "$gh_calls" "--delete-branch"
expect_text_lacks "--merge-existing opens no PR" "$gh_calls" "pr create"
[ "$(git -C "$sigma_wt" rev-parse HEAD)" != "$queued_tip" ] ||
  fail "--merge-existing did not rebase the branch"
git -C "$sigma_wt" merge-base --is-ancestor "$(git -C "$work/sigma-other" rev-parse HEAD)" HEAD ||
  fail "--merge-existing did not rebase onto the latest base"
expect_equal "--merge-existing pushed the rebased branch" \
  "$(git -C "$sigma_wt" rev-parse HEAD)" "$(remote_tip "$sigma_wt" feat/queued)"
expect_equal "--merge-existing pushed with a lease" true "$(field force_pushed <<< "$run_out")"
expect_equal "--merge-existing leaves the worktree on its branch" feat/queued \
  "$(git -C "$sigma_wt" branch --show-current)"
git -C "$sigma" show-ref --verify --quiet refs/heads/feat/queued ||
  fail "--merge-existing deleted the branch"
expect_text_contains "--merge-existing kept the unrelated local edit" \
  "$(cat "$sigma_wt/README.md")" "local edit"

tau="$(new_repo tau)"
tau_wt="$work/tau-wt"
git -C "$tau" worktree add -q -b feat/queued-clash "$tau_wt" main
printf 'mine\n' > "$tau_wt/README.md"
cd "$tau_wt"
run bash "$land" --branch feat/queued-clash --message-file "$work/msg.txt" \
  --title 'Queued clash' --body-file "$work/body.txt" --file README.md --base main --no-merge
expect_equal "fixture: the clashing PR is open" 0 "$run_code"
clash_tip="$(git -C "$tau_wt" rev-parse HEAD)"
land_upstream tau README.md theirs
: > "$GH_STUB_LOG"
run env GH_STUB_PR_LIST='[{"number":8,"url":"https://github.com/acme/demo/pull/8"}]' \
  bash "$land" --merge-existing --branch feat/queued-clash --base main --strategy merge
expect_equal "--merge-existing reports a conflict as exit 11" 11 "$run_code"
expect_json "a --merge-existing conflict prints one JSON object" "$run_out"
expect_equal "a --merge-existing conflict names the file" '["README.md"]' \
  "$(field conflict_files <<< "$run_out")"
rebase_in_progress "$tau_wt" && fail "--merge-existing left the conflicted rebase in progress"
expect_equal "the conflict left the branch where it was" "$clash_tip" \
  "$(git -C "$tau_wt" rev-parse HEAD)"
expect_equal "the conflict pushed nothing" "$clash_tip" "$(remote_tip "$tau_wt" feat/queued-clash)"
expect_text_lacks "the conflict never merged" "$(cat "$GH_STUB_LOG")" "pr merge"

cd "$repo_root"
printf 'ok - push helpers hold their contract\n'
