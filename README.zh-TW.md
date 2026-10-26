# Friday

[English](./README.md) · **繁體中文**

> **摘要**：Friday 是可受版本控管的共享專案基線（shared project baseline）；個人層不在這裡。
> 先以 `--check` 預覽，再安裝封閉式的 allowlist。衝突絕不覆寫，現有專案需經
> 人工審查後調和。

Friday 是一套可攜式、經過審查的共享專案基線（baseline）。它會把專案範圍內的政策、Git
skills、共用的暫存檔規範，以及 Claude/Codex 的 guard 接線，複製進消費端（consumer）
repository，而不依賴開發者個人的 home 目錄、個人 Skills 或 vendor 工作流程。

它同時處理三個限制：封閉式 allowlist 讓 bootstrap 維持衝突安全（conflict-safe）；
以複製方式交付內容讓 baseline 保持可攜且可審查；既有消費端的變更則停留在經審查的
調和（reconciliation）邊界之後，而不會變成自動更新。開發者的個人層不屬於這裡：
請勿將個人的 Skills、settings 或其他依賴個人 home 目錄的內容，放進 Friday 的專案契約中。
可攜的成果應該放在專案自己管控的文件、測試或自動化裡；輔助工具可以協助操作者，
但沒有任何消費端被允許把這些輔助工具當成 bootstrap 或滿足 Friday 契約的前提。

Friday 是怎麼走到現在的，記錄在 [`docs/history.md`](./docs/history.md)（英文）：有日期的
決策與事故、實測記錄與近期進度。本 README 只描述現在。

## 何時該使用 Friday

| 情境 | Friday 的角色 | 該怎麼做 |
| --- | --- | --- |
| 全新的 Git repository | Bootstrap 經審查的 baseline | 先 Preview，安裝最新的 release，然後再 Preview 一次。 |
| 既有專案 | 取走 managed core，保留專案自己的檔案 | 執行 `--managed-only`，然後在一次經審查的變更中，以人工調和列出的 seeds。 |
| 個人 Skills 或偏好 | 讓個人範圍維持個人 | 留在你的個人層；不要把它推進 Friday。 |
| 專案特有的政策或檢查 | 保留消費端的所有權 | 在審查過共享 baseline 之後，再新增消費端 overlay。 |

## 架構

Friday 是一個 repository：baseline。它收納 **payload**（`payload/`，專案收到的檔案）、
搬運 payload 的工具，以及證明這些工具的測試。拿了 payload 的專案叫 **consumer**
（消費端）。payload 是被複製進消費端的，而不是連結（link）回 Friday 的 checkout，
所以消費端對 Friday 的檔案系統沒有相依性。

### Payload 包含什麼

[`bin/managed-core.txt`](./bin/managed-core.txt) 為每個 payload 檔案分類，清單沒有點名的檔案會讓工具失敗。
檔案分三種：

| 種類 | 哪些檔案 | 規則 |
| --- | --- | --- |
| **Managed core** | 十五個檔案：`.agents/docs` 底下的政策文件、`.agents/bin/setup.sh`、guard 與它的 checker、三個 Git hooks、三個 Git Skills | 逐位元組比對。消費端讓它們與某個 release 完全相同；每一次變更都經由 release 到達。 |
| **Seeds** | `AGENTS.md`、`CLAUDE.md`、`.agents/AGENTS.md`、`.gitignore`、`.claude/settings.json`、`.codex/hooks.json`（清單中帶 `!` 的項目） | 只在新專案複製一次。之後就是專案自己的：不比對、不帶出。 |
| **消費端自己的 overlay** | 專案另外加入的任何東西：自己的 Skills、自己的文件、`.agents/hooks/check-project-agent-integration.sh` | Friday 絕不碰，也不列在清單裡。 |

runtime hook 連結與 `.claude/skills/<name>` 連結，由 `setup.sh` 在每個 clone 裡建立；它們不是 payload 檔案。

### 工具，以及各自何時執行

| 工具 | 何時執行 | 做什麼 |
| --- | --- | --- |
| [`install.sh`](./install.sh) | 每個專案一次，從 Friday checkout 執行 | 預覽、寫入前先拒絕衝突，然後把 release 放進專案（`--working-tree` 則是這個 checkout；`--managed-only` 則只放 managed core），執行 `setup.sh`（該 release 有附的話）、寫入 lock、執行 self-check。 |
| [`.agents/bin/setup.sh`](./payload/.agents/bin/setup.sh) | 在消費端，v1.1.0 起：由安裝執行，之後每次 clone、每次 Skill 變動後再執行 | 不從 Friday 搬任何東西。補上 clone 缺少的接線：`core.hooksPath`、runtime hook 連結、缺少時的 root pointer、Skill 連結。 |
| [`bin/friday-lock`](./bin/friday-lock) | `write` 由安裝與 `friday-propagate` 執行；`check` 隨時可用 | 寫入並讀取消費端的 `.friday-lock.json`，並說明消費端是 in sync、drifted 還是 behind。 |
| [`bin/friday-propagate`](./bin/friday-propagate) | 維護者有 release 要帶出去時 | 把某個 release 的 managed-core 變更，以 pull request 的形式複製進每個 behind 的消費端。它永遠不會 merge。 |

