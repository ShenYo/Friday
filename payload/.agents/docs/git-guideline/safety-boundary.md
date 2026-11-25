# Collaborative Git Safety Boundary

> **中文摘要**：commit 與 push（非 default branch）由 agent 自行判斷，不需逐次
> 授權；真正的門檻是三件事：破壞性／不可回復的操作永久禁止、需要人工審核的
> 操作（PR merge、直接推 default branch）一律交回使用者（auto-merge 只在
> `check-auto-merge` 通過且 fresh agent review 無未解 finding 時由 agent 開啟）、以及每個
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

A `pre-commit` hook enforces this one mechanically: see the enforcement layers
below. It reports the rule and the file and never echoes the matched value. It
recognises common credential formats, so treat it as a net under the check
rather than a replacement for reading the diff.

## Human-review checkpoints

These are not destructive, and some are reversible. They are reserved for a
person because automated review cannot substitute for the judgement they carry.
The user must name the operation and its exact target in the current turn.

| Checkpoint | Why it is reserved |
| --- | --- |
| Merging a pull request | However many checks a PR passed, the final decision to integrate is a person's. No combination of green CI, review bots, or agent analysis substitutes for it. |
| Enabling auto-merge | This is the same decision taken in advance and delegated to CI, so it is reserved for the same reason as merging, with one exception: the agent arms it under [Arming auto-merge](#arming-auto-merge), where the base branch's rules keep the owner's approval of the latest push decisive. |
| Pushing directly to the default branch | A direct push bypasses the PR checkpoint above, so leaving it open would make that checkpoint optional in practice. Enforced by `pre-push`. |
| Closing or reopening a pull request | It changes the state of a shared review artifact that others may be acting on. |
| Changing branch protection, required checks, or repository settings | These define the checkpoints themselves. |
| Pushing a tag, or publishing a GitHub Release | No agent may delete a tag, so a pushed tag is one the agent cannot take back, and a release tag is also the name consumers take a release by. A GitHub Release is published under that name for people to read, and an agent cannot delete one either. An agent pushes a tag, including through `--tags`, `--follow-tags` or `push.followTags`, only when the user names the tag and the commit in the current turn; it never pushes one on its own judgement. The same holds for publishing, editing or uploading to a GitHub Release (`gh release create`, `gh release edit`, `gh release upload`, or the same through the API): only when the user names the release and its tag in the current turn. Friday's guard and `pre-push` do not check this row: it is enforced by instruction. |

### Arming auto-merge

An agent arms auto-merge on a pull request only when both hold:

- a fresh agent, one that did not write the change, has reviewed it and the
  review ended with no must-fix or should-fix finding open. The author's own
  checks and a green CI are not that review;
- `.agents/bin/check-auto-merge <n> -R <owner>/<repo>` exits 0.

The check is what makes the exception safe. Without a ruleset that requires the
owner's approval, an armed pull request merges as soon as CI is green. It exits
0 only when all of these hold, and otherwise prints the condition that failed:

- `.agents/auto-merge`, read from the base branch of the target repository
  through the contents API and not from the local checkout, is absent (404) or
  says `on` (`off` opts the repository out; anything else, or any other error,
  fails). A change takes effect only once it is merged;
- the repository is owned by a user, not an organization (`* @<owner>` is not a
  valid CODEOWNERS owner for an organization);
- the base branch has exactly one `pull_request` rule, requiring at least one
  approving review, code-owner review, dismissal of stale approvals on push and
  approval of the last push, and that rule's ruleset is `active` with
  `current_user_can_bypass` `never`;
- `.github/CODEOWNERS` on the base branch is, apart from comments, a single
  `* @<owner>` rule;
- the acting login's `role_name` on the repository is `write`, and neither
  `GH_TOKEN` nor `GITHUB_TOKEN` is set. That check sees the environment of the
  hook process; a variable exported only in a shell profile is not visible to it;
- the repository allows auto-merge, and the pull request is open.

Any error reading these, a 403 included, is a failure: a private repository on
a free GitHub plan cannot read rulesets, so there the answer is always no. The
shared runtime guard, which the Claude Code and Codex adapters both invoke,
refuses the plain spellings at the moment of use: it allows `gh pr merge`
with `--auto` only as the whole command `gh pr merge <n> --auto --squash -R
<owner>/<repo>`, and only when the check passes; any other form with `--auto`,
or a failing check, is blocked with the check's reason, whether `gh` is typed
bare, as `\gh`, quoted, or with a path. A `gh api` call that names
`enablePullRequestAutoMerge`, `mergePullRequest` or a `pulls/<n>/merge` path is
refused whatever its method: merging and arming go through the plain
`gh pr merge <n> --auto --squash -R owner/repo` form only. `--disable-auto`
stays allowed. This is a tripwire, not a lock: the spellings that still pass
are listed under [what neither layer enforces](#what-neither-layer-enforces).

When the check fails, or the repository opted out, the agent does not arm: it
leaves the merge to a person and says in the pull request which condition
failed. Merging itself stays a person's.

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
| Destroying remote state | deleting a GitHub repository or a GitHub Release (`gh release delete`); a GitHub API `DELETE` request |

Deleting a merged branch is routine housekeeping for a person and still sits
here, because an agent cannot reliably tell a merged branch from one that only
looks merged, and the mistake costs unpushed work.

## The server-side ruleset

The hooks are local, so a clone without them, a CI checkout or a call to the
GitHub API passes them by. The part that holds is a ruleset on the default
branch, and the owner applies it: changing branch protection is a checkpoint
above. The ruleset binds the agent only where the agent works through its own
account without admin rights; where it uses an admin login, the ruleset does not
bind it (see below). The seed
`.github/rulesets/main.json` is the file, and it enforces what this document
assumes of the default branch:

- **No deletion** and **no force push** (`deletion`, `non_fast_forward`): the
  prohibitions above, on the server.
- **Changes arrive through a pull request** (`pull_request`): a direct push is
  a checkpoint above. The ruleset does not make the merge a person's: that rule
  is instruction-only, and once the owner has approved, an account with write
  access can merge.
- **One approving review, from the code owner**, stale approvals dismissed on
  push, the last push approved by someone other than its author, and every
  review thread resolved. An agent's own approval of its own work therefore
  does not count.

The file has no required status checks, because they differ per repository.
Add the rule to `rules` before applying, with the names your workflows report:

```json
{ "type": "required_status_checks",
  "parameters": { "strict_required_status_checks_policy": false,
                  "do_not_enforce_on_create": false,
                  "required_status_checks": [ { "context": "<job name>", "integration_id": 15368 } ] } }
```

`15368` is GitHub Actions. Code-owner review needs `.github/CODEOWNERS`, which
Friday does not ship because it names a person: add a single line, `* @your-login`.

`bypass_actors` holds the repository admin role in `pull_request` mode, so the
owner can still merge by hand. An account that is an admin of the repository
bypasses the ruleset the same way. So the ruleset binds the agent only when the
agent uses its own account without admin rights. Where the agent uses an admin
login, such as the owner's own, the ruleset does not bind it, and the safety
boundary there rests on the hooks and on instruction alone. Emptying
`bypass_actors` does not change that: the agent would still hold admin rights,
and the owner could no longer merge their own pull request.

Run these from the repository root, as the repository's admin, in your own
terminal, never from an agent session (`OWNER/REPO` is the repository):

```sh
gh api --method POST repos/OWNER/REPO/rulesets --input .github/rulesets/main.json
```

POST adds a ruleset every time, so run it once. If `gh api --paginate repos/OWNER/REPO/rulesets`
already lists one for the default branch, replace it by its ID instead:
`gh api --method PUT repos/OWNER/REPO/rulesets/ID --input .github/rulesets/main.json`.

Check that it is in force. The first command reads the ruleset back and must
print nothing; the second lists the rules GitHub applies to the branch:

```sh
ID=$(gh api --paginate repos/OWNER/REPO/rulesets --jq '.[] | select(.name == "'"$(jq -r .name .github/rulesets/main.json)"'") | .id')
f='{name, target, enforcement, conditions, rules, bypass_actors}'
diff <(jq -S "$f" .github/rulesets/main.json) <(gh api repos/OWNER/REPO/rulesets/$ID | jq -S "$f")
gh api "repos/OWNER/REPO/rules/branches/$(gh api repos/OWNER/REPO --jq .default_branch)" --jq '.[].type'
```

A private repository on a free GitHub plan cannot use rulesets: the API answers
`Upgrade to GitHub Pro or make this repository public`. There the hooks are all
a consumer has, and they guard against mistakes, not against anyone who skips
them. Do not claim more for such a repository.

## Runtime guardrails and verification limits

Two layers enforce parts of this document. They see different things, which is
why both exist.

**The runtime guard.** Friday installs and checks a Claude Code `PreToolUse`
adapter and a Codex `PreToolUse` adapter for `Bash` and `apply_patch`. Both
invoke the shared guard, which refuses the operations in the prohibitions table
and the hook-enforceable checkpoints. It sees the command string and nothing
else: it cannot read a staged diff, and `git commit -F -` passes the message on
stdin where it is invisible. The checker validates the wiring and executes the
configured launchers against allow and block payloads.

**The push-time Git hook.** `.agents/githooks/pre-push` receives the refs and
object ids Git is about to send, so it decides from what a push *does* rather
than how it was written. Deleting a ref, rewriting history, and pushing to the
default branch are refused identically whether they were spelled `--force`,
`-f`, `+refspec`, `--mirror`, `--delete` or `:ref`. The default branch is
resolved from the local remote HEAD; when that reference is missing, malformed,
or locally dangling, the hook refuses every push until it can resolve the
checkpoint.

**The commit-time Git hooks.** `.agents/githooks/pre-commit` and
`.agents/githooks/commit-msg`, wired through `core.hooksPath` at install, see
the staged diff and the message however it was supplied, and apply to a
person's commits as well as an agent's. `pre-commit` refuses staged content
matching known credential formats. `commit-msg` refuses a message that breaks
the format rules in [`git-commit.md`](git-commit.md), including a summary too
vague to trace to one task. The runtime guard refuses `--no-verify`, its
bundled short form, and `-c core.hooksPath`, without which either hook could be
skipped. The checker executes both in a scratch repository.

<a id="what-neither-layer-enforces"></a>
What **neither** layer enforces. Independent review established this list by
probing the guard directly; treat every row here as instruction-only, and do
not assume a rule has machinery behind it because it appears in a table above.

- **Local prohibitions, in some spelling.** The guard matches command shapes,
  not operations. `git restore`, `git checkout -- <path>`, `git rm <file>`,
  `git remote rm` and `git update-ref -d` reach a prohibited outcome locally
  without matching a pattern, and plumbing equivalents of a blocked porcelain
  command generally do too. What leaves the machine is covered by `pre-push`
  below; what stays local is not.
- **`gh` reached by an unusual spelling.** A path prefix, `\gh` and a quoted
  `gh` are now refused for every merge or arming form, and a `gh api` call
  that names `enablePullRequestAutoMerge`, `mergePullRequest` or a
  `pulls/<n>/merge` path is refused, `$n` and `${n}` spellings included. Still
  passing: `eval`, `bash -c`, a command name or path built from a variable,
  `gh api graphql -F query=@file`, `--input`, `-f query="$Q"`, `gh alias`, a
  `;`, `|` or `&` inside a quoted argument before the name or path (the match
  stops there so that a chained read-only command is not refused), and
  the other REST routes to a blocked operation (deleting through
  `gh api -X delete`, or changing branch protection, collaborators or
  visibility through their endpoints). Against these, the control that holds is
  the server-side ruleset, which requires the owner's approval of the last push
  ([above](#the-server-side-ruleset)).
- **Whether a commit actually covers one task.** A vague summary is refused
  because a lumped commit cannot be given a specific one, but a
  specific-sounding summary on a mixed commit passes.
- **Whether a value the scanner does not recognise is a secret.** It matches a
  list of credential formats, not meaning. A custom or low-entropy credential
  passes, and so does an uppercase assignment that the keyword rule misses.
- **Commits that never reach the hooks.** `core.hooksPath` is per-clone local
  config, so a fresh clone, a CI checkout, or a worktree created outside the
  installer runs no commit-time hook at all until someone re-runs it. Plumbing
  (`git commit-tree`), `cherry-pick`, and server-side commits through the API
  bypass them by construction.
- **The self-approval rule, as described above.**

The honest summary is that the guard is a best-effort tripwire against the
ordinary spelling of a mistake. It is not a control surface, and a rule that
matters must be enforced where the semantics are known -- in a Git hook that
receives the refs or the staged content -- or accepted as instruction-only.

The Codex hook is a non-managed project runtime seed, not managed-core content;
review and trust its pinned hash before relying on it. Handler ordering,
concurrency, and fail-closed behavior under hook error are verified only where
a project records that evidence. Gemini remains pending. These hooks are
guardrails against mistakes, not a security boundary: where a hard boundary is
needed, use the runtime's own approval controls, branch protection, and
least-privilege credentials.
