#!/usr/bin/env bash
# Merge cursor/plugins main into this fork's main, keep fork-only tweaks,
# and regenerate the Claude Code build of pstack.
#
#   fork/sync-upstream.sh          # merge + regenerate, local only
#   fork/sync-upstream.sh --push   # also push main to origin
#
# Before merging it writes a report of every pstack/ file that both this fork
# and upstream changed, with both diffs, to $SYNC_REPORT
# (default .git/pstack-sync-report.md).
#
# Exit codes: 0 synced (report may still list overlaps), 1 error,
# 2 conflicts left for a human (repo is left mid-merge).
#
# Merge, never rebase, so origin/main is never force-pushed.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PUSH=0
[[ "${1:-}" == "--push" ]] && PUSH=1

UPSTREAM_URL="https://github.com/cursor/plugins.git"
UPSTREAM_WEB="https://github.com/cursor/plugins"
BRANCH="main"
WATCH="pstack"
GENERATED="harness/pstack"
# Files the fork changes on purpose; on conflict our version wins.
OURS=(".claude-plugin/marketplace.json")
REPORT="${SYNC_REPORT:-$(git rev-parse --absolute-git-dir)/pstack-sync-report.md}"
MAX_DIFF_LINES=150

if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$UPSTREAM_URL"
  git remote set-url --push upstream DISABLED
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree is dirty; commit or stash first" >&2
  exit 1
fi

git fetch upstream "+refs/heads/$BRANCH:refs/remotes/upstream/$BRANCH"
git switch "$BRANCH"
: >"$REPORT"

if git merge-base --is-ancestor "upstream/$BRANCH" HEAD; then
  echo "already up to date with upstream/$BRANCH"
else
  BASE=$(git merge-base HEAD "upstream/$BRANCH")
  UP=$(git rev-parse "upstream/$BRANCH")
  # base..HEAD is everything this fork changed relative to upstream, ever:
  # each sync moves base forward, and our edits stay on top of it.
  mine=$(git diff --name-only "$BASE" HEAD -- "$WATCH" | sort)
  theirs=$(git diff --name-only "$BASE" "$UP" -- "$WATCH" | sort)
  overlap=$(comm -12 <(echo "$mine") <(echo "$theirs") | sed '/^$/d')

  fence() { # print a diff, truncated, in a fenced block
    local out n
    out=$(git diff "$@")
    n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
    echo '```diff'
    printf '%s\n' "$out" | head -n "$MAX_DIFF_LINES"
    echo '```'
    if (( n > MAX_DIFF_LINES )); then echo "_…truncated, $n lines total._"; fi
  }

  {
    echo "upstream: [\`${BASE:0:7}...${UP:0:7}\`]($UPSTREAM_WEB/compare/$BASE...$UP)"
    echo
    echo "| | files in \`$WATCH/\` |"
    echo "|---|---|"
    echo "| changed by upstream | $(echo "$theirs" | sed '/^$/d' | wc -l | tr -d ' ') |"
    echo "| changed by you | $(echo "$mine" | sed '/^$/d' | wc -l | tr -d ' ') |"
    echo "| changed by both | $(echo "$overlap" | sed '/^$/d' | wc -l | tr -d ' ') |"
    echo
    if [[ -n "$overlap" ]]; then
      echo "## files you both changed"
      echo
      while read -r f; do
        echo "### \`$f\`"
        echo
        echo "<details open><summary>how upstream changed it</summary>"
        echo
        fence "$BASE" "$UP" -- "$f"
        echo
        echo "</details>"
        echo
        echo "<details><summary>your changes, for comparison</summary>"
        echo
        fence "$BASE" HEAD -- "$f"
        echo
        echo "</details>"
        echo
      done <<<"$overlap"
    fi
  } >>"$REPORT"

  if ! git merge --no-edit --no-ff "upstream/$BRANCH" -m "chore: sync with upstream cursor/plugins"; then
    for f in "${OURS[@]}"; do
      if git diff --name-only --diff-filter=U | grep -qxF "$f"; then
        git checkout --ours -- "$f" && git add -- "$f"
      fi
    done
    # The generated tree is rebuilt below, so its conflicts don't matter.
    git diff --name-only --diff-filter=U -- "$GENERATED" | while read -r f; do
      if git checkout --theirs -- "$f" 2>/dev/null; then git add -- "$f"; else git rm -q -- "$f"; fi
    done
    conflicts=$(git diff --name-only --diff-filter=U)
    if [[ -n "$conflicts" ]]; then
      {
        echo "## ⚠️ merge conflicts, nothing was merged"
        echo
        sed 's/^/- `/; s/$/`/' <<<"$conflicts"
        echo
        echo "Resolve locally:"
        echo '```bash'
        echo "fork/sync-upstream.sh   # stops mid-merge at the conflicts"
        echo "# fix the files, then:"
        echo "node scripts/generate-pstack-harness-trees.mjs && git add -A && git commit --no-edit && git push"
        echo '```'
      } >>"$REPORT"
      echo "conflicts need a human:" >&2
      echo "$conflicts" >&2
      echo "resolve them, then: node scripts/generate-pstack-harness-trees.mjs && git add -A && git commit --no-edit" >&2
      echo "report: $REPORT" >&2
      exit 2
    fi
    node scripts/generate-pstack-harness-trees.mjs
    git add -A
    git commit --no-edit
  fi
  if [[ -n "$overlap" ]]; then
    echo "merged cleanly; git kept both sides' edits in the files above." >>"$REPORT"
  fi
fi

node scripts/generate-pstack-harness-trees.mjs
if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -m "chore(pstack): regenerate claude code harness tree"
fi

if (( PUSH )); then
  git push origin "$BRANCH"
fi
[[ -s "$REPORT" ]] && echo "report: $REPORT"
echo "synced. in claude code: claude plugin marketplace update pstack-fork && claude plugin update pstack@pstack-fork"
