# Friday

> **中文摘要**：Friday 是可版控的 shared project baseline；Jarvis 是個人層。
> 先以 `--check` 預覽，再安裝封閉的 allowlist。衝突絕不覆寫，現有專案需經
> 人工審查後調和。

Friday bootstraps a blank Git repository with a small, reviewed agent baseline.
It copies project-scoped policy, Git skills, a shared temporary-file contract,
and Claude/Codex guard wiring. Personal or vendor skills remain outside this
repository's contract.

Friday is deliberately not a universal runtime manager. It checks static Codex
wiring, not native callback behavior or fail-closed enforcement; Gemini is
pending. It does not discover arbitrary skills or install a consumer's domain
workflow.

## Install

```sh
git clone git@github.com:ShenYo/Friday.git ~/Friday
~/Friday/install.sh --check /path/to/your/repo
~/Friday/install.sh /path/to/your/repo      # defaults to the current directory
```

Requires `jq` and a blank or compatible target with a `.git/` directory
(linked worktrees are not supported). The target is the repository root, not
an `.agents/` subdirectory. `--check` reports `NEW`, `IDENTICAL`, or
`CONFLICT`, exits nonzero on conflicts, and does not copy, chmod, create links,
or run the self-check. Both modes validate prerequisites and every destination
before any target write. Unexpected destination symlinks, including ancestor
symlinks, conflict; the exact expected Claude hook link is accepted.

Installation fills missing files and preserves identical content. It refuses
different content rather than overwriting it, including `.claude/settings.json`.
There is deliberately no force mode. Review and reconcile conflicts in the
target project first, then preview again. Project-specific files alongside the
payload remain local; only payload-owned hook scripts receive executable modes.
Preview compares content and path types, not executable modes. Preflight is
not a transaction: a later I/O or self-check failure can leave new files in
place, and concurrent target changes are outside this guarantee. Inspect the
result before retrying; never run concurrent installers against one target.

The install ends by running the payload's own self-check, so broken runtime
wiring fails now rather than the first time someone relies on the boundary.

Use the complete sequence for a blank repository:

```sh
~/Friday/install.sh --check /path/to/your/repo
~/Friday/install.sh /path/to/your/repo
~/Friday/install.sh --check /path/to/your/repo
```

## MVP installed scope

Friday has two installed classes. The managed core is exact: existing
consumers compare these ten files byte-for-byte with their reviewed Friday
version.

```
.agents/docs/agent-rules.md
.agents/docs/scratch-files.md
.agents/docs/git-guideline/git-commit.md
.agents/docs/git-guideline/pr-evidence.md
.agents/docs/git-guideline/safety-boundary.md
.agents/hooks/check-collaborative-git.sh
.agents/hooks/guard-collaborative-git.sh
.agents/skills/git/commit/SKILL.md
.agents/skills/git/create-pr/SKILL.md
.agents/skills/git/push/SKILL.md
```

The following are blank-repository seeds or runtime integration, not the
managed core. Existing consumers reconcile them manually:

```
AGENTS.md                                    root pointer
.agents/AGENTS.md                            shared policy router
.gitignore                                   temporary-file ignore rule
.claude/settings.json                        Claude PreToolUse wiring
.claude/hooks/guard-collaborative-git.sh     generated symlink to the guard
.codex/hooks.json                            Codex PreToolUse runtime seed
.codex/hooks/guard-collaborative-git.sh      generated symlink to the guard
```

The Codex seed shows `Checking collaborative Git safety boundary` while its
shared guard runs. The core checker permits consumer handlers alongside that
single shared handler, but requires the shared handler exactly once.

Consumer overlays remain outside both lists. A consumer may add an executable
regular-file `.agents/hooks/check-project-agent-integration.sh`; when present,
the managed core checker runs it and propagates failures. Friday does not ship
that extension.

This is an explicit static allowlist in `install.sh`, not automatic payload
discovery. A new payload file fails inventory validation until it is reviewed
and added to that list. There is no manifest or update engine in this MVP.

## Updating an existing consumer

An existing consumer update is a reviewed reconciliation, not an installer
upgrade. Pin a reviewed Friday commit first; use a placeholder rather than a
mutable branch name:

