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
