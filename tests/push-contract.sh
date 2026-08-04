#!/usr/bin/env bash
# Contract test for /todo-push's deterministic helpers.
# Proves preflight.sh reports repo facts without mutating anything, and that land.sh
# stages only what it was told to, refuses unsafe arguments, is re-entrant, and never
# runs the checkout/delete-branch commands git rejects inside a linked worktree.
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
for key in sys.argv[1].split("."):
    if not isinstance(value, dict) or key not in value:
        print("<missing>")
        raise SystemExit(0)
    value = value[key]
print(value if isinstance(value, str) else json.dumps(value))
' "$1"
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
    if [[ "$*" == *viewerPermission* ]]; then
      printf '{"nameWithOwner":"acme/demo","viewerPermission":"%s"}\n' \
        "${GH_STUB_VIEWER_PERMISSION:-WRITE}"
    elif [ -n "${GH_STUB_REPO_VIEW:-}" ]; then
      printf '%s\n' "$GH_STUB_REPO_VIEW"
    else
      echo '{"mergeCommitAllowed":true,"squashMergeAllowed":false,"rebaseMergeAllowed":false}'
    fi
    ;;
  "pr list")
    printf '%s\n' "${GH_STUB_PR_LIST:-[]}"
    ;;
  "pr create")
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
: > "$GH_STUB_LOG"

# Keep the machine's real git identity and hooks out of the scratch repos.
export GIT_CONFIG_GLOBAL="$work/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
: > "$GIT_CONFIG_GLOBAL"

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
# Allowed is not the same as used: a linear history means the repo squashes or rebases,
# whatever gh reports as permitted.
expect_equal "a linear history reads as linear" linear \
  "$(field observed_merge_pattern <<< "$report")"
expect_equal "a linear history counts no merge commits" 0 \
  "$(field recent_merge_commits <<< "$report")"

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
expect_equal "rejected branch created no branch" main "$(git -C "$delta" branch --show-current)"

run bash "$land" --branch feat/ok --message-file "$work/nope.txt" \
  --title 'missing message' --body-file "$work/body.txt" --file feature.txt --base main
expect_equal "land rejects a missing message file" 12 "$run_code"

run bash "$land" --branch feat/ok --message-file "$work/msg.txt" \
  --title 'missing file' --body-file "$work/body.txt" --file ghost.txt --base main
expect_equal "land rejects a named file that does not exist" 12 "$run_code"

run bash "$land" --branch feat/ok --message-file "$work/msg.txt" \
  --title 'no files' --body-file "$work/body.txt" --base main
expect_equal "land requires at least one --file" 12 "$run_code"

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

cd "$repo_root"
printf 'ok - push helpers hold their contract\n'
