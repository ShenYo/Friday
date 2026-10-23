# Friday

[English](./README.md) · **繁體中文**

> **摘要**：Friday 是可受版本控管的共享專案基線（shared project baseline）；Jarvis 則是個人層。
> 先以 `--check` 預覽，再安裝封閉式的 allowlist。衝突絕不覆寫，現有專案需經
> 人工審查後調和。

Friday 是一套可攜式、經過審查的共享專案基線（baseline）。它會把專案範圍內的政策、Git
skills、共用的暫存檔規範，以及 Claude/Codex 的 guard 接線，複製進消費端（consumer）
repository，而不依賴開發者個人的 home 目錄、個人 Skills 或 vendor 工作流程。

它同時處理三個限制：封閉式 allowlist 讓 bootstrap 維持衝突安全（conflict-safe）；
以複製方式交付內容讓 baseline 保持可攜且可審查；既有消費端的變更則停留在經審查的
調和（reconciliation）邊界之後，而不會變成自動更新。Jarvis 僅是個人層；請勿將
Jarvis 的 Skills、settings 或其他依賴個人 home 目錄的內容，放進 Friday 的專案契約中。

## 何時該使用 Friday

| 情境 | Friday 的角色 | 該怎麼做 |
| --- | --- | --- |
| 全新的 Git repository | Bootstrap 經審查的 baseline | 先 Preview，再安裝，然後再 Preview 一次。 |
| 既有消費端 | 安全地揭露差異 | Pin 住 Friday 版本、執行 `--check`，並在一次經審查的消費端變更中調和每一個衝突。 |
| 個人 Skills 或偏好 | 讓個人範圍維持個人 | 使用 Jarvis；不要把它推進 Friday。 |
| 專案特有的政策或檢查 | 保留消費端的所有權 | 在審查過共享 baseline 之後，再新增消費端 overlay。 |

## 架構

```text
Friday payload
     |
     v
install.sh (closed allowlist + preflight)
     |
     v
copied consumer baseline + runtime seed + consumer overlay
```

Payload 的內容是被複製進消費端的，而不是連結（link）回 Friday 的 checkout。兩個
生成出來的 runtime hook 連結，都指向消費端自己那份已複製的共用 guard，因此這些
adapter 共用同一份經審查的 guard 實作，而不會對 Friday 的檔案系統產生相依性。

Friday 刻意不做成一個通用的 runtime manager。它檢查的是靜態的 Codex 接線（wiring），
而不是原生的 callback 行為、exit handling、handler 順序，或 fail-closed 的強制
執行；Gemini 的支援仍是 pending。這四項已在某個消費端的 Claude 側實測（見下方
「在 Claude 側實測到的 runtime 行為」），但 Codex 是另一個 adapter，對它而言
仍未驗證。Friday 也不會自動探索任意 Skills，或安裝消費端專屬的 domain workflow。

## 現行運作情境

> **摘要**：Friday 的可攜成果必須由專案本身承載；輔助工具可以選用但
> 不可成為 baseline 前提。十四個 managed-core 檔維持封閉
> byte-exact 範圍，seed、runtime integration 與 overlay 仍由 consumer 擁有。
> 現行 guard 安全修正已在 payload 與 self-check 實作；B06 的 immutable SHA、
> 手動採用及 rollback 責任不變，backup、replay 與外部 runtime 仍待完成。

可攜的成果應該放在專案自己管控的文件、測試或自動化裡。輔助工具可以協助操作者，
但沒有任何消費端被允許把這些輔助工具當成 bootstrap 或滿足 Friday 契約的前提。
封閉的十四檔 managed core，始終是唯一的 byte-exact 比對集合；消費端的 seeds、
runtime integration 與 overlay，仍由消費端自行擁有並以人工方式調和。

