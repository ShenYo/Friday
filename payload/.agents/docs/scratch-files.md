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
