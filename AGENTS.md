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
   bin/friday-lock check .                  → classified neither managed nor consumer-owned
   bash install.sh --check <empty git repo> → undeclared payload file
   ```

2. **Keep the mirrors byte-identical.** `.githooks/` holds copies of
   `payload/.agents/githooks/`, and this repository runs them. Copy the changed
   hook over and run `bin/friday-lock write .` in the **same commit**. Done when
   `bin/friday-lock check .` reports `in sync`. A forgotten copy shows up there
   as `behind`. `hooks-drift.yml` makes the same comparison on every pull
   request that touches a hook, and also fails a hook that is no longer
   executable, because git skips such a hook without stopping the commit.

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
- **Root `hooks.json` is a sha256 record** of the three mirrors. Hook
  *configuration* is `payload/.codex/hooks.json`. The two names look alike and
  are unrelated.
- **Run the checker inside an installed target.**
  `check-collaborative-git.sh` run from `payload/` reports
  `Claude guard link missing`, on `main` as well, because `payload/` is not an
  installation. Step 3 is the place to run it.
- **Edit `README.md` and `README.zh-TW.md` in the same commit.** Nothing here
  checks their parity, so the second edit is yours to remember.
- **Everything Friday needs lives in this repository.** Jarvis, the owner's
  personal layer, copies three hooks from here and gives nothing back. Keep the
  dependency one-way.
- **Adopting into a project that already has files** follows
  [`ADOPTING.md`](ADOPTING.md). `install.sh` only previews there. It never
  merges, and it refuses on conflict.
