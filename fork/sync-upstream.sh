#!/usr/bin/env bash
# Merge cursor/plugins main into this fork's main, keep fork-only tweaks,
# and regenerate the Claude Code build of pstack.
#
#   fork/sync-upstream.sh          # merge + regenerate, local only
#   fork/sync-upstream.sh --push   # also push main to origin
#
# Merge, never rebase, so origin/main is never force-pushed.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PUSH=0
[[ "${1:-}" == "--push" ]] && PUSH=1

UPSTREAM_URL="https://github.com/cursor/plugins.git"
BRANCH="main"
GENERATED="harness/pstack"
# Files the fork changes on purpose; on conflict our version wins.
OURS=(".claude-plugin/marketplace.json")

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

if git merge-base --is-ancestor "upstream/$BRANCH" HEAD; then
  echo "already up to date with upstream/$BRANCH"
else
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
    if [[ -n "$(git diff --name-only --diff-filter=U)" ]]; then
      echo "conflicts need a human:" >&2
      git diff --name-only --diff-filter=U >&2
      echo "resolve them, then: node scripts/generate-pstack-harness-trees.mjs && git add -A && git commit" >&2
      exit 2
    fi
    node scripts/generate-pstack-harness-trees.mjs
    git add -A
    git commit --no-edit
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
echo "synced. in claude code: claude plugin marketplace update pstack-fork && claude plugin update pstack@pstack-fork"
