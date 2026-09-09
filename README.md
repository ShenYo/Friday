# Friday

> **中文摘要**：Friday 提供專案內可版控的共用規則；Jarvis 管理個人設定。
> 安裝前先用 `--check` 唯讀預覽；任何既有內容或路徑衝突都會在寫入前停止。
> 更新需先審查差異與引用依賴，不會自動覆寫專案的修改。

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
~/Friday/install.sh --check /path/to/your/repo
~/Friday/install.sh /path/to/your/repo      # defaults to the current directory
```

Requires `jq` and a target with a `.git/` directory (linked worktrees are not
supported). `--check` reports `NEW`, `IDENTICAL`, or `CONFLICT`, exits nonzero
on conflicts, and does not copy, chmod, create links, or run the self-check.
Both modes validate prerequisites and every destination before any target
write. Unexpected destination symlinks, including ancestor symlinks, conflict;
the exact expected Claude hook link is accepted.

Installation fills missing files and preserves identical content. It refuses
different content rather than overwriting it, including `.claude/settings.json`.
There is deliberately no force mode. Review and reconcile conflicts in the
target project first, then preview again. Project-specific files alongside the
payload remain local; only payload-owned hook scripts receive executable modes.
Preview compares content and path types, not executable modes. Preflight is
not a transaction: a later I/O or self-check failure can leave new files in
place, and concurrent target changes are outside this guarantee. Inspect the
result before retrying; never run concurrent installers against one target.

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

**Copy, not link.** Projects retain their own reviewed baseline and local
overlays. Choose a reviewed Friday commit before installation and record its
SHA in the project's adoption record; a mutable branch is not a reproducible
version. `--check` detects content differences, not who authored them or whether
an update is safe to merge. Keep unknown Skill provenance read-only.

Before promoting changes from a consumer such as pet-care, agree the shared
file list and verify every transitive reference is shipped or explicitly
provided by the consuming project. Do not copy a whole `.agents/` directory:
domain paths, routing, runtime settings, and project overlays need separate
review. In particular, dispatch is not currently shipped; promoting a core
rule that depends on it needs a dependency decision first. Test the reviewed
kit in a disposable project before adoption; this is not permission to refresh
an existing consumer or change personal Jarvis settings.

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

That paragraph records the original failure, not current pet-care behavior.

## Installer regression check

Run `bash tests/install-smoke.sh /absolute/path/to/retained-test-output`.
The check creates fresh fixture targets, uses an inert fixture self-check, and
retains its evidence for review; it never installs into an existing project.
It verifies installer behavior, not live runtime hook coverage. Cleanup is a
separate, explicitly authorized operation.
