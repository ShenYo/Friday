# Agent Instructions

Friday is the shared baseline for projects. Everything under `payload/`
**ships**: `install.sh` copies it into a new consumer, and
`bin/friday-propagate` carries each later change to the existing ones as pull
requests. A change in `payload/` is a change in every consumer.

Git and GitHub operations here follow
[`payload/.agents/docs/git-guideline/`](payload/.agents/docs/git-guideline/):
the same rules this repository ships, and the authority on them.

## Changing the payload

Each step ends on the condition that says it is done.

1. **Classify a new file in both lists.** These are `install.sh`'s
   `files=( … )` allowlist and
   [`bin/managed-core.txt`](bin/managed-core.txt): either a managed entry or a
   `!`-prefixed consumer-owned one. Both tools refuse a payload they cannot
   account for. Done when, with the new file in place, neither of these
   appears:

   ```text
   bin/friday-lock check .                  → classified neither managed nor consumer-owned
   bash install.sh --check <empty git repo> → undeclared payload file
   ```

2. **Keep the mirrors byte-identical.** `.githooks/` holds copies of
   `payload/.agents/githooks/`, and this repository runs them. Copy the changed
   hook over and run `bin/friday-lock write .` in the **same commit**. Done when
   `bin/friday-lock check .` reports `in sync`. That command is the one that
   compares the mirrors with the payload. A forgotten copy shows up there as
   `behind`.

3. **Prove it in a real install.** Run
   `bash tests/install-smoke.sh docs/temp/<purpose>/<date>`. Done when both
   `PASS:` lines print. This is the checker run that counts, because it
   self-checks inside a fresh install.

4. **After merge, propagate.** Run `bin/friday-propagate --dry-run <consumer>…`,
   read the file list, then run it without `--dry-run`. Done when every
   consumer that was `behind` has a pull request. A person merges each one.

## What the files will not tell you

- **Consumer-owned files reach new installs only.** Propagation carries managed
  core and skips every `!` entry, because a consumer reconciles its seeds by
  hand. To change existing consumers' `AGENTS.md`, `.gitignore`,
  `.claude/settings.json` or `.codex/hooks.json`, open a pull request in each.
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
