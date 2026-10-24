---
name: git-commit
description: Create one verified Git commit using this repository's commit format.
disable-model-invocation: true
---

# Git Commit

This skill is the procedure for committing correctly, not a permission to
commit. Committing is at the agent's discretion — see the default posture in
`.agents/docs/git-guideline/safety-boundary.md` — so the same rules apply
whether or not this skill was invoked. Read that document and
`.agents/docs/git-guideline/git-commit.md` before acting; together they are the
source of truth for the message format, the one-task-per-commit traceability
rule, and the sensitive-information check that runs before staging.

## Inspect and stage

1. Run `git branch --show-current`, `git status --short`,
   `git diff --cached`, and `git diff`.
2. Stop if the current branch is `main`, there are no changes, or the work is
   not one atomic change.
3. Preserve an existing staged set and commit only that set. If nothing is
   staged, stage only files clearly belonging to the task just completed. If
   the scope is ambiguous, stop and ask the user to name the files; never use
   a blanket `git add .`.
4. Run relevant verification for the staged change and
   `git diff --cached --check`.

## Write and commit

1. Build the message solely from the staged diff.
2. Use `type(scope): summary`: imperative, no final period, target 50
   characters or fewer. Prefer lowercase after the prefix; a proper noun, a
   `code` name, a number or a non-English summary starts however it naturally
   does.
3. Add a body only when it clarifies why. Use real newlines and Markdown `-`
   bullets; wrap prose at 72 characters. Add `Co-Authored-By` only when an
   agent materially co-authored the change.
4. Commit the staged change. Do not amend, force, or push.

## Read back

Immediately run:

```sh
git show -s --format=%B HEAD
git status --short
```

Confirm the raw message has the intended subject, actual line breaks, and
Markdown bullets; reject literal `\n` in place of a newline. Report the commit
ID, verification run, and any remaining uncommitted files.
