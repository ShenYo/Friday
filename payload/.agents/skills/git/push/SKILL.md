---
name: git-push
description: Push the current Git branch safely to its configured remote.
disable-model-invocation: true
---

# Git Push

This skill is the procedure for pushing correctly, not a permission to push.
Pushing a non-default branch is at the agent's discretion — see the default
posture in `.agents/docs/git-guideline/safety-boundary.md` — so the same rules
apply whether or not this skill was invoked. Pushing directly to the default
branch remains a human-review checkpoint. Read that document before acting,
and confirm no commit going out carries sensitive information.

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