目前的 payload 已實作 guard 的安全性更新，其 self-check 也會演練相關的允許與
禁止指令形式。但這僅是靜態且針對 guard 本身的證據，並不足以證明原生的 callback
傳遞、exit handling、執行順序或 fail-closed 的強制執行。那些是在消費端的
Claude 側另行建立的，不是由這個 self-check 證明的。發行版本仍是經審查的
immutable SHA，採用方式仍是人工進行；當需要 rollback 時，由 Friday 維護者提出，
消費端的擁有者負責執行。指定備援維護者、真正的新機器 replay、進一步的消費端
replay，以及 external-runtime 的收尾，都仍待完成。

## 生命週期治理（B06）

> **摘要**：Friday 的 MVP 採「可審查 SHA + consumer 手動採用」模式：
> repository owner 負責維護，backup maintainer 尚待指定；不自動同步、不強制
> 更新，也不自動 rollback。

本節為 Friday MVP 生命週期的規範性章節。

- Repository owner 是 Friday 的主要維護者。備援維護者（backup maintainer）
  目前仍是 **PENDING**；在指定之前，主要維護者仍負責發行審查、復原提案，
  以及記錄相關決策。
- 一個經審查的 immutable Friday commit SHA，才是發行管道（release channel）。
  可變動的 branch 名稱不算是發行版本。
- 消費端的擁有者，以人工方式採用一個經審查的發行版本，並保留該消費端自己的
  seeds、runtime integration 與 overlay。Friday 不會自動同步，也不會自動
  更新既有的消費端。
- 當需要復原時，由 Friday 維護者提出經審查的 rollback 或調和方案。消費端
  擁有者，在該消費端 repository 中執行這個經審查的還原或調和；Friday 絕不會
  強制更新消費端，也不會自動替消費端 rollback。
- 每一個候選發行版本，在被消費端採用之前，都必須先經過一次 disposable-project
  的 replay。真正的新機器 replay、以第三個 genuine consumer 進行驗證，以及
  cross-runtime 的收尾，都仍是 **PENDING** 的後續工作。

Vendor Skills（包含 Matt Pocock Skills）仍歸 Jarvis 所有，並維持 vendor-pristine
狀態。Friday 只管理可攜的、專案本地輸出內容契約，內容記錄在
[`scratch-files.md`](./payload/.agents/docs/scratch-files.md)；它既不安裝也
不複製 vendor Skills，也不宣稱擁有 runtime 的 invocation 或 precedence 強制力。

## 快速開始

> 要把 Friday 採用到**既有**專案，而 `--check` 吐出一串 CONFLICT？
> [`ADOPTING.zh-TW.md`](./ADOPTING.zh-TW.md) 有判讀決策樹 ——
> 哪些是預期的 overlay、哪些是真衝突。


> **摘要**：blank project 先在乾淨、固定 SHA 的 Friday checkout 上預覽，
> 再 install、再預覽並檢查差異；這是 copy-based baseline，不是複製整個 Friday
> repo 或把 consumer symlink 到它。既有 consumer 請走後面的 manual reconciliation。

對於一個全新的空白 repository，請先取得另外經過審查、釘選在某個 immutable
commit 上的 Friday checkout。先備條件是 Git、Bash 與 `jq`。請不要把一個
dirty（有未提交變更）的 Friday checkout 當作範例來源：下面的流程會在那個
已審查的 pin 上建立一份新的 checkout。執行前，請把兩個絕對路徑與那個 SHA
的 placeholder 都換成實際值。這些指令不會建立 commit、安裝 runtime，也不會
設定任何憑證。

```sh
(
  set -eu
  TARGET='/absolute/path/to/new-project'
  FRIDAY='/absolute/path/to/new-Friday-checkout'
  PIN='replace-with-reviewed-immutable-Friday-SHA'

  command -v git >/dev/null
  command -v bash >/dev/null
  command -v jq >/dev/null
  test ! -e "$FRIDAY"
  test ! -L "$FRIDAY"
  git clone https://github.com/ShenYo/Friday.git "$FRIDAY"
  git -C "$FRIDAY" checkout --detach "$PIN"
  test "$(git -C "$FRIDAY" rev-parse HEAD)" = "$PIN"
  test -z "$(git -C "$FRIDAY" status --porcelain)"
  test ! -e "$TARGET"
  test ! -L "$TARGET"
  mkdir -p "$TARGET"
  git -C "$TARGET" init
  bash "$FRIDAY/install.sh" --check "$TARGET"
  bash "$FRIDAY/install.sh" "$TARGET"
  bash "$FRIDAY/install.sh" --check "$TARGET"
  (cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)
  git -C "$TARGET" diff --check
  git -C "$TARGET" status --short
)
```

