# cindy-hookspath-repro

This repository reproduces a problem in [Cindy](https://cindy.app/).
When Cindy creates a Git worktree, it writes an absolute `core.hooksPath` into the shared `.git/config` of the repository.
This change replaces any value that the repository already set.
After the change, no Git hook runs in the main checkout or in any worktree.

## Cause

Cindy runs this function each time it creates a worktree:

[`apps/desktop/src/main/worktree/WorktreeManager.ts:662-667`](https://github.com/makecindy/cindy/blob/cadb0c4f1b527914bb214216e456e28155d177eb/apps/desktop/src/main/worktree/WorktreeManager.ts#L662-L667) (commit `cadb0c4`)

```ts
async function configureHooksPath(worktreePath: string, baseRepo: string): Promise<void> {
  const hooksPath = path.join(baseRepo, '.git', 'hooks').replace(/\\/g, '/');
  await gitExec(['-C', worktreePath, 'config', 'core.hooksPath', hooksPath]);
}
```

- The command has no `--worktree` option. Thus Git writes the value into the shared `.git/config`. The value applies to the main checkout and to all worktrees.
- The function does not read the current value. It replaces values that tools set, for example `.vite-hooks/_` ([Vite+](https://viteplus.dev/)) or `.husky/_` (husky v9).
- The value stays after you remove the worktree.
- `vp config` does not repair the value. It does not replace a value that another tool set, so it skips (step 4 of the result).

When `core.hooksPath` is not set, Git already uses the shared `.git/hooks` directory in every worktree. Thus the function is not necessary to share hooks.

## Run the reproduction

You need Git 2.20 or later and a POSIX shell.

```sh
sh repro.sh
```

The script does not use Cindy. It runs the same `git config` command that Cindy runs.
It does not use your global or system Git configuration.
It creates its files in `./work` and deletes them again at each run.

The script does not use Vite+. Its `vp_config` function does the same steps as `install()` in [`packages/cli/src/config/hooks.ts`](https://github.com/voidzero-dev/vite-plus/blob/1d30b8acf75e5ddf00a3f2e0a6ebe46f73d24a4e/packages/cli/src/config/hooks.ts#L576-L641) (commit `1d30b8a`):

1. If `core.hooksPath` already has a different value, it writes nothing.
2. It writes the hook dispatcher into `.vite-hooks/_/`. A `.gitignore` with `*` keeps this directory out of Git. Thus each checkout makes its own copy, for example when `vp install` runs `vp config`.
3. It sets `core.hooksPath` to the relative path `.vite-hooks/_`. Git resolves this path from the root of each worktree.

The committed hook `.vite-hooks/pre-commit` only prints `VITE_PLUS_HOOK_RAN`.

## Result

```text

== 1. Repository with a committed Vite+ hook, then 'vp config'
  vp config (repo): dispatcher installed
file:.git/config	.vite-hooks/_
[main checkout] pre-commit hook: RAN

== 2. Plain 'git worktree add', then 'vp config' in it (as 'vp install' does)
  wt-plain/.vite-hooks/_ does not exist yet (ignored by git)
  vp config (wt-plain): dispatcher installed
[plain worktree] pre-commit hook: RAN

== 3. Cindy creates a worktree and runs its configureHooksPath
file:.git/config	<work>/repo/.git/hooks
  vp config (wt-cindy): core.hooksPath is already set to "<work>/repo/.git/hooks", skipping
[main checkout] pre-commit hook: DID NOT RUN
[plain worktree] pre-commit hook: DID NOT RUN
[cindy worktree] pre-commit hook: DID NOT RUN

== 4. Remove the Cindy worktree; the overwrite stays and 'vp config' does not repair it
file:.git/config	<work>/repo/.git/hooks
  vp config (repo): core.hooksPath is already set to "<work>/repo/.git/hooks", skipping
[main checkout] pre-commit hook: DID NOT RUN

== 5. Recovery: set the value again by hand
file:.git/config	.vite-hooks/_
[main checkout] pre-commit hook: RAN
[plain worktree] pre-commit hook: RAN
```

## Possible fixes

1. Remove the `configureHooksPath` call. Git shares `.git/hooks` between worktrees without it.
2. If Cindy must keep the call, do not write when `git config --get core.hooksPath` already returns a value.

## Recover an affected repository

In the main checkout, set the value that your tool uses again. For Vite+:

```sh
git config core.hooksPath .vite-hooks/_
```
