# Temporary Files and Durable Outputs

> **中文摘要**：暫存檔統一放在已忽略的 `docs/temp/` 子目錄；不得 stage、
> commit 或 force-add。清理必須取得明確授權；要保存為長期文件時，另行界定
> 範圍並移至受追蹤位置。handoff 例外：每個 worktree 一個 `handoff.md`，以日期分
> section，同日改寫、隔日在最上方新增（見 Handoff documents）。

Use this shared policy for temporary agent artifacts. The repository root's
`.gitignore` ignores `docs/temp/`; keep every scratch artifact below a
purpose-specific subdirectory, never at `docs/temp/` itself.

## Locations

| Artifact | Location |
| --- | --- |
| Handoff | `<main-root>/docs/temp/handoff/<worktree>/handoff.md` ([Handoff documents](#handoff-documents)) |
| Session retrospective | `docs/temp/retro/<date-or-suffix>/` |
| Pull-request visual evidence | `docs/temp/<branch-slug>/` |
| Required pre-edit snapshot | `docs/temp/backup/<branch-slug>/` |
| Other scratch work | `docs/temp/<purpose>/<date-or-suffix>/` |

Replace each `/` in a branch name with `-`. Add a date or suffix before
writing when an artifact with the same name could already exist; do not
overwrite a prior artifact. A handoff is the exception, as
[Handoff documents](#handoff-documents) describes.

## Rules

- Do not stage, commit, or force-add scratch artifacts.
- Cleanup, deletion, or replacement needs the user's explicit authorization,
  except revising today's own section of a handoff.
- Promoting an artifact into tracked documentation is a separate scoped
  change: choose its durable location, review its content, and then add it
  deliberately.
- A consumer repository may designate a more specific project location for
  project-scoped handoff output. That project policy wins for the location;
  compatible handoff-skill requirements still apply. Such a location replaces
  `<main-root>/docs/temp/handoff/` in [Handoff documents](#handoff-documents),
  whose other rules still apply: a relative location is resolved against
  `<main-root>`, and the ignore check and the sandbox fallback use it in place
  of `docs/temp/handoff/`.

## Handoff documents

> **中文摘要**：handoff 放在主 checkout 的 `docs/temp/handoff/<worktree>/handoff.md`，
> 每個 worktree 一個檔案；每天一個 `## YYYY-MM-DD` section，最新在最上面，每個
> section 都是完整的當前狀態。同日改寫同一 section，隔日才新增 section。

This applies to every handoff, including when a handoff Skill suggests another
location, such as an OS temporary directory. The Skill's other requirements
still apply: redacting sensitive information, referring to artifacts rather
than duplicating them, and any section it asks for.

1. **Location.** The handoff location is `<main-root>/docs/temp/handoff/`, or
   a consumer's designated location. Its folder for this worktree is found or
   claimed as item 2 says. `<main-root>` is the primary checkout, so every
   worktree writes to one place: take the output of
   `git rev-parse --path-format=absolute --git-common-dir`, which must be a
   single line ending in `/.git`, and drop that suffix. Use
   `git rev-parse --show-toplevel` as `<main-root>` instead when it is not (a
   bare repository, a separate git directory, or Git older than 2.31), or
   when `git -C <main-root> check-ignore -q docs/temp/handoff/<worktree>/handoff.md`
   fails (the result is not a checkout, or does not ignore `docs/temp/`).
   `<worktree>` is the basename of `git rev-parse --show-toplevel`, each
   Unicode code point outside `[A-Za-z0-9._-]` replaced by `-`, with `_`
   prepended if the result starts with `-` or `.`. If writing under
   `<main-root>` is refused, for example by a sandbox, use the current
   worktree's own copy of that location (`docs/temp/handoff/` by default) as
   the handoff location, the fallback location, and report the path.
2. **One file.** The folder holds only `handoff.md`, created if absent:

   ```markdown
   # Handoff: <worktree>

   Worktree: `<output of git rev-parse --show-toplevel>`

   ## <YYYY-MM-DD>
   ```

   A folder is this worktree's only if its `handoff.md` has a `Worktree:` line
   whose value inside the backticks is exactly the output of
   `git rev-parse --show-toplevel`. Find it by reading that line in every
   `*/handoff.md` under the handoff location, never by guessing from the folder
   name. Leave alone every other folder, including one whose `handoff.md` is
   missing or lacks that line. When none matches, create the first of
   `<worktree>`, `<worktree>-2`, `-3`, and so on that does not exist, with a
   plain `mkdir` (no `-p` on that folder), and write `handoff.md` at once; if
   `mkdir` fails because the folder appeared, search again. If more than one
   folder matches, use the one whose top date is newest.
3. **Dated sections.** Each day is one `## <YYYY-MM-DD>` section, the date
   being the machine's local date (`date +%F`), newest first. Headings inside a
   section are level 3 or deeper. Every section is the complete current state;
   it may point to an earlier section by date rather than copy it. Re-read the
   file immediately before writing. If today's section exists, revise it in
   place, merging what another session added into the current state. Otherwise
   insert a new section before the first existing `## ` date heading, or at the
   end when there is none. Never change an earlier day's section.
4. **Picking up.** Find the matching folder as item 2 says, in both the
   handoff location and the worktree's own fallback location. If it exists in
   both, start from the file whose top date is newer (the fallback file on a
   tie). When you next write under the handoff location, carry over the
   sections it lacks from the other, and merge a section both hold for the same
   date as item 3 merges another session's additions. Read `handoff.md` from
   the top section, and go further down only where it points.
5. **Older files.** Files and folders under `docs/temp/handoff/` from before
   this layout stay where they are, and are never matched by item 2.

## Optional external workflow trackers

> **中文摘要**：個人或第三方的 tracker 可選用，但其暫存輸出一律以 Git
> repository root 為基準，放在專案的
> `docs/temp/matt-pocock/<feature>/<unique-suffix>/`；無法辨識 root 或功能不存在
> 時停止，不建立替代檔案或寫入個人設定目錄。

This is a location contract for optional external workflow trackers, including
the Matt Pocock local tracker. It is not an installation, fallback, or
project-required dependency.

1. Resolve the repository root with `git rev-parse --show-toplevel` before
   choosing a destination. If that command cannot produce a repository root,
   stop without writing anything.
2. Use a safe one-level feature slug only: it must match
   `^[A-Za-z0-9][A-Za-z0-9._-]*$` and must not contain `/`, `\\`, or `..`.
3. Place tracker output below
   `<repo>/docs/temp/matt-pocock/<feature>/<date-or-unique-suffix>/`. Use a
   collision-safe suffix such as `YYYYMMDD-HHMMSS-<counter-or-random>`, confirm
   that destination does not already exist before writing, and never overwrite
   a prior tracker run.
4. Do not use a CWD-relative `.scratch/` path and do not write tracker output
   into a personal Skill home such as `~/.agents`, or a vendor Skill directory.

If the personal or vendor Skill is unavailable, report the optional capability
as unavailable and stop that optional workflow. Do not install, copy, emulate,
or substitute the Skill, and do not make a project-required workflow depend on
it. This policy controls only project-local output location; it does not claim
to enforce a runtime Skill invocation, selection, or precedence rule.
