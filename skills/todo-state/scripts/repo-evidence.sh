#!/usr/bin/env bash
# Read-only git and GitHub evidence for the hub projects that share one target repo.
# /todo-state audit calls it once per distinct repo; /todo-refer resume calls it for one
# project. Every value is derived from the repo itself — nothing comes from the registry
# except the repo path and the short-names, and both are validated before use.
#
# usage: repo-evidence.sh <repo-path> <short-name> [<short-name>...] [--fetch] [--hub <dir>]
#
#   --fetch       run `git fetch origin` once before reading refs. Without it the helper
#                 writes nothing at all; with it, only remote-tracking refs change.
#   --hub <dir>   also read every short-name in <dir>/index.md and <dir>/archive.md, so a
#                 prefix match goes to the longest registered name even when that name
#                 was not requested. Only requested names are reported.
#
# Output, one tab-separated row per fact:
#   REPO      <primary-path>  slug=<owner/name|->  base=<branch|->  fetch=<ok|failed|skipped|no-remote>  gh=<ok|unavailable|failed|no-github-remote>
#   BRANCH    <short>  <branch>  local=<yes|no>  remote=<yes|no>  ahead=<n|unknown>  state=<merged|open|empty|unknown>  via=<merge|rebase|squash|pr|->
#   WORKTREE  <short>  <path>  branch=<name|detached>  state=<present|missing>  uncommitted=<n|unknown>  ahead=<n|unknown>
#   PR        <short>  <number>  <OPEN|MERGED|CLOSED>  <head-branch>  <url>
#   SUMMARY   repo-evidence  project=<short>  branch=<merged|open|empty|absent|unknown>  pr=<merged|open|none|unknown>  worktree=<present|absent|unknown>  unshipped=<n|unknown>  uncommitted=<n|unknown>
#   ERROR     <CODE>  <detail>
#
# A branch, worktree, or PR belongs to a project when one `/`-separated segment of its
# branch name (or a worktree's folder name under `<repo>-wt/`) equals the short-name or
# starts with `<short-name>-`. When several known names match, the longest wins, so
# `api` and `api-v2` never collapse — pass --hub, or every project that shares the repo.
#
# `ahead` counts commits not reachable from the base branch; a squash, rebase, or PR merge
# can ship them anyway, which `state=merged` records. SUMMARY `unshipped` counts only the
# commits on branches and worktrees that are not merged — the work still at risk.
# `unknown` means not checked (no base branch, failed fetch, no gh), never "absent".
# Exit: 0 evidence emitted · 2 invalid input, nothing ran · 3 repo unavailable (every
# SUMMARY field is unknown).
set -uo pipefail

export GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 LC_ALL=C

emit() {
  local IFS=$'\t'
  printf '%s\n' "$*"
}

invalid() {
  emit ERROR INVALID_INPUT "$1"
  printf 'repo-evidence: %s\n' "$1" >&2
  printf 'usage: repo-evidence.sh <repo-path> <short-name> [<short-name>...] [--fetch] [--hub <dir>]\n' >&2
  exit 2
}

