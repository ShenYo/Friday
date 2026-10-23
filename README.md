# Friday

**English** · [繁體中文](./README.zh-TW.md)

> **中文摘要**：Friday 是可版控的 shared project baseline；Jarvis 是個人層。
> 先以 `--check` 預覽，再安裝封閉的 allowlist。衝突絕不覆寫，現有專案需經
> 人工審查後調和。

Friday is a portable, reviewed shared project baseline. It copies
project-scoped policy, Git skills, a shared temporary-file contract, and
Claude/Codex guard wiring into a consumer repository without depending on a
developer's personal home directory, personal skills, or vendor workflow.

It addresses three constraints at once: a closed allowlist makes bootstrap
conflict-safe, copied content keeps the baseline portable and reviewable, and
existing-consumer changes stay behind a reviewed reconciliation boundary rather
than becoming an automatic update. Jarvis is a personal layer only; do not
place Jarvis skills, settings, or other personal-home dependencies in Friday's
project contract.

## When to use Friday

| Scenario | Friday's role | What to do |
| --- | --- | --- |
| Blank Git repository | Bootstrap the reviewed baseline | Preview, install, then preview again. |
| Existing consumer | Reveal differences safely | Pin Friday, run `--check`, and reconcile every conflict in a reviewed consumer change. |
| Personal skills or preferences | Keep personal scope personal | Use Jarvis; do not promote it into Friday. |
| Project-specific policy or checks | Preserve consumer ownership | Add a consumer overlay after reviewing the shared baseline. |

## Architecture

```text
Friday payload
     |
     v
install.sh (closed allowlist + preflight)
     |
     v
copied consumer baseline + runtime seed + consumer overlay
```

Payload content is copied into the consumer, not linked to the Friday checkout.
The two generated runtime hook links point to the consumer's copied shared
guard, so the adapters share one reviewed guard implementation without creating
a dependency on Friday's filesystem.

Friday is deliberately not a universal runtime manager. It checks static Codex
wiring, not native callback behavior, exit handling, handler order, or
fail-closed enforcement; Gemini is pending. Those four were measured on the
Claude side in a consumer (see "Runtime behaviour measured on the Claude side"
below) and remain unverified for Codex, which is a different adapter. Friday
does not discover arbitrary skills or install a consumer's domain workflow.

## Current operating context

> **中文摘要**：Friday 的可攜成果必須由專案本身承載；輔助工具可以選用但
> 不可成為 baseline 前提。十四個 managed-core 檔維持封閉
> byte-exact 範圍，seed、runtime integration 與 overlay 仍由 consumer 擁有。
> 現行 guard 安全修正已在 payload 與 self-check 實作；B06 的 immutable SHA、
> 手動採用及 rollback 責任不變，backup、replay 與外部 runtime 仍待完成。

Portable outcomes belong in project-controlled documentation, tests, or
automation. Optional helpers may assist an operator, but no consumer may
require them to bootstrap or satisfy the Friday contract. The closed
fourteen-file managed core remains the only byte-exact comparison set;
consumer seeds, runtime integration, and overlays remain consumer-owned and
are reconciled manually.

The current payload implements the guard security updates, and its self-check
exercises the relevant allowed and blocked command forms. That is static and
direct-guard evidence only; it does not establish native callback delivery,
exit handling, ordering, or fail-closed enforcement. Those were established
separately on the Claude side, in a consumer, not by this self-check. Releases remain reviewed
immutable SHAs, adoption remains manual, and the Friday maintainer proposes a
rollback while the consumer owner performs it. A named backup maintainer,
real new-machine replay, a further consumer replay, and external-runtime
closure are still pending.

## Lifecycle governance (B06)

> **中文摘要**：Friday 的 MVP 採「可審查 SHA + consumer 手動採用」模式：
> repository owner 負責維護，backup maintainer 尚待指定；不自動同步、不強制
> 更新，也不自動 rollback。

This section is normative for Friday's MVP lifecycle.

