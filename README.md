# Friday

**English** · [繁體中文](./README.zh-TW.md)

> **中文摘要**：Friday 是可版控的 shared project baseline；個人層不在這裡。
> 先以 `--check` 預覽，再安裝封閉的 allowlist。衝突絕不覆寫，現有專案需經
> 人工審查後調和。

## Before you adopt Friday

- **Who it is for.** A developer or team that wants a reviewed, project-scoped
  baseline (Git policy, guards, Git skills) copied into its own repositories, and
  will review each update as a pull request. It is not a home for personal skills.
- **Two paths.** *Consume `ShenYo/Friday` releases* (the default): install the
  newest release, and take later ones as pull requests; see
  [Choose your path](./ADOPTING.md#choose-your-path). *Fork and cut your own
  releases* (advanced): see
  [Cutting releases from a fork](./ADOPTING.md#cutting-releases-from-a-fork).
- **Support.** macOS and Claude Code first. Codex is pending. Linux and Windows
  are not supported: CI also runs the test suites on ubuntu, but that is not a
  support promise.
- **Prerequisites.** Git, Bash and `jq` (`friday-propagate` also needs `gh`,
  authenticated, with push access to each consumer, to open pull requests).
  The test suites pass under Bash 3.2, which macOS ships,
  and under Bash 5.
- **What you can rely on.** Releases are versioned `vMAJOR.MINOR.PATCH`, but
  this is not strict semantic versioning: any release that changes a
  consumer-owned seed, a PATCH included, needs a hand edit, which its Seed
  changes section gives ([rules](./docs/releases.md#releases)). Every release
  from `v1.2.0` that changes a consumer-owned seed carries a migration note in
  its changelog entry
  ([Seed changes](./CHANGELOG.md#seed-changes)); CI enforces it with
  `bin/friday-seed-check`. There is no response-time promise, and Friday is
  maintained by one person.

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

## Status (2026-11-13)

> **中文摘要**：managed core 現為十七檔，最新 release 是 v1.3.0（2026-11-13），最近的
> protected-paths guard 會跟著 Bash 指令裡的 `cd`／`pushd`。
> pet_care 與 Finance 兩個 consumer 記錄的是 v1.2.0；
> v1.3.0 沒有改任何 seed，只需收 `friday-propagate` 開的 sync PR。已知限制：只有一位維護者、
> 兩個 consumer 都是維護者自己的私有 repository、新機器安裝尚未由獨立採用者 replay、
> external-runtime 收尾，以及 managed-core 更新 bot。

In place:

- The managed core: 17 files, listed in [`bin/managed-core.txt`](./bin/managed-core.txt).
  `v1.0.0` (2026-10-25) shipped the first 14; `.agents/bin/setup.sh` is the 15th,
  `.agents/hooks/guard-protected-paths.sh` the 16th, and `github-pr-verify` the 17th.
- Released as `v1.0.0` and `v1.0.1` (2026-10-25), then `v1.1.0` and `v1.1.1`
  (2026-10-26), `v1.1.2` (2026-11-03), `v1.1.3` (2026-11-04), `v1.1.4`
  (2026-11-10), `v1.2.0` (2026-11-11) and `v1.3.0` (2026-11-13): `v1.1.0` brought `.agents/bin/setup.sh`, the `CLAUDE.md` seed and
  release-based install (`install.sh` installs a release, not the checkout). Consumers receive the managed core only as a release
  (see [Releases](./docs/releases.md#releases)). `v1.2.0` brought the
  protected-paths guard and `github-pr-verify` into the managed core. `v1.3.0` made that guard follow `cd` and `pushd` in a Bash command.
- Both consumers, `pet_care` and Finance, record `v1.2.0`. `v1.3.0` changed no seed, so each
  only takes the sync PR that `friday-propagate` opens
  (see the [v1.3.0 note](./docs/changelog/v1.md#v130-2026-11-13)).
- CI is required on `main`: the test suites on ubuntu and macos, shellcheck, and
  gitleaks ([`ci.yml`](./.github/workflows/ci.yml)).

Known limits and open work:

- One maintainer, no named backup (see [Lifecycle governance](./docs/releases.md#lifecycle-governance-b06)).
- Adopted so far by two private repositories of the maintainer, `pet_care` and
  Finance; no third consumer yet.
- The new-machine install has not been replayed by an independent adopter.
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

`~/.Friday` is a convention, not a requirement: `install.sh`, `bin/friday-lock` and
`bin/friday-propagate` find the kit from their own location, so a clone anywhere works. The
pull request body that `friday-propagate` writes tells the reviewer to run `bash ~/.Friday/bin/friday-lock check .`; substitute
your own path there.

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