has_metachar() {
  case "$1" in
    *[\;\|\&\$\`\"\'\\\(\)\<\>]* | *$'\n'* | *$'\r'*) return 0 ;;
  esac
  return 1
}

fetch=0
hub=""
expect_hub=0
repo=""
repo_set=0
names=()
name_re='^[a-z0-9][a-z0-9-]*$'
for arg in "$@"; do
  if [ "$expect_hub" = 1 ]; then
    hub="$arg"
    expect_hub=0
    continue
  fi
  case "$arg" in
    --fetch) fetch=1 ;;
    --hub) expect_hub=1 ;;
    --*) invalid "unknown option" ;;
    *)
      if [ "$repo_set" = 0 ]; then
        repo="$arg"
        repo_set=1
        continue
      fi
      [[ $arg =~ $name_re ]] || invalid "short-name must match ^[a-z0-9][a-z0-9-]*\$"
      duplicate=0
      for existing in ${names[@]+"${names[@]}"}; do
        [ "$existing" = "$arg" ] && duplicate=1
      done
      [ "$duplicate" = 1 ] || names+=("$arg")
      ;;
  esac
done

[ -n "$repo" ] || invalid "missing <repo-path>"
[ "$repo" != "-" ] || invalid "repo-path is '-': a hub-only project has no repo to inspect"
has_metachar "$repo" && invalid "repo-path contains a shell metacharacter or newline"
[ "${#names[@]}" -gt 0 ] || invalid "missing <short-name>"
[ "$expect_hub" = 0 ] || invalid "--hub needs a directory"

expand_home() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s\n' "$HOME/${1#"~/"}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}
repo="$(expand_home "$repo")"
if [ -n "$hub" ]; then
  has_metachar "$hub" && invalid "hub path contains a shell metacharacter or newline"
  hub="$(expand_home "$hub")"
  [ -d "$hub" ] || invalid "hub directory not found"
fi

# Names that compete for prefix matches: the requested ones plus, with --hub, every
# short-name cell in either registry table.
known="${names[*]}"
if [ -n "$hub" ]; then
  known="$known $(
    for registry in "$hub/index.md" "$hub/archive.md"; do
      [ -f "$registry" ] || continue
      awk -F '|' '/^[[:space:]]*\|/ {
        cell = $2
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell)
        if (cell ~ /^[a-z0-9][a-z0-9-]*$/) print cell
      }' "$registry"
    done | sort -u | tr '\n' ' '
  )"
fi

unknown_summaries() {
  local name
  for name in "${names[@]}"; do
    emit SUMMARY repo-evidence "project=$name" branch=unknown pr=unknown \
      worktree=unknown unshipped=unknown uncommitted=unknown
  done
}

if [ ! -d "$repo" ] || ! git -C "$repo" rev-parse --git-dir > /dev/null 2>&1; then
  emit ERROR REPO_UNAVAILABLE "not a local git repository"
  unknown_summaries
  exit 3
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

worktree_state=ok
git -C "$repo" worktree list --porcelain > "$tmp/worktrees.raw" 2> /dev/null ||
  worktree_state=failed
primary_raw="$(sed -n '1s/^worktree //p' "$tmp/worktrees.raw")"
[ -n "$primary_raw" ] ||
  primary_raw="$(git -C "$repo" rev-parse --show-toplevel 2> /dev/null || true)"
primary="$(cd -- "$primary_raw" 2> /dev/null && pwd -P)" || primary=""
if [ -z "$primary" ]; then
  emit ERROR REPO_UNAVAILABLE "no working tree (bare repository?)"
  unknown_summaries
  exit 3
fi

g() {
  git -C "$primary" "$@"
}

# --- origin, slug, fetch -----------------------------------------------------------
origin_url="$(g config --get remote.origin.url 2> /dev/null || true)"

slug="-"
parse_slug() {
  local url="$1" rest host path owner name
  case "$url" in
    *://*)
      rest="${url#*://}"
      rest="${rest#*@}"
      host="${rest%%/*}"
      host="${host%%:*}"
      path="${rest#*/}"
      ;;
    *@*:*)
      rest="${url#*@}"
      host="${rest%%:*}"
      path="${rest#*:}"
      ;;
    *) return 1 ;;
  esac
  path="${path%/}"
  path="${path%.git}"
  owner="${path%%/*}"
  name="${path#*/}"
  [ "$owner" != "$path" ] || return 1
  case "$name" in */*) return 1 ;; esac
  [[ $host =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  [[ $owner =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  if [ "$host" = github.com ]; then
    slug="$owner/$name"
  else
    slug="$host/$owner/$name"
  fi
}
[ -n "$origin_url" ] && parse_slug "$origin_url"

if [ -z "$origin_url" ]; then
  fetch_state=no-remote
elif [ "$fetch" = 1 ]; then
  if g fetch --quiet origin > /dev/null 2>&1; then
    fetch_state=ok
  else
    fetch_state=failed
  fi
else
  fetch_state=skipped
fi

# --- base branch -------------------------------------------------------------------
base=""
if ref="$(g symbolic-ref --quiet refs/remotes/origin/HEAD 2> /dev/null)"; then
  base="${ref#refs/remotes/origin/}"
fi
if [ -z "$base" ]; then
  for candidate in main master; do
    if g show-ref --verify --quiet "refs/remotes/origin/$candidate"; then
      base="$candidate"
      break
    fi
  done
fi
if [ -z "$base" ]; then
  for candidate in main master; do
    if g show-ref --verify --quiet "refs/heads/$candidate"; then
      base="$candidate"
      break
    fi
  done
fi
if [ -n "$base" ] && has_metachar "$base"; then
  emit ERROR INVALID_BASE "base branch name contains a shell metacharacter"
  base=""
fi
base_ref=""
if [ -n "$base" ]; then
  if g show-ref --verify --quiet "refs/remotes/origin/$base"; then
    base_ref="refs/remotes/origin/$base"
  elif g show-ref --verify --quiet "refs/heads/$base"; then
    base_ref="refs/heads/$base"
  fi
fi
base_sha=""
[ -n "$base_ref" ] && base_sha="$(g rev-parse --verify --quiet "$base_ref^{commit}")"

# --- GitHub PRs (one call per helper run) ------------------------------------------
: > "$tmp/prs"
if [ "$slug" = "-" ]; then
  gh_state=no-github-remote
elif ! command -v gh > /dev/null 2>&1 || ! command -v python3 > /dev/null 2>&1; then
  gh_state=unavailable
elif gh pr list --repo "$slug" --state all --limit 500 \
  --json number,state,headRefName,headRefOid,url > "$tmp/prs.json" 2> /dev/null &&
  python3 -c '
import json, sys
clean = lambda value: " ".join(str(value).split()) or "-"
for pr in json.load(sys.stdin):
    print("\t".join(clean(pr.get(key, "-")) for key in
                    ("number", "state", "headRefName", "headRefOid", "url")))
' < "$tmp/prs.json" > "$tmp/prs" 2> /dev/null; then
  gh_state=ok
else
  gh_state=failed
  : > "$tmp/prs"
fi

emit REPO "$primary" "slug=$slug" "base=${base:--}" "fetch=$fetch_state" "gh=$gh_state"

# --- attribution --------------------------------------------------------------------
# Prefixes each input row whose name field(s) belong to a project with that project;
# drops the rest. Field numbers name a branch column and, optionally, a path column
# that counts only under <primary>-wt/.
attribute() {
  awk -F '\t' -v OFS='\t' -v names="$known" -v base="$base" \
    -v branch_field="$1" -v path_field="${2:-0}" \
    -v wt_raw="${primary_raw}-wt/" -v wt_phys="${primary}-wt/" '
    BEGIN { count = split(names, list, " ") }
    function owner(value,   n, segs, i, j, best, name, seg) {
      best = ""
      n = split(tolower(value), segs, "/")
      for (j = 1; j <= count; j++) {
        name = list[j]
        for (i = 1; i <= n; i++) {
          seg = segs[i]
          if (seg == name || index(seg, name "-") == 1) {
            if (length(name) > length(best)) best = name
            break
          }
        }
      }
      return best
    }
    function folder(path,   rest) {
      if (index(path, wt_raw) == 1) rest = substr(path, length(wt_raw) + 1)
      else if (index(path, wt_phys) == 1) rest = substr(path, length(wt_phys) + 1)
      else return ""
      return index(rest, "/") ? "" : rest
    }
    {
      best = ""
      if ($branch_field != base && $branch_field != "-") best = owner($branch_field)
      if (path_field > 0) {
        by_path = owner(folder($path_field))
        if (length(by_path) > length(best)) best = by_path
      }
      if (best != "") print best, $0
    }'
}

# Branches: "<owner>\t<branch>\t<local yes|no>\t<remote yes|no>".
g for-each-ref --format='%(refname)' refs/heads refs/remotes/origin 2> /dev/null |
  awk -v OFS='\t' '
    /^refs\/heads\// { name = substr($0, 12); local_ref[name] = 1; seen[name] = 1 }
    /^refs\/remotes\/origin\// {
      name = substr($0, 21)
      if (name != "HEAD") { remote_ref[name] = 1; seen[name] = 1 }
    }
    END {
      for (name in seen)
        print name, (name in local_ref ? "yes" : "no"), (name in remote_ref ? "yes" : "no")
    }' |
  attribute 1 | sort > "$tmp/branches"

# Worktrees: "<owner>\t<path>\t<branch|->\t<head>\t<prunable 0|1>".
awk -v OFS='\t' '
  function flush() {
    if (path != "") print path, (branch == "" ? "-" : branch), head, prunable
    path = ""; branch = ""; head = ""; prunable = 0
  }
  /^worktree / { flush(); path = substr($0, 10); next }
  /^HEAD / { head = substr($0, 6); next }
  /^branch refs\/heads\// { branch = substr($0, 19); next }
  /^prunable/ { prunable = 1; next }
  END { flush() }
' "$tmp/worktrees.raw" | attribute 2 1 | sort > "$tmp/worktrees"

# PRs: "<owner>\t<number>\t<state>\t<head>\t<oid>\t<url>".
attribute 3 < "$tmp/prs" | sort -t "$(printf '\t')" -k1,1 -k2,2n > "$tmp/prs.owned"

# --- merge classification -----------------------------------------------------------
pr_merged_at() {
  # $1 project, $2 head branch, $3 commit: true when a merged PR for that head carried it.
  local oid
  for oid in $(awk -F '\t' -v p="$1" -v h="$2" \
    '$1 == p && $3 == "MERGED" && $4 == h { print $5 }' "$tmp/prs.owned"); do
    [ "$oid" = "$3" ] && return 0
    g merge-base --is-ancestor "$3" "$oid" 2> /dev/null && return 0
  done
  return 1
}

squash_merged() {
  # True when base holds one commit whose patch equals the branch's whole diff.
  local sha="$1" fork patch
  fork="$(g merge-base "$base_ref" "$sha" 2> /dev/null)" || return 1
  patch="$(g diff --no-ext-diff --no-textconv --no-color "$fork" "$sha" |
    g patch-id --stable | awk '{ print $1 }')"
  [ -n "$patch" ] || return 1
  # awk reads to EOF: an early-exit reader would SIGPIPE git and, under pipefail, turn a
  # match into a failure.
  g log -p --no-merges --no-ext-diff --no-textconv --no-color --max-count=1000 \
    "$fork..$base_ref" | g patch-id --stable |
    awk -v patch="$patch" '$1 == patch { found = 1 } END { exit !found }'
}

# Sets tip_state (merged|open|empty) and tip_via for one commit of branch $2.
classify_tip() {
  local project="$1" head="$2" sha="$3" own last unmatched
  tip_via="-"
  tip_state=unknown
  [ -n "$sha" ] || return
  own="$(g rev-list --count "$sha" --not "$base_ref" 2> /dev/null)" || return
  if [ "$own" -eq 0 ]; then
    tip_state=empty
    if [ "$sha" != "$base_sha" ]; then
      last="$(g rev-list --first-parent --ancestry-path "$sha..$base_ref" | tail -n 1)"
      if [ -n "$last" ] && [ "$(g rev-parse "$last^1" 2> /dev/null)" != "$sha" ]; then
        tip_state=merged
        tip_via=merge
        return
      fi
    fi
    if pr_merged_at "$project" "$head" "$sha"; then
      tip_state=merged
      tip_via=pr
    fi
    return
  fi
  unmatched="$(g cherry "$base_ref" "$sha" 2> /dev/null | awk '/^\+/ { n++ } END { print n + 0 }')"
  if [ "$unmatched" = 0 ]; then
    tip_state=merged
    tip_via=rebase
  elif squash_merged "$sha"; then
    tip_state=merged
    tip_via=squash
  elif pr_merged_at "$project" "$head" "$sha"; then
    tip_state=merged
    tip_via=pr
  else
    tip_state=open
  fi
}

# --- per-project evidence -----------------------------------------------------------
for project in "${names[@]}"; do
  tips=()
  merged_branches=" "
  branches_seen=0
  branches_open=0
  branches_merged=0
  branch_unknown=0

  while IFS=$'\t' read -r owner branch has_local has_remote <&3; do
    [ "$owner" = "$project" ] || continue
    branches_seen=$((branches_seen + 1))
    refs=()
    [ "$has_local" = yes ] && refs+=("refs/heads/$branch")
    [ "$has_remote" = yes ] && refs+=("refs/remotes/origin/$branch")
    if [ -z "$base_ref" ]; then
      emit BRANCH "$project" "$branch" "local=$has_local" "remote=$has_remote" \
        ahead=unknown state=unknown via=-
      branch_unknown=1
      continue
    fi
    ahead="$(g rev-list --count "${refs[@]}" --not "$base_ref")"
    state=empty
    via="-"
    for ref in "${refs[@]}"; do
      classify_tip "$project" "$branch" "$(g rev-parse --verify --quiet "$ref^{commit}")"
      case "$tip_state" in
        open) state=open ;;
        unknown) [ "$state" = open ] || state=unknown ;;
        merged)
          [ "$state" = open ] || state=merged
          [ "$via" != "-" ] || via="$tip_via"
          ;;
      esac
    done
    [ "$state" = merged ] || via="-"
    case "$state" in
      unknown) branch_unknown=1 ;;
      open) branches_open=$((branches_open + 1)) ;;
      merged)
        branches_merged=$((branches_merged + 1))
        merged_branches="$merged_branches$branch "
        ;;
    esac
    [ "$state" = merged ] || tips+=("${refs[@]}")
    emit BRANCH "$project" "$branch" "local=$has_local" "remote=$has_remote" \
      "ahead=$ahead" "state=$state" "via=$via"
  done 3< "$tmp/branches"

  worktrees_present=0
  uncommitted=0
  while IFS=$'\t' read -r owner path branch head prunable <&3; do
    [ "$owner" = "$project" ] || continue
    [ "$branch" = "-" ] && branch_label=detached || branch_label="$branch"
    if [ "$prunable" = 1 ] || [ ! -d "$path" ]; then
      emit WORKTREE "$project" "$path" "branch=$branch_label" state=missing \
        uncommitted=unknown ahead=unknown
      continue
    fi
    worktrees_present=$((worktrees_present + 1))
    if status="$(git -C "$path" status --porcelain 2> /dev/null)"; then
      dirty="$(printf '%s\n' "$status" | awk 'NF { n++ } END { print n + 0 }')"
      [ "$uncommitted" = unknown ] || uncommitted=$((uncommitted + dirty))
    else
      dirty=unknown
      uncommitted=unknown
    fi
    if [ -n "$base_ref" ] && [ -n "$head" ]; then
      ahead="$(g rev-list --count "$head" --not "$base_ref" 2> /dev/null || echo unknown)"
      case "$merged_branches" in
        *" $branch "*) ;;
        *) tips+=("$head") ;;
      esac
    else
      ahead=unknown
    fi
    emit WORKTREE "$project" "$path" "branch=$branch_label" state=present \
      "uncommitted=$dirty" "ahead=$ahead"
  done 3< "$tmp/worktrees"

  prs_open=0
  prs_merged=0
  while IFS=$'\t' read -r owner number state head oid url <&3; do
    [ "$owner" = "$project" ] || continue
    case "$state" in
      OPEN) prs_open=$((prs_open + 1)) ;;
      MERGED) prs_merged=$((prs_merged + 1)) ;;
    esac
    emit PR "$project" "$number" "$state" "$head" "$url"
  done 3< "$tmp/prs.owned"

  if [ "$gh_state" != ok ]; then
    pr=unknown
  elif [ "$prs_open" -gt 0 ]; then
    pr=open
  elif [ "$prs_merged" -gt 0 ]; then
    pr=merged
  else
    pr=none
  fi

  if [ -z "$base_ref" ] || [ "$fetch_state" = failed ] || [ "$branch_unknown" = 1 ]; then
    branch_verdict=unknown
  elif [ "$branches_open" -gt 0 ]; then
    branch_verdict=open
  elif [ "$branches_merged" -gt 0 ]; then
    branch_verdict=merged
  elif [ "$branches_seen" -gt 0 ]; then
    branch_verdict=empty
  elif [ "$pr" = merged ] || [ "$pr" = open ]; then
    branch_verdict="$pr"
  else
    branch_verdict=absent
  fi

  if [ -z "$base_ref" ]; then
    unshipped_total=unknown
  elif [ "${#tips[@]}" -eq 0 ]; then
    unshipped_total=0
  else
    unshipped_total="$(g rev-list --count "${tips[@]}" --not "$base_ref" 2> /dev/null ||
      echo unknown)"
  fi

  if [ "$worktree_state" != ok ]; then
    worktree_verdict=unknown
    uncommitted=unknown
  elif [ "$worktrees_present" -gt 0 ]; then
    worktree_verdict=present
  else
    worktree_verdict=absent
  fi

  emit SUMMARY repo-evidence "project=$project" "branch=$branch_verdict" "pr=$pr" \
    "worktree=$worktree_verdict" "unshipped=$unshipped_total" "uncommitted=$uncommitted"
done
exit 0
