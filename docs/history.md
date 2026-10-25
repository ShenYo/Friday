# Friday history

> **中文摘要**：這份文件收錄 Friday 的歷史與觀察：有日期的決策與事故、在 Claude 側實測的
> runtime 行為與 adoption 證據，以及 2026-10-23 至 2026-10-25 合併的工作。README 只描述
> 現在的樣子；這裡記錄當時發生了什麼。內容原樣搬自 README，只調整時態並補上原本缺的日期。

[`README.md`](../README.md) describes what Friday is today: what it is, how to use
it, and the rules with a one-sentence reason each. This file holds what the
README no longer carries: dated decisions and incidents, measurements, and a
record of recent work. Nothing here is a current rule. Dates are in the
maintainer's local time (UTC+8). Pull requests and commits are in
[ShenYo/Friday](https://github.com/ShenYo/Friday).

## Decisions and incidents

Newest first.

### 2026-10-22 The Git hooks were missing from the managed-core list

An earlier revision of the README's managed-core list omitted the three Git
hooks, `pre-commit`, `commit-msg` and `pre-push`, which left the reconciliation
recipe silently incomplete. It was the gap that let three githooks sit outside
the byte-exact set while the docs still said eleven. Carrying a managed-core
change out to the consumers was done from memory, and that is how the five stale
counts happened.

What changed: [`23c1ece`](https://github.com/ShenYo/Friday/commit/23c1eceb167c363521866e8a79342b304f8ee2ac)
listed the hooks in the managed core,
[`d785746`](https://github.com/ShenYo/Friday/commit/d7857463bdaa616fd2b392892870ab3610fe0ef1)
corrected the count in both READMEs and
[`6eb6423`](https://github.com/ShenYo/Friday/commit/6eb6423377d88dfd54479265a3a267656d40005c)
corrected it in the English README's Chinese summary. Two tools followed the
same day: [`0223516`](https://github.com/ShenYo/Friday/commit/02235162cc93b458c568d5cbb53a7b10e136c29f)
added `bin/friday-lock`, which made `bin/managed-core.txt` the single source of
truth for which files are managed and which are consumer-owned, so that a
payload file listed as neither fails the tool loudly rather than shipping
unchecked; and
[`af6304d`](https://github.com/ShenYo/Friday/commit/af6304d49ea5fafefed45253049819bac4285541)
added `bin/friday-propagate`, which carries a managed-core change out to the
consumers.

### 2026-10-16 The first promotion named its source commit

The README said that the reviewed generic promotion source was `pet_care`
commit `3e4f03b` (made on 2026-10-15); that its protected-path consumer overlay
was intentionally excluded; and that the corresponding Friday adoption SHA was
to be recorded only after that payload change was committed. The README text
came in with Friday commit
[`5629c77`](https://github.com/ShenYo/Friday/commit/5629c77020c6dd661588fa023c91fe47fe99317d),
"fix(agents): harden Codex hook seed".

What changed: nothing is pending from it. A consumer's adoption is now recorded
in its `.friday-lock.json` by `bin/friday-lock`, and a consumer adopts a
release rather than a commit.

### 2026-09-08 The payload was checked for project references before the first commit

The payload owns no project references: worked examples use `#123` rather than
real issue numbers, and no file names another repository's documents. This was
checked before the first commit
([`3285b3a`](https://github.com/ShenYo/Friday/commit/3285b3a3e66ec30e2db0e91045be30fae1cf3131),
2026-09-08) — the version in `pet_care` did carry issue numbers and paths,
which is exactly the coupling that makes a library unportable.

What changed: the rule stayed. The README keeps it, with its reason, under
"Design notes".

### 2026-09-08 The self-check searched with a tool that was not there

The self-check originally used ripgrep for its stale-reference scan. On the
machine this kit was built on, `rg` exists only as an interactive shell
function, so a script calling it failed with "command not found" — and because
that check treats "found nothing" as success, it had been passing vacuously.
The fix was made in `pet_care` the same day, before Friday's first commit
(`pet_care` commit `563b790`, "fix(hooks): make the stale-reference check
actually run"). It now uses `grep`, and first proves the search can find a
string that is definitely present before trusting any negative result.

That paragraph records the original failure, not current pet-care behavior.

What changed: the self-check depends on `grep`, never on `rg`, and proves the
search works before it trusts "found nothing".

## Measured observations

### 2026-10-22 Runtime behaviour measured on the Claude side

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

### 2026-10-13 Adoption evidence

As of 2026-10-13, `pet_care` and Finance were verified as 10/10 exact matches
for the managed core at Friday `b44e1ff`. This is historical evidence only:
any later payload change requires a fresh managed-core comparison before either
consumer records a new adoption SHA. It does not claim whole-repository
equality or native runtime enforcement in either consumer.

Since then the managed core has grown to 14 files, and on 2026-10-25 both
consumers recorded release `v1.0.0` and reported `status: in sync` under
`bin/friday-lock check`.

## Progress, 2026-10-23 to 2026-10-25

Grouped by theme. PR numbers are in
[ShenYo/Friday](https://github.com/ShenYo/Friday/pulls?q=is%3Apr+is%3Amerged),
except where a consumer is named.

### Releases

The payload is carried to consumers only as an annotated release tag, and a
consumer's lock records the tag; `v1.0.0` was cut on 2026-10-25. Pushing a tag
became a checkpoint in the safety boundary in the same change.
[#42](https://github.com/ShenYo/Friday/pull/42)

### The Git hooks

Friday first kept hook mirrors byte-identical to their payload source and
checked them in CI, then dropped the mirrors and runs the payload's own hooks
through `core.hooksPath`. The commit-message check stopped refusing a summary
for the case of its first letter. The secret scanner learned seven more token
formats, and `pre-push` lets a first push bootstrap an empty remote.
[#13](https://github.com/ShenYo/Friday/pull/13),
[#16](https://github.com/ShenYo/Friday/pull/16),
[#17](https://github.com/ShenYo/Friday/pull/17),
[#19](https://github.com/ShenYo/Friday/pull/19),
[#20](https://github.com/ShenYo/Friday/pull/20),
[#25](https://github.com/ShenYo/Friday/pull/25),
[#31](https://github.com/ShenYo/Friday/pull/31),
[#33](https://github.com/ShenYo/Friday/pull/33)

### Lock and propagation tooling

`friday-lock` learned to see managed files that join or leave the core, and
`friday-propagate` reads everything once from one pinned commit, reports in a
dry run what it would open, and stops when its sync branch or commit does not
land.
[#26](https://github.com/ShenYo/Friday/pull/26),
[#27](https://github.com/ShenYo/Friday/pull/27),
[#36](https://github.com/ShenYo/Friday/pull/36),
[#37](https://github.com/ShenYo/Friday/pull/37)

### The installer

`install.sh` checks the target's hook setup before writing anything, reads its
allowlist from `bin/managed-core.txt`, and refuses a linked worktree with the
real reason.
[#32](https://github.com/ShenYo/Friday/pull/32),
[#38](https://github.com/ShenYo/Friday/pull/38),
[#40](https://github.com/ShenYo/Friday/pull/40)

### Payload rules and guidance for agents

The payload states its safety rules itself instead of delegating them to a
path, and its hook guideline fallback points at a document that exists. The
repository's `AGENTS.md` says what a change reaches, that propagation runs only
while no other agent is in the checkout, and that a `.agents/` directory does
not make a repository a consumer. The install an agent runs is written down,
`ADOPTING.zh-TW.md` is level with the English, and Friday no longer names a
repository that is not a consumer.
[#21](https://github.com/ShenYo/Friday/pull/21),
[#22](https://github.com/ShenYo/Friday/pull/22),
[#24](https://github.com/ShenYo/Friday/pull/24),
[#28](https://github.com/ShenYo/Friday/pull/28),
[#30](https://github.com/ShenYo/Friday/pull/30),
[#34](https://github.com/ShenYo/Friday/pull/34),
[#35](https://github.com/ShenYo/Friday/pull/35),
[#41](https://github.com/ShenYo/Friday/pull/41)

### CI

Every test suite, shellcheck and gitleaks run on each pull request, from one
workflow with no path filter, so that it can be a required check.
[#39](https://github.com/ShenYo/Friday/pull/39)

### The consumers

`pet_care` and Finance (`Miko-Sam-chon/money-pit-nephew`) synced their managed
core to Friday `c61dd0b` (#19), `485a893` (#22), `394b932` (#31), `662412d`
(#35) and finally release `v1.0.0`. Each added a scheduled check of whether
Friday's payload has moved, later made it ignore pull requests and scan for
secrets, then compared it against Friday's newest release; each kept its
verification rules and retired its copies of the dispatch documents.

- `pet_care`:
  [#66](https://github.com/dameiwoha/pet_care/pull/66),
  [#68](https://github.com/dameiwoha/pet_care/pull/68),
  [#69](https://github.com/dameiwoha/pet_care/pull/69),
  [#70](https://github.com/dameiwoha/pet_care/pull/70),
  [#73](https://github.com/dameiwoha/pet_care/pull/73) (syncs);
  [#67](https://github.com/dameiwoha/pet_care/pull/67),
  [#71](https://github.com/dameiwoha/pet_care/pull/71),
  [#74](https://github.com/dameiwoha/pet_care/pull/74) (CI);
  [#72](https://github.com/dameiwoha/pet_care/pull/72) (dispatch copies)
- Finance:
  [#30](https://github.com/Miko-Sam-chon/money-pit-nephew/pull/30),
  [#32](https://github.com/Miko-Sam-chon/money-pit-nephew/pull/32),
  [#33](https://github.com/Miko-Sam-chon/money-pit-nephew/pull/33),
  [#34](https://github.com/Miko-Sam-chon/money-pit-nephew/pull/34),
  [#37](https://github.com/Miko-Sam-chon/money-pit-nephew/pull/37) (syncs);
  [#31](https://github.com/Miko-Sam-chon/money-pit-nephew/pull/31),
  [#35](https://github.com/Miko-Sam-chon/money-pit-nephew/pull/35),
  [#38](https://github.com/Miko-Sam-chon/money-pit-nephew/pull/38) (CI);
  [#36](https://github.com/Miko-Sam-chon/money-pit-nephew/pull/36) (dispatch copies)
