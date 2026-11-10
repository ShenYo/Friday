# Releases and lifecycle

> **中文摘要**：release 與 lock 的關係、release 的版本規則與發行流程，
> 以及 Friday 的生命週期治理（B06）。本文件只有英文版。

## Releases and the lock

A **release** is an annotated tag `vMAJOR.MINOR.PATCH` on a reviewed commit on
`main`, pushed to `origin` (see [Releases](#releases)). It is the only thing a
consumer receives: `install.sh` and `friday-propagate` both take a release,
never a branch and never whatever a checkout holds at the moment. The consumer's
`.friday-lock.json` records the release's tag, the commit that last changed the
payload, and the sha256 of each managed file as installed (see
[Knowing where a consumer stands](./updating-consumers.md#knowing-where-a-consumer-stands)).

```text
  Friday checkout (~/.Friday)                 consumer project
  +----------------------------+              +----------------------------+
  | main  --o--o--o            |              | managed core   identical   |
  |              \             |  install.sh  | seeds          yours       |
  |           [v1.1.0] --------+------------> | overlays       yours       |
  |                            |  (the tag's  | .friday-lock.json          |
  | feature branch, edits      |   tree only) |   tag, commit, sha256      |
  |   never installed, unless  |              +-------------^--------------+
  |   --working-tree           |                            |
  +-------------|--------------+          .agents/bin/setup.sh: hooks and
                |                         links, in every clone (the install
                v                         runs it too)
  bin/friday-propagate: the tag's managed-core changes become a pull request
  in each consumer that is behind; a person merges it.
  bin/friday-lock: writes the lock at install and propagate; check compares a
  consumer with its lock and with Friday.
```

## Releases

A release is an annotated tag `vMAJOR.MINOR.PATCH` on a reviewed commit on
`main`. The commit is the record; the tag is its name, and a tag can be moved
where a commit cannot. Any reviewed change on `main` may be released, the
documentation included; only a release whose payload or
[`bin/managed-core.txt`](../bin/managed-core.txt) differs gives consumers
anything to take, and `friday-propagate` leaves the others alone.

- **PATCH** for documentation-only changes, the payload's documents included.
- **MINOR** for changes to what runs: the Skills, the Git hooks and the guard
  scripts.
- **MAJOR** for a large structural change.

The release note is the entry for the release, in the file for its major version
under [`docs/changelog/`](./changelog/), which [`CHANGELOG.md`](../CHANGELOG.md)
links: what changed, and what a consumer must do. The release's pull request adds
the entry, so it is reviewed with the change. The entry's heading is `## vX.Y.Z
(YYYY-MM-DD)`, the date being the tag's own date in Taipei time (UTC+8). The
annotated tag's message is that entry, and after the tag is pushed the GitHub Release is created from the tag,
with the same text.

```sh
git tag -a vX.Y.Z <commit> -F <file with the entry>
git push origin vX.Y.Z
gh release create vX.Y.Z --notes-from-tag
bin/friday-propagate <consumer>...
```

`install.sh` installs a release the same way: by default the newest, chosen and
checked as below, or the one named with `--release vX.Y.Z`; it refuses, writing
nothing, when none qualifies, and says to fetch tags or cut one. A release
older than the one that added `--working-tree` has no such flag; its own
installer runs under its old interface and installs its own tree, which is
exactly the release.

Pushing any tag, and creating, editing or uploading to a GitHub Release, are
checkpoints
([`safety-boundary.md`](../payload/.agents/docs/git-guideline/safety-boundary.md)):
an agent pushes a tag, including through `--tags` or `--follow-tags`, or
publishes a release, only when the user names the tag and its commit in the
current turn. Neither Friday's guard nor `pre-push` checks it; it is enforced
by instruction.

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
in [`scratch-files.md`](../payload/.agents/docs/scratch-files.md); it neither
installs nor copies vendor Skills and does not claim runtime invocation or
precedence enforcement.
