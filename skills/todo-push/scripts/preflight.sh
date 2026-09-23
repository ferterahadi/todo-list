#!/usr/bin/env bash
# Read-only repo reconnaissance for /todo-push. Emits one JSON object describing the
# facts the skill would otherwise re-derive in prose, and fails before anything mutates
# when the ship can't work (no origin, no gh auth, no write access, nothing to ship).
#
# usage: preflight.sh          # operates on the current working directory's repo
#
# Two gh calls in total: one `gh auth status`, one `gh repo view`.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

die() {
  # Machine-readable on stdout, human-readable on stderr, non-zero either way.
  python3 -c 'import json, sys; print(json.dumps({"error": sys.argv[1]}))' "$1"
  printf 'preflight: %s\n' "$1" >&2
  exit 1
}

git rev-parse --git-dir > /dev/null 2>&1 || die "not a git repository"

git_dir="$(cd "$(git rev-parse --absolute-git-dir)" && pwd -P)"
common_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
if [ "$git_dir" != "$common_dir" ]; then
  is_worktree=true
else
  is_worktree=false
fi

repo_root="$(git rev-parse --show-toplevel)"
primary_worktree="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
current_branch="$(git branch --show-current)"

git remote get-url origin > /dev/null 2>&1 ||
  die "no origin remote — nothing to push to (git remote -v)"

# One call proves the login and names the active account. Older gh has no --active; only
# then is a second, plain call made.
if ! auth_out="$(gh auth status --active 2>&1)"; then
  case "$auth_out" in
    *"unknown flag"*) auth_out="$(gh auth status 2>&1)" ||
      die "gh auth failed — authenticate before shipping (gh auth status)" ;;
    *) die "gh auth failed — authenticate before shipping (gh auth status)" ;;
  esac
fi

# Being logged in proves only that *some* account is active. When that account has no write
# access to this repo, `gh pr create` fails with "must be a collaborator" — by which point
# land.sh has already branched, committed and pushed. Resolve the permission here instead,
# while nothing has moved, and fail closed if it can't be read.
# "Logged in to github.com account <login> (keyring)" — match the field, not a substring:
# a login can itself end in "account".
gh_account="$(printf '%s\n' "$auth_out" |
  awk '{for (i = 1; i < NF; i++) if ($i == "account") { print $(i + 1); exit }}')"
[ -n "$gh_account" ] || gh_account="unknown"

# One repo view answers both the permission and the merge strategies the repo allows.
repo_json="$(
  gh repo view --json \
    nameWithOwner,viewerPermission,mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed \
    2>/dev/null || true
)"
access_facts="$(
  printf '%s\n' "$repo_json" |
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
print(data.get("nameWithOwner") or "")
print((data.get("viewerPermission") or "").upper())
' 2>/dev/null || true
)"
repo_slug="$(printf '%s\n' "$access_facts" | sed -n 1p)"
viewer_permission="$(printf '%s\n' "$access_facts" | sed -n 2p)"
[ -n "$repo_slug" ] || repo_slug="$(git remote get-url origin)"
strategies="$(printf '%s\n' "$repo_json" | allowed_strategies 2>/dev/null || true)"

case "$viewer_permission" in
  ADMIN | MAINTAIN | WRITE) ;;
  "")
    die "could not read the gh account's permission on $repo_slug — active account is \
$gh_account; confirm it has access, or switch (gh auth switch)"
    ;;
  *)
    die "gh account $gh_account has $viewer_permission access to $repo_slug — the PR could \
not be opened after the branch was pushed; switch accounts (gh auth switch) and re-run"
    ;;
esac

# Base branch: the remote's default, then the remote's own report, then convention.
base=""
if ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"; then
  base="${ref#refs/remotes/origin/}"
fi
if [ -z "$base" ]; then
  base="$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' | head -1)"
fi
if [ -z "$base" ] || [ "$base" = "(unknown)" ]; then
  for candidate in main master; do
    if git show-ref --verify --quiet "refs/heads/$candidate"; then
      base="$candidate"
      break
    fi
  done
fi
[ -n "$base" ] || die "could not determine the base branch"

# Parsed NUL-separated (lib.sh): untracked files are listed individually, since a collapsed
# "dir/" can't be handed to land.sh --file, and a rename is its two paths, not "old -> new".
changed_list="$(status_paths changed)"
staged_list="$(status_paths staged)"
renames_list="$(status_paths renames)"