- The repository owner is the primary Friday maintainer. A backup maintainer
  is **PENDING**; until one is named, the primary maintainer remains accountable
  for release review, recovery proposals, and recording the decision.
- A reviewed immutable Friday commit SHA is the release channel. Mutable branch
  names are not releases.
- A consumer owner manually adopts a reviewed release and preserves that
  consumer's seeds, runtime integration, and overlays. Friday does not
  auto-sync or automatically update an existing consumer.
- When recovery is needed, the Friday maintainer proposes a reviewed rollback
  or reconciliation. The consumer owner executes the reviewed revert or
  reconciliation in that consumer repository; Friday never force-updates or
  automatically rolls back a consumer.
- Every candidate release requires a disposable-project replay before consumer
  adoption. A real new-machine replay, validation with a third genuine
  consumer, and cross-runtime closure remain **PENDING** follow-up work.

Vendor Skills, including Matt Pocock Skills, remain Jarvis-owned and
vendor-pristine. Friday manages only the portable project-local output contract
in [`scratch-files.md`](./payload/.agents/docs/scratch-files.md); it neither
installs nor copies vendor Skills and does not claim runtime invocation or
precedence enforcement.

## Quick start

> Adopting an **existing** project, where `--check` reports CONFLICT lines?
> [`ADOPTING.md`](./ADOPTING.md) has the decision tree for reading them —
> which are expected overlays and which are real.


> **中文摘要**：blank project 先在乾淨、固定 SHA 的 Friday checkout 上預覽，
> 再 install、再預覽並檢查差異；這是 copy-based baseline，不是複製整個 Friday
> repo 或把 consumer symlink 到它。既有 consumer 請走後面的 manual reconciliation。

For a new blank repository, first obtain a separately reviewed Friday checkout
at an immutable commit. Prerequisites are Git, Bash, and `jq`. Do not use a
dirty Friday checkout as the example source: this creates a new checkout at
the reviewed pin. Before running it, replace both absolute paths and the
literal SHA placeholder. The commands do not create a commit, install a
runtime, or configure credentials.

```sh
(
  set -eu
  TARGET='/absolute/path/to/new-project'
  FRIDAY='/absolute/path/to/new-Friday-checkout'
  PIN='replace-with-reviewed-immutable-Friday-SHA'

  command -v git >/dev/null
  command -v bash >/dev/null
  command -v jq >/dev/null
  test ! -e "$FRIDAY"
  test ! -L "$FRIDAY"
  git clone https://github.com/ShenYo/Friday.git "$FRIDAY"
  git -C "$FRIDAY" checkout --detach "$PIN"
  test "$(git -C "$FRIDAY" rev-parse HEAD)" = "$PIN"
  test -z "$(git -C "$FRIDAY" status --porcelain)"
  test ! -e "$TARGET"
  test ! -L "$TARGET"
  mkdir -p "$TARGET"
  git -C "$TARGET" init
  bash "$FRIDAY/install.sh" --check "$TARGET"
  bash "$FRIDAY/install.sh" "$TARGET"
  bash "$FRIDAY/install.sh" --check "$TARGET"
  (cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)
  git -C "$TARGET" diff --check
  git -C "$TARGET" status --short
)
```

The first preview reports `NEW`, `IDENTICAL`, or `CONFLICT`; resolve every
conflict in a reviewed change before retrying. Review the resulting worktree
diff, then decide separately whether and how to commit it under the target
repository's own rules. Friday copies its closed payload into the target; it
does not copy the whole Friday repository or link the target back to Friday.

Requires `jq` and a blank or compatible target with a `.git/` directory
(linked worktrees are not supported). The target is the repository root, not
an `.agents/` subdirectory. `--check` reports `NEW`, `IDENTICAL`, or
`CONFLICT`, exits nonzero on conflicts, and does not copy, chmod, create links,
or run the self-check. Both modes validate prerequisites and every destination
before any target write. Unexpected destination symlinks, including ancestor
symlinks, conflict; only the two exact expected Claude and Codex hook links
are accepted.

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