第一次 preview 會回報 `NEW`、`IDENTICAL` 或 `CONFLICT`；在重新執行之前，
請先在一次經審查的變更中解決每一個衝突。審查完產生的 worktree diff 之後，
再依目標 repository 自己的規則，另外決定是否、以及如何 commit 它。Friday
複製的是它自己封閉的 payload 到目標專案；它不會複製整個 Friday repository，
也不會把目標專案連結（link）回 Friday。

需要 `jq`，且目標必須是空白或相容的專案，並具有 `.git/` 目錄（不支援 linked
worktree）。目標是 repository 的根目錄，而不是某個 `.agents/` 子目錄。
`--check` 會回報 `NEW`、`IDENTICAL` 或 `CONFLICT`，遇到衝突時以非零碼結束，
且不會複製檔案、改變檔案權限、建立連結，也不會執行 self-check。兩種模式都會
在對目標進行任何寫入之前，先驗證所有先備條件與每一個目的地。任何非預期的
目的地 symlink（包含祖先路徑上的 symlink）都視為衝突；只有那兩個精確指定的
Claude 與 Codex hook 連結會被接受。

安裝會補齊缺少的檔案，並保留內容相同的既有檔案。當內容不同時，它會拒絕
覆寫，`.claude/settings.json` 也包含在內。這裡刻意沒有提供強制（force）模式。
請先在目標專案中審查並調和衝突，再重新預覽一次。與 payload 並存的專案特定
檔案維持本地狀態；只有 payload 自己擁有的 hook 腳本，才會被賦予可執行權限。
Preview 比對的是內容與路徑型別，而不是可執行權限。Preflight 本身不是一個
transaction：之後發生的 I/O 或 self-check 失敗，可能會讓新檔案已經留在原地，
而並行發生的目標端變更，也不在這個保證範圍之內。請在重試之前先檢查結果；
絕對不要對同一個目標同時執行多個安裝程序。

安裝流程的最後一步，會執行 payload 自己的 self-check，因此執行環境接線出錯時，
會在當下就失敗，而不是等到有人真正依賴那個邊界時才出事。

## 在已完成 Bootstrap 的專案中啟動 Agent

> **摘要**：安裝只 seed root [`AGENTS.md`](./payload/AGENTS.md) 與
> [`.agents/AGENTS.md`](./payload/.agents/AGENTS.md) 的 agent
> instructions；不會生成 root `CLAUDE.md`、`GEMINI.md` 或 `setup-ai.sh`。先讀
> 兩個 AGENTS，再選擇已安裝的單一 runtime 啟動；各 runtime 的 trust 與原生行為
> 仍須各自驗證。

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

Friday 不會生成 root 的 `CLAUDE.md`、`GEMINI.md` 或 `setup-ai.sh`。因此
Claude 的使用者，需要有一個已驗證的 Claude 進入點，或者在 session 裡明確地
提示它去讀 AGENTS 檔案；本 README 無法保證 AGENTS 會被自動載入。原生的
workspace trust、callback 傳遞、優先序，以及其他 runtime 行為，仍屬於各
runtime 自己要補的證據工作。Gemini CLI 與 `agy` 在這裡仍是 pending，所以
本指南刻意不為它們提供任何臆測性的啟動指令。

## 所有權：Managed Core、Seeds 與 Overlays

Managed core 是精確比對的：既有消費端會把這十四個檔案，與他們審查過的
Friday 版本逐位元組（byte-for-byte）比對。

