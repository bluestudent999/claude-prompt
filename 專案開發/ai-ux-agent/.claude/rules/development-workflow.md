# 開發工作流程

> 本文規範 AI UX Audit Platform 開發的生命週期（準備 → 研究 → 規格 → 規劃 → 實作 → 審查 → 提交）。所有成員與 AI Agent 必須遵循。

---

## 需求提交格式（使用者端）

```
需求類型：新功能 / Bug 修改 / 重構 / 調整
需求簡述：（一句話說明目標）
所屬環境階段：（E1 / E2 / E3）
受影響管線階段：（browser / observation / reasoning / evaluation / report / persona / task）
預期結果：（可觀測的變化，如「報告新增 X 要件」）
備註：（工單 ID、Spec/Backlog 章節）
```

---

## 開發生命週期（7 步）

### Step -1：環境 Preflight（啟動後首次動工前）
```bash
# 1. 驗證 Python 與工具鏈
python --version
ruff --version
# 2. 快速煙霧測試（不連真實服務）
pytest -q -m "not integration and not slow" || echo "[Preflight] 單元測試未綠燈，先修環境/HEAD"
# 3. 若涉及瀏覽器：確認 Playwright 瀏覽器已安裝
playwright install --dry-run 2>/dev/null || true
```
- **Preflight 失敗處理**：先修環境或 HEAD 本身問題，不帶病開工。

---

### Step 0：研究與設計定位（Research）
1. **管線定位**：對照架構管線（browser → observation → reasoning → evaluation → report），確認本次改動落在哪一階段、經哪個 Port。
2. **資料契約確認**：改動是否影響 `Observation / Issue / Report / Persona / Task` 契約（architecture §4）？影響則須同步契約與其測試。
3. **E-Phase 定位**：確認需求屬 E1/E2/E3，**不得**在當前階段實作後續階段能力（dev-plan §6）。
4. **大檔案讀取限制**：檔案 **> 300 行禁止一次性 Full Read**，先 `grep -n` 定位再分段讀取。

---

### Step 1：規格確認（Spec）
- 業務邏輯 / 新功能開發，須對照 `plan/ai-ux-agent-spec.md` 與當前階段 Backlog 的 AC；**規格未確認前不動手寫代碼**。
- **Mental Model Check**：產出詳細設計前，輸出 ≤100 字的現況摘要（資料契約真相、受影響 Port / 階段、關鍵檔案），供開發者 Sanity Gate 確認。

---

### Step 2：規劃（Plan）
- 使用 `planner` agent 生成實作步驟，寫入 `plan/task-xxx-plan.md`。
- **任務單一職責**：一個 TASK 只做一件事。禁止把「觀察落地 + 推理 + 報告」混在單一 TASK（對映 Backlog 垂直切片）。
- **邊界與範圍管理**：明確指定 `Allowed Stages`（如只允許改 `observation`）與預期新增 / 修改檔案清單。
- **依賴管理**：標示 TASK 間依賴（如 TASK-3 → TASK-4）；前置未完成禁止開始。
- **Open Questions（OQ）管理**：
  - 不確定的技術選擇 / 未決業務分支，列為 `⏳ 待決 OQ-xxx`。
  - **硬規則**：OQ 未被開發者解答前，禁止開始編寫業務代碼。
  - 純技術實作細節（模型 ID、SDK、重試參數、路徑規則）標 `➡️ defer-to-dev`，由開發 planner 決定，不阻塞。
  - **越界回企劃**：若 OQ 被判定為企劃階段的商業/範圍/Persona/驗收問題，除引導回 Spec/Backlog 外，明確提示使用者切換 `prompt-setup 專案企劃`（見 CLAUDE.md『跨 prompt-setup 職責路由』表）。
- **風險標註（L1–L3）**：對映 testing §3（登入 / 憑證 / 證據連結 / 例外留痕 = L1）。

---

