# Changelog

> **中文摘要**：這裡是 Friday 每個 release 的 release note，最新的在最上面。
> release 的 pull request 把 `Unreleased` 的條目改名為版本號；annotated tag 的訊息就是該條目，
> GitHub Release 由 tag 建立，文字相同。PATCH 一行即可；MINOR 與 MAJOR 要寫改了什麼、為什麼、
> consumer 必須做什麼。

How entries are written. A change that a release will carry is added under
`## Unreleased` as it merges. The release's pull request renames that section
to `## vX.Y.Z`, so the entry is reviewed with the release. The heading carries no date: the
tag's own date, on the release page and in `git for-each-ref`, is the record. The annotated tag's message is that entry, and the
GitHub Release is created from the tag with the same text (see
[Releases](./docs/releases.md#releases)). A PATCH entry may be one line. A MINOR or
MAJOR entry says what changed, why, and what a consumer must do.

## v1.1.4

- **Handoffs** now go to one `docs/temp/handoff/<worktree>/handoff.md` per worktree, under the
  primary checkout, with a dated section per day (the same day revises it, a new day adds one),
  in [`scratch-files.md`](./payload/.agents/docs/scratch-files.md#handoff-documents). It changes
  a managed-core document only, so this is a PATCH.

## v1.1.3

Documentation only, and no payload file changes, so this is a PATCH.

- **What only Codex can verify** is listed in
  [`docs/codex-pending-action-items.md`](./docs/codex-pending-action-items.md), for Codex
  to measure in a disposable fixture: hook delivery for `Bash` and `apply_patch`, exit
  handling, handler order, timeouts, and user-level hooks alongside the project's.
  [`docs/safety.md`](./docs/safety.md) points at it.
- **Staying current** in [`ADOPTING.md`](./ADOPTING.md) (and `ADOPTING.zh-TW.md`) now lists the
  situations and the steps for each: cutting a release and propagating it, catching up every
  machine's clone after a propagate pull request merges (pull, `setup.sh`, and a new `/hooks`
  trust when `.codex/hooks.json` changed), fetching before running Friday, and checking where a
  consumer stands.

## v1.1.2

Documentation only, and no payload file changes, so this is a PATCH.

- The README is split into documents ([ShenYo/Friday#50](https://github.com/ShenYo/Friday/issues/50)).
  `README.md` and `README.zh-TW.md` keep the introduction, when to use Friday,
  the status, a quick start and a table of links. Adopting Friday, with the
  setup script and starting an agent, moved into `ADOPTING.md` and
  `ADOPTING.zh-TW.md`. Architecture and ownership, updating consumers, safety,
  releases with the lifecycle governance, and verification are new English-only
  documents under `docs/`, each opening with a Chinese summary, so
  `README.zh-TW.md` no longer carries a translation of those sections.

## v1.1.1

The payload changes only in documentation, so this is a PATCH.

- safety-boundary.md: publishing, editing or uploading to a GitHub Release
  (`gh release create|edit|upload`, or the same through the API) is a
  human-review checkpoint on the same terms as pushing a tag: an agent does it
  only when the user names the release and its tag in the current turn.
- safety-boundary.md: deleting a GitHub Release (`gh release delete`) is
  named among the permanently prohibited operations, beside deleting a
  repository.
- Each release now carries a note people can read: this changelog, the
  annotated tag's message and the GitHub Release share one text, and the
  READMEs and AGENTS.md state the process.
- friday-propagate no longer prints "could not open directory" when a
  managed file joins the core in a directory a consumer lacks.

### What a consumer must do

Merge the sync pull request friday-propagate opens; nothing else.

## v1.1.0

Friday v1.1.0: consumer setup, and installing from a release

What runs changed, so this is a MINOR release.

- .agents/bin/setup.sh joins the managed core (15 files). Run it after
  cloning a consumer, and again after its Skills change: it sets
  core.hooksPath (per-clone, so a fresh clone otherwise runs no Git
  hooks), checks the runtime guard links, creates AGENTS.md or
  CLAUDE.md only when missing, and links every Skill into
  .claude/skills. It never overwrites what it did not create.
- CLAUDE.md becomes a consumer-owned seed.
- install.sh installs the newest release by default (or --release
  vX.Y.Z), from the release's own tree, so a development checkout
  cannot leak into a new project; --managed-only takes only the
  managed core into an existing project; --working-tree is for
  Friday's own development.
- The self-check no longer leaves two temporary directories behind.

### What a consumer must do

Merge the sync pull request friday-propagate opens; then run
`bash .agents/bin/setup.sh` once in each clone.

## v1.0.1

Friday v1.0.1: documentation

No payload change; consumers have nothing to take.

- The READMEs keep to the present. History, dated evidence and the
  Claude-side runtime measurements moved to docs/history.md, and each
  rule links to its story there.
- Status (2026-10-25) replaces "Current operating context".
- Releases state the versioning rule: PATCH for documentation, MINOR
  for what runs (Skills, Git hooks, guard scripts), MAJOR for a large
  structural change.

## v1.0.0

Friday v1.0.0: the first tagged payload release

The managed core as pet_care and Finance hold it today, plus one change:

- safety-boundary.md: pushing a tag is a human-review checkpoint. An
  agent pushes a tag, including through --tags, --follow-tags or
  push.followTags, only when the user names the tag and its commit in
  the current turn. Enforced by instruction.

### What a consumer must do

Merge the sync pull request friday-propagate opens. Its .friday-lock.json then
records "tag": "v1.0.0".

From this release on, friday-propagate carries only releases.
