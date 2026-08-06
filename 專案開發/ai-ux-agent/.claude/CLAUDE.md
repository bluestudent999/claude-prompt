# CLAUDE.md — AI UX Agent 開發專案（實作期 AI Agent 規範）

> **用途：** 規範 **AI UX Audit Platform** 開發專案的 AI Agent 工作方式。本檔隨整個 `.claude/` 目錄一同配置於開發 Repo 根目錄下。
> **部署位置：** 複製到開發專案後，置於**專案根目錄**作為 `CLAUDE.md`。
> **產品定位：** 本專案**不是** Selenium Automation、**不是** RPA，而是一套 **AI Native UX Audit Platform**。核心軸線恆為 `Observation → Reasoning → Evaluation → Reporting`。

---

## 0. 運作模式：Task 驅動（最高優先）

本專案以 **TASK 工單**與 **7 步生命週期**（Step -1 ~ Step 5）推進。當下達「執行 TASK-xxx」時，AI Agent 依下列流程工作：

1. **讀工單與規劃**：到 `plan/` 下尋找對應 TASK（如 `ai-ux-agent-e1-backlog.md`）。調用 `planner` 分步拆解，並於 `plan/task-xxx-plan.md` 中管理 `Open Questions (OQ)`。
2. **遵守 Rules**：編寫、測試與提交時，必須嚴格遵守 `.claude/rules/` 目錄下所有規範。
3. **自我驗收**：依該 TASK 的「對應 AC / 退出閘門」逐項檢查，全部通過才回報完成。
4. **回填狀態**：完成後回填該 TASK 狀態與關鍵產出（Completed / Modified Files、Report 產出路徑）。

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

> **你在這裡：開發 · AI UX 稽核（Python）**（表格第 2 列為本職，不適用切換）。切換提示範例：「此需求屬企劃職責（例：新增 Persona / 改驗收標準 / 定範圍），本開發範本不處理；請先 `prompt-setup 專案企劃` 收斂為 Spec/Backlog 後再回來實作。」

---

## 1. 指路（每次開工先看）

- **當前環境階段（E-Phase）：** `<在此標註，例如：E1 · Demo>`（E1 雲端 API / E2 本地 Mac M4 / E3 DGX Spark）
- **產品規格（需求源頭）：** `plan/ai-ux-agent-spec.md`
- **分階段交付計畫：** `plan/ai-ux-agent-dev-plan.md`
- **當前階段 Backlog：** `plan/ai-ux-agent-e1-backlog.md`
- **生命週期規範與步驟：** `.claude/rules/development-workflow.md`
- **管線與分層架構：** `.claude/rules/architecture.md`
- **Python 代碼風格與異常規範：** `.claude/rules/coding-style.md`
- **pytest 測試政策：** `.claude/rules/testing.md`
- **憑證、脫敏與證據完整性：** `.claude/rules/security-audit.md`
- **提交與 MR 指標：** `.claude/rules/git-workflow.md`

---

## 2. 不可妥協紅線（產品成敗點）

- **非 RPA 紅線（最高）：** 任何階段都不得退化成「Click → Assert → Pass」測試框架思維。設計恆繞 `Observation → Reasoning → Evaluation → Reporting`（Spec §15）。
- **證據優先（Evidence Based）：** 每一個 UX Issue **必須**附 Evidence（Screenshot 或 DOM 片段）。**沒有證據的結論不得寫入報告**（Spec §9）。
- **Issue 四欄位齊全：** 每個 Issue 必含 `Severity / Category / Evidence / Recommendation`；`Severity ∈ {Blocker, Major, Minor, Suggestion}`（Spec §10）。
- **失敗不靜默：** 登入失敗、Session 逾時、憑證缺失、API 逾時、目標站不可達等例外**不得靜默吞掉**，必須在報告中留痕並附失敗證據（dev-plan §2.6）。
- **憑證安全：** 登入帳密等 secret 一律由環境變數 / `.env`（gitignore）注入，**嚴禁**明碼寫入任何進版控的檔案；Log 一律脫敏（OQ-4、security-audit §1）。
- **階段範圍紀律（E-Phase Scope）：** 不得在當前階段做後續階段的事。E1 = 雲端 API、單 Task 串行、Markdown、僅 Screenshot+DOM 觀察；多 Persona / HTML / A11y·Network·Console·Perf / 排程 / 多 Agent / CI/CD 皆為 E2/E3（dev-plan §6 能力矩陣）。

---

## 3. 可用工具與 Sub-agents

- **自訂 Skills**：`/run-audit`、`/ux-audit-eval`、`/arch-check`、`/new-capability`、`/strategic-compact`
- **Sub-agents**（AI 自動路由調用）：
  - `planner`：任務拆解、假設驗證與 OQ 管理（含 E-Phase 範圍守門）。
  - `code-reviewer`：通用 Python Clean Code、安全與效能審查。
  - `arch-guard`：管線/分層邊界 + 非 RPA + 證據紀律 + 階段範圍靜態守門人。
  - `observation-reviewer`：Observation / Issue / Report 資料契約與證據紀律審查。
  - `ux-evidence-auditor`：對「已產出的報告」度量證據完整性與 Issue 品質（不修改，只度量）。
  - `persona-task-modeler`：Persona / Task / Observation / Issue / Report 模型草案設計者。
  - `port-adapter`：InferencePort / BrowserPort / ReportPort 的 Port+Adapter+Stub 接縫建立者。
  - `build-error-resolver`：Python import / 相依 / 執行期 / Playwright 安裝錯誤診斷與修復。

---

## 4. 提交前固定動作

1. 本地綠燈：確認 `pytest -q` 通過（含 `-m architecture` 邊界測試若有）。
2. Lint / 型別：`ruff check .` 與（若配置）`mypy` 無錯。
3. 進行 Review（**依 L 層決定強度，不是每次全套**，見 `development-workflow.md` Step 4）：
   - **L3**（設定 / 文案 / docstring / 純重構）→ `code-reviewer` × 1 輕掃即可。
   - **L2** → `code-reviewer` + 擇一（`arch-guard` 或 `observation-reviewer`）。
   - **L1**（登入 / 憑證 / 證據連結 / 例外留痕 / 契約變更）→ `code-reviewer` + `arch-guard`，涉契約再加 `observation-reviewer`。
4. 檢查 OQ：確認 `plan/` 中無「⏳ 待決」的 Open Questions（否則提交將被 git hook 攔截）。
5. 若本次涉及審計輸出：跑 `/ux-audit-eval` 確認產出報告的每個 Issue 皆有證據、四欄位齊全。
6. 發起 MR：檢附 AIDD 指標（見 `git-workflow.md`；**E1 demo 階段與 L3 micro 改動可省略**）。
