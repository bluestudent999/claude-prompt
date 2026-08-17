# CLAUDE.md — Java / Spring Boot 版本升級專案（AI Agent 規範）

> **用途：** 規範**將既有 Maven 多模組專案從 Java 8 / Spring Boot 2.x 升級到 Java 17/21 / Spring Boot 3.x** 的 AI Agent 工作方式。
> **部署位置：** 整個 `.claude/` 目錄複製到「待升級專案」根目錄，本檔置於根目錄作為 `CLAUDE.md`。
> **升級策略：** 直接跳躍升級（一次跳到目標版本，靠**自動遷移 + 編譯錯誤收斂 + 回歸測試**驗證，不逐版遞進）。

---

## 0. 運作模式：升級即「行為等價遷移」（最高優先）

升級的成功定義是 **「版本到位 + 行為不變」**，不是新增功能。任何「順手重構 / 順手改邏輯」都是升級期紅線（見 §2）。

本專案以 **UPGRADE 工單**與 **6 步生命週期**推進。當下達「執行 UPGRADE-xxx」時，AI Agent 依下列流程工作：

1. **盤點與規劃**：`/upgrade-inventory` 掃描升級面（javax import、棄用 API、依賴版本、設定屬性），`upgrade-planner` 拆解步驟並於 `upgrade/task-xxx-plan.md` 管理 `Open Questions (OQ)`。
2. **自動遷移優先**：能用 **OpenRewrite** recipe 自動完成的（jakarta namespace、Boot 3 屬性、棄用 API），**一律先跑 recipe**，再人工收尾——禁止手刻可被 recipe 覆蓋的大批量改動（見 `.claude/rules/openrewrite.md`）。
3. **遵守 Rules**：嚴格遵守 `.claude/rules/` 下所有規範，尤其 `version-matrix.md`（版本單一事實來源）與 `breaking-changes.md`。
4. **編譯收斂 + 回歸驗證**：直接跳躍升級後必有大量編譯錯誤，依 `build-error-resolver` 分類修復；最終以 `.claude/rules/verification.md` 的回歸政策驗證行為等價。
5. **回填狀態**：完成後回填工單狀態與關鍵產出（版本前後對照、移除/替換的依賴、行為差異記錄）。

---

## 跨 prompt-setup 職責路由（越界即提示切換）

本範本（`.claude/`）只負責軟體生命週期的**單一階段**。若接到的工作**不屬於本階段職責**——例如「這其實是新功能開發」或「這其實是新需求規劃」——**不要硬接、不要在本階段臆測代答**，而是明確**提示使用者切換到對應的 prompt-setup 範本**，並附一句「為什麼這屬於他階段」。升級期紅線是「行為等價」，任何「順手加功能 / 改邏輯」本就越界。

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

> **你在這裡：版本管理 · 升級遷移**（表格第 6 列為本職，不適用切換）。切換提示範例：「此工作是新增功能而非行為等價遷移，違反升級紅線；請 `prompt-setup 專案開發 <java|ai-ux-agent>` 後再進行」「這是新需求規劃，請先 `prompt-setup 專案企劃`」。

---

## 1. 指路（每次開工先看）

- **當前升級階段：** `<在此標註，例如：Phase 1 jakarta 遷移>`
- **版本相容矩陣（單一事實來源）：** `.claude/rules/version-matrix.md`
- **升級生命週期與步驟：** `.claude/rules/upgrade-workflow.md`
- **javax → jakarta 遷移規範：** `.claude/rules/jakarta-migration.md`
- **已知 breaking change 清單：** `.claude/rules/breaking-changes.md`
- **OpenRewrite 自動遷移規範：** `.claude/rules/openrewrite.md`
- **回歸驗證政策：** `.claude/rules/verification.md`
- **分支策略與提交粒度：** `.claude/rules/git-workflow.md`

---

## 2. 不可妥協紅線（升級期）

- **行為等價優先**：升級期**禁止**夾帶功能變更、邏輯重構、效能調優、命名美化。升級 commit 只做「讓它在新版本上以相同行為運作」的最小改動。要重構 → 另開非升級 MR。
- **版本鎖定單一來源**：所有 Java / Spring Boot / 依賴版本以 `version-matrix.md` 為準，**禁止**在個別 `pom.xml` 散落寫死版本號；用 `<properties>` 或 parent BOM 統一管理。
- **自動遷移優先於手刻**：可被 OpenRewrite recipe 覆蓋的大批量機械改動，**禁止**逐檔手刻（易漏、不一致、吃 token）。先 recipe，diff 審查，再人工補 recipe 未覆蓋的尾巴。
- **不繞過編譯/測試**：`mvn -DskipTests` 只能用於「隔離編譯錯誤」的診斷暫態；**禁止**用 `-Dmaven.test.skip=true` 把升級 MR 推上去當作「綠燈」。回歸測試是升級唯一的安全網。
- **jakarta 單向性**：進入 Boot 3 階段後，**禁止**再新增任何 `javax.*`（除 Java SE 本身保留的 `javax.*`，如 `javax.crypto`、`javax.sql`、`javax.net`——清單見 `jakarta-migration.md`）。hook 會攔截。

---

## 3. 可用工具與 Sub-agents

- **自訂 Skills：** `/upgrade-inventory`（升級面盤點）、`/rewrite-run`（跑 OpenRewrite recipe）、`/boot3-config-migrate`（設定屬性遷移）、`/dependency-bump`（單一依賴升級查相容）、`/strategic-compact`（context 壓縮）
- **Sub-agents**（AI 自動路由調用）：
  - `upgrade-planner`：升級盤點結果 → 分階段計畫與 OQ 管理。
  - `dependency-analyzer`：`dependency:tree` 衝突分析、jakarta/Spring 6 相容版本決策。
  - `compat-researcher`：查第三方庫對 jakarta + Spring Boot 3 的最低相容版本（走 Context7 / WebSearch）。
  - `build-error-resolver`：升級後編譯錯誤分類與最小修復（專精 namespace / 移除 API / 簽名變更）。
  - `config-migrator`：`application.yml` / `.properties` / `bootstrap.yml` 的 Boot 3 屬性遷移。
  - `regression-reviewer`：行為等價 / 回歸風險審查（升級期主審）。

---

## 4. 提交前固定動作

1. **真編譯綠燈**：`mvn -pl <module> -am clean compile`（去掉所有 skip 旗標）通過。
2. **回歸測試綠燈**：依 `verification.md` 跑該模組回歸測試套件；CI 若 skip test，必須本地手動跑。
3. **Review**：調用 `regression-reviewer`（行為等價）+ 視內容 `dependency-analyzer` / `config-migrator`。
4. **檢查 OQ**：確認 `upgrade/*-plan.md` 無「⏳ 待決」OQ（否則 git hook 攔截）。
5. **檢查 jakarta 單向性**：Boot 3 階段後不得殘留非 Java SE 的 `javax.*` import。
6. **發起 MR**：附「版本前後對照表 + 行為差異記錄 + 回歸測試證據」。