```
.agents/docs/agent-rules.md
.agents/docs/testing.md
.agents/docs/scratch-files.md
.agents/docs/git-guideline/git-commit.md
.agents/docs/git-guideline/pr-evidence.md
.agents/docs/git-guideline/safety-boundary.md
.agents/hooks/check-collaborative-git.sh
.agents/hooks/guard-collaborative-git.sh
.agents/githooks/pre-commit
.agents/githooks/commit-msg
.agents/githooks/pre-push
.agents/skills/git/commit/SKILL.md
.agents/skills/git/create-pr/SKILL.md
.agents/skills/git/push/SKILL.md
```

這三個 [`githooks`](./payload/.agents/githooks) 檔案是 Git hooks，而非 runtime
tool hooks，由 installer 透過 `core.hooksPath` 接上。
[`pre-commit`](./payload/.agents/githooks/pre-commit) 掃描 staged 內容中的憑證、
[`commit-msg`](./payload/.agents/githooks/commit-msg) 強制訊息契約、
[`pre-push`](./payload/.agents/githooks/pre-push) 則依 Git 即將送出的 refs 判斷，
因此刪除 ref、改寫歷史或推送 default branch，無論指令怎麼拼寫都會被拒絕。
對一個完全沒有 ref 的 remote 做第一次推送則會放行：沒有 default branch 要保護、
沒有 ref 可刪、也沒有歷史可改寫，而拒絕它會讓「建立一個 repository」在不繞過
hook 的前提下變得不可能。它們
與 managed core 其餘檔案一樣需要逐位元組比對：先前版本的清單遺漏了它們，使得
下方的對帳流程在無聲中並不完整。

以下這些屬於空白 repository 的 seeds 或 runtime integration，並不是
managed core。既有消費端需要自行以人工方式調和它們：

```
AGENTS.md                                    root pointer
.agents/AGENTS.md                            shared policy router
.gitignore                                   temporary-file ignore rule
.claude/settings.json                        Claude PreToolUse wiring
.claude/hooks/guard-collaborative-git.sh     generated symlink to the guard
.codex/hooks.json                            Codex PreToolUse runtime seed
.codex/hooks/guard-collaborative-git.sh      generated symlink to the guard
```

空白 repository 的 Codex seed，剛好只有一個 collaborative handler，而它的
共用 guard 在執行時，會顯示 `Checking collaborative Git safety boundary`。
它那個經過強化的啟動器（launcher），會先建立一個已知的 PATH、檢查 `git` 與
`bash`、在不洩漏 Git 診斷資訊的前提下解析出 Git root、驗證專案本地的 guard
可被讀取，然後才執行它。它並不包含消費端自己的 protected-path handler。
managed core 的 checker，允許消費端在那唯一的共用 handler 之外再加上自己的
handler，但要求那個共用 handler 必須恰好存在一次。

這次審查過的通用化（generic promotion）來源，是 `pet_care` 的 commit
`3e4f03b`；其 protected-path 消費端 overlay 刻意被排除在外。只有在這個
payload 變更被 commit 之後，才記錄對應的 Friday 採用 SHA。

消費端的 overlay，不屬於上面任何一份清單。消費端可以額外加入一個可執行的
一般檔案 `.agents/hooks/check-project-agent-integration.sh`；當它存在時，
managed core 的 checker 會執行它，並把失敗結果往外傳遞。Friday 本身不會
附帶這個擴充功能。

這是在 [`install.sh`](./install.sh) 裡，一份明確的靜態 allowlist，而不是
自動的 payload 探索機制。新的 payload 檔案在被審查並加進這份清單之前，
都會在清查（inventory）驗證階段失敗。這個 MVP 裡沒有 manifest，也沒有
update engine。

## 更新既有消費端

既有消費端的更新，是一次經審查的調和（reconciliation），而不是安裝程式的
升級。請先釘選（pin）一個經審查的 Friday commit；用一個 placeholder，而不是
一個可變動的 branch 名稱：

```sh
PIN='replace-with-reviewed-immutable-Friday-SHA'
FRIDAY='/absolute/path/to/Friday'
TARGET='/absolute/path/to/consumer'

test "$(git -C "$FRIDAY" rev-parse HEAD)" = "$PIN"
test -z "$(git -C "$FRIDAY" status --porcelain)"
bash "$FRIDAY/install.sh" --check "$TARGET"
```

