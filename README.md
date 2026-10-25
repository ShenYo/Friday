# Friday

**English** · [繁體中文](./README.zh-TW.md)

> **中文摘要**：Friday 是可版控的 shared project baseline；個人層不在這裡。
> 先以 `--check` 預覽，再安裝封閉的 allowlist。衝突絕不覆寫，現有專案需經
> 人工審查後調和。

Friday is a portable, reviewed shared project baseline. It copies
project-scoped policy, Git skills, a shared temporary-file contract, and
Claude/Codex guard wiring into a consumer repository without depending on a
developer's personal home directory, personal skills, or vendor workflow.

It addresses three constraints at once: a closed allowlist makes bootstrap
conflict-safe, copied content keeps the baseline portable and reviewable, and
existing-consumer changes stay behind a reviewed reconciliation boundary rather
than becoming an automatic update. A developer's personal layer stays out of
it: do not place personal skills, settings, or other personal-home
dependencies in Friday's project contract. Portable outcomes belong in
project-controlled documentation, tests, or automation; optional helpers may
assist an operator, but no consumer may require them to bootstrap or satisfy the
Friday contract.

How Friday got here is in [`docs/history.md`](./docs/history.md): dated
decisions and incidents, measurements, and recent progress. This README
describes the present.

## When to use Friday

