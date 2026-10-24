# Agent Instructions

Friday is the shared baseline for projects. Everything under `payload/`
**ships**: `install.sh` copies all of it into a new consumer, and
`bin/friday-propagate` carries later changes to the **managed core** of
existing ones as pull requests. A managed-core change reaches every consumer.
A consumer-owned file reaches new installs only; see below.

Git and GitHub operations here follow
[`payload/.agents/docs/git-guideline/`](payload/.agents/docs/git-guideline/):
the same rules this repository ships, and the authority on them.

## Changing the payload

Each step ends on the condition that says it is done.

1. **Add or remove a file in all three places.** These are `install.sh`'s
   `files=( … )` allowlist,
   [`bin/managed-core.txt`](bin/managed-core.txt) (either a managed entry or
   a `!`-prefixed consumer-owned one), and the `expected` inventory at the top
   of `tests/install-smoke.sh`. The first two tools refuse a payload they
   cannot account for. The smoke test fails in step 3 when its inventory and
   the payload disagree, and it names the path and the direction. Done when,
   with the change in place, neither of these appears:

   ```text
   bin/friday-lock check <any consumer>     → classified neither managed nor consumer-owned
   bash install.sh --check <empty git repo> → undeclared payload file
   ```

2. **A changed hook runs here first.** This repository's `core.hooksPath` is
   `payload/.agents/githooks`, so the hook you edit is the one your next
   commit and push run. There is no copy to keep in step. A broken hook stops
   Friday's own commits before it can reach a consumer. Done when a commit on
   your branch has run the changed hook, and the hook is still mode 100755:
   `hooks-drift.yml` fails a payload hook that is not executable, because git
   skips such a hook without stopping the commit. A clone that has not set
   `core.hooksPath` runs no hook at all. The README says how to set it.

3. **Prove it in a real install.** Run
   `bash tests/install-smoke.sh docs/temp/<purpose>/<date>`. Done when both
   `PASS:` lines print. This is the checker run that counts, because it
   self-checks inside a fresh install.

4. **After merge, propagate from a clean, current `main`.** Propagation
   copies the payload *as checked out here* and labels it with the last commit
   that touched `payload/`. That goes wrong in two directions:

   - A checkout behind `origin/main` lacks the change, so it cannot carry it.
     Consumers read `in sync`, or `ahead`, which is refused, and nothing is
     opened.
   - A feature branch, or uncommitted edits under `payload/`, go out as if
     merged, labelled with a commit that does not contain them.

   Run **one propagation at a time**, and keep this checkout and every
   consumer idle from the checks below until the real run finishes, not only
   while each invocation runs. That includes a second invocation by the same
   agent. A run reads mutable state many times: the payload commit at the
   start, and again per consumer inside `friday-lock check` and
   `friday-lock write`; each consumer's clean state; and the payload files when
   it copies them. A change in either repository between those reads ships
   under the wrong label, gets recorded against a different commit, or is
   overwritten -- and two overlapping runs can switch each other's worktree so
   a sync commit lands on the consumer's `main`. ShenYo/Friday#29 tracks
   making a run read each thing once.

   So first run `git switch main && git pull --ff-only`. Then confirm that
   `git status --porcelain -- payload/` prints nothing and that
   `git rev-parse HEAD` equals `git rev-parse origin/main`. After that,
   `git log -1 --format=%h -- payload/` names the commit the sync branch and
   the lock will carry. For a merged pull request this is the PR's own commit,
   not the merge commit, because git skips a merge whose `payload/` matches
   its parent's. Then run `bin/friday-propagate --dry-run <consumer>…`, read
   the file list, and run it again without `--dry-run`. Done when every
   consumer that was `behind` has a pull request. A person merges each one.

## What the files will not tell you

- **Consumer-owned files reach new installs only.** Propagation carries managed
  core and skips every `!` entry, because a consumer reconciles its seeds by
  hand. To change one of those files (the `!` entries in
  `bin/managed-core.txt`) in existing consumers, open a pull request in each.
- **Run the checker inside an installed target.**
  `check-collaborative-git.sh` run from `payload/` reports
  `Claude guard link missing`, on `main` as well, because `payload/` is not an
  installation. Step 3 is the place to run it.
- **Edit `README.md` and `README.zh-TW.md` in the same commit.** Nothing here
  checks their parity, so the second edit is yours to remember.
- **Everything Friday needs lives in this repository, and Friday depends on
  no other repository, the personal layer included.** Consumers receive copies
  through `install.sh` and `friday-propagate`, and Friday tracks them only
  through their `.friday-lock.json`. Do not add a reference to, or a record of,
  any repository that is not a consumer.
- **A merged pull request can be missing its last commit.** GitHub can keep
  reporting a PR's old head for a while after a push has moved the branch, and
  a merge taken then uses the old head. #24's merge commit `582a286` was built
  from head `77b2dc2`, so `f9868c3` was left out. Merge with the head you mean
  to merge, read from the **remote** branch:

  ```sh
  gh pr merge <n> --match-head-commit "$(git ls-remote origin refs/heads/<branch> | cut -f1)"
  ```

  It refuses when the PR's head differs from that SHA. A push after the merge
  still escapes, so afterwards run `git fetch origin` and then
  `git cherry origin/main <branch>`: it lists commits left behind. It cannot
  judge a squash merge, where every commit shows as left behind. This
  repository uses merge commits.
- **Adopting into a project that already has files** follows
  [`ADOPTING.md`](ADOPTING.md). `install.sh` only previews there. It never
  merges, and it refuses on conflict.
