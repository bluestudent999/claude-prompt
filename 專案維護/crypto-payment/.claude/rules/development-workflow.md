# 開發工作流程（crypto-payment）

> 開發流程層規範（環境、研究、規劃、TDD、審查）。git 操作見 [git-workflow.md](./git-workflow.md)。

---

## 需求提交格式（使用者端）

**軟性格式**（缺欄位不擋工，由 `spec-review` 以 `⏳` 補問）。建議 6 欄位：

| 欄位 | Claude 端用途 |
|------|------------|
| **需求類型** | 路由 Step 1 gate：新功能/修改 → `spec-review`；bug fix（非業務）→ 跳過；純重構 → 跳過 spec+tdd；typo/config → 全略 |
| **需求簡述** | 交叉驗證需求類型 |
| **業務關鍵字** | 觸發 L 層判定 + reviewer 路由（見 `modules.md` / `agents.md`） |
| **觸發情境** | 定位受影響 Controller/Service/webhook → Step 0 研究起點 |
| **預期結果** | 寫入 spec 驗收條件；缺 → **必問**（無可觀察變化＝無法驗收） |
| **備註** | deadline / 工單連結 |

---

## Agentic 任務指令三要素

```
[動詞 + 目標] + [範圍限制] + [完成條件]
```
範例：「實作 ETH 鏈入款 webhook 處理，只改 `service/` 和 `event/`，`mvn test` 通過後暫停等我確認」

**任何會修改多個檔案的任務，必須先做分析步驟（不得直接動程式碼）：** 列出將新增/修改的檔案路徑 → 說明每個改動原因 → 指出風險點 → 等待確認。

---

## 功能實作工作流程

### Step -1：環境 preflight（每個 session 第 1 次動工前）

```bash
# JDK 對齊（Java 21）
export JAVA_HOME=<你的 JDK 21 路徑>
export PATH="$JAVA_HOME/bin:$PATH"
java -version 2>&1 | grep '21' || { echo "[preflight] JDK 未對齊 21"; exit 1; }
```

視情境（剛 pull 大量 commit / 改 pom / 上個 session build 壞）再跑：
```bash
mvn -pl crypto-payment-service compile -o -q
```

| 失敗 | 處置 |
|------|------|
| JDK 未對齊 21 | **必修，不動工** |
| dep 缺（`was not found`） | 不阻塞 Edit，記 warning，push 前處理；IDE 大量錯誤訊號不可靠，靠 grep + 人工驗證 |
| 實際 code 編譯錯 | **必修**（HEAD 本身壞） |

**Commit 前必跑** `mvn -pl crypto-payment-service compile -q` 驗 HEAD。

### Step 0：研究與重用

- **先查庫內**：grep `utils/`（25 類，避免重造）+ 既有 `service/` 有無類似實作
- **查函式庫文件**：Context7 MCP 確認 Web3j / Trident / ShardingSphere / Jedis API
- **資料流向驗證**（涉及「存到哪、從哪讀」）：grep DB 欄位（mapper XML）+ 對應 POJO + 是否 config 表 / *ConfigCache，證據貼進 spec「影響範圍」
- **決策矩陣**：完全匹配 → 採用｜部分 → 擴展包裝｜多弱匹配 → 組合｜找不到 → 自建

### Step 1：規格確認（涉及業務邏輯時強制）

- 用 **`spec-review`** skill；**規格未確認不寫程式碼**
- 業務 grounding 後先過 **Mental Model Check**（≤100 字現況摘要：資料結構真相 + 關鍵檔案清單 + 架構決策），使用者回「架構錯了」→ 回 Step 0 重 grep
- 規格存 `plan/YYYY-MM-DD_<功能名>_spec.md`
- **CONFIRM gate**：所有 ⏳ 已決議 + 開發者顯式 CONFIRM 才進 Step 2

### Step 2：規劃

- 用 **planner** agent 產出 `plan/YYYY-MM-DD_<功能名>_plan.md`
- **回流硬規則**：發現 spec 漏業務規則 / L 層該升級 → **暫停 plan，回 Step 1 補 spec 重 CONFIRM**，禁在 plan 偷補業務邏輯
- plan 必含 8 章節：§1 Investigation · §2 Architecture Changes（檔案清單，單一事實來源）· §3 Implementation Steps · §4 Test Plan · §5 Risk Callouts · §6 Sequencing · §7 Open Questions · §8 Success Criteria
- **OQ 硬規則**：可 grep/read 驗證的 planner **自答鎖定**；需業務判斷（金額語意、狀態機、歸集門檻、確認數、是否回溯）**必列 OQ 嚴禁推測**；OQ 決議必回寫 plan（原文加刪除線 + ✅ 決議），只存 chat 不算數

### Step 3：測試（Mode B）

| 層 | 範圍 | 執行 |
|----|------|------|
| **L1** | 金額/入帳/歸集/狀態機/併發/冪等/私鑰/HMAC/platform_id | JUnit 5 整合測試，**強制** |
| **L2** | 一般 service/controller | 可選 |
| **L3** | config/VO/refactor/typo | 不寫 |

詳見 [`testing.md`](./testing.md)。有疑問升級。

