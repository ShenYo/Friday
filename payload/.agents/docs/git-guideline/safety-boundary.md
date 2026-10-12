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
| Remote write | `git push`; changing an `origin` URL; creating, editing, closing, or merging a PR; any GitHub issue, release, or repository mutation |
| Local deletion or discard | deleting a file or directory; `git rm`; `git restore`; `git checkout -- <path>`; dropping a stash; removing a worktree |
| Local commit | `git commit` |

Examples of sufficient authorization:

- "Push `chore/post-s0-optimization` to `origin`."
- "Create a PR from this branch to `main`."
- "Delete `docs/temp/chore-post-s0-optimization/`."

When authorized, first inspect and report the resolved target, perform only
the named action, then read back its result. Never add force flags, delete
refspecs, or extra GitHub mutations unless the user named them too.

## Enforced Claude Bash adapter

Friday installs and checks a Claude Code `PreToolUse` Bash adapter. It blocks
the following operations when they are issued through that adapter. Even after
a user asks, explain that they must run the command directly:

- force push, including `--force-with-lease`;
- `git reset --hard`, `git clean`, `git branch -D`, `git stash clear/drop`,
  and `git worktree remove`;
- recursive local deletion (`rm -r*` or `find -delete`);
- removing or rewriting a Git remote URL;
- deleting a GitHub repository or issuing a GitHub API `DELETE` request.

The same policy applies to every runtime, but Friday has not installed or
verified Codex or Gemini adapters. Use each runtime's approval controls and
least-privilege GitHub credentials where a hard security boundary is needed.
