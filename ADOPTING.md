# Adopting Friday

Two paths. A blank repository is seven commands. An existing project needs one
judgement call, made once, and this page exists because that call was not
written down.

## A blank repository

```sh
FRIDAY=~/.Friday
PIN=<a reviewed Friday commit>
TARGET=<your new repo>

git clone https://github.com/ShenYo/Friday.git "$FRIDAY"
git -C "$FRIDAY" checkout --detach "$PIN"

git -C "$TARGET" init
bash "$FRIDAY/install.sh" --check "$TARGET"   # preview; writes nothing
bash "$FRIDAY/install.sh" "$TARGET"
bash "$FRIDAY/install.sh" --check "$TARGET"   # every line should read IDENTICAL
```

Then verify, rather than assuming:

```sh
bash "$FRIDAY/bin/friday-lock" check "$TARGET"   # expect: status: in sync
git -C "$TARGET" status --short
```

### When an agent runs the install

This is for a blank repository. An existing project has expected conflicts and
follows the manual path in the next section instead. The preview and the
install are two separate decisions, and an agent takes only the first on its
own.

1. **Check the inputs.** `TARGET` is a repository root with a `.git`
   directory. `FRIDAY` is a different directory, holds `install.sh` and
   `payload/`, and is a clean checkout of the reviewed commit the person named
   as `PIN`: `git -C "$FRIDAY" rev-parse HEAD` equals it in full. A dirty
   checkout, or one at any other commit, is not that pin. Stop and let the
   person choose. Nothing in `FRIDAY` runs before this holds, because the
   preview executes its `install.sh`. Done when both paths and the SHA are
   written down and match.
2. **Preview.** Run only `bash "$FRIDAY/install.sh" --check "$TARGET"`, by its
   full path, and report the SHA and the complete `NEW`/`IDENTICAL` result.
   Any `CONFLICT` or nonzero exit ends the workflow here. Do not edit either
   repository to make the preview pass.
3. **Ask for the install.** The preview does not authorize the write, and
   neither does the request that started the work. Install only after a new
   message from the person that names this `TARGET` and this SHA.
4. **Install and verify.** First confirm again that `FRIDAY` is clean and at
   the authorized SHA; if it moved, stop. Then run
   `bash "$FRIDAY/install.sh" "$TARGET"`, the second preview, the lock check,
   `(cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)` and
   `git -C "$TARGET" status --short`. Report each result as observed. Done
   when every one of them succeeded: the install exited 0, the second preview
   reads `IDENTICAL` on every line, the lock check reports `in sync`, and the
   self-check passed. If any step fails or the install stops partway, report
   it and stop. Recovering the target is the person's decision, made from its
   Git history.

`install.sh` is the only thing that writes. The agent does not edit Friday,
its payload or the lock to get there. The pinned SHA is recorded in the
target's own adoption commit, in that project's convention.

## An existing project: reading CONFLICT

`--check` writes nothing and refuses the whole install if anything conflicts.
That refusal is the design — the installer will not merge, so nothing is lost
while you decide. What it does *not* do is tell you which conflicts matter.

A realistic project that already has its own `AGENTS.md`, `.agents/AGENTS.md`
and `.gitignore` produces this:

```
CONFLICT AGENTS.md (existing content)
CONFLICT .agents/AGENTS.md (existing content)
NEW .agents/docs/agent-rules.md
...
CONFLICT .gitignore (existing content)
NEW .claude/settings.json
error: resolve conflicts in a reviewed change; nothing was written.
```

**Every conflict there is expected and none is a real one.** Three CONFLICT
lines, and the right action for all three is "keep yours and merge Friday's
contribution in".

### The decision tree

Look only at the path on each CONFLICT line.

| CONFLICT on | What it is | What to do |
| --- | --- | --- |
| `AGENTS.md` | your root pointer | **expected** — keep yours; it only has to point at `.agents/AGENTS.md` |
| `.agents/AGENTS.md` | your routing table | **expected** — keep yours; add Friday's routing rows to it |
| `.gitignore` | yours | **expected** — append Friday's entries |
| `.claude/settings.json` | your runtime wiring | **expected** — add Friday's handler to your `hooks` array, do not replace the file |
| `.codex/hooks.json` | your Codex wiring | **expected** — same |
| `core.hooksPath` | another hook manager, such as husky, is already wired | **decide first** — wiring Friday's hooks replaces it, so fold its checks into a reviewed change, then unset it |
| `.git/hooks` | hooks that `core.hooksPath` would stop running | **decide first** — move what they do into the reviewed hooks, or drop them deliberately |
| **anything else** | **the managed core** | **a real conflict** — see below |

Those five are the only files Friday seeds and then leaves to you. Everything
else it ships is the managed core, which must end up byte-identical.

### A real conflict

A CONFLICT on one of the fourteen managed-core files means your copy and
Friday's have diverged. Reconcile it file by file, in a reviewed commit:

```sh
diff "$FRIDAY/payload/<path>" "$TARGET/<path>"
```

Take Friday's version unless you can say precisely why yours differs. If you
keep a difference, it is no longer managed core and this whole mechanism
stops being able to tell you anything about it.

### The installer does not finish the job here

On an existing project, `install.sh` is **preview-only**. It refuses while any
declared file conflicts, and your `AGENTS.md`, `.agents/AGENTS.md` and
`.gitignore` conflict *by design* and always will — they are yours. So the
installer will never run to completion on a project that already has them, and
that is correct rather than a problem to work around.

Copy the managed core across yourself, in a reviewed commit, and leave your own
files alone:

```sh
while IFS= read -r rel; do
  case "$rel" in ''|'#'*|'!'*) continue ;; esac
  mkdir -p "$TARGET/$(dirname "$rel")"
  cp "$FRIDAY/payload/$rel" "$TARGET/$rel"
done < "$FRIDAY/bin/managed-core.txt"

git -C "$TARGET" config core.hooksPath .agents/githooks
bash "$FRIDAY/bin/friday-lock" write "$TARGET"
```

Never copy a whole `.agents/` directory: that would overwrite the routing table
you just merged.

### Why not just let the installer merge

Because a three-way merge on a file that carries a safety boundary can produce
something neither side reviewed. Refusing and handing the decision back is the
slower, duller, correct behaviour — see `payload/.agents/docs/git-guideline/safety-boundary.md`.

## After adopting

```sh
bash "$FRIDAY/bin/friday-lock" check "$TARGET"       # in sync / drifted / behind
bash "$TARGET/.agents/hooks/check-collaborative-git.sh"
```

`core.hooksPath` is per-clone config that is never cloned. A fresh clone, a CI
checkout or a worktree made outside the installer runs **no commit-time hook**
until someone sets it again:

```sh
git -C "$TARGET" config core.hooksPath .agents/githooks
```

This cannot be fixed by a hook. The checker reports it as a note rather than a
failure, because a CI checkout never has it and never will.

## What adoption does not give you

Read `payload/.agents/docs/git-guideline/safety-boundary.md` before relying on
any of this. It lists what nothing enforces — `gh` and REST API routes, git
plumbing, per-clone `core.hooksPath`, and more. These are guardrails against
mistakes, not a security boundary.
