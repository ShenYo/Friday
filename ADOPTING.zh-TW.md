# 採用 Friday

兩條路徑。空 repository 是七個指令；既有專案需要一次判斷，而這份文件之所以存在，
就是因為那個判斷從來沒有被寫下來。

## 空 repository

```sh
FRIDAY=~/.Friday
PIN=<一個經審查的 Friday release 的 commit>   # clone 之後：git -C "$FRIDAY" rev-parse 'vX.Y.Z^{commit}'
TARGET=<你的新 repo>

git clone https://github.com/ShenYo/Friday.git "$FRIDAY"
git -C "$FRIDAY" checkout --detach "$PIN"

git -C "$TARGET" init
bash "$FRIDAY/install.sh" --check "$TARGET"   # 預覽，不寫入任何東西
bash "$FRIDAY/install.sh" "$TARGET"
bash "$FRIDAY/install.sh" --check "$TARGET"   # 每一行都應該是 IDENTICAL
```

然後驗證，而不是假設：

```sh
bash "$FRIDAY/bin/friday-lock" check "$TARGET"   # 預期：status: in sync
git -C "$TARGET" status --short
```

### 由 agent 執行安裝時

這一節適用於空 repository。既有專案會有預期中的衝突，改走下一節的手動流程。
預覽和安裝是兩個分開的決定，agent 只能自行做第一個。

1. **檢查輸入。** `TARGET` 是帶有 `.git` 目錄的 repository 根目錄。`FRIDAY`
   是另一個目錄，裡面有 `install.sh` 與 `payload/`，而且是使用者指定為 `PIN`
   的那個經審查 release 的 commit 的乾淨 checkout：`git -C "$FRIDAY" rev-parse HEAD` 與它
   完全相同。有未提交修改的 checkout，或停在其他 commit 的 checkout，都不是
   那個 pin。停下來讓使用者選擇。在這項成立之前，不執行 `FRIDAY` 裡的任何
   東西，因為預覽會執行它的 `install.sh`。兩個路徑和 SHA 都寫下來且相符，才算
   完成。
2. **預覽。** 只以完整路徑執行 `bash "$FRIDAY/install.sh" --check "$TARGET"`，
   回報 SHA 和完整的 `NEW`／`IDENTICAL` 結果。只要出現任何 `CONFLICT` 或非零的
   結束碼，流程就在這裡停止。不要為了讓預覽通過而修改任何一個 repository。
3. **請求安裝。** 預覽不代表授權寫入，一開始交辦這件事的那則訊息也不算。只有在
   使用者以新的訊息點名這個 `TARGET` 和這個 SHA 之後，才能安裝。
4. **安裝並驗證。** 先再次確認 `FRIDAY` 是乾淨的，且停在被授權的 SHA；如果它
   動過，就停止。接著執行 `bash "$FRIDAY/install.sh" "$TARGET"`、第二次預覽、
   lock check、`(cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)`
   與 `git -C "$TARGET" status --short`，每一項都照實回報。每一項都成功才算
   完成：安裝以 0 結束、第二次預覽每一行都是 `IDENTICAL`、lock check 回報
   `in sync`，且 self-check 通過。任何一步失敗，或安裝中途停止，就回報並停下。
   要怎麼復原目標，由使用者依它的 Git 歷史決定。

唯一會寫入的是 `install.sh`。agent 不會為了完成安裝而修改 Friday、它的
payload 或 lock。pin 住的 SHA 記錄在目標專案自己的 adoption commit 裡，依照該
專案的慣例。

## 既有專案：怎麼讀 CONFLICT

`--check` 不寫入任何東西，而且只要有任何衝突就拒絕整個安裝。這個拒絕是刻意的設計
——安裝程式不會合併，所以在你做決定之前不會有任何東西被弄丟。它**沒有**做的，是
告訴你哪些衝突重要。

一個已經有自己的 `AGENTS.md`、`.agents/AGENTS.md` 與 `.gitignore` 的典型專案，
會得到這樣的輸出：

```
CONFLICT AGENTS.md (existing content)
CONFLICT .agents/AGENTS.md (existing content)
NEW .agents/docs/agent-rules.md
...
CONFLICT .gitignore (existing content)
NEW .claude/settings.json
error: resolve conflicts in a reviewed change; nothing was written.
```

**那裡的每一個衝突都是預期的，沒有一個是真衝突。** 三行 CONFLICT，三個的正確
處理都是「保留你的，把 Friday 的內容併進去」。

### 判讀決策樹

