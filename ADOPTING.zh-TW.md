# 採用 Friday

> **摘要**：`install.sh` 預設安裝最新的 release，不是這個 checkout 目前的內容；
> 新專案用 `install.sh`，既有專案用 `--managed-only` 只拿 managed core、seeds 留給專案自己
> 調和；clone 之後執行 `setup.sh`；之後由你自己（採用者）在更新過的 checkout 執行 `friday-propagate` 開 pull request，upstream 不會替你開。

## 選擇路徑

- **使用 `ShenYo/Friday` 的 release（預設）。** 除了 upstream repository 之外你什麼都不需要：clone
  它，`install.sh` 會安裝它最新的 annotated release tag。之後的 release 以 pull request 抵達你的專案，
  而 pull request 是你自己開的：更新你的 Friday checkout，再執行 `friday-propagate`（見
  [持續保持最新](#持續保持最新)）；upstream 不會在你的 repository 開 pull request。改動 seed 的 release
  會在它的 changelog 條目中說明（[Seed changes](./CHANGELOG.md#seed-changes)，英文）。除了 fork
  那一節，以下都是針對這條路徑寫的。
- **Fork 並發行自己的 release（進階）。** 安裝程式安裝的是 release，絕不是 checkout，所以 fork 必須自己在
  `main` 上建立形如 `vMAJOR.MINOR.PATCH` 的 annotated tag，並推到 fork 的 `origin`。producer slug
  設定在 `bin/friday-lock`，只對該修改之後發行的 release 生效，所以第一個 fork release 要在第一次安裝
  consumer 之前發行。步驟見[從 fork 發行 release](#從-fork-發行-release)。

兩種入口。空 repository 只要幾個指令；既有專案需要一次判斷，而這份文件之所以存在，
就是因為那個判斷從來沒有被寫下來。

## 先備條件

先備條件是 Git、Bash 與 `jq`；`friday-propagate` 另需 `gh`，且須已登入，並對每個 consumer 有 push 權限。`.agents/bin/setup.sh` 與 `CLAUDE.md` seed 從 `v1.1.0` 起才附帶；更早的 release
（`v1.0.0`、`v1.0.1`）兩者都沒有，它的安裝程式自己為 clone 接線，從這類 release 安裝的專案也沒有 `setup.sh`
可在 clone 之後執行（那裡全新 clone 缺少的是 `git config core.hooksPath .agents/githooks`）。安裝程式是本機
Friday checkout 裡的一支腳本；還沒有的話，一行就能取得（路徑只是慣例，不是必要條件：腳本會從自己所在的位置找到 kit）：

```sh
git clone https://github.com/ShenYo/Friday.git ~/.Friday
```

那個 checkout 是開發用 checkout，常常停在 feature branch 上或有未提交的修改，所以 `install.sh`
絕不安裝它手上的內容。它安裝的是一個 release：最新的 annotated tag `vX.Y.Z`，挑選與檢查的方式與
`friday-propagate` 相同（在 `origin` 上是同一個 tag object，且可從 `main` 到達）。它會匯出該 release
的 tree，並在其上執行該 release 自己的 `install.sh`，因此不論 checkout 長什麼樣子，lock 記錄的都是
release 的 commit 與 tag。`--working-tree` 則照原樣安裝這個 checkout，會附上警告，
只供開發 Friday 本身使用。

## 空 repository

```sh
FRIDAY=~/.Friday
TARGET=<你的新 repo>

git -C "$TARGET" init

bash "$FRIDAY/install.sh" --check "$TARGET"   # 預覽，不寫入任何東西
bash "$FRIDAY/install.sh" "$TARGET"           # 最新的 release
bash "$FRIDAY/install.sh" --check "$TARGET"   # 每個檔案行都應該是 IDENTICAL
```

要釘選某個 release 而不是取最新的，在安裝指令加上 `--release vX.Y.Z`。沒有合格的 release 時
（完全沒有，或最新的不是 annotated、不在 `origin` 上、或不在 `main` 上），安裝會拒絕，並說明怎麼 fetch
或建立一個；它不會寫入任何東西。

安裝最後會執行 payload 自己的 self-check，因此 runtime 接線出錯時會在當下就失敗，
而不是等到有人真正依賴那個邊界時才出事。

然後驗證，而不是假設。`FRIDAY_TREE` 讓 `friday-lock` 讀 release 本身，所以這是拿專案的位元組對照那個 release；
單純的 `friday-lock check` 讀的是 Friday checkout 的 working tree，在開發用 checkout 上它比 release 新，
會對一個正確的安裝回報 `behind`：

```sh
# vX.Y.Z 是安裝輸出第一行 "release: vX.Y.Z (commit ...)" 的 tag
FRIDAY_TREE=vX.Y.Z bash "$FRIDAY/bin/friday-lock" check "$TARGET"   # 預期：status: in sync
(cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)
git -C "$TARGET" status --short
```

審查完產生的 worktree diff 之後，再依專案自己的規則，另外決定是否、以及如何 commit 它。

### 由 agent 執行安裝時

這一節適用於空 repository。既有專案有預期中的 seeds，改走下一節的 `--managed-only`。
預覽和安裝是兩個分開的決定，agent 只能自行做第一個。

1. **檢查輸入。** `TARGET` 是帶有 `.git` 目錄的 repository 根目錄。`FRIDAY`
   是另一個目錄，裡面有 `install.sh` 與 `payload/`，而且是乾淨的 `main` checkout：
   `git -C "$FRIDAY" symbolic-ref --short HEAD` 印出 `main`，`git -C "$FRIDAY" status
   --porcelain` 什麼都不印。這個 checkout 自己的 `install.sh` 會啟動整個流程（它挑選 release，
   再交給該 release 的安裝程式），所以它應該是經審查的那一份。不是的話，停下來讓使用者選擇。
   在這項成立之前，不執行 `FRIDAY` 裡的任何東西，因為預覽會執行它的 `install.sh`。
   也要寫下使用者指定的 release，或他們要的是最新的。路徑和 release 都寫下來，才算完成。
2. **預覽。** 只以完整路徑執行 `bash "$FRIDAY/install.sh" --check "$TARGET"`（有指定 release
   時加上 `--release vX.Y.Z`），回報 `release:` 那一行和完整的 `NEW`／`IDENTICAL` 結果。只要出現
   任何 `CONFLICT` 或非零的結束碼，流程就在這裡停止。不要為了讓預覽通過而修改任何一個 repository。
3. **請求安裝。** 預覽不代表授權寫入，一開始交辦這件事的那則訊息也不算。只有在
   使用者以新的訊息點名這個 `TARGET` 和這個 release 之後，才能安裝。
4. **安裝並驗證。** 先再次確認 `FRIDAY` 是乾淨的、在 `main` 上，且預覽點名的是被授權的 release；
   任何一項變了，就停止。接著以同樣的旗標執行 `bash "$FRIDAY/install.sh" "$TARGET"`、第二次預覽、
   `FRIDAY_TREE=vX.Y.Z bash "$FRIDAY/bin/friday-lock" check "$TARGET"`（tag 取自 `release:` 那一行）、
   `(cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)`
   與 `git -C "$TARGET" status --short`，每一項都照實回報。每一項都成功才算
   完成：安裝以 0 結束、第二次預覽每個檔案行都是 `IDENTICAL`、對照被授權的 release 的 lock check 回報
   `status: in sync`，且 self-check 通過。任何一步失敗，或安裝中途停止，就回報並停下。
   要怎麼復原目標，由使用者依它的 Git 歷史決定。

唯一會寫入的是 `install.sh`。agent 不會為了完成安裝而修改 Friday、它的
payload 或 lock。release 記錄在目標的 lock 裡，也記錄在目標專案自己的 adoption commit 裡，
依照該專案的慣例。

## 既有專案

已經有自己的 `AGENTS.md`、`.agents/AGENTS.md`、`.gitignore` 或 runtime 接線的專案，只取
managed core：

```sh
bash "$FRIDAY/install.sh" --managed-only --check "$TARGET"   # 預覽，不寫入任何東西
bash "$FRIDAY/install.sh" --managed-only "$TARGET"
```

`--managed-only` 複製 release 的 managed core、執行 `.agents/bin/setup.sh`，並寫入 lock。seeds 不論
內容為何都仍是你的，預覽會把每一個列出來，讓你看到還有哪些要以人工調和：

```
NEW .agents/docs/agent-rules.md
...
SEED AGENTS.md (yours; not touched)
SEED CLAUDE.md (missing; setup.sh creates it from Friday's seed)
SEED .agents/AGENTS.md (yours; not touched)
SEED .agents/protected-paths.conf (missing; not created)
SEED .gitignore (yours; not touched)
SEED .claude/settings.json (yours; not touched)
SEED .codex/hooks.json (identical to Friday's; not touched)
```

`SEED` 那一行也可能是 `(missing; not created)`；release 有附 `setup.sh` 時，兩個 root pointer
會是 `(missing; setup.sh creates it from Friday's seed)`；或是 `(identical to Friday's; not touched)`。

它可與預設的 release、`--release vX.Y.Z`、`--working-tree` 搭配。不加 `--managed-only` 時，同一個專案會被
拒絕，每個內容不同的 seed 都是一行 `CONFLICT`：這對空 repository 是正確的解讀，對既有專案則是用錯工具。
self-check 仍在最後執行，在帶有 guard 接線的 seeds（`.claude/settings.json`、`.codex/hooks.json`）
成為專案自己的、並接好線之前，它會失敗。

### 判讀預覽

`--check` 不寫入任何東西。真正執行時，它會寫入的部分仍維持寫入前拒絕的 preflight：任何 `CONFLICT` 都會
拒絕整個安裝，且不寫入任何東西。只看每一行 `SEED` 或 `CONFLICT` 後面的路徑。

| 該行 | 這是什麼 | 怎麼處理 |
| --- | --- | --- |
| `SEED AGENTS.md` | 你的 root pointer | **預期** —— 保留你的；它只需要指向 `.agents/AGENTS.md` |
| `SEED CLAUDE.md` | 你給 Claude Code 的 root pointer | **預期** —— 保留你的；它只需要 import `.agents/AGENTS.md`。缺少時由 `setup.sh`（v1.1.0 起）從 seed 建立 |
| `SEED .agents/AGENTS.md` | 你的路由表 | **預期** —— 保留你的；把 Friday 的路由列加進去 |
| `SEED .agents/protected-paths.conf` | 你的 protected-paths 清單 | **預期** —— 保留你的；缺少時在你加上之前什麼都不受保護（先放一份空的 seed 即可） |
| `SEED .gitignore` | 你的 | **預期** —— 把 Friday 的條目附加上去 |
| `SEED .claude/settings.json` | 你的 runtime 接線 | **預期** —— 把 Friday 的 handler 加進你的 `hooks` 陣列，不要替換整個檔案；缺少時，在你加上之前安裝的 self-check 會失敗 |
| `SEED .codex/hooks.json` | 你的 Codex 接線 | **預期** —— 同上 |
| `CONFLICT core.hooksPath` | 已經接上另一套 hook 管理工具（例如 husky） | **先決定** —— 接上 Friday 的 hook 會取代它，所以先把它的檢查併進一個經過審查的變更，再取消這項設定 |
| `CONFLICT .git/hooks` | `core.hooksPath` 生效後就不會再執行的 hook | **先決定** —— 把它們做的事移進經過審查的 hook，或刻意捨棄 |
| `CONFLICT .claude/skills/<name>` | `setup.sh` 要建立的 Skill 連結被擋住，或兩個 Skill 同名 | **先決定** —— 改名或移除擋路的那一個 |
| **其他任何檔案的 `CONFLICT`** | **managed core** | **真衝突** —— 見下 |

這七個是 Friday 只負責 seed、之後就交給你的全部檔案。它發出的其他東西都是
managed core，最終必須 byte-identical。已經完全相同的 managed 檔案不是衝突，會顯示為 `IDENTICAL`。

### 真衝突

CONFLICT 出現在十七個 managed-core 檔案之一，代表你的副本與 Friday 的已經分歧。
請逐檔對照你要採用的 release 調和，並放在一次經審查的 commit 裡：

```sh
git -C "$FRIDAY" show "vX.Y.Z:payload/<path>" | diff - "$TARGET/<path>"
```

除非你能精確說出你的版本為什麼不同，否則採用 Friday 的版本。如果你保留了差異，
那個檔案就不再是 managed core，整套機制也就再也無法告訴你任何關於它的事。然後再執行一次安裝。

### 安裝替你做了什麼

從 `v1.1.0` 起，`.agents/bin/setup.sh` 是 managed core 的一部分，安裝會在目標中執行它（更早的 release
沒有它，由它的安裝程式自己接線）：它會設定
`core.hooksPath`、連結 runtime guard 與 Claude Code 的 Skills，並且只在 `AGENTS.md`
與 `CLAUDE.md` 不存在時才建立它們。它絕不覆寫不是它自己建立的東西，所以你自己的
pointer 會維持原樣。唯一會替換的，是指向 `../../.agents/skills/`（它自己寫入的
唯一形式）的斷掉的 `.claude/skills/<name>` 連結；其他任何斷鏈都會回報為 CONFLICT
並原封不動。要單獨預覽它：

```sh
cd "$TARGET"
bash .agents/bin/setup.sh --check   # 有東西會被改變時結束碼為 1
```

絕對不要複製整個 `.agents/` 目錄：那會覆蓋你剛剛合併好的路由表。

### 為什麼不讓安裝程式直接合併

因為對一個承載安全邊界的檔案做三方合併，可能產生一個**雙方都沒有審查過**的結果。
拒絕並把決定交還回去，是比較慢、比較無趣、但正確的行為 —— 見
`payload/.agents/docs/git-guideline/safety-boundary.md`。

## 安裝會檢查並拒絕什麼

`--check` 會回報 `NEW`、`IDENTICAL` 或 `CONFLICT`（搭配 `--managed-only` 時還有 `SEED`），遇到衝突時以
非零碼結束，且不會複製檔案、改變檔案權限、建立連結，也不會執行 self-check。兩種模式都會在對目標進行
任何寫入之前，先驗證所有先備條件、每一個目的地，以及目標現有的 hook 設定（任何設定範圍中生效、且不是
`.agents/githooks` 的 `core.hooksPath`，或接線後會被略過的 `.git/hooks` 裡的 hook 與 hook symlink）。
目標是 repository 的根目錄，而不是某個 `.agents/` 子目錄，且具有 `.git/` 目錄（linked worktree 會被
拒絕，因為 `core.hooksPath` 由同一個 repository 的所有 worktree 共用，從其中一個接線會讓其他 worktree
不再執行任何 hook）。它們也會檢查 `setup.sh` 將建立的 `.claude/skills/<name>` 連結，依複製完成後的 Skills
（目標自己的 `.agents/skills` 加上 payload 的）計算：兩個 Skill 同名、被真實檔案或目錄擋住、指向別處的連結、
複製後會變成有效的斷鏈、或不是 `setup.sh` 寫的斷鏈，都是衝突，所以安裝會被拒絕，而不是做到一半才停下。
任何非預期的目的地 symlink（包含祖先路徑上的 symlink）都視為衝突；只接受三種連結：那三個精確指定的
hook 連結（Claude 的 collaborative-Git 與 protected-paths 連結，以及 Codex 的那一個）、已經正確的 `.claude/skills/<name>` 連結，以及指向 `.agents/skills/`、會由
`setup.sh` 替換掉的斷鏈。

安裝會補齊缺少的檔案，並保留內容相同的既有檔案。當內容不同時，它會拒絕覆寫，`.claude/settings.json`
也包含在內。這裡刻意沒有提供強制（force）模式。請先在目標專案中審查並調和衝突，再重新預覽一次。與
payload 並存的專案特定檔案維持本地狀態；只有 payload 自己擁有的 hook 腳本，才會被賦予可執行權限。
Preview 比對的是內容與路徑型別，而不是可執行權限。Preflight 本身不是一個 transaction：之後發生的 I/O
或 self-check 失敗，可能會讓新檔案已經留在原地，而並行發生的目標端變更，也不在這個保證範圍之內。請在
重試之前先檢查結果；絕對不要對同一個目標同時執行多個安裝程序。Friday 複製的是它自己封閉的 payload 到
目標專案；它不會複製整個 Friday repository，也不會把目標專案連結（link）回 Friday。

## 採用之後

```sh
FRIDAY_TREE=vX.Y.Z bash "$FRIDAY/bin/friday-lock" check "$TARGET"   # 對照該 release：in sync
bash "$TARGET/.agents/hooks/check-collaborative-git.sh"
```

`bash "$FRIDAY/bin/friday-lock" check "$TARGET"` 拿消費端與它所在的 Friday checkout 比對，所以只有在
那個 checkout 的 payload 就是消費端採用的 release 時，它才會顯示 `in sync`。Friday 往前走之後它會顯示
`behind`，[持續保持最新](#持續保持最新)說明怎麼把消費端帶到下一個 release。

## 持續保持最新

Friday 發了新 release 之後，會以 pull request 的形式送到每個 consumer，之後每台機器再各自更新自己的 clone。先找出符合你狀況的情境，再照它的步驟做。`$FRIDAY` 是你的 Friday checkout，也就是上面的 `~/.Friday`；`$CONSUMER` 是某個 consumer repository 的 clone。

| 情境 | 誰、在哪裡 | 前往 |
| --- | --- | --- |
| Friday 發了新的 release | 你，在執行 `friday-propagate` 的那台機器上 | [1](#1-friday-發了新的-release) |
| 某個 consumer merge 了 propagate 的 pull request | 每一台有那個 consumer clone 的機器 | [2](#2-propagate-的-pull-request-merge-之後) |
| 準備在某台機器上執行 `install.sh` 或 `friday-propagate` | 要執行的那台機器 | [3](#3-在機器上執行-friday-之前) |
| 不確定某個 consumer 目前在什麼狀態 | 任何一台機器 | [4](#4-consumer-目前在什麼狀態) |

### 1. Friday 發了新的 release

1. 先把 checkout 更新到最新，做法見第 3 節。
2. 先預覽每個 consumer 會改什麼，再開 pull request：

   ```sh
   bash "$FRIDAY/bin/friday-propagate" --dry-run ~/path/to/consumer ...
   bash "$FRIDAY/bin/friday-propagate"           ~/path/to/consumer ...
   ```

   它會在每個落後的 consumer 開一個 pull request，帶上有變動的 managed-core 檔案。已經是最新的 consumer 不會被動到。它絕不寫入 seed。pull request 內文會帶上 consumer 所跨 release 範圍內
   每個 release 的 `### Seed changes` 段落（[慣例](./CHANGELOG.md#seed-changes)，英文），沒有 seed 改動時
   用一行說明，若某個 release 改了 seed 卻沒有該段落則指名提醒；那項修改要由你親手做。
3. 由人 review 並 merge 每個 pull request，然後在每台機器上做第 2 節。

檢查：merge 之後，`bash "$FRIDAY/bin/friday-lock" check "$CONSUMER"` 會顯示 `in sync`。更多細節見[把變更帶到各個 consumer](./docs/updating-consumers.md#carrying-a-change-out-to-consumers)。

### 2. propagate 的 pull request merge 之後

在每一台有那個 consumer clone 的機器上：

1. 拉下最新的內容：

   ```sh
   git -C "$CONSUMER" switch main && git -C "$CONSUMER" pull --ff-only
   ```

2. 重跑接線。release 可能改了 hook 或 Skill 的連結：

   ```sh
   (cd "$CONSUMER" && bash .agents/bin/setup.sh)
   ```

   檢查：`(cd "$CONSUMER" && bash .agents/bin/setup.sh --check)` 回報沒有需要變更的地方。
3. 如果這個 pull request 改了 `.codex/hooks.json`，在你重新信任之前，Codex 會跳過這個專案的 hook：在 Codex 裡打開這個專案，執行 `/hooks` 並重新信任。如果只改了 hook 腳本本身，不需要重新信任。
4. 在這個專案開一個新的 agent session，讓它載入新的檔案。

### 3. 在機器上執行 Friday 之前

`install.sh` 和 `friday-propagate` 用的一定是 release，不是這個 checkout 目前的內容，但它們要透過這個 checkout 才找得到 release。所以先 fetch：

```sh
git -C "$FRIDAY" fetch --tags origin && git -C "$FRIDAY" switch main && git -C "$FRIDAY" pull --ff-only
```

檢查：`git -C "$FRIDAY" describe --tags --abbrev=0` 印出的是 [Releases](https://github.com/ShenYo/Friday/releases) 上最新的版本。

### 4. consumer 目前在什麼狀態？

```sh
bash "$FRIDAY/bin/friday-lock" check "$CONSUMER"
```

`in sync` 表示已經是最新的。其他狀態，例如 `behind` 或 `tag-moved`，以及各自該怎麼處理，見[查看 consumer 目前的狀態](./docs/updating-consumers.md#knowing-where-a-consumer-stands)。

## 每次 clone 之後

`core.hooksPath` 是 per-clone 設定，永遠不會被 clone 帶走。重新 clone、CI
checkout、或在安裝程式之外建立的 worktree，在有人再次設定之前都**不會執行任何
commit 期的 hook**。clone 之後，以及專案的 Skills 變動之後，請執行：

```sh
bash .agents/bin/setup.sh   # --check 可預覽；會拒絕 linked worktree
```

這無法用 hook 修復。checker 會把它回報成 note 而不是失敗，因為 CI checkout
永遠不會有它。

### setup.sh 做什麼

在 consumer 內的任何位置執行；clone 之後，以及新增、移除或改名 Skill 之後都要再執行。
`--check` 只預覽，不寫入任何東西。

它做四件事：

- 把 `core.hooksPath` 設為 `.agents/githooks`（任何設定範圍中生效、且是別的值時，
  回報為 `CONFLICT`，不會覆蓋它），並回報缺少或不可執行的 Git hook，以及接線後會被
  略過的 `.git/hooks` 裡的 hook 與 hook symlink；
- 把 `.claude/hooks/guard-collaborative-git.sh` 與
  `.codex/hooks/guard-collaborative-git.sh` 連結到共用 guard，並把
  `.claude/hooks/guard-protected-paths.sh` 連結到 protected-paths guard（僅 Claude）；
- root 的 `AGENTS.md` 與 `CLAUDE.md` 不存在時，從 seed 建立；已存在時不論內容為何
  都不動它；
- 把 `.agents/skills` 底下的每個 Skill（深度 1 或 2、含 `SKILL.md` 的目錄）連結為
  `.claude/skills/<name>`，`<name>` 取自 Skill 的 `name:` frontmatter，沒有則用
  目錄名，讓 Claude Code 看得到它們。`.claude/skills` 裡已斷掉、或對不上任何
  Skill 的項目，會回報為 `STALE`，由人決定是否移除（以 `.` 開頭的名稱會被略過）。
  本身是 symlink 的 Skill 目錄不會被跟隨：解析後落在 `.agents/skills` 之外的，
  回報為 `SKIPPED`；落在其中的別名（如 `git-commit -> git/commit`）則靜默略過。

它絕不覆寫、移動或刪除不是它自己建立的東西。唯一的例外是指向
`../../.agents/skills/`（它自己寫入的唯一形式）的斷掉的 `.claude/skills/<name>`
連結，它會替換；其他任何斷鏈都是 `CONFLICT`。擋在路上的項目會回報為
`CONFLICT <path> (<reason>)` 並原封不動，其餘步驟照常執行，結束碼為 1；`--check`
在有東西會被改變時，結束碼同樣是 1。再執行一次不會改變任何東西，並會印出
`nothing to change`。安裝程式在目標中執行的就是這支腳本。它與 `install.sh` 一樣，
基於相同的理由拒絕 linked worktree。

## 在已完成 Bootstrap 的專案中啟動 Agent

> **摘要**：安裝會 seed root [`AGENTS.md`](./payload/AGENTS.md)、
> [`CLAUDE.md`](./payload/CLAUDE.md) 與 [`.agents/AGENTS.md`](./payload/.agents/AGENTS.md)；
> 不會生成 `GEMINI.md` 或 `setup-ai.sh`。clone 一個 consumer 之後、以及新增／移除／
> 改名 Skill 之後，執行 `bash .agents/bin/setup.sh`。先讀兩個 AGENTS，再選擇已安裝的
> 單一 runtime 啟動；各 runtime 的 trust 與原生行為仍須各自驗證。

在要求 agent 變更任何東西之前，請先從目標 repository 的根目錄，讀過那兩份
已安裝的 instruction 進入點：

```sh
cd '/absolute/path/to/new-project'
sed -n '1,240p' AGENTS.md
sed -n '1,240p' .agents/AGENTS.md
```

如果已經安裝了 Claude Code，就從該根目錄用 `claude` 啟動它。如果已經安裝了
Codex，就另外從該根目錄用 `codex` 啟動它；請依你實際要用的 runtime 來選擇，
而不是把兩者當成一套自動化的連續流程。在第一個 prompt 裡，請要求它先讀過
root 的 instructions，並回報它實際載入了哪些 instruction 文件，以及目前的
branch、HEAD 與 working-tree 狀態，再開始進行任何編輯。

Friday 會 seed 一個 import `.agents/AGENTS.md` 的 root `CLAUDE.md`，但不會生成
`GEMINI.md` 或 `setup-ai.sh`。Claude session 是否真的載入了那個 import，屬於
runtime 行為，本指南無法保證，所以請持續要求 agent 回報它實際載入了哪些
instruction 文件。原生的 workspace trust、callback 傳遞、優先序，以及其他 runtime 行為，仍屬於各
runtime 自己要補的證據工作。Gemini CLI 與 `agy` 在這裡仍是 pending，所以
本指南刻意不為它們提供任何臆測性的啟動指令。

## 從 fork 發行 release

fork 本身就是 producer，而安裝程式執行的是它所安裝那個 release 自己的 `bin/friday-lock`。`v1.3.0`
（含）以前的 release，在它們自己的 `bin/friday-lock` 裡把 `ShenYo/Friday` 寫死，所以從其中任何一個
安裝的 consumer 會記載 upstream 為 producer。請依序進行：

1. clone 你的 fork，不是 upstream（`git clone <你的 fork 的 URL>`），讓 `origin` 就是 fork，所有指令
   都在這個 checkout 執行。安裝程式與 `friday-propagate` 都以 `origin` 檢查 release tag，安裝程式
   還需要本機有 `main`。
2. 在 branch 上設定 producer slug（見下），並透過 pull request merge 進 fork 的 `main`：release 是在
   `main` 上經審查的 commit 上建立的（`docs/releases.md`），而且 hook 接好線時，Friday 的 `pre-push`
   hook 會拒絕推送到預設 branch（`docs/safety.md`）。
3. 你的 release 從 `v2.0.0` 開始編號，高於 upstream 的 `v1.x`。沒有 `--release` 時，安裝程式與
   `friday-propagate` 一樣，會挑 checkout 裡最高的 `vMAJOR.MINOR.PATCH` tag，而 upstream 的 release
   記載的是 upstream 的 producer。所以絕不要抓取 upstream 的 tag：
   `git remote add upstream <upstream URL>`，然後
   `git config remote.upstream.tagOpt --no-tags`。之後要帶入 upstream 的變更，和任何變更一樣經由
   branch 與 pull request，並讓你的 release 一直高於 upstream 的 major 版本。`v2.0.0` release 會開啟新的
   changelog 檔：`docs/changelog/v2.md` 與 `CHANGELOG.md` 表格裡它的那一列，屬於該 release 的 pull
   request。來自 upstream 的 seed 變更，必須在你自己的條目裡寫成 Seed changes 段落，因為
   `bin/friday-seed-check` 與 `friday-propagate` 讀的是 fork 的條目，依 fork 的 tag 名稱與最上面的條目查找。
4. release 的 pull request merge 之後，pull `main`，在 `main` 上含有 slug 修改的 commit（通常就是新增
   changelog 檔的 release commit）上建立 annotated tag：`git tag -a vX.Y.Z <commit> -m <note>`，
   然後只推送 tag：`git push origin vX.Y.Z`。建立並推送 release tag 是人的步驟（`docs/releases.md`）。
   tag 必須是 annotated、在 `main` 上，且在 `origin` 上是同一個 tag object。
5. 從那個 checkout 安裝，例如先 `bash install.sh --check <target>`，再 `bash install.sh <target>`。

fork 的 consumer lock 必須記載 fork 自己的名稱。producer slug 只設定一次，就是
`bin/friday-lock` 開頭附近 `PRODUCER` 的預設值。記載其他 producer 的 lock
會被拒絕，訊息會同時寫出兩個名稱。

請在 fork 的第一個 consumer 安裝之前就改好預設值。lock 已經記載其他 producer
（包含 upstream）的 consumer，從那之後都會被拒絕。要把它轉過來，先對照它記載的
producer 檢查一次（`FRIDAY_PRODUCER=<那個 producer> bin/friday-lock check <consumer>`）。
結果是 `in sync` 或 `behind` 時，執行 `bin/friday-lock write <consumer>`；`behind`
只代表 fork 的 payload 已經往前走，下一次 propagation 會帶過去。結果是 `drifted`
時，先把 drift 的檔案處理好：write 會把檔案目前的內容當成新的基準，被蓋過去的
drift 之後不會再被回報。其他任何 status，先照該 status 自己的訊息處理，再檢查
一次才 write。`FRIDAY_PRODUCER` 只覆寫單一指令的預設值；不要在 shell profile 裡
export 它。

`payload/.agents/githooks/` 裡的 hook 訊息與 `payload/.agents/docs/agent-rules.md`
裡的連結，是刻意指向 upstream `ShenYo/Friday` 的。它們屬於 managed core 的
bytes：讓它們跟著 slug 走會改動每個 consumer 都帶著的檔案，因此需要發一次
release，而且每個 consumer 都要同步。`install.sh` 錯誤文字裡的 clone 指令也寫
upstream；它不會被複製到 consumer，所以 fork 可以自行修改。

## 採用不會給你什麼

在依賴以上任何東西之前，請讀
`payload/.agents/docs/git-guideline/safety-boundary.md`。它列出了哪些事沒有
任何東西在強制執行 —— `gh` 與 REST API 路徑、git plumbing、per-clone 的
`core.hooksPath` 等等。這些是防手滑的護欄，不是安全邊界。