請讀過每一個 `CONFLICT`，並在一次經審查的消費端變更中調和它。只同步上面
列出的十四個 managed-core 路徑，然後逐一證明它們的內容，與
`"$FRIDAY/payload/$rel"` 完全一致。請保留消費端自己的 seeds、runtime
integration 與 overlay；不要整個複製一份 `.agents/` 目錄。

調和完成之後，請驗證該消費端，而不是把安裝程式當成一個更新引擎來用：

```sh
(cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)
bash "$FRIDAY/bin/friday-lock" check "$TARGET"
git -C "$TARGET" diff --check
```

這個 checker，在消費端的擴充存在時會執行它。請審查產生出來的消費端 diff，
並依該 repository 自己的規則，建立一個原子性（atomic）的消費端 commit。
Friday 沒有強制模式、沒有 manifest、沒有自動同步，也沒有自動調和機制。

### 具日期標記的採用證據

截至 2026-10-13，`pet_care` 與 Finance 都已驗證，在 Friday 的 `b44e1ff`
上，managed core 達到 10/10 的完全相符。這僅是歷史性的證據：之後任何
payload 的變更，都需要重新做一次 managed-core 的比對，才能讓任一消費端
記錄新的採用 SHA。它也不代表整個 repository 相等，或在任一消費端有原生
runtime 的強制執行。

## 安全模型與限制

[`guard-collaborative-git.sh`](./payload/.agents/hooks/guard-collaborative-git.sh)
會在每一次 Bash 工具呼叫之前執行，並拒絕以下情況：

- `git push --force` / `--force-with-lease`、`reset --hard`、`clean`、
  `branch -D`、`stash clear|drop`、`worktree remove`、
  `remote remove|set-url`
- `find … -delete`、`gh repo delete`、`gh api -X DELETE`
- 任何遞迴式（recursive）的 `rm`（`-r`、`-R`、`--recursive`），並以可避免
  在 `--` 之後夾帶路徑混進去的方式解析

遇到以上任一情況的 agent，會被告知改請使用者自己手動執行該指令。Claude
Code 的 Bash，以及 Codex 的 Bash/`apply_patch`，都收到了靜態的專案接線，
指向這個共用的 guard。在依賴 Codex 之前，請先審查受信任的專案 hook
定義，以及釘選的 Friday hash；就 Codex 而言，其 callback 傳遞、exit
handling、handler 順序，以及 fail-closed 行為都尚未被驗證。Gemini 仍是
pending。這四項都已在 Claude 側實測 —— 見下方。
這套機制是一個 guardrail，而不是一個安全邊界（security boundary）。

另外一半則是那三個 Git skills。
[`safety-boundary.md`](./payload/.agents/docs/git-guideline/safety-boundary.md) 把呼叫
`$git-commit`、`$git-push` 或 `$git-create-pr`，視為針對那一個動作、在那
一個 turn 裡的授權（authorisation）——因此 commit 與 push 仍然是刻意的
行為，而不是 agent 無意間就做掉的事。

### 為什麼 Self-check 很重要

[`check-collaborative-git.sh`](./payload/.agents/hooks/check-collaborative-git.sh)
會驗證 runtime 的接線，*同時*餵給 guard 安全與不安全的 Bash、`apply_patch`
payload，只要有禁止的 payload 沒被擋下，就會判定失敗。Codex 的 seed 使用的
是在 macOS/Linux 上有支援的專案本地 hooks；Windows 上的行為尚未驗證。

最後這一點，正是值得特別留意的地方。一個被動過手腳、形同虛設的 guard，
看起來會和一個正常運作的 guard 一模一樣——直到真正出事的那一刻才會顯現。

## Friday 自身的 branch protection

這個 repository 是 private,而所屬方案無法使用 GitHub branch protection 與
rulesets,因此原本該設定的保護 —— 禁止直接推送 default branch、禁止 force
push、禁止刪除 ref —— 無法在 server 端設定。
[`.githooks/pre-push`](./.githooks/pre-push) 是本機的替代方案,接法:

