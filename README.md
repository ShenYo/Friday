# Friday

A kit that installs project-scoped agent management into a repository: the
safety boundary that stops an agent doing irreversible damage, the rules it
works under, and the Git skills that gate authorisation.

Personal, machine-level agent configuration is a different thing and lives in
[`ShenYo/Jarvis`](https://github.com/ShenYo/Jarvis). Project configuration
cannot use that repo's symlink approach: a clone has to carry its own rules, CI
checks out only the project, and collaborators cannot be asked to depend on one
person's home directory. So this kit **copies** its payload in.

## Install

```sh
git clone git@github.com:ShenYo/Friday.git ~/Friday
~/Friday/install.sh /path/to/your/repo      # defaults to the current directory
```

Idempotent — re-run it to repair a partial install or to pick up a newer
payload. It refuses to run outside a Git repository, since the boundary guards
Git operations. It needs `jq`.

The install ends by running the payload's own self-check, so a broken install
fails now rather than the first time someone relies on the boundary.

## What v1 installs

```
.agents/hooks/guard-collaborative-git.sh    the boundary itself
.agents/hooks/check-collaborative-git.sh    its self-check
.agents/docs/agent-rules.md                 how agents must work here
.agents/docs/git-guideline/                 commit, PR evidence, issue tracker,
                                            and the safety-boundary policy
.agents/skills/git/                         commit, create-pr, push,
                                            github-pr-verify
.claude/settings.json                       PreToolUse wiring
.claude/hooks/guard-collaborative-git.sh    symlink to the payload guard
```

### The boundary

`guard-collaborative-git.sh` runs before every Bash tool call and refuses:

- `git push --force` / `--force-with-lease`, `reset --hard`, `clean`,
  `branch -D`, `stash clear|drop`, `worktree remove`,
  `remote remove|set-url`
- `find … -delete`, `gh repo delete`, `gh api -X DELETE`
- any recursive `rm` (`-r`, `-R`, `--recursive`), parsed so that a path after
  `--` cannot smuggle one past
- Codex `apply_patch` file deletions

An agent that hits one is told to ask the user to run the command themselves.
This is not advisory: the tool call never executes.

The four Git skills are the other half. `safety-boundary.md` treats invoking
`$git-commit`, `$git-push` or `$git-create-pr` as the authorisation for that
one action in that one turn — so committing and pushing stay deliberate acts
rather than something an agent drifts into.

### Why the self-check matters

`check-collaborative-git.sh` verifies the wiring *and* feeds the guard a real
force-push payload, failing if it is not blocked. Verified against a scratch
repository: removing `settings.json`, removing the hook symlink, and replacing
the guard with a stub that exits 0 are each detected.

That last one is the case worth having. A guard that has been neutered looks
exactly like a guard that is working, right up until it matters.

## What v1 does not install

The per-project layer — `.agents/AGENTS.md` (the routing table agents actually
read), the domain glossary, the issue-tracker choice, the avoid-terms list.
Those need answers only the project owner has. **Until an `AGENTS.md` exists
and is pointed at from the repo root, agents will not read any of the docs this
kit installed** — though the hook still blocks, because it is wired
independently of whether anything is read.

Also absent by choice: dispatch policy, prompt templates, judgment rubrics,
scratch-file conventions, and MCP tooling. They exist and work in `pet_care`,
but each still names that project's own files, and shipping them before they
are decoupled would install the coupling into every new project.

## Design notes

**Copy, not link.** See the top of this file. The cost is drift: a project can
edit its copy, and there is currently no mechanism to tell it apart from the
payload. v1 accepts that. Deciding how updates should reach an installed
project depends on knowing which files projects actually change, and that is
guesswork until a second project exists.

**The payload owns no project references.** Worked examples use `#123` rather
than real issue numbers, and no file names another repository's documents. This
was checked before the first commit — the version in `pet_care` did carry issue
numbers and paths, which is exactly the coupling that makes a library
unportable.

**No dependency on `rg`.** The self-check originally used ripgrep for its
stale-reference scan. On the machine this kit was built on, `rg` exists only as
an interactive shell function, so a script calling it failed with "command not
found" — and because that check treats "found nothing" as success, it had been
passing vacuously. It now uses `grep`, and first proves the search can find a
string that is definitely present before trusting any negative result.

`pet_care` still has the original, and still has that bug.
