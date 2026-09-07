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

1. Read `.agents/AGENTS.md`, `.agents/docs/judgment-rubrics.md` section 5,
   `.agents/docs/git-guideline/safety-boundary.md`,
   `.agents/docs/git-guideline/pr-evidence.md`, and
   `.github/pull_request_template.md`.
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
   git diff "origin/<base>...origin/<head>" -- <source dirs> ':(exclude)*.feature' \
     | grep '^+' \
     | grep -inE -f <(grep -v '^ *#' .agents/avoid-terms.grep)
   ```

   The Avoid-list command passes only when it has no matches. Distinguish a
   no-match exit from a command error. Search for TODO, FIXME, XXX,
   `console.log`, and `debugger` only in added executable/configuration files
   (`.agents/hooks`, `.claude`, `.codex`, `.github`, `backend`, `frontend`),
   not prose that legitimately documents those terms.
5. Read the PR's current-head CI status checks. Green CI is evidence; do not
   rerun the full suite solely to duplicate successful GitHub Actions. Treat a
   pending, missing, or failed check as an action item and include its URL.
6. Inspect touched application directories and their `PATTERNS.md` files.
   Report the review focus; do not claim this judgement is mechanically
   verified unless a relevant check actually proves it.
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