```sh
git config core.hooksPath .githooks
```

它與 Friday 出貨給 consumer 的
[`payload/.agents/githooks/pre-push`](./payload/.agents/githooks/pre-push)
是同一個 hook,只有訊息指向的文件不同。它依 Git 即將送出的 refs 判斷,而非
依指令文字,因此刪除 ref、改寫歷史與推送 default branch,無論指令怎麼拼寫都會
被拒絕 —— `--force`、`-f`、refspec 前綴 `+`、`--mirror`、`--delete` 與 `:ref`
最終都歸結到同樣的兩項測試。

有三個限制必須講清楚。它只保護這個 clone:新 clone 不帶 `core.hooksPath`,在
有人設定之前都沒有保護。它無法要求 review approval,那本質上屬於 server 端。
而它是防止失誤的護欄,不是控制面 —— installer 不會把 Friday 的 payload 安裝到
Friday 自己,所以這個 repository 的 commit 並不受 consumer 所擁有的 commit-time
hooks 覆蓋。

## 非目標與復原

Friday 會安裝進入點與一個共用的 router，但它不會安裝 domain glossary、
issue tracker、Wayfinder map、prompt 範本、判斷用的 rubric、MCP 設定、
消費端專屬的 PR 驗證，或個人與 vendor 的 Skills。消費端的 overlay，可以在
審查過共享 baseline 之後，進一步延伸它，只要其引用的內容能在該專案內部
閉環即可。

Friday 也沒有 manifest、沒有自動探索（auto-discovery）、沒有自動的
更新/調和機制，也沒有強制模式。上面「更新既有消費端」的流程，是一次刻意
進行的專案變更，不是自動化的刷新。

如果 preview 發現衝突，請調和它，而不是直接覆寫。如果安裝在 preflight
之後失敗，請在重試之前先檢查那個部分建立完成的目標狀態。Git 歷史就是復原
機制：revert 那個經審查的消費端採用 commit，或是在一次新的經審查變更中，
還原回選定的那個 pin 版本。`--check` 回報的是內容與路徑型別上的差異；
它並不會替你判斷某次合併是否安全。

## 設計筆記

**複製，而不是連結（link）。** 專案會保留自己那份經審查的 baseline，以及
本地的 overlay。請在安裝前先釘選一個經審查的 Friday commit，並把它的
SHA 記錄在專案的採用紀錄裡；一個可變動的 branch，並不是一個可重現的版本。
Git 歷史提供了 rollback 的能力：revert 那個採用 commit，或是在一次經審查
的變更中還原回選定的 pin 版本。`--check` 偵測的是內容差異，而不是這些
差異是誰造成的，也不會判斷某次更新是否適合合併。

**既有消費端以人工方式調和。** Managed-core 檔案，是唯一需要逐位元組
相符的比對集合。Seeds、runtime integration，以及消費端的 overlay，會因
專案而異，需要以人工方式調和。
[`.gitignore`](./payload/.gitignore) 是一個普通、已列入 allowlist 的
seed：目標端只要內容不同，寫入前就會被視為衝突。Friday 這套空白專案的
MVP，刻意不去解析或合併 `.gitignore` 裡的 marker block。

在從像 pet-care 這樣的消費端推廣（promote）變更之前，請先就共用檔案清單
取得共識，並確認每一個遞移相依（transitive reference）都已經被附帶，或由
使用端專案明確提供。請不要整個複製一份 `.agents/` 目錄：domain 路徑、
routing、runtime 設定，以及專案 overlay，都需要分別審查。特別是 dispatch
目前尚未被納入 payload；要推廣一條依賴它的 core 規則之前，必須先做出
相依性方面的決定。請先在一個 disposable 的專案裡測試過這份審查過的套件，
才能進入採用階段；這並不代表可以藉此去刷新一個既有消費端，或變更個人的
Jarvis settings。

