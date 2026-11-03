# Codex: pending verification items

> **中文摘要**：這份清單列出 Friday 中只有 Codex 本身才能驗證的項目，主要是 consumer 專案的 Codex hook 實際怎麼運作：會不會被呼叫、exit code 怎麼處理、多個 handler 的執行順序、逾時或出錯時會不會擋下。
>
> 這些行為目前只在 Claude Code 那邊量過。請 Codex 在新的 session 讀這份清單，在一次性的 fixture 裡逐項實測，把結果寫進 `docs/history.md`，並更新相關文件和本清單，最後開 PR。

You are Codex, on the owner's machine, in this Friday checkout. Friday wires the
shared guard into a consumer's Codex through the payload's `.codex/hooks.json`
(`PreToolUse`, matcher `^(Bash|apply_patch)$`). Friday checks that wiring only
statically.

The runtime behaviour was measured on the Claude side only
([measurements](./history.md#2026-10-22-runtime-behaviour-measured-on-the-claude-side)),
and [`safety.md`](./safety.md) and [`architecture.md`](./architecture.md) say
it is unverified for Codex. Measure it. Quote real output. A result you could
not measure is `UNVERIFIED`, with the reason; never infer one.

## How to work

1. Start from an up-to-date `main` on a new branch, `docs/codex-runtime-<date>`.
2. Build every probe in a disposable fixture under `docs/temp/codex-runtime/`,
   which is ignored by Git. Never use the real consumers (`pet_care`, Finance).
   The fixture is a small Git repository with its own `.codex/hooks.json`,
   whose probe handlers append to a log file and exit as each item needs.
3. **Owner:** trusting a hook lets it run with the owner's local privileges,
   so the owner reviews it first:
   - Before asking for trust, show the owner the fixture's exact `.codex/hooks.json`
     and every handler script.
   - Each handler may only append one line to the fixture's log file, optionally
     sleep, and then exit or print JSON, as its item needs. It must not touch the
     network or any path outside the fixture.
   - Once the owner has read them, ask them to open the fixture in Codex, trust
     the project, and trust its hooks in `/hooks`. Wait for them.
   - Each change to a probe handler needs a new review and a new trust, so plan
     the probes to need as few changes as possible.

   That a changed or new hook is skipped until it is trusted comes from
   [OpenAI's Codex hooks documentation](https://developers.openai.com/codex/hooks).
   F0 measures it for this fixture.
4. Record the results in [`history.md`](./history.md) as a new dated section,
   `### <date> Runtime behaviour measured on the Codex side`, in the style of
   the Claude-side section. Include the Codex version and the exact commands.
   Then correct the "unverified for Codex" sentences in
   [`safety.md`](./safety.md) and [`architecture.md`](./architecture.md) to
   match.
5. Update this file. Set each item's **Status** to its result, with the date
   and your `codex --version`. When an item passes, move it to [Done](#done).
6. Commit following Friday's [`AGENTS.md`](../AGENTS.md), push, and open one pull
   request. Then add the PR's link to each Status you set, in a second commit on
   the same branch. Ask the owner to **Approve as ShenYo** before merging.

Stop and report instead of working around anything a guard refuses.

## Items

### F0. An untrusted hook does not run

- **Question:** is a project hook really skipped until it is trusted?
- **Steps:** before the owner trusts the fixture's hooks, make one Bash call in
  the fixture and read the probe's log. After the trust, make the call again.
- **Done when:** the log is empty before the trust and has the entry after it.
  Record whether Codex warned about the untrusted hook.
- **Status:** open.

### F1. Callback delivery

- **Question:** does the project's `PreToolUse` hook run for every `Bash` call
  and every `apply_patch` edit?
- **Steps:**
  1. Run one Bash command in the fixture.
  2. Make one `apply_patch` edit in the fixture.
  3. Read the probe's log.
- **Done when:** the log has one entry per call, naming the tool. If either tool
  is missing from the log, the item is FAIL.
- **Status:** open.

### F2. Exit handling

- **Question:** which hook exits stop the call?
- **Steps:** for each of these, give the call, its result, and what the model was told:
  - exit 2 with a reason on stderr;
  - exit 1;
  - exit 127, as a command that is not found would give;
  - a JSON `deny` on stdout with exit 0;
  - a hook command that cannot be launched at all: its `command` names a file
    that does not exist;
  - a handler killed by a signal, `kill -9 $$`, rather than one that exits.
- **Done when:** all six are recorded separately, so that a crash, a launch
  failure and an exit code are not taken for one another. An earlier
  measurement of a user-level Codex hook, on codex-cli 0.164, found that a crash
  fails open. Confirm or correct that for project hooks.
- **Status:** open.

### F3. Handler order and several handlers

- **Question:** with two handlers under one matcher, do they run in declared
  order or concurrently? Do both run when the first blocks? When both block,
  which reason reaches the model?
- **Steps:** make the first handler sleep 2 s and then log, and the second log
  at once. Compare the timestamps. Repeat with both handlers blocking, each
  with a different reason.
- **Done when:** order, completion and the delivered reason are recorded.
- **Status:** open.

### F4. Timeout and fail-closed

- **Question:** when a handler overruns its `timeout`, does the call run or is
  it blocked?
- **Steps:**
  1. Give a handler `timeout: 2` and a 5 s sleep.
  2. Make one Bash call.
- **Done when:** the outcome is recorded. If the call runs, the payload's
  guards fail open on a timeout in Codex. Say so plainly in
  [`safety.md`](./safety.md).
- **Status:** open.

### F5. User-level and project hooks together

- **Question:** if this machine has a user-level Codex hook in
  `~/.codex/hooks.json` that refuses some command, do both it and the project's
  hook run? Can a permissive project hook lift the user-level refusal?
- **Steps:**
  1. First, set the fixture's `PreToolUse` hook to one that always allows and
     logs, and have it reviewed and trusted (step 3 above).
  2. Then, in the fixture, run a command the user-level hook refuses, chosen so
     that running it would be harmless and visible. Running
     `git commit --allow-empty --no-verify -m probe` in the fixture, for
     example, is refused by a guard that forbids `--no-verify`. If it ran, it
     would add only an empty commit to the disposable fixture, which
     `git log -1 --format=%s` shows.
  3. If this machine has no such user-level hook, mark the item UNVERIFIED and
     say so.
- **Done when:**
  - the transcript shows the user-level hook's refusal, not a command error;
  - the fixture's `git log` has no new `probe` commit;
  - the project hook's log records whether it ran too.
- **Status:** open.

## Done

Nothing yet.

