# Changelog

> **中文摘要**：這是 Friday 的 release note 導引。條目依大版號分檔，放在
> [`docs/changelog/`](./docs/changelog/)，最新的在每個檔案的最上面；這個檔案只留規則和各版本檔的連結。
> release 的 pull request 把 `Unreleased` 的條目改名為「版號 + 日期」，日期是 tag 當天的台北時間（UTC+8）；
> annotated tag 的訊息就是該條目，GitHub Release 由 tag 建立，文字相同。PATCH 一行即可；MINOR 與 MAJOR
> 要寫改了什麼、為什麼、consumer 必須做什麼。

Friday's release notes are kept one file per major version, so no single file grows
too long to read. This page holds the rules and links to each file.

| Major | File | About |
| --- | --- | --- |
| v1 | [`docs/changelog/v1.md`](./docs/changelog/v1.md) | The first major version: the managed core, `install.sh`, the lock file and `friday-propagate`, then `.agents/bin/setup.sh`, release-based install, and the per-worktree handoff rule. |

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