```sh
PIN=<reviewed-Friday-SHA>
FRIDAY=/path/to/Friday
TARGET=/path/to/consumer

test "$(git -C "$FRIDAY" rev-parse HEAD)" = "$PIN"
bash "$FRIDAY/install.sh" --check "$TARGET"
```

Read every `CONFLICT` and reconcile it in a reviewed consumer change. Sync
only the ten managed-core paths listed above, then prove each has the exact
bytes of `"$FRIDAY/payload/$rel"`. Preserve consumer seeds, runtime
integration, and overlays; do not copy a whole `.agents/` directory.

After reconciliation, verify the consumer rather than treating the installer
as an update engine:

```sh
(cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)
for rel in \
  .agents/docs/agent-rules.md \
  .agents/docs/scratch-files.md \
  .agents/docs/git-guideline/git-commit.md \
  .agents/docs/git-guideline/pr-evidence.md \
  .agents/docs/git-guideline/safety-boundary.md \
  .agents/hooks/check-collaborative-git.sh \
  .agents/hooks/guard-collaborative-git.sh \
  .agents/skills/git/commit/SKILL.md \
  .agents/skills/git/create-pr/SKILL.md \
  .agents/skills/git/push/SKILL.md; do
  cmp "$TARGET/$rel" "$FRIDAY/payload/$rel"
done
git -C "$TARGET" diff --check
```

The checker runs a consumer extension when one exists. Review the resulting
consumer diff and create one atomic consumer commit under that repository's
own rules. Friday has no force mode, manifest, auto-sync, or automatic
reconciliation.

### The boundary

`guard-collaborative-git.sh` runs before every Bash tool call and refuses:

- `git push --force` / `--force-with-lease`, `reset --hard`, `clean`,
  `branch -D`, `stash clear|drop`, `worktree remove`,
  `remote remove|set-url`
- `find … -delete`, `gh repo delete`, `gh api -X DELETE`
- any recursive `rm` (`-r`, `-R`, `--recursive`), parsed so that a path after
  `--` cannot smuggle one past

An agent that hits one is told to ask the user to run the command themselves.
Claude Code Bash and Codex Bash/`apply_patch` receive static project wiring to
the shared guard. Review the trusted project hook definition and pinned Friday
hash before relying on Codex; callback delivery, exit handling, handler order,
and fail-closed behavior are not verified. Gemini remains pending. This setup
is a guardrail, not a security boundary.

The three Git skills are the other half. `safety-boundary.md` treats invoking
`$git-commit`, `$git-push` or `$git-create-pr` as the authorisation for that
one action in that one turn — so committing and pushing stay deliberate acts
rather than something an agent drifts into.

### Why the self-check matters

`check-collaborative-git.sh` verifies the runtime wiring *and* feeds the guard
safe Bash and `apply_patch` payloads, failing if a prohibited payload is not
blocked. The Codex seed uses project-local hooks supported on macOS/Linux;
Windows behavior is unverified.

That last one is the case worth having. A guard that has been neutered looks
exactly like a guard that is working, right up until it matters.

## Deliberate MVP exclusions

Friday installs entrypoints and a shared router, but it does not install a
domain glossary, issue tracker, Wayfinder map, prompt templates, judgment
rubrics, MCP configuration, consumer-specific PR verification, or personal
and vendor Skills. Consumer overlays may extend the shared baseline after
review, provided their references close within that project.

Friday also has no manifest, auto-discovery, automatic update/reconciliation,
or force mode. The existing-consumer workflow above is a deliberate project
change, not an automated refresh.

## Design notes

**Copy, not link.** Projects retain their own reviewed baseline and local
overlays. Pin a reviewed Friday commit before installation and record its SHA
in the project's adoption record; a mutable branch is not a reproducible
version. Git history provides rollback: revert the adoption commit or restore
the selected pinned version in a reviewed change. `--check` detects content
differences, not who authored them or whether an update is safe to merge.

**Existing consumers reconcile manually.** The managed-core files are the
only byte-identical comparison set. Seeds, runtime integration, and consumer
overlays may differ by project and need manual reconciliation. `.gitignore` is
an ordinary allowlisted seed: a target with different content conflicts before
any write. Friday's blank-repository MVP intentionally does not parse or merge
`.gitignore` marker blocks.

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
The check creates disposable Git fixtures, installs the repository's actual
payload, and retains evidence for review. It never installs into an existing
project. Cleanup is a separate, explicitly authorized operation.
