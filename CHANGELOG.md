# Changelog

> **中文摘要**：這裡是 Friday 每個 release 的 release note，最新的在最上面。
> release 的 pull request 把 `Unreleased` 的條目改名為版本號；annotated tag 的訊息就是該條目，
> GitHub Release 由 tag 建立，文字相同。PATCH 一行即可；MINOR 與 MAJOR 要寫改了什麼、為什麼、
> consumer 必須做什麼。

How entries are written. A change that a release will carry is added under
`## Unreleased` as it merges. The release's pull request renames that section
to `## vX.Y.Z (YYYY-MM-DD)`, the date being the tag's own date, so the entry is
reviewed with the release. The annotated tag's message is that entry, and the
GitHub Release is created from the tag with the same text (see
[Releases](./README.md#releases)). A PATCH entry may be one line. A MINOR or
MAJOR entry says what changed, why, and what a consumer must do.

## Unreleased

Documentation only, so the next release is a PATCH (v1.1.1).

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

## v1.1.0 (2026-10-26)

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

## v1.0.1 (2026-10-25)

Friday v1.0.1: documentation

No payload change; consumers have nothing to take.

- The READMEs keep to the present. History, dated evidence and the
  Claude-side runtime measurements moved to docs/history.md, and each
  rule links to its story there.
- Status (2026-10-25) replaces "Current operating context".
- Releases state the versioning rule: PATCH for documentation, MINOR
  for what runs (Skills, Git hooks, guard scripts), MAJOR for a large
  structural change.

## v1.0.0 (2026-10-25)

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
