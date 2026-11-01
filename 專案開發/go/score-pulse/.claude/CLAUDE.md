# CLAUDE.md — score-pulse 開發專案（實作期 AI Agent 規範）

> **專案定位：** On 體育網精簡版（導流版）的**後端 API 與兩套後台**。一套系統服務多位業主（一業主一域名、一品牌 App），四大球種即時比分、賠率、數據，資料全由 TheSports 供應。**H5 與 App 畫面由另一部門負責**，本 repo 對他們交付的是契約。
> **執行環境：** Go 1.23 + sp-framework（gin／fx／gorm／go-redis／sarama／gorilla ws）｜MySQL 8 + Redis + Kafka｜後台前端 Vue 3 + Element Plus + Pinia（`web/admin`）
> **部署位置：** 隨整個 `.claude/` 部署到 score-pulse repo 根目錄（與 `plan/` 同一個 repo）。

---

## 0. 運作模式：ticket 驅動（最高優先）

**企劃階段已經跑完。** `plan/on-sports-lite/` 有 Brief、6 份 Spec、6 份 Backlog、總計畫、部門分工、**129 張開發 ticket**（`tickets/S*-T*.md`）、16 張開工前置（`tickets/prep/P-*.md`）、以及技術決策 `tech-decisions.md`。

接到「做 S2-T8」這類指令時：

1. **讀整張 ticket**（它很短）：Scope 含／不含、Depends On、AC、部門分工、**只讀這幾節（Required Spec Sections）**。
2. **只讀指定的 spec 節**：spec 每份 300～560 行，**不要通讀**。企劃已經切好上下文，照著讀就不會爆。
3. **planner 拆解**：產出 `plan/task-<ticket>-plan.md`，判定工作類別（A 後端 API／B 後台前端／C 契約交付），列出每個 API 的測試名，管理 `⏳ 待決` OQ。
4. **實作 → 驗收 → 審查 → 回填**（`rules/development-workflow.md`）。

> **回填不是可選的。** plan §8 完成紀錄 + ticket 狀態欄；沒回填 = 未完成。

### 0.1 三類工作怎麼認

| 類 | 認法 | 驗收 |
|----|------|------|
| **A · 後端 API** | ticket 主責後端；或主責前端但畫面在 H5／App（只做後端部分） | AC + 每個 API 的單元測試 + 不變量測試 |
| **B · 後台前端** | 畫面在總控或業主後台（`web/admin`） | AC + 畫面三態 + 後端 API 測試 |
| **C · 契約交付** | 動到 `/api/front/**`、WebSocket、Kafka 封包 | `/contract-export` + `contract-reviewer` |

### 0.2 開工前的骨架不是 ticket

repo 初始化、框架 tag、三份 profile、docker-compose、migrate、swag、lint、CI、`thesports-sim` → `/bootstrap`（B-01 ～ B-10），W1 做完才開第一張 ticket。

---

## 跨 prompt-setup 職責路由（越界即提示切換）

本範本（`.claude/`）只負責軟體生命週期的**單一階段**。若接到的工作**不屬於本階段職責**——包含 planner 分流出的 OQ 被判定為「其實是他階段的事」——**不要硬接、不要在本階段臆測代答**，而是明確**提示使用者切換到對應的 prompt-setup 範本**，並附一句「為什麼這屬於他階段」。

| 撞到的工作性質（非本職） | 應切換到 | 指令 |
|---|---|---|
| 需求收斂 / 商業價值 / 範圍界定 / Persona / 驗收標準 / 規格 / 任務拆解 | 企劃 | `prompt-setup 專案企劃` |
| 新功能開發（Python / AI UX 稽核平台） | 開發 | `prompt-setup 專案開發 ai-ux-agent` |
| 新功能開發（Java 21 / Spring Modulith） | 開發 | `prompt-setup 專案開發 java` |
| 既有主業務維護 / 修 bug（cx-sports-v2，Java 8 / Boot 2） | 維護 | `prompt-setup 專案維護 cx-sports` |
| 既有加密支付維護 / 修 bug（crypto-payment，Java 21 / Boot 3） | 維護 | `prompt-setup 專案維護 crypto-payment` |
| Java 8→21 / Boot 2→3 版本升級遷移 | 版本管理 | `prompt-setup 版本管理` |
| 已完成網站的 UX 體驗稽核（實際開瀏覽器體驗、產 UX 修改建議報告） | 網站體驗稽核 | `prompt-setup 網站體驗稽核` |
| 既有骰寶辨識維護 / 修 bug（sicbo，Python / YOLO 影像辨識） | 維護 | `prompt-setup 專案維護 sicbo` |
| crypto-node 鏈下索引服務開發（Java 21 / Boot 3.5 / 多租戶） | 開發 | `prompt-setup 專案開發 java crypto-node` |
| YUMMY 老虎機開發（Java 21 / Boot 3.5 + H5 遊戲前端，複製既有玩法） | 開發 | `prompt-setup 專案開發 java slots` |
| lion-service 包網平台資安掃描（原始碼與設定靜態稽核，只產報告不改 code） | 資訊安全 | `prompt-setup 資訊安全 lion-service` |
| cx-sports-v2 體育投注主業務資安掃描（原始碼與設定靜態稽核，只產報告不改 code） | 資訊安全 | `prompt-setup 資訊安全 cx-sports-v2` |
| 既有包網彩票平台維護 / 修 bug（lion-service，Java 8 / Boot 2.0） | 維護 | `prompt-setup 專案維護 lion-service` |

