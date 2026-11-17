#!/bin/sh
# Reproduce: Cindy worktree creation overwrites the shared core.hooksPath set by Vite+.
# Cindy source: makecindy/cindy@cadb0c4 apps/desktop/src/main/worktree/WorktreeManager.ts:662-667
#   git -C <worktreePath> config core.hooksPath <baseRepo>/.git/hooks
# Usage: sh repro.sh [work-dir]   (default: ./work next to this script)
set -eu

WORK=${1:-"$(cd "$(dirname "$0")" && pwd)/work"}
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

# Isolate from the user's global/system git config (global hooks, signing, templates).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=repro GIT_AUTHOR_EMAIL=repro@example.invalid
export GIT_COMMITTER_NAME=repro GIT_COMMITTER_EMAIL=repro@example.invalid

step() { printf '\n== %s\n' "$*"; }
try_commit() { # $1 = dir, $2 = label
  out=$(git -C "$1" commit --allow-empty -q -m "$2" 2>&1 || true)
  case "$out" in
    *VITE_PLUS_HOOK_RAN*) echo "[$2] pre-commit hook: RAN" ;;
    *) echo "[$2] pre-commit hook: DID NOT RUN" ;;
  esac
}
show_config() { # paths shown relative to <work>
  { git -C repo config --show-origin --get-all core.hooksPath || echo "(core.hooksPath unset)"; } | sed "s|$WORK|<work>|g"
}

step "1. Repository with a Vite+-style dispatcher (what 'vp config' sets up)"
git init -q -b main repo
mkdir -p repo/.vite-hooks/_
printf '#!/bin/sh\necho VITE_PLUS_HOOK_RAN\n' > repo/.vite-hooks/_/pre-commit
chmod +x repo/.vite-hooks/_/pre-commit
git -C repo add -A
git -C repo commit -q --no-verify -m init
git -C repo config core.hooksPath .vite-hooks/_
show_config
try_commit repo "main checkout"

step "2. Plain 'git worktree add' (no Cindy): relative hooksPath works in the worktree"
git -C repo worktree add -q ../wt-plain
try_commit wt-plain "plain worktree"

step "3. Cindy's configureHooksPath on a new worktree"
git -C repo worktree add -q ../wt-cindy
BASE=$(cd repo && pwd)
git -C wt-cindy config core.hooksPath "$BASE/.git/hooks"   # exact Cindy command
show_config
try_commit repo "main checkout"
try_commit wt-plain "plain worktree"
try_commit wt-cindy "cindy worktree"

step "4. Cleanup: remove the Cindy worktree; the overwrite stays"
git -C repo worktree remove wt-cindy 2>/dev/null || git -C repo worktree remove ../wt-cindy
show_config
try_commit repo "main checkout"

step "5. Recovery"
git -C repo config core.hooksPath .vite-hooks/_
show_config
try_commit repo "main checkout"
try_commit wt-plain "plain worktree"

printf "\nWork dir: %s\n" "$WORK"