**Payload 本身不帶有任何專案引用。** 範例一律使用 `#123` 這類佔位符，
而不是真實的 issue 編號，也不會有任何檔案指向另一個 repository 的文件。
這一點在第一次 commit 之前就已經檢查過——`pet_care` 裡原本的那個版本，
確實帶有真實的 issue 編號與路徑，而這正是會讓一個 library 無法保持可攜
（unportable）的那種耦合。

**不依賴 `rg`。** Self-check 原本用 ripgrep 來做 stale-reference 的掃描。
但在打造這套工具的機器上，`rg` 只存在於一個互動式的 shell function 裡，
所以透過腳本呼叫它時，會出現「command not found」的錯誤——而因為那個檢查
把「什麼都沒找到」當成成功，所以它其實一直都是以一種空洞的方式「通過」。
現在它改用 `grep`，並且會先證明這個搜尋確實能找到一個已知存在的字串，
才會去信任任何「找不到」的結果。

這一段記錄的是當時那次失敗的經過，並不代表目前 pet-care 的實際行為。

## 知道某個 consumer 站在哪裡

`install.sh` 會在目標寫入 `.friday-lock.json`：記錄安裝時的 Friday commit，
以及每個 managed-core 檔案當時的 sha256。
[`bin/friday-lock`](./bin/friday-lock) 負責讀回來比對。

```sh
bin/friday-lock check <target>     # 也可以直接在 consumer 內部執行
bin/friday-lock write <target>     # 經審查的調和完成後刷新
```

三種狀態，而這個區分正是重點：

| 狀態 | 意思 | 該做什麼 |
| --- | --- | --- |
| `in sync` | 每個記錄的檔案都相符，payload 也沒動 | 不用做事 |
| `drifted` | consumer 裡的檔案與 lock 記錄的不符 | 有人在本機改了 managed-core 檔，去調和它 |
| `behind` | lock 寫下之後，Friday 的 payload 前進了 | 以一次經審查的 commit 接收變更，然後 `friday-lock write` |
| `ahead` | 這個 consumer 持有 Friday 尚未合併的 payload | **不要**把 payload 蓋上去 |
| `diverged` | 兩條 payload 線並存，互不包含 | 先 checkout 你真正要帶的那條 Friday 分支 |

**`behind` 是依內容判斷，不是比對 commit。** 一個只改 README 的 Friday commit
不會移動任何 payload 雜湊，因此不會觸發任何東西 —— 這正是讓每日排程檢查安靜到
值得一直跑的原因。

Jarvis 與 Friday 不是 payload consumer，但它們各自保有三個 payload 檔的
`.githooks` 副本。那些副本與 payload 來源**逐位元組相同**，所以 `friday-lock`
以「相等」為基準：只要 mirror 有差異就會被回報，而記錄下的兩個雜湊負責指出是哪
一邊動了。

它們過去在六行文件路徑上不同，因為正確的路徑取決於誰在執行這個檔案。現在 hook
自己解析，所以同一份檔案在 consumer、在 Friday、在只做 mirror 的 repo 裡都正確。
之所以取消那個差異，是因為**需要人工重套的差異就是會被漏掉的差異** —— 上一次
payload 移動時正是如此，而且一次漏掉四個地方。

[`bin/managed-core.txt`](./bin/managed-core.txt) 是「哪些檔案屬於 managed、
哪些屬於 consumer」的唯一真實來源。一個兩邊都沒登記的 payload 檔會讓工具大聲
失敗，而不是悄悄被發出去卻從不比對 —— 那正是當初讓三個 githooks 落在 byte-exact
集合之外、而文件還寫著十一檔的那個缺口。

## 把變更帶到各個 consumer

managed core 的變更必須到達每一個 consumer，而憑記憶做這件事，正是那五處
過期數字的由來。

```sh
bin/friday-propagate --dry-run ~/Github_Folks/pet_care ~/Desktop/Finance_App_Project
bin/friday-propagate           ~/Github_Folks/pet_care ~/Desktop/Finance_App_Project
```