| score-pulse 比分平台後端與後台開發（Go / sp-framework / MySQL / Kafka） | 開發 | `prompt-setup 專案開發 go score-pulse` |

> **你在這裡：開發 · score-pulse（Go / sp-framework）**（表格第 14 列為本職，不適用切換）。
> **跨部門邊界（極重要）：**
> - **H5 與 App 畫面不在本 repo。** 本 repo 只保證「照契約提供正確的 API 與即時推送」。他們怎麼畫畫面、App 沿用 H5 還是另做（OQ-63）、媒體在 App 能不能播（OQ-62）、哪些瀏覽器支援推播（OQ-32a），是他們的事，**不得代答、不得在 API 裡預設答案**。
> - 契約改動是雙邊變更 → `rules/api-contract.md` §3。
> - 需求若是「幫我做 H5 的比賽列表頁」→ 回覆：那是另一部門的範圍，本 repo 提供 `docs/contract/` 的契約。
> - 業務規則疑問（範圍、AC、優先序）→ 切 `prompt-setup 專案企劃`；本 repo 不改 spec。

---

## 1. 指路（每次開工先看）

### 文件優先序（衝突時的裁決順序）

```
tickets/<id>.md（範圍、Required Spec Sections、AC）  ← 以此為準
        ↑ 衍生自
backlog-spec-N.md → spec/spec-*.md → brief.md         ← 業務行為以 spec 的 R# / E# / AC# 為準
────────────────────────────────────────────────────
tech-decisions.md（D1～D17、不做清單、拓樸、topic）    ← 技術決策以此為準；rules/ 是它的執行版
master-plan.md（波次、里程碑、外部等待）              ← 只決定先做哪張
```

- **工單：** `plan/on-sports-lite/tickets/README.md`（129 張總表）、`tickets/<id>.md`
- **技術決策：** `plan/on-sports-lite/tech-decisions.md`（**衝突時以此為準**）
- **業務規格：** `plan/on-sports-lite/spec/spec-{1,2a,2b,3,4,5,6}-*.md`（依 Required Spec Sections 分節讀，禁 full read）
- **排程：** `plan/on-sports-lite/master-plan.md`（§3 波次、§1.2 M0 開工前置、§4 外部等待）

### 規範

- **已鎖定決策（不得自行推翻）：** [`.claude/rules/locked-decisions.md`](.claude/rules/locked-decisions.md)
- **10 條不變量（最高紅線）：** [`.claude/rules/invariants.md`](.claude/rules/invariants.md)
- **架構：單 binary 多角色 + 功能分包：** [`.claude/rules/architecture.md`](.claude/rules/architecture.md)
- **sp-framework 慣例（最容易寫錯）：** [`.claude/rules/framework-conventions.md`](.claude/rules/framework-conventions.md)
- **多業主隔離：** [`.claude/rules/tenant-isolation.md`](.claude/rules/tenant-isolation.md)
- **對外 API 契約（跨部門）：** [`.claude/rules/api-contract.md`](.claude/rules/api-contract.md)
- **即時資料契約（Kafka／WebSocket）：** [`.claude/rules/realtime-contract.md`](.claude/rules/realtime-contract.md)
- **TheSports 接入：** [`.claude/rules/thesports-ingest.md`](.claude/rules/thesports-ingest.md)
- **多語系：** [`.claude/rules/i18n.md`](.claude/rules/i18n.md)
- **開發流程與回填：** [`.claude/rules/development-workflow.md`](.claude/rules/development-workflow.md)
- **測試政策（每個 API 必有單元測試、雙租戶）：** [`.claude/rules/testing.md`](.claude/rules/testing.md)
- **DB migration：** [`.claude/rules/db-migration.md`](.claude/rules/db-migration.md)
- **Go 風格：** [`.claude/rules/coding-style.md`](.claude/rules/coding-style.md)
- **後台前端（Vue 3）：** [`.claude/rules/web-frontend.md`](.claude/rules/web-frontend.md)
- **分支與提交：** [`.claude/rules/git-workflow.md`](.claude/rules/git-workflow.md)（**測試分支的程式碼禁止回流開發分支**）

---

## 2. 不可妥協紅線

