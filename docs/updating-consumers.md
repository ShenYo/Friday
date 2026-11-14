# Updating consumers

> **中文摘要**：如何讓既有 consumer 跟上某個 release：手動調和的流程、用
> `friday-lock` 查看 consumer 的狀態，以及維護者用 `friday-propagate`
> 把變更以 pull request 帶到各個 consumer。本文件只有英文版。

## Updating an existing consumer

An existing consumer is brought up to a release by `bin/friday-propagate`, which
opens the pull request (see [Staying current](../ADOPTING.md#staying-current)). Doing it by
hand is a reviewed reconciliation, not an installer upgrade: `--managed-only`
is for adopting the managed core, and a managed file that moved is a `CONFLICT`
there, never overwritten. Preview which files differ, against the release you
mean to take:

```sh
FRIDAY=~/.Friday
TARGET='/absolute/path/to/consumer'

bash "$FRIDAY/install.sh" --managed-only --check --release vX.Y.Z "$TARGET"
```

Read every `CONFLICT` and reconcile it in a reviewed consumer change. Sync
only the seventeen managed-core paths listed under
[Ownership](./architecture.md#ownership-managed-core-seeds-and-overlays), taking each from the release
(`git -C "$FRIDAY" show "vX.Y.Z:payload/$rel" > "$TARGET/$rel"`, and keep the
mode of the Git hooks and scripts). Preserve consumer seeds, runtime
integration, and overlays; do not copy a whole `.agents/` directory. Then run
`bash .agents/bin/setup.sh` in the consumer (`--check` first to preview) to wire
the clone, and `bash "$FRIDAY/bin/friday-lock" write "$TARGET"` to refresh the
lock.

A release that changes a seed needs a hand edit the sync does not make, because propagation
never writes a seed. Its changelog entry has a `### Seed changes` section (capability, who
is affected, action, check), in the format [`CHANGELOG.md`](../CHANGELOG.md#seed-changes) sets
out, and `friday-propagate` copies that section into the pull request body. Make the edit in the
same pull request, then run the check the section names. When the body says `Seed changes: none`,
nothing needs reconciling by hand.

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

## Knowing where a consumer stands

`install.sh` writes `.friday-lock.json` into the target: the Friday commit it
was installed from, the release tag that names that payload when there is one
(always, for a release install; `null` when a `--working-tree` payload matches
no release), and the sha256 of every managed-core file as installed.

[`bin/friday-lock`](../bin/friday-lock) reads it back. Only a payload consumer
has one. A repository that wants one of the payload's hooks without adopting
the payload keeps its own copy, and Friday does not track it.

```sh
bin/friday-lock check <target>     # or run it from inside the consumer
bin/friday-lock write <target>     # refresh after a reviewed reconciliation
```

`check` compares the consumer with the Friday checkout it runs from, so on a
checkout whose payload is ahead of the release the consumer took, it reads
`behind`: Friday has moved on, not the install went wrong. To check a consumer
against the release it took, name it: `FRIDAY_TREE=vX.Y.Z bin/friday-lock check
<target>`.

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

[`bin/managed-core.txt`](../bin/managed-core.txt) is the single source of truth
for which files are managed and which are consumer-owned. A payload file listed
as neither fails the tool loudly rather than shipping unchecked
([history](./history.md#2026-10-22-the-git-hooks-were-missing-from-the-managed-core-list)).

## Carrying a change out to consumers

A managed-core change has to reach every consumer, and doing that from memory
leaves stale counts behind
([history](./history.md#2026-10-22-the-git-hooks-were-missing-from-the-managed-core-list)).

Run it from a `main` that matches `origin/main`; step 4 of
[`AGENTS.md`](../AGENTS.md#changing-the-payload) says how to confirm that. The
run pins the commit a release tag names (see [Releases](./releases.md#releases)) and carries only that
commit's tree, so an uncommitted payload edit, a payload change merged to
`main` but not yet released, or a Friday commit made while it runs, cannot
reach a consumer.

```sh
bin/friday-propagate --dry-run ~/Github_Folks/pet_care ~/Desktop/Finance_App_Project
bin/friday-propagate           ~/Github_Folks/pet_care ~/Desktop/Finance_App_Project
```

Per consumer it asks [`friday-lock`](../bin/friday-lock) where that repository
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
