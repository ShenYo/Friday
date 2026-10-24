# Git Commit Guidelines

> **中文摘要**：commit 訊息格式採 Conventional Commits（`type(scope): summary`），
> 主旨祈使語氣、≤50 字元、不加句號；內文 72 字元換行、講「為什麼」。
> 提交前必跑 `git status` + `git diff --staged`，訊息只能描述實際 staged
> 的變更；agent 實質協作時可附 Co-Authored-By。提交後讀回原始訊息。
> commit 與 push（非 default branch）由 agent 自行判斷，條件是一個 commit
> 只承載一個 task 的 context，且 staged diff 不含敏感資訊；直接推 default
> branch、merge PR、開啟 auto-merge 仍需人工審核。

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
- Prefer lowercase after `type(scope): `. The Conventional Commits spec's
  examples use lowercase summaries, though the spec itself sets no rule, and
  Beams' "capitalize" rule applies to prefix-less messages. This is style, so
  `commit-msg` only prints a note for an ordinary capitalised word and lets the
  commit through. A summary that starts with a proper noun (`README`,
  `GitHub`), a `code` name, a number, or a language other than English starts
  however it naturally does.

## 3. Body rules

- Blank line between summary and body (Beams).
- Wrap body text at 72 characters (Beams).
- Explain WHAT changed and WHY — not how; the diff already shows how (Beams).
- If an issue exists, reference it in the body or a footer line, e.g.
  `Refs #123`. Do not
  invent a reference if none exists.

## 4. Atomicity

- One logical change per commit, and one task's context per commit. If the
  staged diff mixes unrelated concerns (e.g. a bug fix + an unrelated
  formatting pass), or mixes work from two different requests, split into
  separate commits before committing — use `git add -p` or stage files
  individually. Do not run a blanket `git add -A` across a mixed working tree.
  If the tree cannot be separated cleanly, stop and say so rather than
  committing a mixture.
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
- (c) Committing, and pushing a non-default branch, are at the agent's
  discretion — see the default posture in
  [`safety-boundary.md`](safety-boundary.md). That discretion is conditional
  on the atomicity rule in section 4 and on the traceability rules in that
  document: one commit carries one task's context, and a commit nobody can
  attribute later is worse than an uncommitted change. Pushing directly to the
  default branch, merging a pull request, and enabling auto-merge remain
  human-review checkpoints.
- (d) If `git branch --show-current` reports `main` (the default branch),
  create and switch to a feature branch first — never commit directly to
  `main`.
- (e) Before staging, read the staged diff and confirm it introduces no
  credential, key, token, private key, password, connection string, cookie, or
  personal identifier the repository does not already carry on purpose. If it
  does, stop without committing and report the file and the kind of value, not
  the value. Before pushing, confirm the same for every commit going out.

## 6. Worked examples

**Good — feat, with body:**

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
   lowercase after the prefix where it reads naturally, no trailing period.
4. Body (if any) wraps at 72 chars, explains what/why, references the
   issue if one exists.
5. If an agent materially co-authored the change, the message names the actual
   model in `Co-Authored-By`; its absence is valid for human-driven commits.
6. Not on `main`. The commit covers one task's context only. The staged diff
   carries no sensitive value. A push to the default branch, a merge, or
   enabling auto-merge has explicit same-turn authorization; an ordinary commit
   or feature-branch push does not need one.

## 8. Post-commit read-back

Immediately after committing, read the raw commit message:

```sh
git show -s --format=%B HEAD
```

Confirm the rendered message has the intended subject, real line breaks, and
Markdown bullets. In particular, reject a literal `\\n` where a newline was
intended. Report any mismatch; do not amend a commit unless the user asks in
the same turn.
