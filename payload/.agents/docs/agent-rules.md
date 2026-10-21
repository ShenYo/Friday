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
5. **Safety and authority.** Follow
   [`git-guideline/safety-boundary.md`](git-guideline/safety-boundary.md) for
   Git and GitHub operations. Committing and pushing a non-default branch are
   your own call there, on the condition that each commit carries one task's
   context and no sensitive value. Never infer authorization for a deletion, a
   discard, a history rewrite, or an operation that document reserves for human
   review, such as merging a pull request or pushing to the default branch.
6. **Git state.** Before an edit batch and before a commit, inspect the
   current branch, `HEAD`, and working-tree status. Repeat that inspection
   after an external change, branch switch, or unexpected drift.
7. **Portable requirements.** Every project-required workflow outcome lives in
   project-controlled documentation, tests, or automation. Personal or vendor
   Skills may assist but are optional; when absent, follow the project contract
   without installing, copying, or implicitly requiring a Skill.
   For testing work, apply the scenario-driven contract in
   [`testing.md`](testing.md) when the requested outcome needs behavioral
   evidence.
