---
name: git-push
description: Push the current Git branch safely to its configured remote.
disable-model-invocation: true
---

# Git Push

Treat explicit manual invocation as authorization to push the current branch
in this turn only. Do not infer push intent outside this skill. Read
`.agents/docs/git-guideline/safety-boundary.md` before acting.

## Confirm the target

1. Run `git branch --show-current`, `git status --short`,
   `git remote get-url origin`, and `git status -sb`.
2. Stop if there is no branch, no `origin` remote, or the branch is `main`.
   A push to the default branch needs a separate explicit user instruction.
3. Report any uncommitted files as excluded from the push. Do not stage,
   commit, stash, discard, or otherwise alter them.

## Push and verify

1. If the current branch already has an upstream, run `git push`.
2. Otherwise run `git push --set-upstream origin <current-branch>`.
3. Never use `--force`, `--force-with-lease`, deletion refspecs, tags, or a
   different remote unless the user explicitly names that action.
4. Run `git status -sb` after a successful push and report the remote branch.