### Step 3：測試與實作（Test & Implement）
- **Golden Rule**：AI 的工作是「依計畫書實作」。禁止自行重設計、優化架構或新增未經計畫的需求。唯一真理來源為 `plan/`。
- **Context & AI Rules**：
  - **最小化讀取**：只讀 TASK 本身與指定 `Required Context`，禁止讀全專案。
  - **禁止越權決策**：不得自行新增 Persona / Task / 觀察種類 / 報告要件，除非計畫已明定。
  - **禁止順便重構**：不得修改與 TASK 無關的階段（開發 observation 時不得順手改 report）。
  - **Stop Rule**：遇文件 / 架構 / 需求衝突，**立即停止並回報**，不得猜測。
- **架構與紅線守護**（實作時嚴守）：
  - 管線單向；Core 不 import Playwright / LLM SDK / HTTP / 檔案 I/O；外部相依走 Port（architecture §2）。
  - **非 RPA**：不寫「Click → Assert → Pass」；恆走 Observation → Reasoning → Evaluation → Reporting。
  - **證據優先**：每個 Issue 必連結真實 Observation，四欄位齊全；無證據不得產 Issue。
  - **失敗不靜默**：可預期例外轉結構化結果並在報告留痕，附失敗證據。
  - **憑證安全**：secret 只從環境變數注入 Adapter，不進 Core / 日誌 / 版控。
- **TDD 與風險要求**：L1 必寫測試（登入態、證據連結、例外留痕）；L2 優先單元測試（Stub 注入）；L3 免。

---

### Step 4：代碼審查與驗收（Review & DoD）
- **Definition of Done**：
  - 編譯 / 匯入無誤；`pytest -q`（含 `-m architecture`）與 `ruff check` 綠燈。
  - 無 TODO / FIXME / lint warning。
  - **Dead Code 只清自己造成的**：本次改動造成的未使用 import / 變數 / 私有函式**必須清掉**；**既有的** dead code **不主動刪除**，僅在 `Remaining Work` 記錄回報（刪它屬於「禁止順便重構」，違反 Step 3 的範圍紀律）。
  - 若涉審計輸出：`/ux-audit-eval` 通過（每 Issue 有證據、四欄位齊全）。
  - 資料契約若變動，測試與 docstring 已同步。
- **完成輸出格式**：`Completed Files`、`Modified Files`、`Tests (PASS)`、`Report 產出路徑`、`Remaining Work`（阻塞註明 `Blocked By: TASK-xxx`）。
- **審查強度依 L 層決定（不是每次都全套）**：

  | L 層 | 典型場景 | reviewer 配置 |
  |------|---------|--------------|
  | **L3** | 設定 / prompt 文案 / docstring / 純重構 | `code-reviewer` × 1 輕掃 |
  | **L2** | Observation 收集器 / 引擎 / 報告格式化 | `code-reviewer` + 擇一（`arch-guard` 或 `observation-reviewer`） |
  | **L1** | 登入 / 憑證 / 證據連結 / 例外留痕 / 契約變更 | `code-reviewer` + `arch-guard`，涉資料契約再加 `observation-reviewer`，最終 Diff 平行啟動 |

  > 有疑問升級不降級；同一 PR reviewer 超過 3 個先考慮拆 TASK。

- **reviewer 職責邊界（避免對同一件事重複把關）**：

  | 角色 | 只管 | 何時 |
  |------|------|------|
  | `arch-guard` | 靜態邊界：分層 / 非 RPA / E-Phase scope | 提交前（不逐一驗個別 Issue 的證據） |
  | `observation-reviewer` | **產生報告的代碼與資料契約**（Observation/Issue/Report 模型、證據連結寫法） | 開發中、改 code 前 |
  | `ux-evidence-auditor` | **已產出的報告成品**度量（evidence-coverage / 四欄位 / 退出閘門），不改 code | 報告產出後 |

  > 三者不重跑同一件事：契約寫法找 `observation-reviewer`，成品品質找 `ux-evidence-auditor`／`/ux-audit-eval`，靜態邊界找 `arch-guard`。**同一次 task 不要三個都對「證據」再驗一遍。**

---

### Step 5：提交與指標（Commit & Metrics）
- **提交攔截**：若 `plan/` 仍留「⏳ 待決」OQ，git commit 被 hook 阻擋。
- **Conventional Commit**：如 `feat(evaluation): enforce evidence link on issue`、`fix(login): trace on session timeout`。
- **AIDD 指標**：MR 描述附 AI 開發指標（git-workflow §4），供持續調優。
