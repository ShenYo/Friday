# Collaborative Git Safety Boundary

> **中文摘要**：預設不做 remote 寫入或本機刪除。必須由使用者在同一個
> turn 明確說出動作與目標；部分高破壞性操作永遠由使用者親自執行。

This boundary applies to every agent and tool in this repository. It prevents
unintended operations; it is not a security boundary against an actor that can
bypass local hooks or use the user's credentials.

## Default posture

- Read-only Git and GitHub inspection is allowed when relevant.
- Do not infer authorization from a previous turn, a branch name, a commit,
  a task being complete, or a user saying "finish".
- A manual Git skill invocation authorizes only that skill's documented action
  in the current turn: `$git-commit`, `$git-push`, or `$git-create-pr`.
- If the action or target is ambiguous, stop and ask. Do not stage, stash,
  discard, delete, force, or select a target on the user's behalf.

## Actions needing explicit same-turn authorization

The user must name both the operation and its exact target before an agent may
perform any of the following:

| Category | Examples |
| --- | --- |
| Remote write | `git push`; creating, editing, closing, or merging a PR; any GitHub issue, release, or repository mutation |
| Local deletion or discard | deleting any file or directory; `git rm`; `git restore`; `git checkout -- <path>` |
| Local commit | `git commit` |

Explicit authorization for the local-deletion row applies only to the allowed
workflows listed there. It never overrides the permanent prohibitions below.

Examples of sufficient authorization:

- "Push `chore/post-s0-optimization` to `origin`."
- "Create a PR from this branch to `main`."
- "Delete `docs/temp/chore-post-s0-optimization/`."

When authorized, first inspect and report the resolved target, perform only
the named action, then read back its result. Never add force flags, delete
refspecs, or extra GitHub mutations unless the user named them too.

## Permanent agent-prohibited operations

The following operations are prohibited for every agent in every runtime,
independent of hooks or other enforcement. An explicit user request does not
authorize an agent to perform them. Identify the exact target and command, then
ask the user to run it directly:

- force push, including `--force-with-lease`;
- `git reset --hard`, `git clean`, `git branch -D`, `git stash clear/drop`,
  and `git worktree remove`;
- recursive local deletion (`rm -r*` or `find -delete`);
- patch-based file deletion, including Codex `apply_patch` deletion;
- removing or rewriting a Git remote URL;
- deleting a GitHub repository or issuing a GitHub API `DELETE` request.

## Runtime guardrails and verification limits

Friday installs and checks a Claude Code `PreToolUse` Bash adapter and a Codex
`PreToolUse` adapter for `Bash` and `apply_patch`. Both invoke the shared
guard; the checker validates their static wiring and directly exercises safe
Bash and `apply_patch` allow/block payloads.

The Codex hook is a non-managed project runtime seed, not managed-core content.
Review and trust its pinned hash before relying on it. Native callback delivery,
exit-code consumption, ordering with other handlers, and fail-closed behavior
remain unverified. These hooks are guardrails, not a security boundary.

Gemini remains pending. The permanent policy still applies to every runtime;
use runtime approval controls and least-privilege GitHub credentials where a
hard security boundary is needed.