## Starting an agent in a bootstrapped project

> **中文摘要**：安裝只 seed root [`AGENTS.md`](./payload/AGENTS.md) 與
> [`.agents/AGENTS.md`](./payload/.agents/AGENTS.md) 的 agent
> instructions；不會生成 root `CLAUDE.md`、`GEMINI.md` 或 `setup-ai.sh`。先讀
> 兩個 AGENTS，再選擇已安裝的單一 runtime 啟動；各 runtime 的 trust 與原生行為
> 仍須各自驗證。

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

Friday does not generate root `CLAUDE.md`, `GEMINI.md`, or `setup-ai.sh`.
Claude users therefore need a verified Claude entrypoint or an explicit
session prompt to read the AGENTS files; this README cannot guarantee automatic
AGENTS loading. Native workspace trust, callback delivery, precedence, and
other runtime behavior remain runtime-specific evidence work. Gemini CLI and
`agy` remain pending here, so this guide intentionally provides no speculative
launch command for either.

## Ownership: managed core, seeds, and overlays

The managed core is exact: existing consumers compare these fourteen files
byte-for-byte with their reviewed Friday version.

```
.agents/docs/agent-rules.md
.agents/docs/testing.md
.agents/docs/scratch-files.md
.agents/docs/git-guideline/git-commit.md
.agents/docs/git-guideline/pr-evidence.md
.agents/docs/git-guideline/safety-boundary.md
.agents/hooks/check-collaborative-git.sh
.agents/hooks/guard-collaborative-git.sh
.agents/githooks/pre-commit
.agents/githooks/commit-msg
.agents/githooks/pre-push
.agents/skills/git/commit/SKILL.md
.agents/skills/git/create-pr/SKILL.md
.agents/skills/git/push/SKILL.md
```

The three [`githooks`](./payload/.agents/githooks) files are Git hooks rather
than runtime tool hooks, wired by the installer through `core.hooksPath`.
[`pre-commit`](./payload/.agents/githooks/pre-commit) scans staged content for
credentials, [`commit-msg`](./payload/.agents/githooks/commit-msg) enforces the
message contract, and [`pre-push`](./payload/.agents/githooks/pre-push) decides
from the refs Git is about to send, so a deletion, a history rewrite or a push
to the default branch is refused however the command was spelled. The first
push to a remote with no refs at all is allowed: there is no default branch to
protect, nothing to delete and no history to rewrite, and refusing it made
creating a repository impossible without bypassing the hook. They are
byte-exact like the rest of the core: an earlier revision of this list omitted
them, which left the reconciliation recipe below silently incomplete.

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

The blank-repository Codex seed has exactly one collaborative handler and
shows `Checking collaborative Git safety boundary` while its shared guard
runs. Its hardened launcher establishes a known PATH, checks `git` and
`bash`, resolves the Git root without leaking Git diagnostics, verifies the
project-local guard is readable, then executes it. It does not include a
consumer protected-path handler. The core checker permits consumer handlers
alongside that single shared handler, but requires the shared handler exactly
once.

The reviewed generic promotion source is `pet_care` commit `3e4f03b`;
its protected-path consumer overlay is intentionally excluded. Record the
corresponding Friday adoption SHA only after this payload change is committed.

Consumer overlays remain outside both lists. A consumer may add an executable
regular-file `.agents/hooks/check-project-agent-integration.sh`; when present,
the managed core checker runs it and propagates failures. Friday does not ship
that extension.

This is an explicit static allowlist in [`install.sh`](./install.sh), not
automatic payload discovery. A new payload file fails inventory validation until it is reviewed
and added to that list. There is no manifest or update engine in this MVP.

## Updating an existing consumer

An existing consumer update is a reviewed reconciliation, not an installer
upgrade. Pin a reviewed Friday commit first; use a placeholder rather than a
mutable branch name:

