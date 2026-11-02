# Architecture

> **中文摘要**：Friday 的架構：payload 收納哪些檔案、各個工具何時執行、
> managed core／seeds／overlays 的所有權劃分，以及設計取捨。
> 本文件只有英文版，內容原樣搬自原本的 README。

Friday is a repository: the baseline. It holds the **payload** (`payload/`), the
files a project receives; the tools that move it; and the tests that prove the
tools. A project that took the payload is a **consumer**. The payload is copied
into the consumer, never linked to Friday's checkout, so a consumer has no
dependency on Friday's filesystem.

## What the payload holds

[`bin/managed-core.txt`](../bin/managed-core.txt) classifies every payload file,
and a file it does not name fails the tools. There are three kinds of file:

| Kind | Which files | Rule |
| --- | --- | --- |
| **Managed core** | fifteen files: the policy documents under `.agents/docs`, `.agents/bin/setup.sh`, the guard and its checker, the three Git hooks, the three Git Skills | Compared byte for byte. A consumer keeps them identical to a release; each change reaches it in a release. |
| **Seeds** | `AGENTS.md`, `CLAUDE.md`, `.agents/AGENTS.md`, `.gitignore`, `.claude/settings.json`, `.codex/hooks.json` (the `!` entries of the list) | Copied once into a new project. From then on they are the project's: never compared, never carried. |
| **The consumer's own overlays** | whatever else a project adds: its Skills, its documents, `.agents/hooks/check-project-agent-integration.sh` | Friday never touches them and never lists them. |

The runtime hook links and the `.claude/skills/<name>` links are made in each
clone by `setup.sh`; they are not payload files.

## The tools, and when each runs

| Tool | Runs | What it does |
| --- | --- | --- |
| [`install.sh`](../install.sh) | once per project, from a Friday checkout | Previews, refuses conflicts before writing, then puts a release into the project (or, with `--working-tree`, this checkout; or, with `--managed-only`, only the managed core), runs `setup.sh` (a release that ships one), writes the lock and runs the self-check. |
| [`.agents/bin/setup.sh`](../payload/.agents/bin/setup.sh) | in the consumer, from v1.1.0 on: by the install, then after every clone and every Skill change | Nothing from Friday. The wiring a clone lacks: `core.hooksPath`, the runtime hook links, the root pointers when missing, the Skill links. |
| [`bin/friday-lock`](../bin/friday-lock) | `write` by the install and by `friday-propagate`; `check` any time | Writes and reads the consumer's `.friday-lock.json`, and says whether the consumer is in sync, drifted or behind. |
| [`bin/friday-propagate`](../bin/friday-propagate) | when the maintainer has a release to carry out | Copies a release's managed-core changes into each consumer that is behind, as a pull request. It never merges. |

## Runtime wiring and scope

The two generated runtime hook links point to the consumer's copied shared
guard, so the adapters share one reviewed guard implementation without creating
a dependency on Friday's filesystem.

