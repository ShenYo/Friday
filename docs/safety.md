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
the shared guard. Review the trusted project hook definition and pinned Friday
hash before relying on Codex; for Codex, callback delivery, exit handling,
handler order, and fail-closed behavior are not verified. Gemini remains
pending. All four were measured on the Claude side
([measurements](./history.md#2026-10-22-runtime-behaviour-measured-on-the-claude-side)).
This setup is a guardrail, not a security boundary.

Two of those results shape the payload. Every handler declares
`onFailure: "block"`, because a failing hook without it fails open silently,
indistinguishable from no guard. And handlers under one matcher run
concurrently, and when several block only one reason reaches the model, so no
handler may assume it runs first or that it alone will be heard. Hook sources
merge rather than override, so a permissive settings file cannot lift a guard:
`claude --settings <empty>.json` is not a bypass.

The three Git skills are the other half.
[`safety-boundary.md`](../payload/.agents/docs/git-guideline/safety-boundary.md) treats invoking
`$git-commit`, `$git-push` or `$git-create-pr` as the authorisation for that
one action in that one turn — so committing and pushing stay deliberate acts
rather than something an agent drifts into.

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
