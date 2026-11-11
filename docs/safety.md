# Safety

> **中文摘要**：guard 會拒絕哪些指令與它的限制、self-check 為什麼重要、
> Friday 自身的 branch protection 與 hooks，以及非目標與復原方式。
> 本文件只有英文版。

## Safety model and limits

[`guard-collaborative-git.sh`](../payload/.agents/hooks/guard-collaborative-git.sh)
runs before every Bash tool call and refuses:

- `git push --force` / `--force-with-lease`, `reset --hard`, `clean`,
  `branch -D`, `stash clear|drop`, `worktree remove`,
  `remote remove|set-url`
- `find … -delete`, `gh repo delete`, `gh api -X DELETE`
- any recursive `rm` (`-r`, `-R`, `--recursive`), parsed so that a path after
  `--` cannot smuggle one past

An agent that hits one is told to ask the user to run the command themselves.
Claude Code Bash and Codex Bash/`apply_patch` receive static project wiring to
the shared guard. Codex runtime behavior was measured on codex-cli 0.166.0 in
reviewed, disposable synthetic hook fixtures, not in a full payload installation
([measurements](./history.md#2026-11-05-runtime-behaviour-measured-on-the-codex-side)).
The probes delivered callbacks for Bash and `apply_patch`. Exit 2 and JSON
deny blocked; exit 1, exit 127, a missing handler executable, a SIGKILLed
handler, and a timed-out handler failed open. **A Codex hook timeout allowed
the tool to run in this measurement; it did not fail closed.** Two handlers ran concurrently;
when both denied, only `PRIMARY_BLOCK` reached the model in that sample. A
permissive project handler ran alongside the user-level refusal in the measured
F5 case and did not lift it. These are runtime observations, not a guarantee
for every version or consumer installation. Gemini remains pending, and Windows
behavior is unverified. This setup is a guardrail, not a security boundary.

The Claude Code hook definitions declare `onFailure: "block"`, because a
failing Claude hook without it fails open silently. Claude handlers under one
matcher also run concurrently, and when several block only one reason reaches
the model; none may assume it runs first or that it alone will be heard. On
Claude Code, hook sources merge rather than override, so a permissive settings
file cannot lift a guard: `claude --settings <empty>.json` is not a bypass.

The three Git skills that commit, push and open a pull request are the other half.
[`safety-boundary.md`](../payload/.agents/docs/git-guideline/safety-boundary.md) treats invoking
`$git-commit`, `$git-push` or `$git-create-pr` as the authorisation for that
one action in that one turn — so committing and pushing stay deliberate acts
rather than something an agent drifts into.

### The protected-paths guard

[`guard-protected-paths.sh`](../payload/.agents/hooks/guard-protected-paths.sh)
refuses agent writes to paths a project lists in `.agents/protected-paths.conf`
(one shell glob per line; `append-only ` allows creating a path but never
changing it). The seed ships with no entries, so nothing is protected until the
consumer adds some. It runs for Claude Code only, before Bash and before
`Write`, `Edit`, `MultiEdit` and `NotebookEdit`. Each target is judged by the
project that owns it, the nearest ancestor holding a `.git`, so a session whose
working directory moved into another repository still applies the right list.
Its launcher falls back to the session project (`CLAUDE_PROJECT_DIR`) only when
the working directory is an unrelated repository; a linked worktree of the same
repository on a branch without the guard still fails closed, and so does a
session project that is not a repository or has no guard. The Write-class
tools hand the guard the resolved path, so that check is exact. The Bash scan is
literal text: a target that is not spelled out in the command (a variable, a
language runtime, an encoded command) escapes it, and a protected path quoted in
a heredoc can raise a false alarm. A `cd` or `pushd` in the command is followed
when its destination is literal: a relative target is judged from the working
directory and from each destination. When the command anywhere contains a
destination the scan cannot read (`cd "$X"`, `cd -`, `cd a\ b`), even in a heredoc body,
every relative target is refused. It is a guardrail against carelessness, not a
security boundary.

### Why the self-check matters

[`check-collaborative-git.sh`](../payload/.agents/hooks/check-collaborative-git.sh)
verifies the runtime wiring *and* feeds the guard
safe Bash and `apply_patch` payloads, failing if a prohibited payload is not
blocked. The Codex seed uses project-local hooks supported on macOS/Linux;
Windows behavior is unverified.

That last one is the case worth having. A guard that has been neutered looks
exactly like a guard that is working, right up until it matters.

## Friday's own branch protection and hooks

Friday is public, and a GitHub ruleset on the default branch refuses its
deletion, force pushes, and changes that do not arrive through a pull request.
The review requirement on those pull requests is set server-side by the owner.

Locally, this repository runs the payload's hooks themselves, not copies:

```sh
git config core.hooksPath payload/.agents/githooks
```

That path is the producer's. An installed consumer has the same hooks at
`.agents/githooks`, and `install.sh` wires that one.

**A clone from before this layout still points at `.githooks`**, which no longer
exists. git then finds no hook and runs none, without saying so. Check and fix
it after pulling:

```sh
git config --get core.hooksPath   # expect: payload/.agents/githooks
git config core.hooksPath payload/.agents/githooks
```

So the `pre-commit` secret scan, the `commit-msg` format check, and the
`pre-push` ref checks that consumers get also run on Friday's own commits and
pushes. A hook changed in the payload takes effect on the next commit here,
before it ships. `pre-push` decides from the refs Git is about to send, not
from the command text, so a deletion, a history rewrite, and a push to the
default branch are refused however the command was spelled: `--force`, `-f`,
a leading `+` on the refspec, `--mirror`, `--delete` and `:ref` all reduce to
the same two tests.

Two limits remain. `core.hooksPath` is per-clone configuration that is never
cloned, so a fresh clone runs no hook until someone sets it (in a consumer,
`bash .agents/bin/setup.sh` does). And the hooks are
a guard against mistakes, not a control surface: the server-side ruleset is the
part that holds when they are skipped.

## Non-goals and recovery

Friday installs entrypoints and a shared router, but it does not install a
domain glossary, issue tracker, Wayfinder map, prompt templates, judgment
rubrics, MCP configuration, consumer-specific PR verification, or personal
and vendor Skills. Consumer overlays may extend the shared baseline after
review, provided their references close within that project.

Friday also has no manifest, auto-discovery, automatic update/reconciliation,
or force mode. The existing-consumer workflow in
[Updating an existing consumer](./updating-consumers.md#updating-an-existing-consumer)
is a deliberate project change, not an automated refresh.

If preview finds a conflict, reconcile it rather than overwriting it. If an
install fails after preflight, inspect the partially created target before
retrying. Git history is the recovery mechanism: revert the reviewed consumer
adoption commit, or restore the selected pinned version in a new reviewed
consumer change. `--check` reports content and path-type differences; it does
not decide whether a merge is safe.
