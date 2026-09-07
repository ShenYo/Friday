# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` - `gh` does this automatically when run inside a clone.

## Remote-write preflight

Before any `gh` command that changes GitHub state, inspect `git remote -v`
and report the resolved repository and exact mutation. Obtain the user's
same-turn authorization for that specific target before creating, editing,
commenting on, closing, assigning, labelling, or linking an issue. Treat a
manual skill invocation as authorization only where its own instructions say
so; never infer it from a prior turn or a completed local step.

Read-only commands, including `gh issue view`, `gh issue list`, and
`gh api --method GET`, need no additional authorization. Do not create labels,
maps, tickets, or dependency edges merely while charting a Wayfinder map
unless the user has authorized those remote writes.

## Slices pulled out of Phase order

Every Phase ends in an owner checkpoint (C0-C3), and the next Phase does not
start before that checkpoint is signed off. A slice is sometimes pulled
forward anyway for a schedule reason — a demo date, an external deadline.
That is a one-off exception, and an exception must never be paid for by
loosening the rule it broke. When it happens:

1. Record it on the checkpoint issue the slice jumped: which slices, whose
   decision, and the date. Leave the checkpoint's acceptance criteria worded
   exactly as they were.
2. Open a one-off checkpoint issue for the pulled-forward slices, labelled
   `checkpoint` and `ready-for-human`. Do not fold them into an existing
   checkpoint's review scope — a jumped gate leaves work merged with nothing
   watching it, and the next scheduled checkpoint is usually weeks away.
3. Leave the slices' `phase:` labels alone. Relabelling makes the tracker
   claim the exception never happened.

What this forbids: rewriting a checkpoint from a Phase gate into a
"whatever has merged so far" gate, deleting a blocked-by edge to unblock a
checkpoint early, and renumbering phases to match the order work actually
landed in.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as
tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes /
  Decisions-so-far / Fog body. Create with
  `gh issue create --label wayfinder:map` after remote-write preflight.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api`
  on the sub-issues endpoint). Where sub-issues are unavailable, add the child
  to a task list in the map body and put `Part of #<map>` at the top of the
  child body. Labels are `wayfinder:<type>`: `research`, `prototype`,
  `grilling`, or `task`. Once claimed, assign it to the driving developer.
- **Blocking**: GitHub's native issue dependencies are canonical and
  UI-visible. Add an edge with
  `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`,
  where `<blocker-db-id>` is the blocker's numeric database id from
  `gh api repos/<owner>/<repo>/issues/<n> --jq .id` — never its `#number` or
  `node_id`. If dependencies are unavailable, use a
  `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is
  unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state
  open`, scoped to the map's sub-issues or task list), exclude tickets with an
  open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue
  in the `Blocked by` line) or an assignee, then select the first in map order.
- **Claim**: after remote-write preflight, run
  `gh issue edit <n> --add-assignee @me`; this is the session's first write.
- **Resolve**: after remote-write preflight, post the answer with
  `gh issue comment <n> --body "<answer>"`, close it with `gh issue close <n>`,
  then append a context pointer (gist + link) to the map's Decisions-so-far.
