# Adopting Friday

> **中文摘要**：`install.sh` 預設安裝最新的 release，不是這個 checkout 目前的內容；
> 新專案用 `install.sh`，既有專案用 `--managed-only` 只拿 managed core、seeds 留給專案自己
> 調和；clone 之後執行 `setup.sh`；之後由維護者用 `friday-propagate` 開 pull request。

Two paths. A blank repository is a handful of commands. An existing project
needs one judgement call, made once, and this page exists because that call was
not written down.

## Prerequisites

Prerequisites are Git, Bash and `jq`. `.agents/bin/setup.sh` and the `CLAUDE.md`
seed ship from `v1.1.0`; a release before that (`v1.0.0`, `v1.0.1`) has neither,
its installer wires the clone itself, and a project installed from one has no
`setup.sh` to run after a clone (there, `git config core.hooksPath
.agents/githooks` is the part a fresh clone lacks). The installer is a script in
a local Friday checkout; if there is none yet, one line gets it:

```sh
git clone https://github.com/ShenYo/Friday.git ~/.Friday
```

That checkout is a development checkout, often on a feature branch or with
uncommitted edits, so `install.sh` never installs what it holds. It installs a
release: the newest annotated tag `vX.Y.Z`, chosen and checked the way
`friday-propagate` does (on `origin` as the same tag object, reachable from
`main`). It exports that release's tree and runs the release's own `install.sh`
on it, so the lock records the release's commit and tag whatever the checkout
looks like. `--working-tree` installs the checkout as it
is, with a warning, for developing Friday itself.

## A blank repository

```sh
FRIDAY=~/.Friday
TARGET=<your new repo>

git -C "$TARGET" init

bash "$FRIDAY/install.sh" --check "$TARGET"   # preview; writes nothing
bash "$FRIDAY/install.sh" "$TARGET"           # the newest release
bash "$FRIDAY/install.sh" --check "$TARGET"   # every file line should read IDENTICAL
```

To pin a release instead of taking the newest, add `--release vX.Y.Z` to the
install. When no release qualifies (none exists, or the newest is not annotated,
not on `origin`, or not on `main`) the install refuses and says how to fetch or
cut one; it writes nothing.

The install ends by running the payload's own self-check, so broken runtime wiring
fails now rather than the first time someone relies on the boundary.

Then verify, rather than assuming. `FRIDAY_TREE` makes `friday-lock` read the
release itself, so this checks the project's bytes against that release; a plain
`friday-lock check` reads the Friday checkout's working tree, which on a
development checkout is ahead of the release and would say `behind` about a
correct install:

```sh
# vX.Y.Z is the tag on the install's first line, "release: vX.Y.Z (commit ...)"
FRIDAY_TREE=vX.Y.Z bash "$FRIDAY/bin/friday-lock" check "$TARGET"   # expect: status: in sync
(cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)
git -C "$TARGET" status --short
```

Review the resulting worktree diff, then decide separately whether and how to commit it
under the project's own rules.

### When an agent runs the install

This is for a blank repository. An existing project has expected seeds and
follows `--managed-only` in the next section instead. The preview and the
install are two separate decisions, and an agent takes only the first on its
own.

