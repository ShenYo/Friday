---
name: github-pr-verify
description: Verify a specified or current branch pull request, then update its Definition of Done evidence.
disable-model-invocation: true
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
   (`pull_request_template.md` in `.github/`, `docs/` or the root, in any
   capitalisation, or the one the PR used from a `PULL_REQUEST_TEMPLATE/`
   directory) and the verification or
   Definition-of-Done rules that `.agents/AGENTS.md` routes to.
2. Inspect the working-tree status and resolve the target PR with `gh pr view`:
   no PR number means the current branch; a supplied PR number means that PR.
   Record the PR number, URL, base branch, head branch, and head SHA. Stop if
   the target PR is not open, or if its head is in a fork
   (`isCrossRepository`): this Skill is for the repository's own branches.
3. Fetch the base branch and the resolved head ref from `origin`. Do not
   checkout, reset, or alter the working tree. Pin every diff command to
   `origin/<base>...<head SHA>`, the recorded SHA rather than the branch
   name, so a branch name never becomes shell text and a later push does not
   change what is verified.
4. Run the repository checks that exist:

   ```sh
   bash .agents/hooks/check-collaborative-git.sh
   git diff --check "origin/<base>...<head SHA>"
   ```

   When the repository keeps an avoid-list at `.agents/avoid-terms.grep`, grep
   the added lines of the application-code paths its rules name, leaving out
   any paths they exclude (not prose, which may legitimately document the
   terms). Write the diff to a file first, so a failed `git diff` stops the
   check instead of reading as no matches:

   ```sh
   git diff "origin/<base>...<head SHA>" -- <application-code paths> \
     ':(exclude)<excluded path>' > "$diff_file"
   grep '^+' "$diff_file" \
     | grep -inE -f <(grep -vE '^[[:space:]]*(#|$)' .agents/avoid-terms.grep)
   ```

   The Avoid-list command passes only when `git diff` succeeded and the grep
   has no matches (exit 1); exit 2 is an error. Search for TODO, FIXME, XXX,
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
   `action required`, or `unverified`), and evidence. When neither the PR
   template nor the routed rules define a Definition of Done, the criteria are
   the checks of steps 4–6 plus fresh-context verification. Keep
   fresh-context verification as `action required`: the authoring agent must
   not self-certify it. State the focused manual-review items for the user or
   an independently authorised reviewer.

## Update evidence

After every invocation:

1. Confirm the resolved PR is open and that its head SHA is the verified SHA.
   Stop on any mismatch.
2. Re-read the body just before editing it. Update only the
   `## Definition of done` section (the heading in any capitalisation) and,
   if needed, a `## Verification evidence` section immediately after it.
   Preserve the summary, visual evidence, and every other section verbatim.
   When the body has no Definition of Done section, append a
   `## Verification evidence` section at the end of the body, with
   `<!-- github-pr-verify -->` on the line after its heading, and change
   nothing else. A rerun replaces only a section carrying that marker; an
   unmarked one is the author's and stays as it is.
3. Check a box only when the just-completed verification has evidence. Leave
   manual or independently verified work unchecked, and state each remaining
   action item in `## Verification evidence`.
4. Read the PR body back after the edit and report the exact changed status.
   Check the head SHA again: if it moved during the update, say that the
   evidence describes the verified SHA, not the new head.