```sh
PIN='replace-with-reviewed-immutable-Friday-SHA'
FRIDAY='/absolute/path/to/Friday'
TARGET='/absolute/path/to/consumer'

test "$(git -C "$FRIDAY" rev-parse HEAD)" = "$PIN"
test -z "$(git -C "$FRIDAY" status --porcelain)"
bash "$FRIDAY/install.sh" --check "$TARGET"
```

Read every `CONFLICT` and reconcile it in a reviewed consumer change. Sync
only the fourteen managed-core paths listed above, then prove each has the exact
bytes of `"$FRIDAY/payload/$rel"`. Preserve consumer seeds, runtime
integration, and overlays; do not copy a whole `.agents/` directory.

After reconciliation, verify the consumer rather than treating the installer
as an update engine:

```sh
(cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)
bash "$FRIDAY/bin/friday-lock" check "$TARGET"
git -C "$TARGET" diff --check
```

The checker runs a consumer extension when one exists. Review the resulting
consumer diff and create one atomic consumer commit under that repository's
own rules. Friday has no force mode, manifest, auto-sync, or automatic
reconciliation.

### Dated adoption evidence

As of 2026-10-13, `pet_care` and Finance were verified as 10/10 exact matches
for the managed core at Friday `b44e1ff`. This is historical evidence only:
any later payload change requires a fresh managed-core comparison before either
consumer records a new adoption SHA. It does not claim whole-repository
equality or native runtime enforcement in either consumer.

## Safety model and limits

[`guard-collaborative-git.sh`](./payload/.agents/hooks/guard-collaborative-git.sh)
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
pending. All four were measured on the Claude side — see below. This setup is
a guardrail, not a security boundary.

The three Git skills are the other half.
[`safety-boundary.md`](./payload/.agents/docs/git-guideline/safety-boundary.md) treats invoking
`$git-commit`, `$git-push` or `$git-create-pr` as the authorisation for that
one action in that one turn — so committing and pushing stay deliberate acts
rather than something an agent drifts into.

### Why the self-check matters

[`check-collaborative-git.sh`](./payload/.agents/hooks/check-collaborative-git.sh)
verifies the runtime wiring *and* feeds the guard
safe Bash and `apply_patch` payloads, failing if a prohibited payload is not
blocked. The Codex seed uses project-local hooks supported on macOS/Linux;
Windows behavior is unverified.

That last one is the case worth having. A guard that has been neutered looks
exactly like a guard that is working, right up until it matters.

## Friday's own branch protection

This repository is private on a plan where GitHub branch protection and
rulesets are unavailable, so the protection it would otherwise configure --
no direct push to the default branch, no force push, no ref deletion --
cannot be set server-side. [`.githooks/pre-push`](./.githooks/pre-push) is the
local substitute, wired with:

```sh
git config core.hooksPath .githooks
```

It is the same hook Friday ships to consumers at
[`payload/.agents/githooks/pre-push`](./payload/.agents/githooks/pre-push),
differing only in the document its messages point at. It decides from the refs
Git is about to send rather than from the command text, so a deletion, a
history rewrite and a push to the default branch are refused however the
command was spelled -- `--force`, `-f`, a leading `+` on the refspec,
`--mirror`, `--delete` and `:ref` all reduce to the same two tests.

Three limits are worth stating plainly. It protects this clone only: a fresh
clone carries no `core.hooksPath` and is unprotected until someone sets it. It
cannot require a review approval, which is inherently server-side. And it is a
guard against mistakes, not a control surface -- the installer does not apply
Friday's payload to Friday itself, so this repository's commits are not covered
by the commit-time hooks that consumers get.

## Non-goals and recovery

Friday installs entrypoints and a shared router, but it does not install a
domain glossary, issue tracker, Wayfinder map, prompt templates, judgment
rubrics, MCP configuration, consumer-specific PR verification, or personal
and vendor Skills. Consumer overlays may extend the shared baseline after
review, provided their references close within that project.

Friday also has no manifest, auto-discovery, automatic update/reconciliation,
or force mode. The existing-consumer workflow above is a deliberate project
change, not an automated refresh.

