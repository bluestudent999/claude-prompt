# 開發工作流程

> 本文規範 SDRP 開發專案的生命週期（準備、研究、規格設計、規劃、實作、審查、提交）。
> 所有專案成員及 AI Agent 必須遵循此流程。

---

## 需求提交格式（使用者端）

使用者提需求時建議提供以下模板（非硬性）：
```
需求類型：新功能 / Bug 修改 / 重構 / 調整
需求簡述：（一句話說明目標）
受影響模組：（例：ingestion, reference, alignment, decision）
預期結果：（可觀測的變化）
備註：（工單 ID、設計限制）
```

---

## 開發生命週期（7 步）

### Step -1：環境 Preflight（啟動後首次動工前）
為防範環境與編譯問題阻礙開發，必須執行基本驗證：
```bash
# 1. 驗證 Java 21 與 Maven 環境
java -version 2>&1 | grep -E "21\." || { echo "[Preflight] JDK 版本不符，需 Java 21"; exit 1; }
# 2. 執行快速編譯煙霧測試
./mvnw clean test-compile -DskipTests -q
```
- **Preflight 失敗處理**：若編譯失敗，先修復環境或 HEAD 本身問題，不帶病開工。

---

### Step 0：研究與設計定位 (Research)
在修改任何代碼前，必須搜尋既有實現，確認架構位置：
1. **模組定位**：對照 `Spring Modulith` 模組邊界（`ingestion`、`reference`、`alignment`、`decision`、`hitl`）。
2. **資料流向驗證**：
   - 涉及欄位或配置異動時，Grep 常見的 POJO、Repository、MyBatis Mapper XML 或 PostgreSQL/PGVector 語句。
   - 確定異動是「獨立 DB 欄位」（需 Flyway DDL）還是「JSON 欄位/快取/內存配置」（不需 DDL）。
3. **大檔案讀取限制**：檔案若 **> 300 行禁止一次性 Full Read**。應先 `grep -n` 定位目標行號，再使用 `Read(offset, limit)` 分段讀取。

---

### Step 1：規格確認 (Spec)
- 業務邏輯修改或新功能開發，必須與 PO / 開發人員確認，**規格未確認前不動手寫代碼**。
- **Mental Model Check**：在產出詳細設計前，輸出 $\le 100$ 字的現況與架構摘要（包含資料結構真相、關鍵檔案、架構決策），讓開發者做 Sanity Gate 確認。
- 規格設計最終存放於 `plan/` 目錄下。

---

### Step 2：規劃 (Plan)
- 使用 `planner` agent 生成具體實作步驟，寫入 `plan/task-xxx-plan.md`。
- **任務單一職責 (Single Responsibility)**：一個 TASK 只能完成一件事情。禁止將 Entity、API、Schema 建立與 Service、UI 開發混雜於單一 TASK 中，必須拆分。
- **邊界與範圍管理 (Scope & File Rule)**：
  - 必須明確指定 `Allowed Modules`（如只允許修改 `reference`，禁止動 `gateway`）。
  - 必須列出預期的新增（Create）與修改（Modify）檔案清單。
- **依賴管理 (Dependency Rule)**：必須標示 TASK 間的依賴關係（如 TASK-101 $\rightarrow$ TASK-102）。若前置依賴未完成，禁止開始。
- **Open Questions (OQ) 管理**：
   - 對於任何不確定的技術選擇、未決議的業務分支，在計畫中列為 `⏳ 待決 OQ-xxx`。
   - **硬規則**：OQ 在未被開發者解答前，禁止開始編寫業務代碼。
- **L 層風險標註**：
   - **L1 (高風險)**：涉及金額、結算對齊、狀態機、併發。必須配有整合測試。
   - **L2 (中風險)**：一般 Service 邏輯、Controller、跨模組事件通訊。
   - **L3 (低風險)**：純 DTO、Config、重構、拼字修正。

---