1. **Check the inputs.** `TARGET` is a repository root with a `.git`
   directory. `FRIDAY` is a different directory, holds `install.sh` and
   `payload/`, and is a clean checkout of `main`: `git -C "$FRIDAY"
   symbolic-ref --short HEAD` prints `main` and `git -C "$FRIDAY" status
   --porcelain` prints nothing. The checkout's own `install.sh` starts the run
   (it picks the release and hands over to the release's installer), so it
   should be the reviewed one. Stop and let the person choose if it is not.
   Nothing in `FRIDAY` runs before this holds, because the preview executes its
   `install.sh`. Also write down the release the person named, or that they
   asked for the newest. Done when the paths and the release are written down.
2. **Preview.** Run only `bash "$FRIDAY/install.sh" --check "$TARGET"` (with
   `--release vX.Y.Z` when one was named), by its full path, and report the
   `release:` line and the complete `NEW`/`IDENTICAL` result. Any `CONFLICT` or
   nonzero exit ends the workflow here. Do not edit either repository to make
   the preview pass.
3. **Ask for the install.** The preview does not authorize the write, and
   neither does the request that started the work. Install only after a new
   message from the person that names this `TARGET` and this release.
4. **Install and verify.** First confirm again that `FRIDAY` is clean and on
   `main`, and that the preview named the authorized release; if either moved,
   stop. Then run `bash "$FRIDAY/install.sh" "$TARGET"` with the same flags, the
   second preview, `FRIDAY_TREE=vX.Y.Z bash "$FRIDAY/bin/friday-lock" check "$TARGET"`
   (the tag from the `release:` line),
   `(cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)` and
   `git -C "$TARGET" status --short`. Report each result as observed. Done when
   every one of them succeeded: the install exited 0, the second preview reads
   `IDENTICAL` on every file line, the lock check reads `status: in sync` against
   the authorized release, and the
   self-check passed. If any step fails or the install stops partway, report it
   and stop. Recovering the target is the person's decision, made from its Git
   history.

`install.sh` is the only thing that writes. The agent does not edit Friday,
its payload or the lock to get there. The release is recorded in the target's
lock, and in the target's own adoption commit, in that project's convention.

## An existing project

A project that already has its own `AGENTS.md`, `.agents/AGENTS.md`,
`.gitignore` or runtime wiring takes only the managed core:

```sh
bash "$FRIDAY/install.sh" --managed-only --check "$TARGET"   # preview; writes nothing
bash "$FRIDAY/install.sh" --managed-only "$TARGET"
```

`--managed-only` copies the managed core of the release, runs `.agents/bin/setup.sh`
and writes the lock. The seeds stay yours, whatever they hold, and the preview
lists each one so you see what is left to reconcile by hand:

```
NEW .agents/docs/agent-rules.md
...
SEED AGENTS.md (yours; not touched)
SEED CLAUDE.md (missing; setup.sh creates it from Friday's seed)
SEED .agents/AGENTS.md (yours; not touched)
SEED .agents/protected-paths.conf (missing; not created)
SEED .gitignore (yours; not touched)
SEED .claude/settings.json (yours; not touched)
SEED .codex/hooks.json (identical to Friday's; not touched)
```

A `SEED` line can also read `(missing; not created)`, `(missing; setup.sh creates it from
Friday's seed)` for the two root pointers when the release ships `setup.sh`, or
`(identical to Friday's; not touched)`.

It works with the default release, with `--release vX.Y.Z`, and with
`--working-tree`. Without `--managed-only` the same project would be refused,
with a `CONFLICT` on every seed that differs: that is the right reading for a
blank repository and the wrong tool for an existing one.
The self-check still runs last, and fails until the seeds that carry the guard wiring
(`.claude/settings.json`, `.codex/hooks.json`) are the project's own and wired.

### Reading the preview

`--check` writes nothing. What it does write when you run it for real keeps the
refuse-before-writing preflight: any `CONFLICT` refuses the whole install and
nothing is written. Look only at the path on each `SEED` or `CONFLICT` line.

| Line | What it is | What to do |
| --- | --- | --- |
| `SEED AGENTS.md` | your root pointer | **expected** — keep yours; it only has to point at `.agents/AGENTS.md` |
| `SEED CLAUDE.md` | your root pointer for Claude Code | **expected** — keep yours; it only has to import `.agents/AGENTS.md`. If it is missing, `setup.sh` (v1.1.0 on) creates it from the seed |
| `SEED .agents/AGENTS.md` | your routing table | **expected** — keep yours; add Friday's routing rows to it |
| `SEED .agents/protected-paths.conf` | your protected-paths list | **expected** — keep yours; if it is missing, nothing is protected until you add one (an empty copy of the seed is enough to start) |
| `SEED .gitignore` | yours | **expected** — append Friday's entries |
| `SEED .claude/settings.json` | your runtime wiring | **expected** — add Friday's handler to your `hooks` array, do not replace the file; if it is missing the install's self-check fails until you do |
| `SEED .codex/hooks.json` | your Codex wiring | **expected** — same |
| `CONFLICT core.hooksPath` | another hook manager, such as husky, is already wired | **decide first** — wiring Friday's hooks replaces it, so fold its checks into a reviewed change, then unset it |
| `CONFLICT .git/hooks` | hooks that `core.hooksPath` would stop running | **decide first** — move what they do into the reviewed hooks, or drop them deliberately |
| `CONFLICT .claude/skills/<name>` | a Skill link `setup.sh` would make is blocked, or two Skills share a name | **decide first** — rename or remove the one in the way |
| **`CONFLICT` on anything else** | **the managed core** | **a real conflict** — see below |

Those seven are the only files Friday seeds and then leaves to you. Everything
else it ships is the managed core, which must end up byte-identical. A managed
file that is already identical is not a conflict; it reads `IDENTICAL`.

### A real conflict

A CONFLICT on one of the seventeen managed-core files means your copy and
Friday's have diverged. Reconcile it file by file, in a reviewed commit, against
the release you are taking:

```sh
git -C "$FRIDAY" show "vX.Y.Z:payload/<path>" | diff - "$TARGET/<path>"
```

Take Friday's version unless you can say precisely why yours differs. If you
keep a difference, it is no longer managed core and this whole mechanism
stops being able to tell you anything about it. Then run the install again.

### What the install does for you

From `v1.1.0`, `.agents/bin/setup.sh` is part of the managed core and the install
runs it in the target (an earlier release has none, and its installer wires the
clone itself): it sets `core.hooksPath`, links the runtime guard and the Claude Code
Skills, and creates `AGENTS.md` and `CLAUDE.md` only if they are missing. It
never overwrites what it did not create, so your own pointers stay as they are.
The one thing it replaces is a dangling `.claude/skills/<name>` link that points
into `../../.agents/skills/` (the only form it writes); any other dangling link is
reported as a CONFLICT and left. To preview it on its own:

```sh
cd "$TARGET"
bash .agents/bin/setup.sh --check   # exits 1 when it would change something
```

Never copy a whole `.agents/` directory: that would overwrite the routing table
you just merged.

### Why not just let the installer merge

Because a three-way merge on a file that carries a safety boundary can produce
something neither side reviewed. Refusing and handing the decision back is the
slower, duller, correct behaviour — see `payload/.agents/docs/git-guideline/safety-boundary.md`.

## What the install checks and refuses

`--check` reports `NEW`, `IDENTICAL` or `CONFLICT` (and, with `--managed-only`,
`SEED`), exits nonzero on conflicts, and does not copy, chmod, create links, or
run the self-check. Both modes validate prerequisites, every destination, and
the target's existing hook setup (an effective `core.hooksPath`, from any config
scope, that is not `.agents/githooks`, or hooks or hook symlinks in `.git/hooks`
that wiring would bypass) before any target write. The target is the repository
root, not an `.agents/` subdirectory, and has a `.git/` directory (a linked
worktree is refused, because `core.hooksPath` is shared by every worktree of a
repository and wiring it from one would leave the others running no hooks).
They also check the `.claude/skills/<name>` links `setup.sh` will make, for the
Skills as they will be once the copy is done (the target's own `.agents/skills`
plus the payload's): a name two Skills share, a real file or directory in the
way, a link elsewhere, and a dangling link that the copy would make live or that
`setup.sh` did not write are all conflicts, so the install is refused rather
than stopped halfway. Unexpected destination symlinks, including ancestor
symlinks, conflict; the only links accepted are the three exact hook links (the
Claude collaborative-Git and protected-paths links, and the Codex one), a `.claude/skills/<name>` link that is already correct, and a
dangling one into `.agents/skills/` that `setup.sh` will replace.

Installation fills missing files and preserves identical content. It refuses
different content rather than overwriting it, including `.claude/settings.json`.
There is deliberately no force mode. Review and reconcile conflicts in the
target project first, then preview again. Project-specific files alongside the
payload remain local; only payload-owned hook scripts receive executable modes.
Preview compares content and path types, not executable modes. Preflight is
not a transaction: a later I/O or self-check failure can leave new files in
place, and concurrent target changes are outside this guarantee. Inspect the
result before retrying; never run concurrent installers against one target.
Friday copies its closed payload into the target; it does not copy the whole
Friday repository or link the target back to Friday.

## After adopting

```sh
FRIDAY_TREE=vX.Y.Z bash "$FRIDAY/bin/friday-lock" check "$TARGET"   # in sync, against that release
bash "$TARGET/.agents/hooks/check-collaborative-git.sh"
```

`bash "$FRIDAY/bin/friday-lock" check "$TARGET"` compares the consumer with the
Friday checkout it runs from, so it reads `in sync` only while that checkout's
payload is the release the consumer took. Once Friday has moved on it reads
`behind`, and [Staying current](#staying-current) says what brings the consumer up to the
next release.

## Staying current

A new Friday release reaches a consumer as a pull request, and each machine then
catches up its own clones. Find the situation that matches, and follow its
steps. `$FRIDAY` is your Friday checkout (`~/.Friday` above), and `$CONSUMER` is a
consumer repository's clone.

| Situation | Who, where | Go to |
| --- | --- | --- |
| Friday cut a new release | the maintainer, on one machine | [1](#1-friday-cut-a-new-release) |
| A propagate pull request merged in a consumer | every machine that has that consumer's clone | [2](#2-a-propagate-pull-request-merged) |
| You are about to run `install.sh` or `friday-propagate` | the machine you run it on | [3](#3-before-running-friday-on-a-machine) |
| You are not sure where a consumer stands | any machine | [4](#4-where-does-a-consumer-stand) |

### 1. Friday cut a new release

1. Bring the checkout up to date. Do step 3 first.
2. Preview what would change in each consumer, then open the pull requests:

   ```sh
   bash "$FRIDAY/bin/friday-propagate" --dry-run ~/path/to/consumer ...
   bash "$FRIDAY/bin/friday-propagate"           ~/path/to/consumer ...
   ```

   It opens one pull request in each consumer that is behind, carrying the
   managed-core files that moved. A consumer that is already current is left
   alone.
3. Review and merge each pull request. A person does this. Then do step 2 on
   every machine.

Check: `bash "$FRIDAY/bin/friday-lock" check "$CONSUMER"` reports `in sync` after
the merge. More detail is in
[Carrying a change out to consumers](./docs/updating-consumers.md#carrying-a-change-out-to-consumers).

### 2. A propagate pull request merged

On every machine that has a clone of that consumer:

1. Pull it:

   ```sh
   git -C "$CONSUMER" switch main && git -C "$CONSUMER" pull --ff-only
   ```

2. Re-run the wiring, because a release can change the hooks or the Skill links:

   ```sh
   (cd "$CONSUMER" && bash .agents/bin/setup.sh)
   ```

   Check: `(cd "$CONSUMER" && bash .agents/bin/setup.sh --check)` reports nothing
   left to change.
3. If the pull request changed `.codex/hooks.json`, Codex skips the project's
   hooks until you trust them again: open the project in Codex, run `/hooks`, and
   trust them. A change to the hook scripts alone needs no new trust.
4. Start a new agent session in the project, so it loads the new files.

### 3. Before running Friday on a machine

`install.sh` and `friday-propagate` always use a release, not what this
checkout holds, but they find releases through it. Fetch first:

```sh
git -C "$FRIDAY" fetch --tags origin && git -C "$FRIDAY" switch main && git -C "$FRIDAY" pull --ff-only
```

Check: `git -C "$FRIDAY" describe --tags --abbrev=0` names the newest release
on [Releases](https://github.com/ShenYo/Friday/releases).

### 4. Where does a consumer stand?

```sh
bash "$FRIDAY/bin/friday-lock" check "$CONSUMER"
```

`in sync` means current. Every other state, such as `behind` or `tag-moved`, and
what to do about it, is in
[Knowing where a consumer stands](./docs/updating-consumers.md#knowing-where-a-consumer-stands).

## After every clone

`core.hooksPath` is per-clone config that is never cloned. A fresh clone, a CI
checkout or a worktree made outside the installer runs **no commit-time hook**
until someone sets it again. After cloning, and after the project's Skills
change, run:

```sh
bash .agents/bin/setup.sh   # --check to preview; refuses a linked worktree
```

This cannot be fixed by a hook. The checker reports it as a note rather than a
failure, because a CI checkout never has it and never will.

### What setup.sh does

Run it from anywhere inside the consumer, after cloning it and again after adding, removing
or renaming a Skill. `--check` previews and writes nothing.

It does four things:

- sets `core.hooksPath` to `.agents/githooks` (an effective value from any
  config scope that is something else is a `CONFLICT`, not overridden), and
  reports Git hooks that are missing or not executable, and hooks or hook
  symlinks in `.git/hooks` that it would bypass;
- links `.claude/hooks/guard-collaborative-git.sh` and
  `.codex/hooks/guard-collaborative-git.sh` to the shared guard, and
  `.claude/hooks/guard-protected-paths.sh` to the protected-paths guard (Claude only);
- creates the root `AGENTS.md` and `CLAUDE.md` from the seeds when they are
  missing, and leaves them alone whatever they say when they are present;
- links every Skill under `.agents/skills` (a directory holding `SKILL.md`, at
  depth 1 or 2) as `.claude/skills/<name>`, taking `<name>` from the Skill's
  `name:` frontmatter, else its directory name, so Claude Code sees them.
  Entries in `.claude/skills` that are dangling or match no Skill are
  reported as `STALE` for a person to remove (names starting with `.` are skipped).
  A Skill directory that is a symlink is not followed: one resolving outside
  `.agents/skills` is reported as `SKIPPED`, and an alias inside it, such as
  `git-commit -> git/commit`, is ignored silently.

It never overwrites, moves or deletes something it did not create. The one
exception is a dangling `.claude/skills/<name>` link that points into
`../../.agents/skills/`, the only form it writes, which it replaces; any other
dangling link is a `CONFLICT`. Anything in the way is reported as `CONFLICT <path> (<reason>)` and left alone while the
rest still runs, and the exit status is then 1; so is `--check`'s when
something would change. A second run changes nothing and says
`nothing to change`. The install runs this same script in the target. It
refuses a linked worktree, for the reason `install.sh` does.

## Starting an agent in a bootstrapped project

> **中文摘要**：安裝會 seed root [`AGENTS.md`](./payload/AGENTS.md)、
> [`CLAUDE.md`](./payload/CLAUDE.md) 與 [`.agents/AGENTS.md`](./payload/.agents/AGENTS.md)；
> 不會生成 `GEMINI.md` 或 `setup-ai.sh`。clone 一個 consumer 之後、以及新增／移除／
> 改名 Skill 之後，執行 `bash .agents/bin/setup.sh`。先讀兩個 AGENTS，再選擇已安裝的
> 單一 runtime 啟動；各 runtime 的 trust 與原生行為仍須各自驗證。

From the target repository root, read the two installed instruction entrypoints
before asking an agent to change anything:

```sh
cd '/absolute/path/to/new-project'
sed -n '1,240p' AGENTS.md
sed -n '1,240p' .agents/AGENTS.md
```

If Claude Code is already installed, launch it from that root with `claude`.
If Codex is already installed, launch it separately from that root with
`codex`; choose the runtime you intend to use rather than treating both as an
automatic sequence. In the first prompt, ask it to read the root instructions
and report the instruction documents it loaded plus its branch, HEAD, and
working-tree status before editing.

Friday seeds a root `CLAUDE.md` that imports `.agents/AGENTS.md`, and does not
generate `GEMINI.md` or `setup-ai.sh`. Whether a Claude session actually loaded
the import is runtime behavior this guide cannot guarantee, so keep asking the
agent to report the instruction documents it loaded. Native workspace trust,
callback delivery, precedence, and other runtime behavior remain
runtime-specific evidence work. Gemini CLI and
`agy` remain pending here, so this guide intentionally provides no speculative
launch command for either.

## What adoption does not give you

Read `payload/.agents/docs/git-guideline/safety-boundary.md` before relying on
any of this. It lists what nothing enforces — `gh` and REST API routes, git
plumbing, per-clone `core.hooksPath`, and more. These are guardrails against
mistakes, not a security boundary.
