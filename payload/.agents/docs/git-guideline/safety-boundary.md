# Collaborative Git Safety Boundary

> **中文摘要**：commit 與 push（非 default branch）由 agent 自行判斷，不需逐次
> 授權；真正的門檻是三件事：破壞性／不可回復的操作永久禁止、需要人工審核的
> 操作（PR merge、直接推 default branch）一律交回使用者、以及每個
> commit/push/PR 都必須有清楚且**不混雜**的 context。commit/push 前必須檢查
> 有無敏感資訊。

This boundary applies to every agent and tool in this repository. It prevents
unintended and untraceable operations; it is not a security boundary against an
actor that can bypass local hooks or use the user's credentials.

## Default posture

Ordinary version control is part of doing the work, not a separate permission.

- Read-only Git and GitHub inspection is allowed whenever it is relevant.
- **Committing is at the agent's discretion.** Commit when a logical unit of
  work is complete, without asking first.
- **Pushing a non-default branch is at the agent's discretion.** Push when the
  branch is in a state someone else could usefully read.
- Opening a pull request is at the agent's discretion.
- The gate is no longer "did the user ask in this turn". The gate is the three
  sections below: traceability, human-review checkpoints, and the permanent
  prohibitions. An operation that clears all three needs no further permission.

Discretion is not licence to batch up unrelated work. The traceability rules
are the condition on which that discretion rests.

## Traceability: one task's context per commit

This is the requirement that makes agent discretion safe. A reader six months
from now must be able to tell what each commit was for and why, without
reconstructing the conversation that produced it.

- **One commit carries one task's context.** Never combine changes that belong
  to different tasks, requests, or investigations in a single commit, even when
  they are small and even when they sit in the same working tree.
- **Say what changed and why.** The message explains the reason the change
  exists. The diff already shows the mechanism. Follow
  [`git-commit.md`](git-commit.md) for the format.
- **If the working tree holds unrelated work, stage selectively.** Stage the
  files for this task only, or split into separate commits. Do not run a
  blanket `git add -A` across a mixed tree, and do not describe a mixed commit
  with the message of whichever task happens to be in focus.
- **If the tree cannot be separated cleanly, stop and say so** rather than
  committing a mixture. A commit nobody can attribute is worse than an
  uncommitted change.
- **A push inherits the same requirement.** Do not push a branch whose commits
  mix task contexts, and state which branch and which commits are going out.
- **A pull request states its own scope.** Its description covers exactly the
  commits on that branch and nothing else. If the branch accumulated unrelated
  commits, that is a problem to resolve before opening the PR, not to explain
  away in the description.

## Check for sensitive information before committing and pushing

Run this check every time, before staging a commit and before pushing.

- Read the staged diff and confirm it contains no credential, API key, access
  or refresh token, private key, certificate, password, connection string with
  embedded credentials, session cookie, or personal identifier that the
  repository does not already carry on purpose.
- Treat generated and copied files with particular suspicion: `.env` and its
  variants, local configuration, editor and tool state, build output, logs,
  database dumps, HAR and network captures, and fixtures recorded from a real
  system.
- Before pushing, confirm the same for every commit being pushed, not only the
  most recent one.
- **If anything sensitive is present, stop. Do not commit and do not push.**
  Report exactly which file and which kind of value, without reproducing the
  value itself.
- **If a secret has already been committed or pushed, say so immediately and
  treat it as compromised.** The agent cannot clean it up: removing it from
  history requires rewriting and force-pushing, both permanently prohibited
  below. The owner's path is to rotate the credential first, then decide about
  history.

A secret that never enters the index is the only case this check can fully
resolve, which is why it runs before staging rather than after.

## Human-review checkpoints

These are not destructive, and some are reversible. They are reserved for a
person because automated review cannot substitute for the judgement they carry.
The user must name the operation and its exact target in the current turn.

| Checkpoint | Why it is reserved |
| --- | --- |
| Merging a pull request | However many checks a PR passed, the final decision to integrate is a person's. No combination of green CI, review bots, or agent analysis substitutes for it. |
| Enabling auto-merge | This is the same decision taken in advance and delegated to CI. It is reserved for the same reason as merging. |
| Pushing directly to the default branch | A direct push bypasses the PR checkpoint above, so leaving it open would make that checkpoint optional in practice. |
| Closing or reopening a pull request | It changes the state of a shared review artifact that others may be acting on. |
| Changing branch protection, required checks, or repository settings | These define the checkpoints themselves. |

**An agent must not approve a pull request containing its own work.** Approval
is the review act; an author approving their own change satisfies the
checkpoint without anyone having reviewed it. An independent reviewing agent
that did not author or direct the change under review may approve. Note the
limit: this row is enforced by instruction, not by the runtime guard, because
the guard sees a command and cannot tell an author from an independent
reviewer. See the verification limits below.

## Permanent agent-prohibited operations

These destroy work or cannot be undone. They are prohibited for every agent in
every runtime, independent of hooks or other enforcement, and **an explicit
user request does not authorize an agent to perform them**. Identify the exact
target and command, then ask the user to run it directly.

| Category | Operations |
| --- | --- |
| History rewriting | force push, including `--force-with-lease`; `git reset --hard`; any history rewrite of a pushed branch |
| Discarding local work | `git clean`; `git stash clear` and `git stash drop`; `git worktree remove`; `git restore` and `git checkout -- <path>` over uncommitted changes |
| Deleting refs | deleting a local or remote branch (`git branch -d`, `-D`, `git push --delete`, `git push <remote> :<ref>`); deleting a tag locally or remotely |
| Deleting files | recursive deletion (`rm -r*`, `find -delete`); `git rm`; patch-based deletion, including Codex `apply_patch` deletion |
| Detaching a remote | removing or rewriting a Git remote URL |
| Destroying remote state | deleting a GitHub repository; a GitHub API `DELETE` request |

Deleting a merged branch is routine housekeeping for a person and still sits
here, because an agent cannot reliably tell a merged branch from one that only
looks merged, and the mistake costs unpushed work.

## Runtime guardrails and verification limits

Friday installs and checks a Claude Code `PreToolUse` adapter and a Codex
`PreToolUse` adapter for `Bash` and `apply_patch`. Both invoke the shared
guard, which refuses the operations in the prohibitions table and the
hook-enforceable checkpoints, and the checker validates their wiring and
executes the configured launchers against allow and block payloads.

What the guard does **not** enforce, and what therefore depends on these
instructions being followed:

- The traceability rules. No hook can tell whether a commit mixes two tasks.
- The sensitive-information check. The guard does not scan diffs.
- The self-approval rule, as described above.
- Any checkpoint reached through a path the guard does not pattern-match, such
  as an unusual command spelling, a wrapper script, or a GitHub API call that
  is not a `DELETE`.

The Codex hook is a non-managed project runtime seed, not managed-core content;
review and trust its pinned hash before relying on it. Handler ordering,
concurrency, and fail-closed behavior under hook error are verified only where
a project records that evidence. Gemini remains pending. These hooks are
guardrails against mistakes, not a security boundary: where a hard boundary is
needed, use the runtime's own approval controls, branch protection, and
least-privilege credentials.