If preview finds a conflict, reconcile it rather than overwriting it. If an
install fails after preflight, inspect the partially created target before
retrying. Git history is the recovery mechanism: revert the reviewed consumer
adoption commit, or restore the selected pinned version in a new reviewed
consumer change. `--check` reports content and path-type differences; it does
not decide whether a merge is safe.

## Design notes

**Copy, not link.** Projects retain their own reviewed baseline and local
overlays. Pin a reviewed Friday commit before installation and record its SHA
in the project's adoption record; a mutable branch is not a reproducible
version. Git history provides rollback: revert the adoption commit or restore
the selected pinned version in a reviewed change. `--check` detects content
differences, not who authored them or whether an update is safe to merge.

**Existing consumers reconcile manually.** The managed-core files are the
only byte-identical comparison set. Seeds, runtime integration, and consumer
overlays may differ by project and need manual reconciliation.
[`.gitignore`](./payload/.gitignore) is an ordinary allowlisted seed: a target
with different content conflicts before any write. Friday's blank-repository
MVP intentionally does not parse or merge `.gitignore` marker blocks.

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

## Knowing where a consumer stands

`install.sh` writes `.friday-lock.json` into the target: the Friday commit it
was installed from, and the sha256 of every managed-core file as installed.

There are **two names**, because a repository is one of two things and a reader
should not have to open the file to tell which:

| file | the repository is | holds |
| --- | --- | --- |
| `.friday-lock.json` | a payload **consumer** | managed core, byte-exact |
| `hooks.json` | a repository that **borrows hooks** — Jarvis, and this repository | three `.githooks` copies, no `.agents/` tree |

`hooks.json` carries no prefix on purpose. Two earlier names carried one:
`mirror-` read as though the repositories were bound together, and
`.friday-hooks` said the hooks were Friday's rather than the holding
repository's. Neither is true — the repositories are maintained separately and
serve different audiences, Jarvis takes three of these nineteen payload files
and nothing else, and Friday depends on Jarvis for nothing. `.friday-lock.json`
keeps its prefix because a consumer's file genuinely is about Friday: the
repository adopted this payload, and it is Friday that reads the file back and
proposes the update.

A hooks record carries no `managed_core` key at all, so its shape matches its
name. `friday-lock` picks the name from what the target actually has, and
refuses a repository holding both.

In this repository, root `hooks.json` is that sha256 record. It is not hook
configuration: that is [`payload/.codex/hooks.json`](./payload/.codex/hooks.json),
which ships to consumers.
[`bin/friday-lock`](./bin/friday-lock) reads it back.

```sh
bin/friday-lock check <target>     # or run it from inside the consumer
bin/friday-lock write <target>     # refresh after a reviewed reconciliation
```

Three states, and the distinction is the point:

| state | means | what to do |
| --- | --- | --- |
| `in sync` | every recorded file matches and the payload has not moved | nothing |
| `drifted` | a file in the consumer no longer matches what the lock recorded | somebody edited a managed-core file locally; reconcile it |
| `behind` | Friday's payload moved since the lock was written | take the change in a reviewed commit, then `friday-lock write` |
| `ahead` | the consumer holds a payload Friday has not merged yet | do **not** copy the payload over it |
| `diverged` | two payload lines exist, neither containing the other | check out the Friday branch you mean to carry |

**`behind` is decided by content, never by comparing commits.** A Friday commit
that only touches a README moves no payload hash and so raises nothing. That is
what makes a daily scheduled check quiet enough to be worth running.

Jarvis and Friday are not payload consumers, but they carry `.githooks` copies
of three payload files. Those copies are **byte-identical** to their payload
source, so `friday-lock` anchors on equality: a mirror that differs is reported
whichever side moved, and the recorded hashes say which.

They used to differ in six lines naming a documentation path, because the right
path depends on who is running the file. The hooks now resolve it themselves,
so one file is correct in a consumer, in Friday and in a repository that only
mirrors it. The delta was removed because a delta re-applied by hand is a delta
that gets missed — which is exactly what happened the last time the payload
moved, in four places at once.