| Scenario | Friday's role | What to do |
| --- | --- | --- |
| Blank Git repository | Bootstrap the reviewed baseline | Preview, install, then preview again. |
| Existing consumer | Reveal differences safely | Pin Friday, run `--check`, and reconcile every conflict in a reviewed consumer change. |
| Personal skills or preferences | Keep personal scope personal | Keep them in your personal layer; do not promote them into Friday. |
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
Claude side in a consumer ([measurements](./docs/history.md#2026-10-22-runtime-behaviour-measured-on-the-claude-side))
and remain unverified for Codex, which is a different adapter. Friday
does not discover arbitrary skills or install a consumer's domain workflow.

## Status (2026-10-25)

> **中文摘要**：managed core 現為十五檔，其中十四檔已以 v1.0.0（2026-10-25）發行，
> `.agents/bin/setup.sh` 隨下一版發行；pet_care 與 Finance
> 兩個 consumer 都已同步在 v1.0.0。待辦：指定 backup maintainer、真正的新機器 replay、
> 第三個 consumer、external-runtime 收尾，以及 managed-core 更新 bot。

In place:

- The managed core: 15 files, listed in [`bin/managed-core.txt`](./bin/managed-core.txt).
  `v1.0.0` (2026-10-25) shipped the first 14; `.agents/bin/setup.sh` is the 15th.
- Released as `v1.0.0` (2026-10-25). Consumers receive the managed core only as a
  release (see [Releases](#releases)).
- Both consumers, `pet_care` and Finance, record `v1.0.0` and are `in sync`.
- CI is required on `main`: the test suites on ubuntu and macos, shellcheck, and
  gitleaks ([`ci.yml`](./.github/workflows/ci.yml)).

Pending:

- A named backup maintainer (see [Lifecycle governance](#lifecycle-governance-b06)).
- A real new-machine replay.
- A third genuine consumer.
- External-runtime closure: Codex and Gemini behaviour Friday does not verify.
- The next payload release will add the two overlay files both consumers
  already hold identically, `mcp.md` and `triage-labels.md`, to the managed core.
- That release also carries `.agents/bin/setup.sh` and the `CLAUDE.md` seed, so
  a consumer stops needing a project-local `setup-ai.sh` for the root pointer and
  the Claude Code Skill links.
- The managed-core update bot, so that a Friday release opens the consumer pull
  requests itself: [ShenYo/Friday#7](https://github.com/ShenYo/Friday/issues/7).

The agent-platform epic that groups the wider work is
[ShenYo/Friday#10](https://github.com/ShenYo/Friday/issues/10); an item above
without its own link has no open issue yet.

## Lifecycle governance (B06)

> **中文摘要**：Friday 的 MVP 採「可審查 release（tag + commit）+ consumer 手動採用」模式：
> repository owner 負責維護，backup maintainer 尚待指定；不自動同步、不強制
> 更新，也不自動 rollback。

This section is normative for Friday's MVP lifecycle.

- The repository owner is the primary Friday maintainer. A backup maintainer
  is **PENDING**; until one is named, the primary maintainer remains accountable
  for release review, recovery proposals, and recording the decision.
- A release is an annotated tag `vMAJOR.MINOR.PATCH` on a reviewed commit on
  `main`. A consumer's `.friday-lock.json` records the tag and, as the record it
  trusts, the commit that last changed the payload at that release, whose
  payload is the release's byte for byte; the tag is a label, and a tag that
  moves is reported by `friday-lock check` as `status: tag-moved`. Mutable
  branch names are not releases.
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

Vendor Skills, including Matt Pocock Skills, stay in the personal layer that
installs them, vendor-pristine. Friday manages only the portable project-local output contract
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
at the commit of a release. Prerequisites are Git, Bash, and `jq`. Do not use a
dirty Friday checkout as the example source: this creates a new checkout at
the reviewed pin. Before running it, replace both absolute paths and the
literal SHA placeholder. The commands do not create a commit, install a
runtime, or configure credentials.

`PIN` is the commit of a reviewed release. To find it, clone Friday once and run
`git -C "$FRIDAY" rev-parse 'vX.Y.Z^{commit}'` there (the `^{commit}` matters:
for an annotated tag, `rev-parse vX.Y.Z` prints the tag object, not the
commit). The script keeps checking that the checkout's `HEAD` equals `PIN`.

```sh
(
  set -eu
  TARGET='/absolute/path/to/new-project'
  FRIDAY='/absolute/path/to/new-Friday-checkout'
  PIN='replace-with-the-commit-of-a-reviewed-Friday-release'

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
(a linked worktree is refused, because `core.hooksPath` is shared by every
worktree of a repository and wiring it from one would leave the others running
no hooks). The target is the repository root, not
an `.agents/` subdirectory. `--check` reports `NEW`, `IDENTICAL`, or
`CONFLICT`, exits nonzero on conflicts, and does not copy, chmod, create links,
or run the self-check. Both modes validate prerequisites, every destination,
and the target's existing hook setup (an effective `core.hooksPath`, from any
config scope, that is not `.agents/githooks`, or hooks or hook symlinks in
`.git/hooks` that wiring would bypass) before any target write. They also
check the `.claude/skills/<name>` links `setup.sh` will make, for the Skills as
they will be once the copy is done (the target's own `.agents/skills` plus the
payload's): a name two Skills share, a real file or directory in the way, a
link elsewhere, and a dangling link that the copy would make live or that
`setup.sh` did not write are all conflicts, so the install is refused rather
than stopped halfway. Unexpected destination symlinks, including ancestor
symlinks, conflict; the only links accepted are the two exact Claude and Codex
hook links, a `.claude/skills/<name>` link that is already correct, and a
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

The install wires the clone by running the payload's own
[`.agents/bin/setup.sh`](./payload/.agents/bin/setup.sh) in the target (see
[After cloning](#after-cloning-a-consumer-or-changing-its-skills)), and ends by
running the payload's own self-check, so broken runtime wiring fails now rather
than the first time someone relies on the boundary.

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
the import is runtime behavior this README cannot guarantee, so keep asking the
agent to report the instruction documents it loaded. Native workspace trust,
callback delivery, precedence, and other runtime behavior remain
runtime-specific evidence work. Gemini CLI and
`agy` remain pending here, so this guide intentionally provides no speculative
launch command for either.

### After cloning a consumer, or changing its Skills

Install runs once, on one machine, and some of what makes a consumer work is
lost on every fresh clone: `core.hooksPath` is local Git config, so a clone has
none of the payload's Git hooks running until it is set. After cloning a
consumer, and again after adding, removing or renaming a Skill, run this from
anywhere inside it (add `--check` to preview; it writes nothing):

```sh
bash .agents/bin/setup.sh
```

It does four things:

- sets `core.hooksPath` to `.agents/githooks` (an effective value from any
  config scope that is something else is a `CONFLICT`, not overridden), and
  reports Git hooks that are missing or not executable, and hooks or hook
  symlinks in `.git/hooks` that it would bypass;
- links `.claude/hooks/guard-collaborative-git.sh` and
  `.codex/hooks/guard-collaborative-git.sh` to the shared guard;
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

The three [`githooks`](./payload/.agents/githooks) files are Git hooks rather
than runtime tool hooks, wired through `core.hooksPath` by
[`setup.sh`](./payload/.agents/bin/setup.sh), which the installer runs and every
clone runs again.
[`pre-commit`](./payload/.agents/githooks/pre-commit) scans staged content for
credentials, [`commit-msg`](./payload/.agents/githooks/commit-msg) enforces the
message contract, and [`pre-push`](./payload/.agents/githooks/pre-push) decides
from the refs Git is about to send, so a deletion, a history rewrite or a push
to the default branch is refused however the command was spelled. The first
push to a remote with no refs at all is allowed: there is no default branch to
protect, nothing to delete and no history to rewrite, and refusing it made
creating a repository impossible without bypassing the hook. They are
byte-exact like the rest of the core, so the reconciliation recipe below must
carry them ([history](./docs/history.md#2026-10-22-the-git-hooks-were-missing-from-the-managed-core-list)).

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
[`bin/managed-core.txt`](./bin/managed-core.txt), which
[`install.sh`](./install.sh) reads; it is not automatic payload discovery. A new
payload file fails inventory validation until it is reviewed and added to that
list. There is no manifest or update engine in this MVP.

## Updating an existing consumer

An existing consumer update is a reviewed reconciliation, not an installer
upgrade. Pin the commit of a reviewed Friday release first (`git -C "$FRIDAY" rev-parse
'vX.Y.Z^{commit}'` prints it); use a placeholder rather than a mutable branch
name:

```sh
PIN='replace-with-the-commit-of-a-reviewed-Friday-release'
FRIDAY='/absolute/path/to/Friday'
TARGET='/absolute/path/to/consumer'

test "$(git -C "$FRIDAY" rev-parse HEAD)" = "$PIN"
test -z "$(git -C "$FRIDAY" status --porcelain)"
bash "$FRIDAY/install.sh" --check "$TARGET"
```

Read every `CONFLICT` and reconcile it in a reviewed consumer change. Sync
only the fifteen managed-core paths listed above, then prove each has the exact
bytes of `"$FRIDAY/payload/$rel"`. Preserve consumer seeds, runtime
integration, and overlays; do not copy a whole `.agents/` directory. Then run
`bash .agents/bin/setup.sh` in the consumer (`--check` first to preview) to wire
the clone.

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
pending. All four were measured on the Claude side
([measurements](./docs/history.md#2026-10-22-runtime-behaviour-measured-on-the-claude-side)).
This setup is a guardrail, not a security boundary.

Two of those results shape the payload. Every handler declares
`onFailure: "block"`, because a failing hook without it fails open silently,
indistinguishable from no guard. And handlers under one matcher run
concurrently, and when several block only one reason reaches the model, so no
handler may assume it runs first or that it alone will be heard. Hook sources
merge rather than override, so a permissive settings file cannot lift a guard:
`claude --settings <empty>.json` is not a bypass.

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
overlays. Pin the commit of a reviewed Friday release before installation and record
its SHA in the project's adoption record; a mutable branch is not a reproducible
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
an existing consumer or change personal settings.

**The payload owns no project references.** Worked examples use `#123` rather
than real issue numbers, and no file names another repository's documents,
because that coupling makes a library unportable
([history](./docs/history.md#2026-09-08-the-payload-was-checked-for-project-references-before-the-first-commit)).

**No dependency on `rg`.** The self-check uses `grep`, and first proves the
search can find a string that is definitely present before trusting any negative
result, because a check that treats "found nothing" as success passes vacuously
when its tool is missing
([history](./docs/history.md#2026-09-08-the-self-check-searched-with-a-tool-that-was-not-there)).

## Knowing where a consumer stands

`install.sh` writes `.friday-lock.json` into the target: the Friday commit it
was installed from, the release tag that names that payload when there is one,
and the sha256 of every managed-core file as installed.

[`bin/friday-lock`](./bin/friday-lock) reads it back. Only a payload consumer
has one. A repository that wants one of the payload's hooks without adopting
the payload keeps its own copy, and Friday does not track it.

```sh
bin/friday-lock check <target>     # or run it from inside the consumer
bin/friday-lock write <target>     # refresh after a reviewed reconciliation
```

The states, and the distinction is the point:

| state | means | what to do |
| --- | --- | --- |
| `in sync` | every recorded file matches and the payload has not moved | nothing |
| `drifted` | a file in the consumer no longer matches what the lock recorded | somebody edited a managed-core file locally; reconcile it |
| `tag-moved` | the lock records a release tag, and Friday's tag of that name now points at a different payload than the lock recorded (a tag this clone lacks is reported as not verified, not as moved) | trust the commit in the lock, not the tag; find out who moved it, then `friday-lock write` |
| `behind` | Friday's payload moved since the lock was written, or a file joined the managed core (listed as `new in the payload`) | take the change in a reviewed commit, then `friday-lock write` |
| `retired` | the lock records a file Friday no longer manages | delete it or keep it as the consumer's own, deliberately, then `friday-lock write`. On a consumer with nothing else to carry, `friday-propagate` names it and touches nothing. When it does carry a change, its pull request names the file, and merging that pull request records it as the consumer's own unless it is deleted on that branch first |
| `ahead` | the consumer holds a payload Friday has not merged yet | do **not** copy the payload over it |
| `diverged` | two payload lines exist, neither containing the other | check out the Friday branch you mean to carry |

**`behind` is decided by content, never by comparing commits.** A Friday commit
that only touches a README moves no payload hash and so raises nothing. That is
what makes a daily scheduled check quiet enough to be worth running.

[`bin/managed-core.txt`](./bin/managed-core.txt) is the single source of truth
for which files are managed and which are consumer-owned. A payload file listed
as neither fails the tool loudly rather than shipping unchecked
([history](./docs/history.md#2026-10-22-the-git-hooks-were-missing-from-the-managed-core-list)).

## Carrying a change out to consumers

A managed-core change has to reach every consumer, and doing that from memory
leaves stale counts behind
([history](./docs/history.md#2026-10-22-the-git-hooks-were-missing-from-the-managed-core-list)).

Run it from a `main` that matches `origin/main`; step 4 of
[`AGENTS.md`](./AGENTS.md#changing-the-payload) says how to confirm that. The
run pins the commit a release tag names (see Releases below) and carries only that
commit's tree, so an uncommitted payload edit, a payload change merged to
`main` but not yet released, or a Friday commit made while it runs, cannot
reach a consumer.

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
| a consumer file changes after that check, before it is written | **refused**, the change left in place |
| pulling the consumer's `main` brings drift, or changes what has to be carried | **refused**, back on `main`, nothing written |
| HEAD leaves the sync branch before the write or the commit | **refused**, and it says where HEAD is |
| `retired` only | **refused**, the retired files named; deleting them is the owner's call |
| Friday not on `main` | **refused**, before any consumer is read |
| no release tag, or the tag is not on `main`, not annotated, or not on `origin` | **refused**, before any consumer is read |
| `tag-moved` | **refused** — the lock's release label can no longer be trusted; a person reconciles it |
| the branch already exists | **refused** |
| `gh` fails after the push | reported as a failure with the command to finish by hand, never counted as opened |

**It never merges.** The human review checkpoint is the one control in this
platform that has never been bypassed, and a propagation tool is a poor place
to start.

### Why this is a local command and not a CI bot

The consumers are private and sit in two other accounts than Friday's, so a
CI-hosted bot needs a cross-repository token with write access to all of them,
living in a secret. A developer machine's `gh` already has that access — scoped to a
person rather than to an always-on workflow — and the end result is identical:
pull requests a human still merges. [Issue #7](https://github.com/ShenYo/Friday/issues/7)
covers the CI-hosted variant if the consumers ever go public or a token is issued.

## Releases

A release is an annotated tag `vMAJOR.MINOR.PATCH` on a reviewed commit on
`main`. The commit is the record; the tag is its name, and a tag can be moved
where a commit cannot. Any reviewed change on `main` may be released, the
documentation included; only a release whose payload or
[`bin/managed-core.txt`](./bin/managed-core.txt) differs gives consumers
anything to take, and `friday-propagate` leaves the others alone.

- **PATCH** for documentation-only changes, the payload's documents included.
- **MINOR** for changes to what runs: the Skills, the Git hooks and the guard
  scripts.
- **MAJOR** for a large structural change.

The annotated tag's message is the release note: what changed, and what a
consumer must do.

```sh
git tag -a vX.Y.Z -m '<release note>' <commit>
git push origin vX.Y.Z
bin/friday-propagate <consumer>...
```

Pushing any tag is a checkpoint
([`safety-boundary.md`](./payload/.agents/docs/git-guideline/safety-boundary.md)):
an agent pushes one, including through `--tags` or `--follow-tags`, only when
the user names the tag and its commit in the current turn. Neither Friday's
guard nor `pre-push` checks it; it is enforced by instruction.

`bin/friday-propagate` carries only releases: the newest tag of the exact form
`vX.Y.Z` by default (a pre-release such as `v1.1.0-rc1` is never one), or the
one named with `--tag vX.Y.Z`. It refuses, before any consumer is read, when
Friday has no release tag, or the tag is not on `main`, is not annotated, or is
not on `origin` as the same tag object. It notes, without carrying, payload
changes on `main` that no release holds yet. Each pull request lists the Friday
commits that changed `payload/` or `bin/managed-core.txt` since the release
(or, for an older lock, the commit) the consumer's lock recorded.

`friday-lock check` prints the recorded release on a `release:` line, `none`
for a lock that records no tag. `friday-lock write` records the release tag
`friday-propagate` named, or the release tag on the commit it reads, or, when
none is there, the newest release with the same payload and the same
managed-core list. If the tag of that name later points at different content,
`check` reports `status: tag-moved`: trust the commit in the lock, not the tag.
A tag this Friday clone does not have is not reported as moved, since a clone
that has not fetched it looks the same: when the recorded commit is here,
`check` prints that the tag is not found and not verified; when the commit is
missing too, nothing can be compared and it says nothing about the tag. Either
way the other checks decide the status.

## Verification and tests

Run `bash` [`tests/install-smoke.sh`](./tests/install-smoke.sh)
`/absolute/path/to/retained-test-output`.
The check creates disposable Git fixtures, installs the repository's actual
payload, and retains evidence for review. It never installs into an existing
project. Cleanup is a separate, explicitly authorized operation.

[`tests/setup.sh`](./tests/setup.sh) proves the setup script case by case, each
in a scratch clone, and prints `all N passed`.