Friday is deliberately not a universal runtime manager. It checks static Codex
wiring, not native callback behavior, exit handling, handler order, or
fail-closed enforcement; Gemini is pending. Those four were measured on the
Claude side in a consumer ([measurements](./history.md#2026-10-22-runtime-behaviour-measured-on-the-claude-side))
and remain unverified for Codex, which is a different adapter. Friday
does not discover arbitrary skills or install a consumer's domain workflow.

## Ownership: managed core, seeds, and overlays

The managed core is exact: existing consumers compare these fifteen files
byte-for-byte with their reviewed Friday version.

```
.agents/docs/agent-rules.md
.agents/docs/testing.md
.agents/docs/scratch-files.md
.agents/docs/git-guideline/git-commit.md
.agents/docs/git-guideline/pr-evidence.md
.agents/docs/git-guideline/safety-boundary.md
.agents/bin/setup.sh
.agents/hooks/check-collaborative-git.sh
.agents/hooks/guard-collaborative-git.sh
.agents/githooks/pre-commit
.agents/githooks/commit-msg
.agents/githooks/pre-push
.agents/skills/git/commit/SKILL.md
.agents/skills/git/create-pr/SKILL.md
.agents/skills/git/push/SKILL.md
```

The three [`githooks`](../payload/.agents/githooks) files are Git hooks rather
than runtime tool hooks, wired through `core.hooksPath` by
[`setup.sh`](../payload/.agents/bin/setup.sh), which the installer runs and every
clone runs again.
[`pre-commit`](../payload/.agents/githooks/pre-commit) scans staged content for
credentials, [`commit-msg`](../payload/.agents/githooks/commit-msg) enforces the
message contract, and [`pre-push`](../payload/.agents/githooks/pre-push) decides
from the refs Git is about to send, so a deletion, a history rewrite or a push
to the default branch is refused however the command was spelled. The first
push to a remote with no refs at all is allowed: there is no default branch to
protect, nothing to delete and no history to rewrite, and refusing it made
creating a repository impossible without bypassing the hook. They are
byte-exact like the rest of the core, so the reconciliation recipe in
[Updating an existing consumer](./updating-consumers.md#updating-an-existing-consumer)
must carry them ([history](./history.md#2026-10-22-the-git-hooks-were-missing-from-the-managed-core-list)).

The following are blank-repository seeds or runtime integration, not the
managed core. Existing consumers reconcile them manually:

```
AGENTS.md                                    root pointer
CLAUDE.md                                    root pointer for Claude Code
.agents/AGENTS.md                            shared policy router
.gitignore                                   temporary-file ignore rule
.claude/settings.json                        Claude PreToolUse wiring
.claude/hooks/guard-collaborative-git.sh     generated symlink to the guard
.claude/skills/<name>                        generated symlinks to .agents/skills
.codex/hooks.json                            Codex PreToolUse runtime seed
.codex/hooks/guard-collaborative-git.sh      generated symlink to the guard
```

The blank-repository Codex seed has exactly one collaborative handler and
shows `Checking collaborative Git safety boundary` while its shared guard
runs. Its hardened launcher establishes a known PATH, checks `git` and
`bash`, resolves the Git root without leaking Git diagnostics, verifies the
project-local guard is readable, then executes it. It does not include a
consumer protected-path handler. The core checker permits consumer handlers
alongside that single shared handler, but requires the shared handler exactly
once.

Consumer overlays remain outside both lists. A consumer may add an executable
regular-file `.agents/hooks/check-project-agent-integration.sh`; when present,
the managed core checker runs it and propagates failures. Friday does not ship
that extension.

This is an explicit static allowlist,
[`bin/managed-core.txt`](../bin/managed-core.txt), which
[`install.sh`](../install.sh) reads; it is not automatic payload discovery. A new
payload file fails inventory validation until it is reviewed and added to that
list. There is no manifest or update engine in this MVP.

## Design notes

**Copy, not link.** Projects retain their own reviewed baseline and local
overlays. The install takes a release, so a project's lock names a tag and the
commit behind it, and `--release vX.Y.Z` pins one; a mutable branch, or a
checkout with edits, is not a reproducible version. Git history provides
rollback: revert the adoption commit or restore the selected release in a
reviewed change. `--check` detects content differences, not who authored them
or whether an update is safe to merge.

**Existing consumers reconcile manually.** The managed-core files are the
only byte-identical comparison set. Seeds, runtime integration, and consumer
overlays may differ by project and need manual reconciliation; `--managed-only`
leaves them alone and lists the seeds.
[`.gitignore`](../payload/.gitignore) is an ordinary allowlisted seed: a target
with different content conflicts before any write. Friday's blank-repository
MVP intentionally does not parse or merge `.gitignore` marker blocks.

Before promoting changes from a consumer such as pet-care, agree the shared
file list and verify every transitive reference is shipped or explicitly
provided by the consuming project. Do not copy a whole `.agents/` directory:
domain paths, routing, runtime settings, and project overlays need separate
review. In particular, dispatch is not currently shipped; promoting a core
rule that depends on it needs a dependency decision first. Test the reviewed
kit in a disposable project before adoption; this is not permission to refresh
an existing consumer or change personal settings.

**The payload owns no project references.** Worked examples use `#123` rather
than real issue numbers, and no file names another repository's documents,
because that coupling makes a library unportable
([history](./history.md#2026-09-08-the-payload-was-checked-for-project-references-before-the-first-commit)).

**No dependency on `rg`.** The self-check uses `grep`, and first proves the
search can find a string that is definitely present before trusting any negative
result, because a check that treats "found nothing" as success passes vacuously
when its tool is missing
([history](./history.md#2026-09-08-the-self-check-searched-with-a-tool-that-was-not-there)).
