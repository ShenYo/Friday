# Agent Rules

Apply these shared rules unless a consumer overlay supplies a more specific,
compatible rule.

1. **Scope.** Make only changes that serve the requested outcome. Preserve
   unrelated work and report relevant discoveries instead of broadening scope.
2. **Understand first.** Read the directly affected code, configuration, and
   local instructions before changing them. Surface material ambiguity,
   conflicts, or long-term tradeoffs before choosing on the user's behalf.
3. **Small, reversible work.** Prefer the smallest change that meets the
   request and the repository's established conventions. Do not introduce
   speculative abstraction or unrelated cleanup.
4. **Verify the outcome.** Choose checks that can demonstrate the requested
   behavior. State what ran, what passed, and any evidence that remains
   unavailable.
5. **Safety and authority.** Read
   [`git-guideline/safety-boundary.md`](git-guideline/safety-boundary.md)
   before a Git or GitHub operation -- or
   [the copy in Friday](https://github.com/ShenYo/Friday/blob/main/payload/.agents/docs/git-guideline/safety-boundary.md)
   where this repository does not ship that tree. It is the authority and this
   rule does not replace it. Three things in it must not be got wrong even by
   an agent that has not opened it yet.
   **Committing, pushing a non-default branch, and opening a pull request are
   your own call**, on one condition: traceability. One task's context per
   commit, the whole branch belonging to that one task, and the pull request
   describing exactly the commits on it.
   **Check for sensitive information before every commit and before every
   push**, across every commit being pushed rather than only the last. If
   anything is present, stop; report which file and which kind of value
   without reproducing the value.
   **Destructive and irreversible operations are prohibited outright, and an
   explicit request does not authorize one** -- force push, `reset --hard` or
   any history rewrite, discarding uncommitted work, deleting a ref, file or
   remote. Identify the target and the command, then ask the user to run it.
   Merging a pull request, enabling auto-merge, pushing to the default branch,
   closing or reopening a pull request, and changing repository or
   branch-protection settings are reserved for a person who names the
   operation and its target in the current turn. Never approve a pull request
   containing your own work.
6. **Git state.** Before an edit batch and before a commit, inspect the
   current branch, `HEAD`, and working-tree status. Repeat that inspection
   after an external change, branch switch, or unexpected drift.
7. **Portable requirements.** Every project-required workflow outcome lives in
   project-controlled documentation, tests, or automation. Personal or vendor
   Skills may assist but are optional; when absent, follow the project contract
   without installing, copying, or implicitly requiring a Skill.
   For testing work, apply the scenario-driven contract in
   [`testing.md`](testing.md) when the requested outcome needs behavioral
   evidence -- or
   [in Friday](https://github.com/ShenYo/Friday/blob/main/payload/.agents/docs/testing.md)
   where this repository does not ship it.
