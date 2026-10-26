# 採用 Friday

兩條路徑。空 repository 只要幾個指令；既有專案需要一次判斷，而這份文件之所以存在，
就是因為那個判斷從來沒有被寫下來。

`install.sh` 安裝的是 release：最新的 annotated tag `vX.Y.Z`，或你用 `--release` 指定的那一個。
它絕不安裝 Friday checkout 剛好持有的內容，所以停在 feature branch、或有未提交修改的 checkout，
不會把尚未發行的 payload 交給專案。`--working-tree` 會照原樣安裝 checkout，並附上警告；
那是用來開發 Friday 的，不是給專案用的。

## 空 repository

```sh
FRIDAY=~/.Friday
TARGET=<你的新 repo>

git clone https://github.com/ShenYo/Friday.git "$FRIDAY"   # 只需一次，還沒有 checkout 時
git -C "$TARGET" init

bash "$FRIDAY/install.sh" --check "$TARGET"   # 預覽，不寫入任何東西
bash "$FRIDAY/install.sh" "$TARGET"           # 最新的 release
bash "$FRIDAY/install.sh" --check "$TARGET"   # 每個檔案行都應該是 IDENTICAL
```

要釘選某個 release 而不是取最新的，在安裝指令加上 `--release vX.Y.Z`。沒有合格的 release 時
（完全沒有，或最新的不是 annotated、不在 `origin` 上、或不在 `main` 上），安裝會拒絕，並說明怎麼 fetch
或建立一個；它不會寫入任何東西。

`.agents/bin/setup.sh` 與 `CLAUDE.md` seed 從 `v1.1.0` 起才附帶。更早的 release（`v1.0.0`、`v1.0.1`）兩者都沒有：
它的安裝程式自己為 clone 接線，從這類 release 安裝的專案也沒有 `setup.sh` 可在 clone 之後執行（那裡全新 clone
缺少的是 `git config core.hooksPath .agents/githooks`）。

然後驗證，而不是假設。`FRIDAY_TREE` 讓 `friday-lock` 讀 release 本身，所以這是拿專案的位元組對照那個 release；
單純的 `friday-lock check` 讀的是 Friday checkout 的 working tree，在開發用 checkout 上它比 release 新，
會對一個正確的安裝回報 `behind`：

```sh
# vX.Y.Z 是安裝輸出第一行 "release: vX.Y.Z (commit ...)" 的 tag
FRIDAY_TREE=vX.Y.Z bash "$FRIDAY/bin/friday-lock" check "$TARGET"   # 預期：status: in sync
(cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)
git -C "$TARGET" status --short
```

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
SEED .gitignore (yours; not touched)
SEED .claude/settings.json (yours; not touched)
SEED .codex/hooks.json (identical to Friday's; not touched)
```

它可與預設的 release、`--release vX.Y.Z`、`--working-tree` 搭配。不加 `--managed-only` 時，同一個專案會被
拒絕，每個內容不同的 seed 都是一行 `CONFLICT`：這對空 repository 是正確的解讀，對既有專案則是用錯工具。

### 判讀預覽

`--check` 不寫入任何東西。真正執行時，它會寫入的部分仍維持寫入前拒絕的 preflight：任何 `CONFLICT` 都會
拒絕整個安裝，且不寫入任何東西。只看每一行 `SEED` 或 `CONFLICT` 後面的路徑。

| 該行 | 這是什麼 | 怎麼處理 |
| --- | --- | --- |
| `SEED AGENTS.md` | 你的 root pointer | **預期** —— 保留你的；它只需要指向 `.agents/AGENTS.md` |
| `SEED CLAUDE.md` | 你給 Claude Code 的 root pointer | **預期** —— 保留你的；它只需要 import `.agents/AGENTS.md`。缺少時由 `setup.sh`（v1.1.0 起）從 seed 建立 |
| `SEED .agents/AGENTS.md` | 你的路由表 | **預期** —— 保留你的；把 Friday 的路由列加進去 |
| `SEED .gitignore` | 你的 | **預期** —— 把 Friday 的條目附加上去 |
| `SEED .claude/settings.json` | 你的 runtime 接線 | **預期** —— 把 Friday 的 handler 加進你的 `hooks` 陣列，不要替換整個檔案；缺少時，在你加上之前安裝的 self-check 會失敗 |
| `SEED .codex/hooks.json` | 你的 Codex 接線 | **預期** —— 同上 |
| `CONFLICT core.hooksPath` | 已經接上另一套 hook 管理工具（例如 husky） | **先決定** —— 接上 Friday 的 hook 會取代它，所以先把它的檢查併進一個經過審查的變更，再取消這項設定 |
| `CONFLICT .git/hooks` | `core.hooksPath` 生效後就不會再執行的 hook | **先決定** —— 把它們做的事移進經過審查的 hook，或刻意捨棄 |
| `CONFLICT .claude/skills/<name>` | `setup.sh` 要建立的 Skill 連結被擋住，或兩個 Skill 同名 | **先決定** —— 改名或移除擋路的那一個 |
| **其他任何檔案的 `CONFLICT`** | **managed core** | **真衝突** —— 見下 |

這六個是 Friday 只負責 seed、之後就交給你的全部檔案。它發出的其他東西都是
managed core，最終必須 byte-identical。已經完全相同的 managed 檔案不是衝突，會顯示為 `IDENTICAL`。

### 真衝突

CONFLICT 出現在十五個 managed-core 檔案之一，代表你的副本與 Friday 的已經分歧。
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

## 採用之後

```sh
FRIDAY_TREE=vX.Y.Z bash "$FRIDAY/bin/friday-lock" check "$TARGET"   # 對照該 release：in sync
bash "$TARGET/.agents/hooks/check-collaborative-git.sh"
```

`bash "$FRIDAY/bin/friday-lock" check "$TARGET"` 拿消費端與它所在的 Friday checkout 比對，所以只有在
那個 checkout 的 payload 就是消費端採用的 release 時，它才會顯示 `in sync`。Friday 往前走之後它會顯示
`behind`；這時維護者的 `bin/friday-propagate` 會開 pull request，把消費端帶到下一個 release。

`core.hooksPath` 是 per-clone 設定，永遠不會被 clone 帶走。重新 clone、CI
checkout、或在安裝程式之外建立的 worktree，在有人再次設定之前都**不會執行任何
commit 期的 hook**。clone 之後，以及專案的 Skills 變動之後，請執行：

```sh
bash .agents/bin/setup.sh   # --check 可預覽；會拒絕 linked worktree
```

這無法用 hook 修復。checker 會把它回報成 note 而不是失敗，因為 CI checkout
永遠不會有它。

## 採用不會給你什麼

在依賴以上任何東西之前，請讀
`payload/.agents/docs/git-guideline/safety-boundary.md`。它列出了哪些事沒有
任何東西在強制執行 —— `gh` 與 REST API 路徑、git plumbing、per-clone 的
`core.hooksPath` 等等。這些是防手滑的護欄，不是安全邊界。