### Step 3：測試與實作 (Test & Implement)
- **實作最高指導原則 (Golden Rule)**：AI 的工作是「依照計畫書實作」。禁止自行重新設計系統、優化架構或新增未經計畫的需求。所有設計的唯一真理來源為 `.plan/`。
- **AI 執行限制與上下文 (Context & AI Rules)**：
  - **最小化讀取**：禁止 AI 讀取全部專案文件，只允許閱讀 TASK 本身與指定的 `Required Context`。
  - **禁止越權決策**：AI 不得自行新增 Table、API、Event 或設定，除非計畫中已明確定義。
  - **禁止順便重構**：開發時嚴禁修改與 TASK 無關的組件（例如：開發 EntityDao 時，禁止順便去改 Gateway 或 Config）。
  - **阻斷條件 (Stop Rule)**：若開發中遇到文件、架構或需求衝突，必須**立即停止並回報**，不得自行猜測。
- **TDD 與風險要求**：
  - L1 風險必須撰寫 JUnit 5 整合測試，且必須有獨立的事務與鎖驗證（悲觀鎖 `FOR UPDATE` / 分散式鎖）。
  - L2 優先覆蓋單元測試或 Modulith 模組驗證。
  - L3 不強制測試。
- **Modulith 邊界守護與架構規範**：
  - 開發時嚴格遵守 L2 Domain $\rightarrow$ L3 Application $\rightarrow$ L1 Infrastructure 的依賴單向性。Domain 層禁用框架技術（Spring、JPA、Redis 等）。
  - 嚴禁跨模組直接調用 `.internal.` 套件，模組間溝通一律使用公開 API 或 `@ApplicationModuleListener` 異步領域事件。
- **編碼與效能守則 (Coding & Performance)**：
  - 遵守 Java 21、Spring Boot 3.5.x 規範，禁止 Field Injection、Magic Number 與循環依賴。
  - 命名須符合規範（Dao、Service、UseCase、Port 等）。
  - 禁止 N+1 查詢與 Full Table Scan；例外處理必須包裝為 BusinessException 或 BaseException；Log 僅限英文並須包含 correlationId。

---

### Step 4：代碼審查與驗收 (Review & DoD)
- **完成定義 (Definition of Done, DoD)**：
  - TASK 完成必須確保：編譯成功、單元/整合/架構測試皆通過。
  - 無 TODO、無 FIXME、無 Warning。
  - **Dead Code 只清自己造成的**：本次改動造成的未使用 import / 變數 / 私有方法**必須清掉**；**既有的** dead code **不主動刪除**，僅在 `Remaining Work` 記錄回報（刪它屬於「順便重構」，違反本 Step 的範圍紀律，且既有未使用碼可能靠反射 / 設定動態引用）。
  - OpenAPI 與 Flyway schema 已同步更新。
- **完成輸出格式 (Completion Output)**：
  - TASK 完成後必須以標準格式輸出成果：`Completed Files`、`Modified Files`、`Tests (PASS)` 與 `Remaining Work`（若有阻塞需註明 `Blocked By: TASK-xxx`）。
- 提交前必須進行雙重審查：
  1. **增量審查**：完成核心領域模型或 SQL 移轉後，先丟給 `domain-reviewer` 或 `db-reviewer`。
  2. **最終平行審查**：調用 `code-reviewer` 與 `arch-guard` 對最終 Diff 進行審查，確保滿足 DoD (完成定義)。

---

### Step 5：提交與指標 (Commit & Metrics)
- **提交攔截**：如果 `plan.md` 中仍留有「⏳ 待決」狀態的 OQ，Git commit 將被自動攔截 hook 阻擋。
- **Conventional Commit**：
  - 格式：`feat(alignment): add confidence score evaluator`、`fix(ingestion): resolve npe on empty payload`。
- **AIDD 指標紀錄**：在 Merge Request 描述中，要求附帶 AI 開發指標數據，供持續調優。
