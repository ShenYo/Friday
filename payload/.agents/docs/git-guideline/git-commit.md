# Git Commit Guidelines

> **中文摘要**：commit 訊息格式採 Conventional Commits（`type(scope): summary`），
> 主旨祈使語氣、≤50 字元、不加句號；內文 72 字元換行、講「為什麼」。
> 提交前必跑 `git status` + `git diff --staged`，訊息只能描述實際 staged
> 的變更；agent 實質協作時可附 Co-Authored-By。提交後讀回原始訊息，且
> 未經使用者要求不得 commit/push。

## 1. Format: Conventional Commits

Use `type(scope): summary` (Conventional Commits). Allowed types for this repo:

- `feat` — a new user-facing capability or behavior.
- `fix` — a bug fix (patches incorrect behavior).
- `docs` — documentation only (README, `.agents/docs/*`, comments-as-docs).
- `refactor` — code change that neither fixes a bug nor adds a feature.
- `test` — adding or correcting tests only.
- `chore` — routine maintenance (deps, config) with no source behavior change.
- `build` — build system or external dependency changes.
- `ci` — CI pipeline/config changes.

`scope` is optional, a noun in parens, e.g. `fix(parser)` (Conventional Commits).

## 2. Summary line rules

- Imperative mood: it must complete "If applied, this commit will ___" (Beams).
  Write `Add validation`, not `Added validation` or `Adds validation`.
- Target ≤50 characters; hard cap 72 (Beams).
- No trailing period (Beams).
- Lowercase after `type(scope): ` — the Conventional Commits spec examples
  use lowercase summaries; Beams' "capitalize" rule applies to prefix-less
  messages and the prefix convention wins here.

## 3. Body rules

- Blank line between summary and body (Beams).
- Wrap body text at 72 characters (Beams).
- Explain WHAT changed and WHY — not how; the diff already shows how (Beams).
- If an issue exists, reference it in the body or a footer line, e.g.
  `Refs #123`. Do not
  invent a reference if none exists.

## 4. Atomicity

- One logical change per commit. If the staged diff mixes unrelated concerns
  (e.g. a bug fix + an unrelated formatting pass), split into separate commits
  before committing — use `git add -p` or stage files individually.
- Never commit commented-out code or debug output (`console.log`, `print`,
  stray `debugger`). If present in the diff, remove it before staging, or stop
  and tell the user rather than committing it.

## 5. AI-agent-specific rules (this repo)

- (a) `Co-Authored-By` is optional. Add it only when an agent materially
  co-authored the commit; human-driven commits may omit it. When adding it,
  name the model actually used, e.g. `Co-Authored-By: Claude Sonnet 5`.
- (b) Before writing the message, run `git status` and `git diff --staged`
  and read the output. The message must describe the actual staged diff, not
  what the conversation intended to do. If they diverge, stop and reconcile
  (re-stage or ask) before committing.
- (c) Never run `git commit` unless the user asked for a commit in this turn.
  Never run `git push` unless the user asked to push. Do not infer consent
  from "looks done" — this matches the surgical-changes / fail-loud rules in
  `.agents/docs/agent-rules.md`.
- (d) If `git branch --show-current` reports `main` (the default branch),
  create and switch to a feature branch first — never commit directly to
  `main`.

## 6. Worked examples

**Good — feat, with body.** Domain nouns come from the project's glossary
(`CONTEXT.md`), and the terms its Avoid list rejects are wrong in a commit
message too, not only in the UI:

```
feat(orders): gate the summary on confirmed line items

The summary totalled parsed values before anyone had confirmed them,
so an unreviewed number could pass for a checked figure. Total only
line items whose record is confirmed and that carry a value and a
unit.

Refs #123

Co-Authored-By: Claude Sonnet 5
```

**Good — docs-only, summary line only:**

```
docs: clarify the retry wording in the spec
```

**BAD — violations called out:**

```
Fixed stuff.

updated some files, also cleaned up formatting and added a new
report screen because it seemed useful, still has a console.log
in there for now
```

Violations: no `type(scope):` prefix (Conventional Commits); subject not
imperative and ends with a period (Beams); body describes *how/whatever*
instead of what/why, and mixes three unrelated concerns (formatting, a new
feature, and a fix) in one commit — should be split (atomicity, rule 4);
leaves debug output (`console.log`) committed (rule 4).

## 7. Pre-commit checklist

1. Ran `git status` and `git diff --staged` and actually read the output.
2. Diff contains exactly one logical change; no commented-out code or debug
   output remains staged.
3. Summary line: `type(scope): summary`, imperative, ≤50 chars (72 hard cap),
   lowercase after the prefix, no trailing period.
4. Body (if any) wraps at 72 chars, explains what/why, references the
   issue if one exists.
5. If an agent materially co-authored the change, the message names the actual
   model in `Co-Authored-By`; its absence is valid for human-driven commits.
6. Not on `main`; user actually asked for this commit (and for any push).

## 8. Post-commit read-back

Immediately after committing, read the raw commit message:

```sh
git show -s --format=%B HEAD
```

Confirm the rendered message has the intended subject, real line breaks, and
Markdown bullets. In particular, reject a literal `\\n` where a newline was
intended. Report any mismatch; do not amend a commit unless the user asks in
the same turn.
