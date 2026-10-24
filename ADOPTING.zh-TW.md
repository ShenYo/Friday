# 採用 Friday

兩條路徑。空 repository 是七個指令；既有專案需要一次判斷，而這份文件之所以存在，
就是因為那個判斷從來沒有被寫下來。

## 空 repository

```sh
FRIDAY=~/.Friday
PIN=<一個經審查的 Friday commit>
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

預覽和安裝是兩個分開的決定，agent 只能自行做第一個。

1. **檢查輸入。** `TARGET` 是帶有 `.git` 目錄的 repository 根目錄。`FRIDAY`
   是另一個目錄，裡面有 `install.sh` 與 `payload/`，而且是乾淨的 checkout。
   有未提交修改的 checkout 不算 pin，所以停下來讓使用者選擇。完整記下
   `git -C "$FRIDAY" rev-parse HEAD`。兩個路徑和 SHA 都寫下來才算完成。
2. **預覽。** 只執行 `install.sh --check "$TARGET"`，回報 SHA 和完整的
   `NEW`／`IDENTICAL` 結果。只要出現任何 `CONFLICT` 或非零的結束碼，流程就在
   這裡停止：先在一個經審查的變更裡調和目標（見下方），再重新預覽。不要為了讓
   預覽通過而修改任何一個 repository。
3. **請求安裝。** 預覽不代表授權寫入，一開始交辦這件事的那則訊息也不算。只有在
   使用者以新的訊息點名這個 `TARGET` 和這個 Friday SHA 之後，才能安裝。
4. **安裝並驗證。** 依序執行安裝、第二次預覽、lock check、
   `(cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)`、
   `git -C "$TARGET" status --short` 與 `git -C "$TARGET" diff --check`，
   每一項都照實回報。第二次預覽每一行都是 `IDENTICAL`，且 lock check 回報
   `in sync`，才算完成。

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
| `.agents/AGENTS.md` | 你的路由表 | **預期** —— 保留你的；把 Friday 的路由列加進去 |
| `.gitignore` | 你的 | **預期** —— 把 Friday 的條目附加上去 |
| `.claude/settings.json` | 你的 runtime 接線 | **預期** —— 把 Friday 的 handler 加進你的 `hooks` 陣列，不要替換整個檔案 |
| `.codex/hooks.json` | 你的 Codex 接線 | **預期** —— 同上 |
| `core.hooksPath` | 已經接上另一套 hook 管理工具（例如 husky） | **先決定** —— 接上 Friday 的 hook 會取代它，所以先把它的檢查併進一個經過審查的變更，再取消這項設定 |
| `.git/hooks` | `core.hooksPath` 生效後就不會再執行的 hook | **先決定** —— 把它們做的事移進經過審查的 hook，或刻意捨棄 |
| **其他任何檔案** | **managed core** | **真衝突** —— 見下 |

這五個是 Friday 只負責 seed、之後就交給你的全部檔案。它發出的其他東西都是
managed core，最終必須 byte-identical。

### 真衝突

CONFLICT 出現在十四個 managed-core 檔案之一，代表你的副本與 Friday 的已經分歧。
請逐檔調和，並放在一次經審查的 commit 裡：

```sh
diff "$FRIDAY/payload/<path>" "$TARGET/<path>"
```

除非你能精確說出你的版本為什麼不同，否則採用 Friday 的版本。如果你保留了差異，
那個檔案就不再是 managed core，整套機制也就再也無法告訴你任何關於它的事。

當每個 managed-core 檔案都相符時，把它記錄下來：

```sh
bash "$FRIDAY/bin/friday-lock" write "$TARGET"
```

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
commit 期的 hook**：

```sh
git -C "$TARGET" config core.hooksPath .agents/githooks
```

這無法用 hook 修復。checker 會把它回報成 note 而不是失敗，因為 CI checkout
永遠不會有它。

## 採用不會給你什麼

在依賴以上任何東西之前，請讀
`payload/.agents/docs/git-guideline/safety-boundary.md`。它列出了哪些事沒有
任何東西在強制執行 —— `gh` 與 REST API 路徑、git plumbing、per-clone 的
`core.hooksPath` 等等。這些是防手滑的護欄，不是安全邊界。
