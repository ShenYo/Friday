# Temporary Files and Durable Outputs

> **中文摘要**：暫存檔統一放在已忽略的 `docs/temp/` 子目錄；不得 stage、
> commit 或 force-add。清理必須取得明確授權；要保存為長期文件時，另行界定
> 範圍並移至受追蹤位置。

Use this shared policy for temporary agent artifacts. The repository root's
`.gitignore` ignores `docs/temp/`; keep every scratch artifact below a
purpose-specific subdirectory, never at `docs/temp/` itself.

## Locations

| Artifact | Location |
| --- | --- |
| Handoff | `docs/temp/handoff/<date-or-suffix>/` |
| Session retrospective | `docs/temp/retro/<date-or-suffix>/` |
| Pull-request visual evidence | `docs/temp/<branch-slug>/` |
| Required pre-edit snapshot | `docs/temp/backup/<branch-slug>/` |
| Other scratch work | `docs/temp/<purpose>/<date-or-suffix>/` |

Replace each `/` in a branch name with `-`. Add a date or suffix before
writing when an artifact with the same name could already exist; do not
overwrite a prior artifact.

## Rules

- Do not stage, commit, or force-add scratch artifacts.
- Cleanup, deletion, or replacement needs the user's explicit authorization.
- Promoting an artifact into tracked documentation is a separate scoped
  change: choose its durable location, review its content, and then add it
  deliberately.
- A consumer repository may designate a more specific project location for
  project-scoped handoff output. That project policy wins for the location;
  compatible handoff-skill requirements still apply.

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
