# CLAUDE.md — SDRP 開發專案（實作期 AI Agent 規範）

> **用途：** 規範**未來 SDRP 開發專案**的 AI Agent 工作方式。本檔隨整個 `.claude/` 目錄一同配置於開發 Repo 根目錄下。
> **部署位置：** 複製到開發專案後，置於**專案根目錄**作為 `CLAUDE.md`。

---

## 0. 運作模式：Task 驅動（最高優先）

本專案以 **TASK 工單**與 **6 步生命週期**推進。當下達「執行 TASK-xxx」時，AI Agent 依下列流程工作：

1. **讀工單與規劃**：到 `plan/` 下尋找對應 TASK 文件。調用 `planner` 分步拆解，並於 `plan/task-xxx-plan.md` 中管理 `Open Questions (OQ)`。
2. **遵守 Rules**：在編寫、測試與提交代碼時，必須嚴格遵守 `.claude/rules/` 目錄下的所有規範。
3. **自我驗收**：依該 TASK 的「驗收標準」逐項檢查，全部通過才回報完成。
4. **回填狀態**：完成後把該 TASK 狀態改為已完成，並回填關鍵產出。

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

> **你在這裡：開發 · SDRP（Java）**（表格第 3 列為本職，不適用切換）。切換提示範例：「此需求屬企劃職責（例：定範圍 / 驗收標準 / 任務拆解），本開發範本不處理；請先 `prompt-setup 專案企劃` 收斂為 Spec/Backlog 後再回來實作。」若接到的是既有 cx-sports-v2 主業務維護或版本升級，同理提示切換到維護或版本管理範本。

---

## 1. 指路（每次開工先看）

- **當前進行中的 Phase：** `<在此標註，例如：Phase 0>`
- **架構總綱與分階段：** `plan/SDRP-implementation-plan.md`
- **生命週期規範與步驟**：`.claude/rules/development-workflow.md`
- **代碼風格與異常規範**：`.claude/rules/coding-style.md`
- **JUnit 5 測試政策**：`.claude/rules/testing.md`
- **Flyway migration 版本號（時間戳）**：`.claude/rules/flyway-migration.md`
- **審計與安全合規**：`.claude/rules/security-audit.md`
- **提交與 MR 指標要求**：`.claude/rules/git-workflow.md`

---

## 2. 不可妥協紅線

- **模組邊界**：遵循 Spring Modulith 規範，L2 Domain 嚴禁依賴外部框架或 SQL；跨模組嚴禁直接 import internal 套件。
- **審計與安全**：所有寫入操作必須記錄 Append-only 審計日誌。金額異動必須使用 BigDecimal (DOWN 取整) 與 DB 悲觀鎖。
- **AI 煞車**：低信心度（Confidence Score 低於閥值）的數據一律轉為 HITL 人工處理，禁止 Fail-Open。

---

## 3. 可用工具與 Sub-agents

- **自訂 Skills**：`/arch-check`、`/db-migrate`、`/new-module`、`/strategic-compact`
- **Sub-agents**（AI 自動路由調用）：
  - `planner`：任務拆解、假設驗證與 OQ 管理。
  - `code-reviewer`：通用代碼 Clean Code 與性能審查。
  - `domain-reviewer`：DDD 領域模型與 Modulith 隔離審查。
  - `build-error-resolver`：Maven 編譯與構建錯誤自動診斷與修復。
  - `arch-guard`：分層與 Modulith 邊界靜態規則守門人。
  - `domain-modeler`：Bounded Context 內 Aggregate/Value Object 草案設計者。
  - `port-adapter` / `migration-author` / `alignment-evaluator`：專項開發與對齊評估子代理。

---

## 4. 提交前固定動作

1. 本地綠燈：確認 `./mvnw test` 通過。
2. 進行 Review：調用 `code-reviewer` 與 `arch-guard` 進行代碼與架構審查。
3. 檢查 OQ：確認 plan 中無「⏳ 待決」的 Open Questions（否則提交將被 git hook 攔截）。
4. 發起 MR：在 Merge Request 中檢附 AIDD 指標數據。
