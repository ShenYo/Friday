# Pull Request Visual Evidence

Use this workflow when adding visual evidence to a pull request. It provides
reviewers with visual context without committing one-off screenshots to the
repository.

## When to add visual evidence

- Add visual evidence when it helps reviewers understand a frontend change
  that changes what a user sees or interacts with.
- Use a screenshot for a static state. Use a short recording or multiple
  screenshots when the interaction or transition is material.
- Include both desktop and mobile only when the change affects responsive
  layout or behavior.
- When no visual evidence is attached, omit the Visual evidence section from
  the PR body; do not add `N/A` or an explanation.

## Agent workflow

1. Confirm the local app and the changed flow work. Run the relevant tests or
   state exactly what could not be run.
2. Create a temporary visual-evidence directory only when providing visual
   evidence:

   ```text
   docs/temp/<branch-slug>/
   ```

   Replace every `/` in the Git branch name with `-`. For example,
   `feat/s1-first-run` becomes `docs/temp/feat-s1-first-run/`.
3. Capture descriptive files such as `desktop-dashboard.png` or
   `mobile-add-record-sheet.png`. Use the locale, timezone, and data state
   relevant to the acceptance criterion. Never capture secrets or personal
   data.
4. Inspect the image and report its local path plus the behavior it proves.
   Do not claim a screenshot proves an interaction that it does not show.
5. Keep every screenshot and recording for that branch in its one temporary
   directory. `docs/temp/` is in `.gitignore`, so nothing under it can be
   committed by accident; never force one in with `git add -f`. They are
   temporary visual evidence for reviewers, not product design
   documentation.
6. Ask the user to upload the image manually to the PR description or a PR
   comment using GitHub's **Attach files** control. The built-in `gh` CLI can
   edit text but does not provide a supported PR-attachment upload command.
7. After the user confirms the upload, read the PR body or comment back to
   confirm an attachment URL is present. Do not claim the image rendered
   unless that was checked in GitHub's UI.

GitHub's official attachment instructions are available at
<https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files>.

## What not to do

- Do not use a feature-branch raw/blob URL for one-off PR visual evidence;
  branch deletion can break it after merge.
- Do not add one-off review screenshots to `docs/design/` or other tracked
  documentation directories.
- Do not create a GitHub Release merely to host a PR screenshot.
- Do not scatter files directly under `docs/temp/`; each branch owns one
  directory so it can be removed as a group when no longer needed.
- Do not delete the branch visual-evidence directory without user direction;
  the user may still need it for manual upload.
