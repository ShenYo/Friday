---
name: git-create-pr
description: Create one verified GitHub pull request for the current branch.
disable-model-invocation: true
---

# Git Create PR

Treat explicit manual invocation as authorization to create one pull request
for the current branch in this turn only. Do not infer PR intent outside this
skill. Read `.agents/docs/git-guideline/safety-boundary.md` before acting. Do
not commit, push, merge, edit reviewers, or change labels.

## Inspect

1. Read `.agents/docs/git-guideline/issue-tracker.md`,
   `.agents/docs/git-guideline/pr-evidence.md`, and
   `.github/pull_request_template.md`.
2. Run `git branch --show-current`, `git status --short`, `git status -sb`,
   `git remote get-url origin`, and `gh repo view --json defaultBranchRef`.
3. Stop if there is no current branch or `origin`, if the current branch is
   the repository default branch, if it has no upstream, if local commits are
   not pushed, if the branch has no committed diff against the default branch,
   or if an open PR already uses this head branch. Tell the user the exact
   condition; use `$git-push` only when they ask to push.
4. Report uncommitted files as excluded from the PR. Do not stage, commit,
   stash, discard, or otherwise modify them.

## Draft and create

1. Draft the title and body solely from the committed branch diff. Use the PR
   template: a concise Summary, the optional Visual evidence section, and the
   Definition of done checklist.
2. Mark a checklist item only when its evidence is available. Leave optional
   visual evidence blank when none is needed; do not write `N/A` or an
   explanation. Follow the visual-evidence SOP for any attachment and never
   commit files under `docs/temp/`.
3. Create the PR with `gh pr create`, explicitly setting its base to the
   repository default branch and its head to the current branch. Pass the
   drafted body via a temporary file so real Markdown line breaks are kept.

## Verify

1. Run `gh pr view --json url,title,baseRefName,headRefName,state`.
2. Confirm that the returned URL, title, base, head, and open state match the
   intended PR. Report them, the uncommitted files excluded (if any), and the
   verification evidence.
