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

## 現況（2026-11-10）

> **摘要**：managed core 現為十五檔，最新 release 是 v1.1.4（2026-11-10），最近加入
> 每個 worktree 一份、依日期分節的 handoff 規則。
> pet_care 與 Finance 兩個 consumer 都已同步在 v1.1.4。待辦：指定 backup maintainer、
> 真正的新機器 replay、第三個 consumer、external-runtime 收尾，以及 managed-core 更新 bot。

已就位：

- managed core：15 個檔案，列在 [`bin/managed-core.txt`](./bin/managed-core.txt)。
  `v1.0.0`（2026-10-25）發行了前 14 個，`.agents/bin/setup.sh` 是第 15 個。
- 已發行 `v1.0.0` 與 `v1.0.1`（2026-10-25），`v1.1.0` 與 `v1.1.1`（2026-10-26）、`v1.1.2`（2026-11-03）、`v1.1.3`（2026-11-04），
  以及 `v1.1.4`（2026-11-10）：
  `v1.1.0` 帶來 `.agents/bin/setup.sh`、`CLAUDE.md` seed 與以 release 為準的安裝（`install.sh` 安裝 release，而不是 checkout）。
  consumer 只以 release 接收 managed core（見 [發行版本（Releases）](./docs/releases.md#releases)）。
- 兩個 consumer，`pet_care` 與 Finance，都記錄 `v1.1.4`，狀態為 `in sync`。
- `main` 上要求 CI：ubuntu 與 macos 的測試、shellcheck 與 gitleaks
  （[`ci.yml`](./.github/workflows/ci.yml)）。

待辦：

- 指定備援維護者（見[生命週期治理](./docs/releases.md#lifecycle-governance-b06)）。
- 真正的新機器 replay。
- 第三個 genuine consumer。
- External-runtime 的收尾：Friday 尚未驗證的 Codex 與 Gemini 行為。
- managed-core 更新 bot，讓 Friday 發行時自動向 consumer 開 pull request：
  [ShenYo/Friday#7](https://github.com/ShenYo/Friday/issues/7)。

把更廣的工作歸在一起的 agent-platform epic 是
[ShenYo/Friday#10](https://github.com/ShenYo/Friday/issues/10)；上面沒有自己連結的項目，
目前沒有 open issue。

## 快速開始

```sh
git clone https://github.com/ShenYo/Friday.git ~/.Friday   # 只需一次
git init my-project
bash ~/.Friday/install.sh --check my-project               # 預覽；不寫入任何東西
bash ~/.Friday/install.sh my-project                       # 最新的 release
```

這會把最新的 release 安裝進一個空 repository。已經有自己檔案的專案，改用 `--managed-only`。
每個步驟、之後要執行的檢查，以及 clone 消費端之後該做什麼，都在
[採用 Friday](./ADOPTING.zh-TW.md)。

## 文件

除了採用指南有繁體中文版之外，其餘文件只有英文版，每份都以中文摘要開頭。

| 文件 | 何時閱讀 |
| --- | --- |
| [採用 Friday](./ADOPTING.zh-TW.md)（[English](./ADOPTING.md)） | 要把 Friday 裝進新專案或既有專案、clone 消費端之後要設定、或要在已完成 bootstrap 的專案中啟動 agent。 |
| [Architecture](./docs/architecture.md)（英文） | 想知道 payload 包含什麼、哪些檔案歸消費端、哪些歸 Friday，或為什麼這樣設計。 |
| [Updating consumers](./docs/updating-consumers.md)（英文） | 消費端落後某個 release、想查看某個消費端的狀態，或要把變更帶到各個消費端。 |
| [Safety](./docs/safety.md)（英文） | 想知道 guard 拒絕什麼、在哪裡停止、Friday 如何保護自己的 branch，或如何復原。 |
| [Releases and lifecycle](./docs/releases.md)（英文） | 要發行 release，或想了解 lock、版本規則與誰在維護 Friday。 |
| [Verification and tests](./docs/verification.md)（英文） | 想用測試套件證明一項變更。 |
| [History](./docs/history.md)（英文） | 想看目前規則背後有日期的決策、事故與實測記錄。 |
| [Changelog](./CHANGELOG.md)（英文） | 想看某個 release 的 release note。 |
