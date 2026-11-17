#!/bin/sh
# Reproduce: Cindy worktree creation overwrites the shared core.hooksPath set by Vite+.
#
# Cindy (makecindy/cindy@cadb0c4, apps/desktop/src/main/worktree/WorktreeManager.ts:662-667)
# runs this command in each new worktree:
#   git -C <worktreePath> config core.hooksPath <baseRepo>/.git/hooks
#
# vp_config below copies what `vp config` does (voidzero-dev/vite-plus@1d30b8a,
# packages/cli/src/config/hooks.ts, install()). It does not need Vite+.
#
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

TARGET=.vite-hooks/_

# Copy of `vp config` -> install() in hooks.ts:
#   1. If core.hooksPath has a different value, skip and change nothing (hooks.ts:598-607).
#   2. Write the dispatcher into .vite-hooks/_/. The `*` .gitignore keeps it out of git,
#      so each checkout must generate it, for example with `vp install` (hooks.ts:609-616).
#   3. git config --local core.hooksPath .vite-hooks/_ (hooks.ts:618, 269-273).
vp_config() { # $1 = checkout dir
  existing=$(git -C "$1" config --get core.hooksPath || true)
  if [ -n "$existing" ] && [ "$existing" != "$TARGET" ]; then
    echo "  vp config ($1): core.hooksPath is already set to \"$(echo "$existing" | sed "s|$WORK|<work>|g")\", skipping"
    return
  fi
  mkdir -p "$1/$TARGET"
  printf '*' > "$1/$TARGET/.gitignore"
  # Simplified `h`: run the committed hook <dir>/<name> (hooks.ts:52 hookScript()).
  cat > "$1/$TARGET/h" <<'EOF'
#!/usr/bin/env sh
n=$(basename "$0")
s=$(dirname "$(dirname "$0")")/$n
[ ! -f "$s" ] && exit 0
sh -e "$s" "$@"
EOF
  printf '#!/usr/bin/env sh\n. "$(dirname "$0")/h"\n' > "$1/$TARGET/pre-commit" # HOOK_STUB_SCRIPT
  chmod +x "$1/$TARGET/h" "$1/$TARGET/pre-commit"
  git -C "$1" config --local core.hooksPath "$TARGET"
  echo "  vp config ($1): dispatcher installed"
}

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

step "1. Repository with a committed Vite+ hook, then 'vp config'"
git init -q -b main repo
mkdir -p repo/.vite-hooks
printf 'echo VITE_PLUS_HOOK_RAN\n' > repo/.vite-hooks/pre-commit
git -C repo add -A
git -C repo commit -q --no-verify -m init
vp_config repo
show_config
try_commit repo "main checkout"

step "2. Plain 'git worktree add', then 'vp config' in it (as 'vp install' does)"
git -C repo worktree add -q ../wt-plain
[ -e "wt-plain/$TARGET" ] || echo "  wt-plain/$TARGET does not exist yet (ignored by git)"
vp_config wt-plain
try_commit wt-plain "plain worktree"

step "3. Cindy creates a worktree and runs its configureHooksPath"
git -C repo worktree add -q ../wt-cindy
BASE=$(cd repo && pwd)
git -C wt-cindy config core.hooksPath "$BASE/.git/hooks"   # exact Cindy command
show_config
vp_config wt-cindy
try_commit repo "main checkout"
try_commit wt-plain "plain worktree"
try_commit wt-cindy "cindy worktree"

step "4. Remove the Cindy worktree; the overwrite stays and 'vp config' does not repair it"
git -C repo worktree remove ../wt-cindy
show_config
vp_config repo
try_commit repo "main checkout"

step "5. Recovery: set the value again by hand"
git -C repo config core.hooksPath "$TARGET"
show_config
try_commit repo "main checkout"
try_commit wt-plain "plain worktree"

printf "\nWork dir: %s\n" "$WORK"