它會逐一詢問 [`friday-lock`](./bin/friday-lock) 該 repository 的狀態，
**只有在 `behind` 時**才從它的 `main` 開分支、複製內容真的移動過的
managed-core 檔案、刷新 lock、commit、push、開 PR。

它選擇拒絕而不是猜測：

| 情況 | 行為 |
| --- | --- |
| `in sync` | 安靜地什麼都不做 |
| `drifted` | **拒絕** —— 那裡有人改過 managed-core 檔，覆蓋過去會同時銷毀那個修改與它的理由 |
| 工作樹不乾淨 | **拒絕**，不會用 stash 繞過 |
| 分支已存在 | **拒絕** |
| push 之後 `gh` 失敗 | 回報為失敗並附上手動完成的指令，絕不算成已開啟 |

**它永遠不會 merge。** 人工審核 checkpoint 是這個平台唯一從未被繞過的控制，
而一個傳播工具不是開這個先例的好地方。

### 為什麼是本機指令而不是 CI bot

四個 repository 都是 private 且分屬三個帳號，所以 CI 託管的 bot 需要一把對
全部都有寫入權的跨 repo token 常駐在 secret 裡。開發機上的 `gh` 本來就有這個
權限 —— 而且它綁定在一個人身上，不是綁在一個永遠在線的 workflow 上 —— 而
最終結果完全相同：開出 PR，仍由人 merge。issue #7 保留給「repo 轉 public 或
核發 token 之後」的 CI 版本。

## 在 Claude 側實測到的 runtime 行為

在某個消費端、以 **Claude Code 2.1.306** 於一次性 fixture 中實測（2026-10-22），
證據記錄在該消費端而不是這裡。Friday 自己的 self-check 證明不了其中任何一項 ——
它是靜態接線與 guard 直接探測的證據。Codex 是另一個 adapter，這些結論都不轉移。

**`onFailure: "block"` 確實做到 payload 所假設的事。** hook 以 0 與 2 以外的
exit code 結束時會擋下工具呼叫，超過 `timeout` 時也會；交給模型的訊息會寫出
`blocking because onFailure is "block"`。

**不設 `onFailure` 時，失敗的 hook 會靜默 fail-open。** 同一個 hook 以 127
結束、但省略該欄位時，指令照常執行，而模型完全沒被告知任何事 —— 沒有錯誤、
沒有警告。從 session 內部看，壞掉的 guard 與沒有 guard 無法區分。這個 payload
的每個 handler 都宣告了該欄位；拿掉它的後果現在是已知的，而不是假設的。

**同一個 matcher 下的 handler 是並行執行，不照宣告順序。** 讓第一個 handler
先睡兩秒，第二個 handler 的工作仍比它早 2.0 秒完成。即使其中一個擋下，所有
handler 仍會執行；而當多個都擋下時，只有一個理由會送達模型，且不一定是宣告在
前的那個。擋下本身是可靠的：任何 handler exit 2 都會拒絕該呼叫。這個 payload
沒有任何東西依賴順序，但未來若有 handler 假設自己會先跑、或假設只有自己會被
聽見，那就會是錯的。

**Hook 來源是疊加的，不能用來解除 guard。** 放在
`.claude/settings.local.json` 或透過 `--settings` 提供的放行 handler，會與
專案中拒絕的 handler **一起**執行，而該呼叫仍然被擋下。把整個 `--settings`
檔傳成 `{}` 也移除不了任何東西：專案的 handler 照樣執行、照樣擋下。所以
`claude --settings <空檔>.json` 不是一條繞過路徑。

未實測：user 層 `~/.claude/settings.json` 的優先序 —— 要測就得把憑證複製到
暫存目錄；以及關於 Codex 或 Gemini 的任何事。

## 驗證與測試

執行 `bash` [`tests/install-smoke.sh`](./tests/install-smoke.sh)
`/absolute/path/to/retained-test-output`。
這個檢查會建立可拋棄的 Git fixture，安裝這個 repository 真正的 payload，
並保留證據供日後審查。它絕對不會安裝進一個既有的專案。清理（cleanup）是
另一個需要另外、明確授權才能執行的操作。
