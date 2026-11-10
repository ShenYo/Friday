---
name: github-pr-verify
description: Verify a specified or current branch pull request, then update its Definition of Done evidence.
---

# GitHub PR Verify

Use this only after selecting an open pull request.

## Modes

- `$github-pr-verify`: verify and update the current branch's open PR.
- `$github-pr-verify <PR-number>`: verify and update that open PR, without
  switching branches.
- `$github-pr-verify publish <PR-number>`: supported alias for the same
  update.

Every invocation updates only the resolved PR's Definition of Done and
verification action items after verification. No suffix resolves to the
current branch's open PR; a numeric suffix resolves to that exact PR. Never
commit, push, merge, or alter unrelated PR-description text.

## Verify

1. Read `.agents/AGENTS.md`, `.agents/docs/git-guideline/safety-boundary.md`
   and `.agents/docs/git-guideline/pr-evidence.md`. Also read, when the
   repository has them, its pull request template
   (`.github/pull_request_template.md`) and the verification or
   Definition-of-Done rules that `.agents/AGENTS.md` routes to.
2. Inspect the working-tree status and resolve the target PR with `gh pr view`:
   no PR number means the current branch; a supplied PR number means that PR.
   Record the PR number, URL, base branch, head branch, and head SHA. Stop if
   the target PR is not open.
3. Fetch only the resolved remote head ref. Do not checkout, reset, or alter
   the working tree. Pin every diff command to
   `origin/<base>...origin/<head>`.
4. Run the repository checks that exist:

   ```sh
   bash .agents/hooks/check-collaborative-git.sh
   git diff --check "origin/<base>...origin/<head>"
   ```

   When the repository keeps an avoid-list at `.agents/avoid-terms.grep`, grep
   the added lines of the application-code paths its rules name (not prose,
   which may legitimately document the terms):

   ```sh
   git diff "origin/<base>...origin/<head>" -- <application-code paths> \
     | grep '^+' \
     | grep -inE -f <(grep -v '^ *#' .agents/avoid-terms.grep)
   ```

   The Avoid-list command passes only when it has no matches. Distinguish a
   no-match exit from a command error. Search for TODO, FIXME, XXX,
   `console.log`, and `debugger` only in added executable/configuration files
   (`.agents/hooks`, `.claude`, `.codex`, `.github`, and the application-code
   paths), not prose that legitimately documents those terms.
5. Read the PR's current-head CI status checks. Green CI is evidence; do not
   rerun the full suite solely to duplicate successful GitHub Actions. Treat a
   pending, missing, or failed check as an action item and include its URL.
6. Inspect the touched directories and any pattern or convention files the
   repository keeps for them. Report the review focus; do not claim this
   judgement is mechanically verified unless a relevant check actually proves
   it.
7. Report a concise table: Definition-of-Done criterion, status (`verified`,
   `action required`, or `unverified`), and evidence. Keep
   fresh-context verification as `action required`: the authoring agent must
   not self-certify it. State the focused manual-review items for the user or
   an independently authorised reviewer.

## Update evidence

After every invocation:

1. Confirm the resolved PR is open and that its head SHA is the verified SHA.
   Stop on any mismatch.
2. Update only the `## Definition of done` section and, if needed, a
   `## Verification evidence` section immediately after it. Preserve the
   summary, visual evidence, and every other section verbatim.
3. Check a box only when the just-completed verification has evidence. Leave
   manual or independently verified work unchecked, and state each remaining
   action item in `## Verification evidence`.
4. Read the PR body back after the edit and report the exact changed status.