### Step 4：審查（分兩階段）

**4a. 增量審查**：寫完一個主要組件（service method / 複雜查詢 / 安全敏感 controller）就先丟合適 reviewer——涉及私鑰/驗簽 → security；金額/入帳/歸集 → business + java；SQL/Flyway → database。

**4b. 最終多 reviewer 平行（commit 前）**：`code-reviewer` + 領域 reviewer 平行（同一則訊息多 Agent），依 [`agents.md`](./agents.md) 路由。依 Harness Output Contract：`block` 必修、`warning`(HIGH>0) 要決議、`approve` 可進 Step 5。

**4c. briefing**：見 [`agents.md`](./agents.md) §子 Agent 規範傳遞（自包含、≤500 字）。

**4d. Compact 評估**：已整讀 ≥3 檔 / reviewer 輸出 ≥2 / 修復 ≥1 輪 / 跨檔 grep ≥5 次 → 建議 `/compact` 或 `strategic-compact` skill。

### Step 5：提交與推送

- 見 [git-workflow.md](./git-workflow.md)：`type(PROJ-XXX): 描述` → `feature/PROJ_XXX` → `merge --no-ff developing_test`
- 提交前跑安全審查清單（見 [security.md](./security.md) §9）：platform_id / SignFilter / 明文私鑰 / `@Transactional` / 輸入驗證 / webhook 冪等

---

## 標準檢查點（功能開發，不得跳過）

```
✓ 檢查點 1：分析需求，列出影響檔案清單 → 等待確認
✓ 檢查點 2：Service 層實作完成 → 暫停 review 業務邏輯
✓ 檢查點 3：測試撰寫完成，mvn test 通過 → 暫停確認
✓ 檢查點 4：安全審查（platform_id、SignFilter、私鑰、@Transactional）→ 等待確認
✓ 檢查點 5：確認 commit message → 執行 commit
```

### 範圍控制

- **允許自主**：`service/` 業務新增、`controller/` 新 endpoint、`repository/` 新查詢、`src/test/` 測試
- **每層完成暫停確認**：Kafka producer/consumer、跨平台查詢、Quartz 排程變更、webhook 驗簽流程
- **絕對禁止自動執行**：任何 Flyway migration、改 `SignFilter.java`、改 AES-GCM 加密碼、刪除既有方法/類、改 `application-*.yml`

---

## 操作原則（工具硬規則）

- **同一工具同參數失敗 ≥ 2 次 → 停手換工具 / 解根因**，不第三次重試
- **大檔案 > 300 行禁 full read**：先 grep 定位再 `Read(offset, limit)`（見 [coding-style.md](./coding-style.md) §6）
- **平行化**：獨立 tool calls 同一則訊息平行啟動
- **Context 管理**：一個工單 = 一個 session，完成 `/clear`；單次任務改檔上限 ~10 檔，超過拆分

---

<!-- shared:oq-plain-language -->
## OQ 與「要問使用者」的兩條硬規則

### 一、用國中生聽得懂的話寫

每一則 `⏳` OQ、以及每一個你要丟給使用者的問題，都必須讓**一個國中生讀完就能直接回你 A 或 B**。
做不到就是寫壞了，**重寫**，不要送出去。

**每則必含三段：**

| 段 | 寫什麼 |
|---|---|
| **情況** | 什麼時候、什麼狀況下會遇到這件事 |
| **卡住什麼** | 不決定的話，哪個功能／流程做不下去 |
| **選項** | 每個一句話 + 它的代價；傾向的那個後面標「（建議：一句理由）」 |

**禁止：**

| ❌ | 為什麼不行 |
|---|---|
| 只寫「OQ-5 未決，無法繼續」 | 看的人不知道 OQ-5 是什麼 |
| 用內部代號當問題本體（任務編號、章節號、模組名、函式庫名） | 那是我們的編號，不是問題 |
| 用技術名詞而不解釋（冪等、併發、接縫、契約、回歸） | 要用就當場用一句話說明白 |
| 沒有選項，只寫「請指示」 | 沒選項等於要對方從零想，那是我們的工作 |

> **反例**：「彩池瓜分的比例演算法與時間窗未定義」
> **正例**：「大獎被好幾個人同時中時，錢怎麼分？」＋ 情況 ／ 卡住什麼 ／ A、B、C 各自的代價

### 二、沒問題就不要硬生問題

送出之前先自問：**這題我能不能從需求、既有文件、或本範本的既有慣例，推出一個合理的預設？**

- **能** → **直接採用預設**，在產出裡用一句話寫明「我採了什麼、為什麼」，然後繼續做。**不要開 OQ。**
- **不能，而且不同答案會導向實質不同的工作** → 這才是真的 OQ，照第一條的格式寫。

> **為什麼**：問題本身有成本。把自己判斷得出來的事丟回去，等於把工作推回給對方；
> 而且會**稀釋真正需要拍板的那一題** —— 一次丟五個問題，重要的那個就被淹掉了。
> **湊數的 OQ 比沒有 OQ 更糟。**

> 兩條不衝突：第二條決定**要不要問**，第一條決定**問了怎麼寫**。
<!-- /shared -->