### 發行版本與 lock

**release** 是 `main` 上某個經審查 commit 的 annotated tag `vMAJOR.MINOR.PATCH`，並已推送到
`origin`（見[發行版本（Releases）](#發行版本releases)）。它是消費端唯一會收到的東西：
`install.sh` 與 `friday-propagate` 都只取 release，絕不取 branch，也不取 checkout 當下持有的內容。
消費端的 `.friday-lock.json` 記錄 release 的 tag、最後一次修改 payload 的 commit，以及安裝當下每個
managed 檔案的 sha256（見[知道某個 consumer 站在哪裡](#知道某個-consumer-站在哪裡)）。

```text
  Friday checkout (~/.Friday)                 consumer project
  +----------------------------+              +----------------------------+
  | main  --o--o--o            |              | managed core   identical   |
  |              \             |  install.sh  | seeds          yours       |
  |           [v1.1.0] --------+------------> | overlays       yours       |
  |                            |  (the tag's  | .friday-lock.json          |
  | feature branch, edits      |   tree only) |   tag, commit, sha256      |
  |   never installed, unless  |              +-------------^--------------+
  |   --working-tree           |                            |
  +-------------|--------------+          .agents/bin/setup.sh: hooks and
                |                         links, in every clone (the install
                v                         runs it too)
  bin/friday-propagate: the tag's managed-core changes become a pull request
  in each consumer that is behind; a person merges it.
  bin/friday-lock: writes the lock at install and propagate; check compares a
  consumer with its lock and with Friday.
```

兩個生成出來的 runtime hook 連結，都指向消費端自己那份已複製的共用 guard，因此這些
adapter 共用同一份經審查的 guard 實作，而不會對 Friday 的檔案系統產生相依性。

Friday 刻意不做成一個通用的 runtime manager。它檢查的是靜態的 Codex 接線（wiring），
而不是原生的 callback 行為、exit handling、handler 順序，或 fail-closed 的強制
執行；Gemini 的支援仍是 pending。這四項已在某個消費端的 Claude 側實測（見
[實測記錄](./docs/history.md#2026-10-22-runtime-behaviour-measured-on-the-claude-side)），但 Codex 是另一個 adapter，對它而言
仍未驗證。Friday 也不會自動探索任意 Skills，或安裝消費端專屬的 domain workflow。

## 採用 Friday

> **摘要**：`install.sh` 預設安裝最新的 release，不是這個 checkout 目前的內容；
> 新專案用 `install.sh`，既有專案用 `--managed-only` 只拿 managed core、seeds 留給專案自己
> 調和；clone 之後執行 `setup.sh`；之後由維護者用 `friday-propagate` 開 pull request。

先備條件是 Git、Bash 與 `jq`。`.agents/bin/setup.sh` 與 `CLAUDE.md` seed 從 `v1.1.0` 起才附帶；更早的 release
（`v1.0.0`、`v1.0.1`）兩者都沒有，它的安裝程式自己為 clone 接線，從這類 release 安裝的專案也沒有 `setup.sh`
可在 clone 之後執行（那裡全新 clone 缺少的是 `git config core.hooksPath .agents/githooks`）。安裝程式是本機
Friday checkout 裡的一支腳本；還沒有的話，一行就能取得：

```sh
git clone https://github.com/ShenYo/Friday.git ~/.Friday
```

那個 checkout 是開發用 checkout，常常停在 feature branch 上或有未提交的修改，所以 `install.sh`
絕不安裝它手上的內容。它安裝的是一個 release：最新的 annotated tag `vX.Y.Z`，挑選與檢查的方式與
`friday-propagate` 相同（在 `origin` 上是同一個 tag object，且可從 `main` 到達）。它會匯出該 release
的 tree，並在其上執行該 release 自己的 `install.sh`，因此不論 checkout 長什麼樣子，lock 記錄的都是
release 的 commit 與 tag。沒有任何 release 合格時，它會拒絕，並說明怎麼 fetch 或建立一個。
`--release vX.Y.Z` 指定其中一個；`--working-tree` 則照原樣安裝這個 checkout，會附上警告，
只供開發 Friday 本身使用。

### 新專案

```sh
git init <project>
bash ~/.Friday/install.sh --check <project>   # 預覽；不寫入任何東西
bash ~/.Friday/install.sh <project>           # 最新的 release
bash ~/.Friday/install.sh --check <project>   # 每個檔案行都應該是 IDENTICAL
```

要釘選某個 release：`bash ~/.Friday/install.sh --release vX.Y.Z <project>`。安裝最後會執行 payload
自己的 self-check，因此 runtime 接線出錯時會在當下就失敗，而不是等到有人真正依賴那個邊界時才出事。
安裝輸出的第一行 `release: vX.Y.Z (commit ...)` 會點名 release；請對它驗證位元組：

```sh
FRIDAY_TREE=vX.Y.Z bash ~/.Friday/bin/friday-lock check <project>   # 預期：status: in sync
```

`FRIDAY_TREE` 讓 `friday-lock` 讀 release 本身。單純的 `check` 讀的是 checkout 的 working tree，在開發用
checkout 上它比 release 新，所以會對一個正確的安裝回報 `behind`。審查完產生的 worktree diff 之後，再依專案
自己的規則，另外決定是否、以及如何 commit 它。

### 既有專案

已經有自己的 `AGENTS.md`、`.gitignore` 或 runtime 接線的專案，只取 managed core：

```sh
bash ~/.Friday/install.sh --managed-only --check <project>
bash ~/.Friday/install.sh --managed-only <project>
```

seeds 仍是專案自己的。每一個都會列成 `SEED <path> (yours; not touched)`（或 `missing; not
created`；release 有附 `setup.sh` 時，兩個 root pointer 會是 `missing; setup.sh creates it from Friday's
seed`；或 `identical to Friday's`），讓人看到還有哪些要以人工調和；[`ADOPTING.zh-TW.md`](./ADOPTING.zh-TW.md)
有判讀預覽輸出的決策樹。安裝真正會寫入的部分，仍維持寫入前拒絕的 preflight：managed 檔案內容不同就是
`CONFLICT`（完全相同則不是），既有的 `core.hooksPath`、`.git/hooks` 裡的 hook，以及擋路的 Skill
連結也是。`--managed-only` 可與預設的 release、`--release`、`--working-tree` 搭配。self-check 仍在最後執行，
在帶有 guard 接線的 seeds（`.claude/settings.json`、`.codex/hooks.json`）成為專案自己的、並接好線之前，
它會失敗。

### clone 消費端之後，或 Skills 變動之後

```sh
bash .agents/bin/setup.sh   # --check 可預覽；它做什麼見下方
```

`core.hooksPath` 是本地 Git 設定，所以全新的 clone 在執行這行之前，不會執行 payload 的任何 Git hooks。
它做什麼，見[setup.sh 做什麼](#setupsh-做什麼)。

### 持續保持最新

Friday 的維護者在建立 release 之後，執行 `bin/friday-propagate <consumer>...`。它會在每個 behind 的
消費端開一個 pull request，帶上有變動的 managed-core 檔案；由人審查並 merge。見
[把變更帶到各個 consumer](#把變更帶到各個-consumer)。

### 安裝會檢查並拒絕什麼

`--check` 會回報 `NEW`、`IDENTICAL` 或 `CONFLICT`（搭配 `--managed-only` 時還有 `SEED`），遇到衝突時以
非零碼結束，且不會複製檔案、改變檔案權限、建立連結，也不會執行 self-check。兩種模式都會在對目標進行
任何寫入之前，先驗證所有先備條件、每一個目的地，以及目標現有的 hook 設定（任何設定範圍中生效、且不是
`.agents/githooks` 的 `core.hooksPath`，或接線後會被略過的 `.git/hooks` 裡的 hook 與 hook symlink）。
目標是 repository 的根目錄，而不是某個 `.agents/` 子目錄，且具有 `.git/` 目錄（linked worktree 會被
拒絕，因為 `core.hooksPath` 由同一個 repository 的所有 worktree 共用，從其中一個接線會讓其他 worktree
不再執行任何 hook）。它們也會檢查 `setup.sh` 將建立的 `.claude/skills/<name>` 連結，依複製完成後的 Skills
（目標自己的 `.agents/skills` 加上 payload 的）計算：兩個 Skill 同名、被真實檔案或目錄擋住、指向別處的連結、
複製後會變成有效的斷鏈、或不是 `setup.sh` 寫的斷鏈，都是衝突，所以安裝會被拒絕，而不是做到一半才停下。
任何非預期的目的地 symlink（包含祖先路徑上的 symlink）都視為衝突；只接受三種連結：那兩個精確指定的
Claude 與 Codex hook 連結、已經正確的 `.claude/skills/<name>` 連結，以及指向 `.agents/skills/`、會由
`setup.sh` 替換掉的斷鏈。

安裝會補齊缺少的檔案，並保留內容相同的既有檔案。當內容不同時，它會拒絕覆寫，`.claude/settings.json`
也包含在內。這裡刻意沒有提供強制（force）模式。請先在目標專案中審查並調和衝突，再重新預覽一次。與
payload 並存的專案特定檔案維持本地狀態；只有 payload 自己擁有的 hook 腳本，才會被賦予可執行權限。
Preview 比對的是內容與路徑型別，而不是可執行權限。Preflight 本身不是一個 transaction：之後發生的 I/O
或 self-check 失敗，可能會讓新檔案已經留在原地，而並行發生的目標端變更，也不在這個保證範圍之內。請在
重試之前先檢查結果；絕對不要對同一個目標同時執行多個安裝程序。Friday 複製的是它自己封閉的 payload 到
目標專案；它不會複製整個 Friday repository，也不會把目標專案連結（link）回 Friday。

從 `v1.1.0` 起，安裝流程會在目標中執行 payload 自己的
[`.agents/bin/setup.sh`](./payload/.agents/bin/setup.sh) 來為這個 clone 接線；更早的 release 沒有
`setup.sh`，由它的安裝程式自己接線。最後一步再執行 payload 自己的 self-check。

## 現況（2026-10-25）

> **摘要**：managed core 現為十五檔，其中十四檔已以 v1.0.0（2026-10-25）發行；
> 下一版 v1.1.0 帶來 `.agents/bin/setup.sh`、`CLAUDE.md` seed 與以 release 為準的安裝。
> pet_care 與 Finance 兩個 consumer 都已同步在 v1.0.0。待辦：指定 backup maintainer、
> 真正的新機器 replay、第三個 consumer、external-runtime 收尾，以及 managed-core 更新 bot。

已就位：

- managed core：15 個檔案，列在 [`bin/managed-core.txt`](./bin/managed-core.txt)。
  `v1.0.0`（2026-10-25）發行了前 14 個，`.agents/bin/setup.sh` 是第 15 個。
- 已發行 `v1.0.0`（2026-10-25），以及 `v1.0.1`（2026-10-25，只有文件，payload 相同）。
  consumer 只以 release 接收 managed core（見 [發行版本（Releases）](#發行版本releases)）。
- 兩個 consumer，`pet_care` 與 Finance，都記錄 `v1.0.0`，狀態為 `in sync`。
- `main` 上要求 CI：ubuntu 與 macos 的測試、shellcheck 與 gitleaks
  （[`ci.yml`](./.github/workflows/ci.yml)）。

待辦：

- 指定備援維護者（見[生命週期治理](#生命週期治理b06)）。
- 真正的新機器 replay。
- 第三個 genuine consumer。
- External-runtime 的收尾：Friday 尚未驗證的 Codex 與 Gemini 行為。
- 下一個 release `v1.1.0` 帶來 `.agents/bin/setup.sh`、`CLAUDE.md` seed 與以 release 為準的安裝
  （`install.sh` 安裝 release，而不是 checkout），讓 consumer 不再需要專案本地的 `setup-ai.sh`
  來建立 root pointer 與 Claude Code 的 Skill 連結。
- managed-core 更新 bot，讓 Friday 發行時自動向 consumer 開 pull request：
  [ShenYo/Friday#7](https://github.com/ShenYo/Friday/issues/7)。

把更廣的工作歸在一起的 agent-platform epic 是
[ShenYo/Friday#10](https://github.com/ShenYo/Friday/issues/10)；上面沒有自己連結的項目，
目前沒有 open issue。

## 生命週期治理（B06）

> **摘要**：Friday 的 MVP 採「可審查 release（tag + commit）+ consumer 手動採用」模式：
> repository owner 負責維護，backup maintainer 尚待指定；不自動同步、不強制
> 更新，也不自動 rollback。

本節為 Friday MVP 生命週期的規範性章節。

- Repository owner 是 Friday 的主要維護者。備援維護者（backup maintainer）
  目前仍是 **PENDING**；在指定之前，主要維護者仍負責發行審查、復原提案，
  以及記錄相關決策。
- 一個 release 是 `main` 上某個經審查 commit 的 annotated tag
  `vMAJOR.MINOR.PATCH`。consumer 的 `.friday-lock.json` 會記錄這個 tag，並以
  「該 release 當下最後一次修改 payload 的 commit」作為信任的依據，它的 payload
  與這個 release 逐位元組相同；tag 只是標籤，tag 被移動時，`friday-lock check`
  會回報 `status: tag-moved`。可變動的 branch 名稱不算是發行版本。
- 消費端的擁有者，以人工方式採用一個經審查的發行版本，並保留該消費端自己的
  seeds、runtime integration 與 overlay。Friday 不會自動同步，也不會自動
  更新既有的消費端。
- 當需要復原時，由 Friday 維護者提出經審查的 rollback 或調和方案。消費端
  擁有者，在該消費端 repository 中執行這個經審查的還原或調和；Friday 絕不會
  強制更新消費端，也不會自動替消費端 rollback。
- 每一個候選發行版本，在被消費端採用之前，都必須先經過一次 disposable-project
  的 replay。真正的新機器 replay、以第三個 genuine consumer 進行驗證，以及
  cross-runtime 的收尾，都仍是 **PENDING** 的後續工作。

Vendor Skills（包含 Matt Pocock Skills）留在安裝它們的個人層，並維持 vendor-pristine
狀態。Friday 只管理可攜的、專案本地輸出內容契約，內容記錄在
[`scratch-files.md`](./payload/.agents/docs/scratch-files.md)；它既不安裝也
不複製 vendor Skills，也不宣稱擁有 runtime 的 invocation 或 precedence 強制力。

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
runtime 行為，本 README 無法保證，所以請持續要求 agent 回報它實際載入了哪些
instruction 文件。原生的 workspace trust、callback 傳遞、優先序，以及其他 runtime 行為，仍屬於各
runtime 自己要補的證據工作。Gemini CLI 與 `agy` 在這裡仍是 pending，所以
本指南刻意不為它們提供任何臆測性的啟動指令。

### setup.sh 做什麼

安裝只執行一次、在一台機器上，所以讓消費端能運作的部分東西，每次重新 clone 都
會遺失：`core.hooksPath` 是本地 Git 設定，clone 在它被設定之前，payload 的 Git
hooks 都不會執行。clone 消費端之後，以及新增、移除或改名 Skill 之後，請在它裡面
的任何位置執行下面這行（加上 `--check` 可預覽，它不會寫入任何東西）：

```sh
bash .agents/bin/setup.sh
```

它做四件事：

- 把 `core.hooksPath` 設為 `.agents/githooks`（任何設定範圍中生效、且是別的值時，
  回報為 `CONFLICT`，不會覆蓋它），並回報缺少或不可執行的 Git hook，以及接線後會被
  略過的 `.git/hooks` 裡的 hook 與 hook symlink；
- 把 `.claude/hooks/guard-collaborative-git.sh` 與
  `.codex/hooks/guard-collaborative-git.sh` 連結到共用 guard；
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

## 所有權：Managed Core、Seeds 與 Overlays

Managed core 是精確比對的：既有消費端會把這十五個檔案，與他們審查過的
Friday 版本逐位元組（byte-for-byte）比對。

```
.agents/docs/agent-rules.md
.agents/docs/testing.md
.agents/docs/scratch-files.md
.agents/docs/git-guideline/git-commit.md
.agents/docs/git-guideline/pr-evidence.md
.agents/docs/git-guideline/safety-boundary.md
.agents/bin/setup.sh
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
tool hooks，透過 `core.hooksPath` 由
[`setup.sh`](./payload/.agents/bin/setup.sh) 接上，installer 會執行它，每個 clone
也會再執行一次。
[`pre-commit`](./payload/.agents/githooks/pre-commit) 掃描 staged 內容中的憑證、
[`commit-msg`](./payload/.agents/githooks/commit-msg) 強制訊息契約、
[`pre-push`](./payload/.agents/githooks/pre-push) 則依 Git 即將送出的 refs 判斷，
因此刪除 ref、改寫歷史或推送 default branch，無論指令怎麼拼寫都會被拒絕。
對一個完全沒有 ref 的 remote 做第一次推送則會放行：沒有 default branch 要保護、
沒有 ref 可刪、也沒有歷史可改寫，而拒絕它會讓「建立一個 repository」在不繞過
hook 的前提下變得不可能。它們
與 managed core 其餘檔案一樣需要逐位元組比對，所以下方的對帳流程必須帶上它們
（[history](./docs/history.md#2026-10-22-the-git-hooks-were-missing-from-the-managed-core-list)）。

以下這些屬於空白 repository 的 seeds 或 runtime integration，並不是
managed core。既有消費端需要自行以人工方式調和它們：

```
AGENTS.md                                    root pointer
CLAUDE.md                                    root pointer for Claude Code
.agents/AGENTS.md                            shared policy router
.gitignore                                   temporary-file ignore rule
.claude/settings.json                        Claude PreToolUse wiring
.claude/hooks/guard-collaborative-git.sh     generated symlink to the guard
.claude/skills/<name>                        generated symlinks to .agents/skills
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

消費端的 overlay，不屬於上面任何一份清單。消費端可以額外加入一個可執行的
一般檔案 `.agents/hooks/check-project-agent-integration.sh`；當它存在時，
managed core 的 checker 會執行它，並把失敗結果往外傳遞。Friday 本身不會
附帶這個擴充功能。

這是一份明確的靜態 allowlist，也就是
[`install.sh`](./install.sh) 讀取的 [`bin/managed-core.txt`](./bin/managed-core.txt)，
而不是自動的 payload 探索機制。新的 payload 檔案在被審查並加進這份清單之前，
都會在清查（inventory）驗證階段失敗。這個 MVP 裡沒有 manifest，也沒有
update engine。

## 更新既有消費端

既有消費端由 `bin/friday-propagate` 更新到某個 release，由它開 pull request（見
[持續保持最新](#持續保持最新)）。手動做則是一次經審查的調和（reconciliation），而不是安裝程式的升級：
`--managed-only` 用來採用 managed core，managed 檔案已經變動時，在那裡是 `CONFLICT`，絕不會被覆寫。
先針對你打算採用的 release，預覽哪些檔案不同：

```sh
FRIDAY=~/.Friday
TARGET='/absolute/path/to/consumer'

bash "$FRIDAY/install.sh" --managed-only --check --release vX.Y.Z "$TARGET"
```

請讀過每一個 `CONFLICT`，並在一次經審查的消費端變更中調和它。只同步上面列出的十五個 managed-core
路徑，每個都取自該 release（`git -C "$FRIDAY" show "vX.Y.Z:payload/$rel" > "$TARGET/$rel"`，並保留
Git hooks 與腳本的檔案權限）。請保留消費端自己的 seeds、runtime integration 與 overlay；不要整個複製一份
`.agents/` 目錄。接著在消費端執行 `bash .agents/bin/setup.sh`（先用 `--check` 預覽）為這個 clone 接線，
再執行 `bash "$FRIDAY/bin/friday-lock" write "$TARGET"` 刷新 lock。

調和完成之後，請驗證該消費端，而不是把安裝程式當成一個更新引擎來用：

```sh
(cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh)
bash "$FRIDAY/bin/friday-lock" check "$TARGET"
git -C "$TARGET" diff --check
```

這個 checker，在消費端的擴充存在時會執行它。請審查產生出來的消費端 diff，
並依該 repository 自己的規則，建立一個原子性（atomic）的消費端 commit。
Friday 沒有強制模式、沒有 manifest、沒有自動同步，也沒有自動調和機制。

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
pending。這四項都已在 Claude 側實測（[實測記錄](./docs/history.md#2026-10-22-runtime-behaviour-measured-on-the-claude-side)）。
這套機制是一個 guardrail，而不是一個安全邊界（security boundary）。

其中兩項結果決定了 payload 的寫法。每個 handler 都宣告 `onFailure: "block"`，因為沒有
它時，失敗的 hook 會靜默 fail-open，與沒有 guard 無法區分。而同一個 matcher 下的
handler 是並行執行的，多個 handler 同時阻擋時只有一個理由會傳到 model，所以任何
handler 都不能假設自己先執行、或只有自己會被聽見。hook 的設定來源是合併而不是覆蓋，
所以寬鬆的設定檔無法解除 guard：`claude --settings <empty>.json` 不是繞過的方法。

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

## Friday 自身的 branch protection 與 hooks

Friday 是 public repository，default branch 上的 GitHub ruleset 會拒絕刪除、
force push，以及不經 pull request 進來的變更。這些 pull request 的 review 要求，
由 owner 在 server 端設定。

在本機，這個 repository 直接執行 payload 的 hooks，而不是副本：

```sh
git config core.hooksPath payload/.agents/githooks
```

這是 producer 的路徑。安裝好的 consumer 在 `.agents/githooks` 有同樣的 hooks，
由 `install.sh` 接上。

**在這個配置之前 clone 的 repository，仍然指向 `.githooks`**，而那個目錄已經不
存在。git 這時找不到任何 hook，也就一個都不執行，而且不會告訴你。pull 之後請檢查
並修正：

```sh
git config --get core.hooksPath   # 預期：payload/.agents/githooks
git config core.hooksPath payload/.agents/githooks
```

因此 consumer 拿到的 `pre-commit` secret scan、`commit-msg` 格式檢查，以及
`pre-push` 的 ref 檢查，也會在 Friday 自己的 commit 與 push 上執行。payload
裡改動的 hook，在出貨之前，就會先在這裡的下一個 commit 生效。`pre-push` 依
Git 即將送出的 refs 判斷，而非依指令文字，因此刪除 ref、改寫歷史與推送 default
branch，無論指令怎麼拼寫都會被拒絕 —— `--force`、`-f`、refspec 前綴 `+`、
`--mirror`、`--delete` 與 `:ref` 最終都歸結到同樣的兩項測試。

仍有兩個限制。`core.hooksPath` 是 per-clone 設定，永遠不會被 clone 帶走，所以
新 clone 在有人設定之前不會執行任何 hook（在消費端，`bash .agents/bin/setup.sh`
會設定它）。而這些 hooks 是防止失誤的護欄，不是
控制面：hooks 被略過時，真正擋得住的是 server 端的 ruleset。

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
本地的 overlay。安裝取的是 release，所以專案的 lock 會記錄 tag 與它背後的 commit，
`--release vX.Y.Z` 可釘選其中一個；可變動的 branch，或帶有修改的 checkout，都不是可重現的
版本。Git 歷史提供了 rollback 的能力：revert 那個採用 commit，或是在一次經審查
的變更中還原回選定的 release。`--check` 偵測的是內容差異，而不是這些
差異是誰造成的，也不會判斷某次更新是否適合合併。

**既有消費端以人工方式調和。** Managed-core 檔案，是唯一需要逐位元組
相符的比對集合。Seeds、runtime integration，以及消費端的 overlay，會因
專案而異，需要以人工方式調和；`--managed-only` 不動它們，只把 seeds 列出來。
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
settings。

**Payload 本身不帶有任何專案引用。** 範例一律使用 `#123` 這類佔位符，
而不是真實的 issue 編號，也不會有任何檔案指向另一個 repository 的文件，
因為那種耦合會讓一個 library 無法保持可攜（unportable）
（[history](./docs/history.md#2026-09-08-the-payload-was-checked-for-project-references-before-the-first-commit)）。

**不依賴 `rg`。** Self-check 使用 `grep`，並且會先證明這個搜尋確實能找到一個已知
存在的字串，才會去信任任何「找不到」的結果，因為把「什麼都沒找到」當成成功的檢查，
在它的工具不存在時會空洞地「通過」
（[history](./docs/history.md#2026-09-08-the-self-check-searched-with-a-tool-that-was-not-there)）。

## 知道某個 consumer 站在哪裡

`install.sh` 會在目標寫入 `.friday-lock.json`：記錄安裝時的 Friday commit、
（有的話）命名了那份 payload 的 release tag（release 安裝一定有；`--working-tree` 的 payload
對不上任何 release 時為 `null`），以及每個 managed-core 檔案當時的 sha256。

[`bin/friday-lock`](./bin/friday-lock) 負責讀回來比對。只有 payload consumer
才有這份記錄。想用 payload 裡某個 hook、但不採用整份 payload 的 repository，
自己保有一份副本，Friday 不追蹤它。

```sh
bin/friday-lock check <target>     # 也可以直接在 consumer 內部執行
bin/friday-lock write <target>     # 經審查的調和完成後刷新
```

`check` 拿消費端與它所在的 Friday checkout 比對，所以當 checkout 的 payload 比消費端採用的 release
更新時，它會顯示 `behind`：這代表 Friday 往前走了，不是安裝出了問題。
要對照消費端採用的那個 release，請點名它：`FRIDAY_TREE=vX.Y.Z bin/friday-lock check <target>`。

這些狀態，而這個區分正是重點：

| 狀態 | 意思 | 該做什麼 |
| --- | --- | --- |
| `in sync` | 每個記錄的檔案都相符，payload 也沒動 | 不用做事 |
| `drifted` | consumer 裡的檔案與 lock 記錄的不符 | 有人在本機改了 managed-core 檔，去調和它 |
| `tag-moved` | lock 記錄了一個 release tag，而 Friday 同名的 tag 現在指向的 payload 與 lock 記錄的不同（這個 clone 沒有的 tag 會回報為未驗證，而不是被移動） | 信任 lock 裡的 commit，不要信任 tag；查出是誰移動了它，然後 `friday-lock write` |
| `behind` | lock 寫下之後，Friday 的 payload 前進了，或有檔案新加入 managed core（標為 `new in the payload`） | 以一次經審查的 commit 接收變更，然後 `friday-lock write` |
| `retired` | lock 記錄了一個 Friday 已不再管理的檔案 | 刻意決定刪除它或保留為 consumer 自己的檔案，然後 `friday-lock write`。consumer 沒有其他東西要帶時，`friday-propagate` 只會列出它，不會動它。有變更要帶時，它的 pull request 會列出這個檔案，merge 之後即記錄為 consumer 自己的檔案，除非先在那個 branch 上刪掉它 |
| `ahead` | 這個 consumer 持有 Friday 尚未合併的 payload | **不要**把 payload 蓋上去 |
| `diverged` | 兩條 payload 線並存，互不包含 | 先 checkout 你真正要帶的那條 Friday 分支 |

**`behind` 是依內容判斷，不是比對 commit。** 一個只改 README 的 Friday commit
不會移動任何 payload 雜湊，因此不會觸發任何東西 —— 這正是讓每日排程檢查安靜到
值得一直跑的原因。

[`bin/managed-core.txt`](./bin/managed-core.txt) 是「哪些檔案屬於 managed、
哪些屬於 consumer」的唯一真實來源。一個兩邊都沒登記的 payload 檔會讓工具大聲
失敗，而不是悄悄被發出去卻從不比對
（[history](./docs/history.md#2026-10-22-the-git-hooks-were-missing-from-the-managed-core-list)）。

## 把變更帶到各個 consumer

managed core 的變更必須到達每一個 consumer，而憑記憶做這件事，會留下過期的數字
（[history](./docs/history.md#2026-10-22-the-git-hooks-were-missing-from-the-managed-core-list)）。

請從一個與 `origin/main` 一致的 `main` 執行；怎麼確認，寫在
[`AGENTS.md`](./AGENTS.md#changing-the-payload) 第 4 步。一次執行會 pin 住 release tag 所指的
commit（見下方 Releases），只帶那個 commit 的 tree，因此未 commit 的 payload 修改、
已 merge 到 `main` 但尚未 release 的 payload 變更，或執行期間才出現的 Friday
commit，都不會到達 consumer。

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
| consumer 的檔案在那次檢查之後、寫入之前被改動 | **拒絕**，保留那個改動 |
| pull consumer 的 `main` 之後出現 drift，或要帶的內容變了 | **拒絕**，回到 `main`，什麼都不寫 |
| 寫入或 commit 之前，HEAD 離開了 sync branch | **拒絕**，並說明 HEAD 在哪裡 |
| 只有 `retired` | **拒絕**，並列出退役的檔案；刪不刪是 owner 的決定 |
| Friday 不在 `main` 上 | **拒絕**，在讀取任何 consumer 之前 |
| 沒有 release tag，或該 tag 不在 `main` 上、不是 annotated、或不在 `origin` 上 | **拒絕**，在讀取任何 consumer 之前 |
| `tag-moved` | **拒絕** —— lock 記錄的 release 標籤已不可信，要由人來調和 |
| 分支已存在 | **拒絕** |
| push 之後 `gh` 失敗 | 回報為失敗並附上手動完成的指令，絕不算成已開啟 |

**它永遠不會 merge。** 人工審核 checkpoint 是這個平台唯一從未被繞過的控制，
而一個傳播工具不是開這個先例的好地方。

### 為什麼是本機指令而不是 CI bot

consumer 都是 private，且位於 Friday 以外的兩個帳號，所以 CI 託管的 bot 需要一把對
全部都有寫入權的跨 repo token 常駐在 secret 裡。開發機上的 `gh` 本來就有這個
權限 —— 而且它綁定在一個人身上，不是綁在一個永遠在線的 workflow 上 —— 而
最終結果完全相同：開出 PR，仍由人 merge。[issue #7](https://github.com/ShenYo/Friday/issues/7) 保留給「consumer 轉 public 或
核發 token 之後」的 CI 版本。

## 發行版本（Releases）

一個 release 是 `main` 上某個經審查 commit 的 annotated tag
`vMAJOR.MINOR.PATCH`。commit 才是記錄；tag 只是它的名字，而 tag 可以被移動、
commit 不行。`main` 上任何經審查的變更都可以發版，文件也包括在內；只有 payload 或
[`bin/managed-core.txt`](./bin/managed-core.txt) 有差異的 release，consumer 才有東西
要接收，其他的 `friday-propagate` 不會動。

- **PATCH**：只有文件的變更，payload 裡的文件也算在內。
- **MINOR**：會執行的東西的變更：Skill、Git hooks 與 guard script。
- **MAJOR**：結構上的大變更。

annotated tag 的訊息就是 release note：改了什麼、consumer 必須做什麼。

```sh
git tag -a vX.Y.Z -m '<release note>' <commit>
git push origin vX.Y.Z
bin/friday-propagate <consumer>...
```

`install.sh` 以同樣方式安裝 release：預設是最新的一個，挑選與檢查的方式如下，或用
`--release vX.Y.Z` 指定；沒有合格的 release 時，它會拒絕、什麼都不寫，並說明要 fetch tags
或建立一個。比加入 `--working-tree` 的那一版更早的 release 沒有這個旗標；它自己的安裝程式以舊介面執行，
安裝它自己的 tree，而那正是這個 release。

推送任何 tag 都是一個 checkpoint
（[`safety-boundary.md`](./payload/.agents/docs/git-guideline/safety-boundary.md)）：
只有在使用者於當下這個 turn 點名 tag 與它的 commit 時，agent 才能推送，透過
`--tags` 或 `--follow-tags` 順帶推送也一樣。Friday 的 guard 和 `pre-push` 都不會檢查
這一條，它是靠 instruction 執行的。

`bin/friday-propagate` 只帶 release：預設是格式剛好為 `vX.Y.Z` 的最新 tag
（`v1.1.0-rc1` 這類 pre-release 永遠不算），或用 `--tag vX.Y.Z` 指定的那一個。
Friday 沒有 release tag，或該 tag 不在 `main` 上、不是 annotated tag、或 `origin`
上沒有同一個 tag object 時，它會在讀取任何 consumer 之前拒絕。`main` 上還沒有被任何
release 涵蓋的 payload 變更，它只會提示、不會帶。每個 pull request 都會列出自
consumer 的 lock 所記錄的 release（較舊的 lock 則是 commit）以來，改動過
`payload/` 或 `bin/managed-core.txt` 的 Friday commit。

`friday-lock check` 會在 `release:` 那一行印出所記錄的 release；lock 沒有記錄
tag 時印 `none`。`friday-lock write` 記錄的是 `friday-propagate` 指定的 release
tag，或它所讀取的那個 commit 上的 release tag；兩者都沒有時，則記錄 payload 與
managed-core list 都相同的最新 release。之後若同名的 tag 指向了不同的內容，
`check` 會回報 `status: tag-moved`：信任 lock 裡的 commit，不要信任 tag。這個
Friday clone 裡沒有的 tag 不會被判定為被移動，因為還沒 fetch 到它的 clone 看起來
完全一樣：lock 記錄的 commit 在本機時，`check` 會印出找不到這個 tag、未驗證；連
commit 都不在時，沒有東西可以比對，它不會提到 tag。兩種情況都交由其他檢查決定狀態。

## 驗證與測試

執行 `bash` [`tests/install-smoke.sh`](./tests/install-smoke.sh)
`/absolute/path/to/retained-test-output`。
這個檢查會建立可拋棄的 Git fixture，以 `--working-tree` 安裝這個 repository 真正的 payload，
並保留證據供日後審查。它絕對不會安裝進一個既有的專案。清理（cleanup）是
另一個需要另外、明確授權才能執行的操作。

[`tests/install-release.sh`](./tests/install-release.sh) 在有自己 origin 與 tag 的拋棄式 Friday repository
中，證明 release 安裝與 `--managed-only`：不論 checkout 在哪個 branch、有什麼修改，安裝的都是最新或指定的
release；`friday-propagate` 會拒絕的 tag 同樣被拒絕；比這些旗標更早的 release 以舊介面安裝；既有專案的 seeds
逐位元組原封不動。它會印出 `all N passed`。

[`tests/setup.sh`](./tests/setup.sh) 逐案證明 setup 腳本，每案都在拋棄式的 clone 中
執行，並印出 `all N passed`。