[`bin/managed-core.txt`](./bin/managed-core.txt) is the single source of truth
for which files are managed and which are consumer-owned. A payload file listed
as neither fails the tool loudly rather than shipping unchecked — the gap that
once let three githooks sit outside the byte-exact set while the docs still
said eleven.

## Carrying a change out to consumers

A managed-core change has to reach every consumer, and doing that from memory
is how the five stale counts happened.

```sh
bin/friday-propagate --dry-run ~/Github_Folks/pet_care ~/Desktop/Finance_App_Project
bin/friday-propagate           ~/Github_Folks/pet_care ~/Desktop/Finance_App_Project
```

Per consumer it asks [`friday-lock`](./bin/friday-lock) where that repository
stands, and **only when it is `behind`** branches from its `main`, copies the
managed-core files whose content actually moved, refreshes the lock, commits,
pushes and opens a pull request.

It refuses rather than guesses:

| situation | what happens |
| --- | --- |
| `in sync` | nothing, quietly |
| `drifted` | **refused** — somebody edited a managed-core file there; copying over it would destroy the edit and the reason for it |
| working tree not clean | **refused**, not stashed around |
| the branch already exists | **refused** |
| `gh` fails after the push | reported as a failure with the command to finish by hand, never counted as opened |

**It never merges.** The human review checkpoint is the one control in this
platform that has never been bypassed, and a propagation tool is a poor place
to start.

### Why this is a local command and not a CI bot

The four repositories are private and span three accounts, so a CI-hosted bot
needs a cross-repository token with write access to all of them, living in a
secret. A developer machine's `gh` already has that access — scoped to a
person rather than to an always-on workflow — and the end result is identical:
pull requests a human still merges. Issue #7 covers the CI-hosted variant if
the repositories ever go public or a token is issued.

## Runtime behaviour measured on the Claude side

Measured in a consumer on **Claude Code 2.1.306** (2026-10-22), in disposable
fixtures, and recorded there rather than here. Friday's own self-check proves
none of it — it is static wiring and direct-guard evidence. Codex is a
different adapter and none of this transfers to it.

**`onFailure: "block"` does what the payload assumes.** A hook exiting a code
other than 0 or 2 blocks the tool call, and so does one that overruns its
`timeout`; the message handed to the model says `blocking because onFailure is
"block"`.

**Without `onFailure`, a failing hook fails open silently.** The same hook
exiting 127 with the field omitted let the command run, and the model was told
nothing at all — no error, no warning. A guard that breaks is then
indistinguishable from no guard, from inside the session. Every handler in
this payload declares the field; the consequence of ever dropping it is now
known rather than assumed.

**Handlers under one matcher run concurrently, not in declared order.** With a
first handler sleeping two seconds, the second handler's work completed 2.0 s
earlier. All handlers run even when one of them blocks, and when several
block, only one reason reaches the model — not necessarily the first declared.
Blocking itself is reliable: any handler exiting 2 refuses the call. Nothing
in this payload depends on ordering, but a future handler that assumes it runs
first, or that it alone will be heard, would be wrong.

**Hook sources merge; they cannot be used to lift a guard.** A permissive
handler in `.claude/settings.local.json`, or supplied through `--settings`,
runs *alongside* a project handler that refuses, and the call is still
blocked. Passing `{}` as an entire `--settings` file removes nothing: the
project handler still ran and still blocked. So `claude --settings
<empty>.json` is not a bypass.

Not measured: precedence for user-level `~/.claude/settings.json`, which could
not be reached without copying a credential into a temporary directory; and
anything at all about Codex or Gemini.

## Verification and tests

Run `bash` [`tests/install-smoke.sh`](./tests/install-smoke.sh)
`/absolute/path/to/retained-test-output`.
The check creates disposable Git fixtures, installs the repository's actual
payload, and retains evidence for review. It never installs into an existing
project. Cleanup is a separate, explicitly authorized operation.
