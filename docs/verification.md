# Verification and tests

> **中文摘要**：如何用 `tests/` 底下的測試驗證 Friday 本身。
> 本文件只有英文版。

Run `bash` [`tests/install-smoke.sh`](../tests/install-smoke.sh)
`/absolute/path/to/retained-test-output`.
The check creates disposable Git fixtures, installs the repository's actual
payload with `--working-tree`, and retains evidence for review. It never
installs into an existing project. Cleanup is a separate, explicitly authorized
operation.

[`tests/install-release.sh`](../tests/install-release.sh) proves the release
install and `--managed-only` in scratch Friday repositories with their own
origin and tags: the newest release or a named one is installed whatever branch
or edits the checkout holds, a tag `friday-propagate` would refuse is refused, a
release older than the flags installs under its old interface, and the seeds of
an existing project are left byte for byte alone. It prints `all N passed`.

[`tests/setup.sh`](../tests/setup.sh) proves the setup script case by case, each
in a scratch clone, and prints `all N passed`.
