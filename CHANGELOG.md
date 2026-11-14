# Changelog

> **中文摘要**：這是 Friday 的 release note 導引。條目依大版號分檔，放在
> [`docs/changelog/`](./docs/changelog/)，最新的在每個檔案的最上面；這個檔案只留規則和各版本檔的連結。
> release 的 pull request 把 `Unreleased` 的條目改名為「版號 + 日期」，日期是 tag 當天的台北時間（UTC+8）；
> annotated tag 的訊息就是該條目，GitHub Release 由 tag 建立，文字相同。PATCH 一行即可；MINOR 與 MAJOR
> 要寫改了什麼、為什麼、consumer 必須做什麼。release 若改了 seed（consumer 自有的檔案），條目必須有固定格式的
> `### Seed changes` 段落（四個欄位：Capability、Who is affected、Action、Check），由 `bin/friday-seed-check` 檢查，
> `friday-propagate` 也會把它帶進 pull request 內文。

Friday's release notes are kept one file per major version, so no single file grows
too long to read. This page holds the rules and links to each file.

| Major | File | About |
| --- | --- | --- |
| v1 | [`docs/changelog/v1.md`](./docs/changelog/v1.md) | The first major version: the managed core, `install.sh`, the lock file and `friday-propagate`, then `.agents/bin/setup.sh`, release-based install, the per-worktree handoff rule, then the protected-paths guard and `github-pr-verify`, then the guard following `cd`. |

How entries are written:

- A change that a release will carry is added under `## Unreleased` as it merges, at the
  top of the file for the major it will be released in (the newest, unless it is a
  maintenance release of an older major). The release's pull request renames that section to
  `## vX.Y.Z (YYYY-MM-DD)`, so the entry is reviewed with the release. The date is the
  tag's own date in Taipei time (UTC+8). Tag on the Taipei day the heading names; if the tag lands on another day, correct the heading in a follow-up pull request.
- The annotated tag's message is that entry, and the GitHub Release is created from the
  tag with the same text (see [Releases](./docs/releases.md#releases)).
- A PATCH entry may be one line. A MINOR or MAJOR entry says what changed, why, and what
  a consumer must do.
- A release that starts a new major version moves `## Unreleased` out of the old file to the
  top of the new `docs/changelog/vN.md`, and adds a row for it to the table above, in the
  same pull request. Apart from a later maintenance release of that major, that is the last edit to the old file.

## Seed changes

Propagation carries only the managed core and never writes a seed (a `!` entry of
[`bin/managed-core.txt`](./bin/managed-core.txt)), so a release that changes a seed needs a hand
edit in every consumer. The entry for that release says what, in a fixed section.

An entry is the text under its `## vX.Y.Z (YYYY-MM-DD)` heading (`## Unreleased` before the
release) up to the next `## ` heading. An entry must not contain a line starting with `## ` inside
a fenced block, because that ends the entry for both tools. A release that changes a seed has,
in that entry, a `### Seed changes` heading, and the section runs to the next `### ` or `## `
heading. By convention it goes at the end of the entry, and holds four fields, each a list item
with text on its first line (a field may continue on indented lines), written in this order:

```markdown
### Seed changes

- **Capability:** what the change gives the consumer.
- **Who is affected:** which consumers, and in which state.
- **Action:** what the consumer does by hand, in a reviewed change.
- **Check:** the command that proves it, and what it prints when it is done.
```

One section covers every seed the release changed. The v1.2.0 entry in
[`docs/changelog/v1.md`](./docs/changelog/v1.md) is the worked example. A released entry may gain,
or have corrected, a Seed changes section afterwards: the tag's message and the GitHub Release keep
their original text, and the file is the authority for seed changes.

Two tools hold to that rule:

- [`bin/friday-seed-check`](./bin/friday-seed-check) fails when the range from the previous
  release to a release (or, for the pending entry, to `HEAD`) changes a seed and that entry has
  no such section, or a section where any of the four fields has no text. The order and the
  position of the section are convention, not checked. The range is read from Git, not from the
  entry, and the seeds are the `!` entries of `bin/managed-core.txt` at either end of it, so a
  seed dropped from the list or promoted to managed core with a content change still counts. The
  previous release is the highest release tag that is an ancestor. It asks nothing of a release
  before v1.2.0 (a repository without a v1.2.0 tag has every release checked), and CI runs it on
  every pull request.
- `bin/friday-propagate` puts the section of every release in the consumer's range into the pull
  request body when the range from the consumer's recorded release (or commit) to the one it
  carries changes a seed, and says in one line that none did otherwise. It names a release in the
  range that changed seeds and has no section. It reads the changelog from the Friday checkout's
  `HEAD` (`main`) at the commit the run started on, once for all consumers, not from the tag, so a
  section added after a release reaches the body; the managed core, the seeds and the range stay
  at the pinned release. It still never writes a seed.