只看每一行 CONFLICT 後面的路徑。

| CONFLICT 的檔案 | 這是什麼 | 怎麼處理 |
| --- | --- | --- |
| `AGENTS.md` | 你的 root pointer | **預期** —— 保留你的；它只需要指向 `.agents/AGENTS.md` |
| `CLAUDE.md` | 你給 Claude Code 的 root pointer | **預期** —— 保留你的；它只需要 import `.agents/AGENTS.md` |
| `.agents/AGENTS.md` | 你的路由表 | **預期** —— 保留你的；把 Friday 的路由列加進去 |
| `.gitignore` | 你的 | **預期** —— 把 Friday 的條目附加上去 |
| `.claude/settings.json` | 你的 runtime 接線 | **預期** —— 把 Friday 的 handler 加進你的 `hooks` 陣列，不要替換整個檔案 |
| `.codex/hooks.json` | 你的 Codex 接線 | **預期** —— 同上 |
| `core.hooksPath` | 已經接上另一套 hook 管理工具（例如 husky） | **先決定** —— 接上 Friday 的 hook 會取代它，所以先把它的檢查併進一個經過審查的變更，再取消這項設定 |
| `.git/hooks` | `core.hooksPath` 生效後就不會再執行的 hook | **先決定** —— 把它們做的事移進經過審查的 hook，或刻意捨棄 |
| **其他任何檔案** | **managed core** | **真衝突** —— 見下 |

這六個是 Friday 只負責 seed、之後就交給你的全部檔案。它發出的其他東西都是
managed core，最終必須 byte-identical。

### 真衝突

CONFLICT 出現在十五個 managed-core 檔案之一，代表你的副本與 Friday 的已經分歧。
請逐檔調和，並放在一次經審查的 commit 裡：

```sh
diff "$FRIDAY/payload/<path>" "$TARGET/<path>"
```

除非你能精確說出你的版本為什麼不同，否則採用 Friday 的版本。如果你保留了差異，
那個檔案就不再是 managed core，整套機制也就再也無法告訴你任何關於它的事。

### 這裡的安裝程式不會替你做完

在既有專案上，`install.sh` **只能預覽**。只要有任何已宣告的檔案衝突，它就會拒絕；
而你的 `AGENTS.md`、`.agents/AGENTS.md` 與 `.gitignore` 是*刻意設計成*會衝突的，
而且永遠都會 —— 它們是你的。所以在已經有這些檔案的專案上，安裝程式永遠不會執行
到完成，這是正確的行為，不是需要繞過的問題。

請自己把 managed core 複製過去，放在一次經審查的 commit 裡，並且不要動你自己的
檔案：

```sh
while IFS= read -r rel; do
  case "$rel" in ''|'#'*|'!'*) continue ;; esac
  mkdir -p "$TARGET/$(dirname "$rel")"
  cp "$FRIDAY/payload/$rel" "$TARGET/$rel"
done < "$FRIDAY/bin/managed-core.txt"

bash "$FRIDAY/bin/friday-lock" write "$TARGET"
```

複製的內容包含 `.agents/bin/setup.sh`。請在目標中執行它來為這個 clone 接線：它會設定
`core.hooksPath`、連結 runtime guard 與 Claude Code 的 Skills，並且只在 `AGENTS.md`
與 `CLAUDE.md` 不存在時才建立它們。它絕不覆寫不是它自己建立的東西，所以你自己的
pointer 會維持原樣。唯一會替換的，是指向 `../../.agents/skills/`（它自己寫入的
唯一形式）的斷掉的 `.claude/skills/<name>` 連結；其他任何斷鏈都會回報為 CONFLICT
並原封不動。請先用 `--check` 預覽：

```sh
cd "$TARGET"
bash .agents/bin/setup.sh --check   # 有東西會被改變時結束碼為 1
bash .agents/bin/setup.sh
```

絕對不要複製整個 `.agents/` 目錄：那會覆蓋你剛剛合併好的路由表。

### 為什麼不讓安裝程式直接合併

因為對一個承載安全邊界的檔案做三方合併，可能產生一個**雙方都沒有審查過**的結果。
拒絕並把決定交還回去，是比較慢、比較無趣、但正確的行為 —— 見
`payload/.agents/docs/git-guideline/safety-boundary.md`。

## 採用之後

```sh
bash "$FRIDAY/bin/friday-lock" check "$TARGET"       # in sync / drifted / behind
bash "$TARGET/.agents/hooks/check-collaborative-git.sh"
```

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
