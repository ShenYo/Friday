# Adopting Friday

Two paths. A blank repository is a handful of commands. An existing project
needs one judgement call, made once, and this page exists because that call was
not written down.

`install.sh` installs a release: the newest annotated tag `vX.Y.Z`, or the one
you name with `--release`. It never installs what the Friday checkout happens to
hold, so a checkout on a feature branch, or with uncommitted edits, cannot hand
a project an unreleased payload. `--working-tree` installs the checkout as it is,
with a warning; that is for developing Friday, not for a project.

## A blank repository

```sh
FRIDAY=~/.Friday
TARGET=<your new repo>

git clone https://github.com/ShenYo/Friday.git "$FRIDAY"   # once, if you have no checkout
git -C "$TARGET" init

bash "$FRIDAY/install.sh" --check "$TARGET"   # preview; writes nothing
bash "$FRIDAY/install.sh" "$TARGET"           # the newest release
bash "$FRIDAY/install.sh" --check "$TARGET"   # every file line should read IDENTICAL
```

To pin a release instead of taking the newest, add `--release vX.Y.Z` to the
install. When no release qualifies (none exists, or the newest is not annotated,
not on `origin`, or not on `main`) the install refuses and says how to fetch or
cut one; it writes nothing.

`.agents/bin/setup.sh` and the `CLAUDE.md` seed ship from `v1.1.0`. A release
before that (`v1.0.0`, `v1.0.1`) has neither: its installer wires the clone
itself, and a project installed from one has no `setup.sh` to run after a clone
(there, `git config core.hooksPath .agents/githooks` is what a fresh clone lacks).

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
SEED .gitignore (yours; not touched)
SEED .claude/settings.json (yours; not touched)
SEED .codex/hooks.json (identical to Friday's; not touched)
```

It works with the default release, with `--release vX.Y.Z`, and with
`--working-tree`. Without `--managed-only` the same project would be refused,
with a `CONFLICT` on every seed that differs: that is the right reading for a
blank repository and the wrong tool for an existing one.

### Reading the preview

`--check` writes nothing. What it does write when you run it for real keeps the
refuse-before-writing preflight: any `CONFLICT` refuses the whole install and
nothing is written. Look only at the path on each `SEED` or `CONFLICT` line.

| Line | What it is | What to do |
| --- | --- | --- |
| `SEED AGENTS.md` | your root pointer | **expected** — keep yours; it only has to point at `.agents/AGENTS.md` |
| `SEED CLAUDE.md` | your root pointer for Claude Code | **expected** — keep yours; it only has to import `.agents/AGENTS.md`. If it is missing, `setup.sh` (v1.1.0 on) creates it from the seed |
| `SEED .agents/AGENTS.md` | your routing table | **expected** — keep yours; add Friday's routing rows to it |
| `SEED .gitignore` | yours | **expected** — append Friday's entries |
| `SEED .claude/settings.json` | your runtime wiring | **expected** — add Friday's handler to your `hooks` array, do not replace the file; if it is missing the install's self-check fails until you do |
| `SEED .codex/hooks.json` | your Codex wiring | **expected** — same |
| `CONFLICT core.hooksPath` | another hook manager, such as husky, is already wired | **decide first** — wiring Friday's hooks replaces it, so fold its checks into a reviewed change, then unset it |
| `CONFLICT .git/hooks` | hooks that `core.hooksPath` would stop running | **decide first** — move what they do into the reviewed hooks, or drop them deliberately |
| `CONFLICT .claude/skills/<name>` | a Skill link `setup.sh` would make is blocked, or two Skills share a name | **decide first** — rename or remove the one in the way |
| **`CONFLICT` on anything else** | **the managed core** | **a real conflict** — see below |

Those six are the only files Friday seeds and then leaves to you. Everything
else it ships is the managed core, which must end up byte-identical. A managed
file that is already identical is not a conflict; it reads `IDENTICAL`.

### A real conflict

A CONFLICT on one of the fifteen managed-core files means your copy and
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

## After adopting

```sh
FRIDAY_TREE=vX.Y.Z bash "$FRIDAY/bin/friday-lock" check "$TARGET"   # in sync, against that release
bash "$TARGET/.agents/hooks/check-collaborative-git.sh"
```

`bash "$FRIDAY/bin/friday-lock" check "$TARGET"` compares the consumer with the
Friday checkout it runs from, so it reads `in sync` only while that checkout's
payload is the release the consumer took. Once Friday has moved on it reads
`behind`; the maintainer's `bin/friday-propagate` then opens the pull request
that brings the consumer up to the next release.

`core.hooksPath` is per-clone config that is never cloned. A fresh clone, a CI
checkout or a worktree made outside the installer runs **no commit-time hook**
until someone sets it again. After cloning, and after the project's Skills
change, run:

```sh
bash .agents/bin/setup.sh   # --check to preview; refuses a linked worktree
```

This cannot be fixed by a hook. The checker reports it as a note rather than a
failure, because a CI checkout never has it and never will.

## What adoption does not give you

Read `payload/.agents/docs/git-guideline/safety-boundary.md` before relying on
any of this. It lists what nothing enforces — `gh` and REST API routes, git
plumbing, per-clone `core.hooksPath`, and more. These are guardrails against
mistakes, not a security boundary.
