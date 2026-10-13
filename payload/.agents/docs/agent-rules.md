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
   Git and GitHub operations. Do not infer authorization for commits, remote
   writes, deletion, or discard actions.
6. **Git state.** Before an edit batch and before a commit, inspect the
   current branch, `HEAD`, and working-tree status. Repeat that inspection
   after an external change, branch switch, or unexpected drift.