# Untracked files that look like build output or local scratch rather than deliverables.
# Reported so the caller leaves them out of --file deliberately; never removed here.
suspicious=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in
    .DS_Store|*/.DS_Store|*.tfplan|*.tfstate|*.tfstate.backup|*.swp|*.swo|*~|*.orig|\
    *.rej|*.pyc|*.log|node_modules/*|dist/*|build/*|target/*|__pycache__/*|\
    .pytest_cache/*|coverage/*|.terraform/*)
      suspicious="${suspicious}${path}"$'\n'
      ;;
  esac
done <<< "$(status_paths untracked)"

if [ -n "$changed_list" ]; then
  dirty=true
else
  dirty=false
fi

# Commits HEAD carries beyond the base: they ship in the PR whatever branch name is picked,
# so the caller has to read them too. Measured against origin/<base> — what the PR is compared
# with — and against the local base only when there is no remote-tracking ref.
compare_ref=""
if git rev-parse --verify --quiet "refs/remotes/origin/$base" > /dev/null; then
  compare_ref="origin/$base"
elif git show-ref --verify --quiet "refs/heads/$base"; then
  compare_ref="$base"
fi
ahead_of_base=0
if [ -n "$compare_ref" ]; then
  ahead_of_base="$(git rev-list --count "$compare_ref..HEAD" 2>/dev/null || printf '0')"
fi

if [ "$dirty" = false ] && [ "$ahead_of_base" -eq 0 ]; then
  die "nothing to ship — the tree is clean and no commits sit ahead of ${compare_ref:-$base}"
fi

# What the repo *allows* is not what it *does*: a repo can permit merge commits and still
# squash every PR. Report the recent pattern, and the strategy land.sh should be handed.
history_ref="origin/$base"
if git show-ref --verify --quiet "refs/heads/$base"; then
  history_ref="$base"
fi
read -r observed_pattern recent_merges recent_total <<< "$(merge_history "$history_ref")"
recommended_strategy="$(pick_merge_strategy "$observed_pattern" "$strategies")"

# What the repo declares as its test command. Choosing and scoping stays with the caller.
candidates=""
add_candidate() {
  candidates="${candidates}${1}=${2}"$'\n'
}
if [ -f "$repo_root/Makefile" ] && grep -Eq '^test:' "$repo_root/Makefile"; then
  add_candidate makefile "make test"
fi
if [ -f "$repo_root/package.json" ] &&
  python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
raise SystemExit(0 if "test" in data.get("scripts", {}) else 1)
' "$repo_root/package.json" 2>/dev/null; then
  add_candidate package_json "npm test"
fi
if [ -f "$repo_root/Cargo.toml" ]; then
  add_candidate cargo "cargo test"
fi
if [ -f "$repo_root/go.mod" ]; then
  add_candidate go "go test ./..."
fi
if [ -f "$repo_root/pytest.ini" ] || [ -f "$repo_root/tox.ini" ] ||
  { [ -f "$repo_root/pyproject.toml" ] && grep -q pytest "$repo_root/pyproject.toml"; }; then
  add_candidate pytest "pytest"
fi
# One candidate per script: `bash tests/*.sh` runs only the first and hands it the rest as
# arguments. A name that could not run as a literal command is skipped rather than quoted.
for script in "$repo_root"/tests/*.sh; do
  [ -f "$script" ] || continue
  name="${script##*/}"
  case "$name" in *[!A-Za-z0-9._-]*) continue ;; esac
  add_candidate "shell_tests/$name" "bash tests/$name"
done
# A doc candidate is a pointer into untrusted repo prose, not a command — the caller reads
# the doc and validates what it finds (SKILL.md § the one rule for command text). Offer one
# only when the doc actually declares how to run tests; the bare word "test" appears in
# almost every README and would manufacture a pointer for every repo.
for doc in AGENTS.md CLAUDE.md README.md; do
  if [ -f "$repo_root/$doc" ] &&
    grep -Eqi 'test (command|suite|script)|run the tests|`[^`]*test[^`]*`' "$repo_root/$doc"; then
    add_candidate "${doc%%.md}_md" "see $doc"
  fi
done

REPO_ROOT="$repo_root" \
IS_WORKTREE="$is_worktree" \
PRIMARY_WORKTREE="$primary_worktree" \
BASE="$base" \
CURRENT_BRANCH="$current_branch" \
GH_ACCOUNT="$gh_account" \
VIEWER_PERMISSION="$viewer_permission" \
REPO_SLUG="$repo_slug" \
DIRTY="$dirty" \
COMPARE_REF="$compare_ref" \
AHEAD_OF_BASE="$ahead_of_base" \
CHANGED_FILES="$changed_list" \
STAGED_FILES="$staged_list" \
RENAMES="$renames_list" \
SUSPICIOUS="$suspicious" \
STRATEGIES="$strategies" \
OBSERVED_PATTERN="$observed_pattern" \
RECOMMENDED_STRATEGY="$recommended_strategy" \
RECENT_MERGES="$recent_merges" \
RECENT_TOTAL="$recent_total" \
CANDIDATES="$candidates" \
python3 -c '
import json, os

def lines(name):
    return [line for line in os.environ.get(name, "").splitlines() if line.strip()]

candidates = {}
for line in lines("CANDIDATES"):
    key, _, value = line.partition("=")
    candidates[key] = value

print(json.dumps({
    "repo_root": os.environ["REPO_ROOT"],
    "is_worktree": os.environ["IS_WORKTREE"] == "true",
    "primary_worktree": os.environ["PRIMARY_WORKTREE"],
    "base": os.environ["BASE"],
    "current_branch": os.environ["CURRENT_BRANCH"],
    "dirty": os.environ["DIRTY"] == "true",
    "compare_ref": os.environ["COMPARE_REF"],
    "ahead_of_base": int(os.environ["AHEAD_OF_BASE"]),
    "changed_files": lines("CHANGED_FILES"),
    "staged_files": lines("STAGED_FILES"),
    "renames": [
        {"from": old, "to": new}
        for old, _, new in (line.partition("\t") for line in lines("RENAMES"))
    ],
    "untracked_suspicious": lines("SUSPICIOUS"),
    "gh_auth": True,
    "gh_account": os.environ["GH_ACCOUNT"],
    "viewer_permission": os.environ["VIEWER_PERMISSION"],
    "repo_slug": os.environ["REPO_SLUG"],
    "has_origin": True,
    "allowed_merge_strategies": lines("STRATEGIES"),
    "observed_merge_pattern": os.environ["OBSERVED_PATTERN"],
    "recommended_strategy": os.environ["RECOMMENDED_STRATEGY"],
    "recent_merge_commits": int(os.environ["RECENT_MERGES"]),
    "recent_commits_sampled": int(os.environ["RECENT_TOTAL"]),
    "test_cmd_candidates": candidates,
}, indent=2))
'