1. **10 條不變量是正確性的定義**（`rules/invariants.md`）。每一條都必須有自動化測試；Code Review 以此為檢查清單。**違反不變量 = block，沒有例外。**
2. **租戶隔離（I1）是正確性問題，不是功能問題。** 違反即業主資料互看，且**在單租戶測試環境下 100% 測不出來**。所有整合測試一律以 `op-a` / `op-b` 雙租戶為基準（`rules/testing.md` §3）。
3. **每一個 API 都必須有單元測試**（`rules/testing.md` §1）：REST handler、WebSocket 訂閱 action、Kafka consumer。沒有測試的 handler，`code-reviewer` 直接 block。
4. **對外契約不可片面變更**（`rules/api-contract.md`、`rules/realtime-contract.md`）。H5／App 在另一部門，契約破了他們不會立刻報錯。
5. **已鎖定的架構決策不得自行推翻**（`rules/locked-decisions.md`）：不拆服務、不依賴 sp-common、不用 Redis Pub/Sub 扇出、第一期不用 protobuf、不以「比分只能變大」過濾、framework 鎖 tag。要翻案 → 停手回報。
6. **sp-framework 的慣例不是建議**（`rules/framework-conventions.md`）：panic 走錯誤流程、`fx.In` 顯式結構、YAML key 小寫、Name() 對上 YAML 鍵、`EmitWithKey(match_id)`。寫錯會跑不起來或靜默失序。
7. **範圍紀律**：只做 ticket 的 Scope「含」；不做「順便加的」功能；不為 H5／App 的畫面寫程式；不做結算。

---

## 3. 可用工具與 Sub-agents

- **自訂 Skills**：`/ticket-run <id>`、`/bootstrap`、`/arch-check`、`/tenant-check`、`/contract-export`、`/sim-scenario`、`/db-migrate`、`/vue3-console`、`/strategic-compact`
- **Sub-agents**（依 `rules/development-workflow.md` Step 4 派工）：
  - `planner`：ticket → `plan/task-<ticket>-plan.md`；判類別、標不變量與租戶表、列每個 API 的測試名、管 OQ。
  - `code-reviewer`：Go 通用品質 + framework-conventions 掃描 + **API 無測試即 block**。
  - `arch-guard`：包依賴方向、角色組裝、禁用相依。
  - `tenant-isolation-reviewer`：逐一盤點查詢的 operator 過濾、授權來源、雙租戶測試。
  - `contract-reviewer`：REST 與 WebSocket／Kafka 契約相容性、是否需通知另一部門。
  - `data-pipeline-reviewer`：collector、`realtime-core`、`persist`、合流、快照、賠率歷史的正確性。
  - `web-reviewer`：`web/admin` 的 Vue 2 混入、授權、三態、憑證不落地。
  - `build-error-resolver`：go build／vet／lint／測試失敗診斷。

---

## 4. 提交前固定動作

1. 本地綠燈：`go build ./... && go vet ./... && golangci-lint run && go test ./internal/...`；動到 dao／consumer 再跑 `go test -tags=integration ./test/...`。
2. `/arch-check`；動到租戶表 `/tenant-check`；動到契約 `/contract-export`。
3. 派 reviewer：`code-reviewer` 一律；其餘依 Step 4 表。
4. 回填：plan §8 + ticket 狀態欄。
5. 檢查 OQ：`plan/` 無「⏳ 待決」（否則 git hook 攔截）。
6. Commit（Conventional Commits，scope = 功能包名）；**不加 `.claude/` 與 `CLAUDE.md`**。

---

<!-- shared:claude-local-only -->
## Claude Code 專案規範 / 範本 — 僅本機使用，不進版控（`settings.json` 除外）

`CLAUDE.md` 與 `.claude/` 是**本機開發輔助設定**，不隨專案進版控；唯一例外是 `.claude/settings.json`（團隊共用的 hook／權限設定）。部署本範本後，專案 `.gitignore` 須含：

```gitignore
# Claude Code 專案規範 / 範本 — 僅本機使用,不進版控(settings.json 除外)
CLAUDE.md
.claude/*
!.claude/settings.json
```
<!-- /shared -->

---

<!-- shared:next-step-closing -->
## 收尾固定格式：每次任務結束必須寫「下一步執行」

任務（一顆 TASK、一次修復、一份產出、一次審查）做完後，回覆的**最後一行**固定為：

> **下一步執行** <下一個流程步驟>（<一句話為什麼是它>）

**硬規則：**

- **一定要寫**，即使使用者沒問。做完就收尾，不留「然後呢」讓使用者自己猜。
- **只寫一個**——流程上真正緊接的那一步，不列待辦清單、不寫「可以考慮…」。
- 步驟名稱**取自本範本自己的工作流程文件**（`rules/` 下的 `*-workflow.md`），照原文用詞，不自創階段名。
- **不知道下一步 → 不要編**。寫「**下一步執行** 待確認（缺 <什麼> 才能決定）」。
- **流程已走完 → 明說**。寫「**下一步執行** 無（<流程名> 已完成）」。
- **有阻塞就指向解除阻塞那一步**（`⏳ 待決` OQ、驗證未過、等外部），不得跳過它往下推。
<!-- /shared -->
