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
| Blank Git repository | Bootstrap the reviewed baseline | Preview, install the newest release, then preview again. |
| Existing project | Take the managed core, leave the project's own files | Run `--managed-only`, then reconcile the listed seeds by hand in a reviewed change. |
| Personal skills or preferences | Keep personal scope personal | Keep them in your personal layer; do not promote them into Friday. |
| Project-specific policy or checks | Preserve consumer ownership | Add a consumer overlay after reviewing the shared baseline. |

## Status (2026-11-11)

> **中文摘要**：managed core 現為十七檔，最新 release 是 v1.2.0（2026-11-11），最近加入
> protected-paths guard 與 `github-pr-verify`。
> pet_care 與 Finance 兩個 consumer 記錄的是 v1.1.4，
> 要手動 reconcile 後才跟上 v1.2.0。待辦：指定 backup maintainer、
> 真正的新機器 replay、第三個 consumer、external-runtime 收尾，以及 managed-core 更新 bot。

In place:

- The managed core: 17 files, listed in [`bin/managed-core.txt`](./bin/managed-core.txt).
  `v1.0.0` (2026-10-25) shipped the first 14; `.agents/bin/setup.sh` is the 15th,
  `.agents/hooks/guard-protected-paths.sh` the 16th, and `github-pr-verify` the 17th.
- Released as `v1.0.0` and `v1.0.1` (2026-10-25), then `v1.1.0` and `v1.1.1`
  (2026-10-26), `v1.1.2` (2026-11-03), `v1.1.3` (2026-11-04), `v1.1.4`
  (2026-11-10) and `v1.2.0` (2026-11-11): `v1.1.0` brought `.agents/bin/setup.sh`, the `CLAUDE.md` seed and
  release-based install (`install.sh` installs a release, not the checkout). Consumers receive the managed core only as a release
  (see [Releases](./docs/releases.md#releases)). `v1.2.0` brought the
  protected-paths guard and `github-pr-verify` into the managed core.
- Both consumers, `pet_care` and Finance, record `v1.1.4`. Each must reconcile
  `v1.2.0` by hand (see the [v1.2.0 note](./docs/changelog/v1.md#v120-2026-11-11)).
- CI is required on `main`: the test suites on ubuntu and macos, shellcheck, and
  gitleaks ([`ci.yml`](./.github/workflows/ci.yml)).

Pending:

- A named backup maintainer (see [Lifecycle governance](./docs/releases.md#lifecycle-governance-b06)).
- A real new-machine replay.
- A third genuine consumer.
- External-runtime closure: Codex and Gemini behaviour Friday does not verify.
- The managed-core update bot, so that a Friday release opens the consumer pull
  requests itself: [ShenYo/Friday#7](https://github.com/ShenYo/Friday/issues/7).

The agent-platform epic that groups the wider work is
[ShenYo/Friday#10](https://github.com/ShenYo/Friday/issues/10); an item above
without its own link has no open issue yet.

## Quick start

```sh
git clone https://github.com/ShenYo/Friday.git ~/.Friday   # once
git init my-project
bash ~/.Friday/install.sh --check my-project               # preview; writes nothing
bash ~/.Friday/install.sh my-project                       # the newest release
```

That installs the newest release into a blank repository. A project that already has its own
files takes `--managed-only` instead. Every step, the checks to run afterwards, and what to do
after cloning a consumer are in [Adopting Friday](./ADOPTING.md).

## Documents

| Document | Read it when |
| --- | --- |
| [Adopting Friday](./ADOPTING.md) ([繁體中文](./ADOPTING.zh-TW.md)) | You are installing Friday into a new or an existing project, setting up a fresh clone of a consumer, or starting an agent in a bootstrapped project. |
| [Architecture](./docs/architecture.md) | You want to know what the payload holds, which files a consumer owns and which Friday owns, or why it is built this way. |
| [Updating consumers](./docs/updating-consumers.md) | A consumer is behind a release, you want to see where one stands, or you are carrying a change out to consumers. |
| [Safety](./docs/safety.md) | You want to know what the guard refuses and where it stops, how Friday protects its own branch, or how to recover. |
| [Releases and lifecycle](./docs/releases.md) | You are cutting a release, or want the lock, the versioning rules and who maintains Friday. |
| [Verification and tests](./docs/verification.md) | You want to prove a change with the test suites. |
| [History](./docs/history.md) | You want the dated decisions, incidents and measurements behind the present rules. |
| [Changelog](./CHANGELOG.md) | You want a release's note. |
