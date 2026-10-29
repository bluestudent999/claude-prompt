# Agent 協作編排

> Agent 定義位於 `.claude/agents/`，此 rule 僅規範使用原則。

---

## 編排模型

### 流程骨架

```
使用者需求
   │
   ▼
[spec-review] — 業務 gate（規格未確認不動工）
   │
   ▼ CONFIRM
[planner] — 拆解步驟 + 每步標示 L1 / L2 / L3（見 development-workflow.md §Step 3）
   │
   ▼ 有 L1 改動時
[tdd-guide] — L1 關鍵路徑整合測試
   │
   ▼
[code-reviewer] + 語言專項（java-reviewer）
   │
   ▼ 視內容並行
[business-reviewer] [security-reviewer] [database-reviewer]
   │
   ▼
L1 附整合測試報告 / L2-L3 附手動 QA checklist → 提交 / MR
```

### 何時繞過

- **Bug 修復（非業務邏輯）**：可省 `spec-review`，直接 `planner` → `tdd-guide`
- **純重構**：可省 `spec-review` / `tdd-guide`，用 `refactor-cleaner` → `code-reviewer`
- **單行改動（typo、config 值）**：可省整個流程，直接改完請 `code-reviewer` 輕掃

---

## 需求入口：先定位 domain（硬規則）

> **收到使用者需求時 → spec-review Step 0 之前**，主 agent 必須先走「domain 定位」三步，避免直接全 repo grep 導致 context 過載。

> **越界先攔（先於 domain 定位）**：若需求本質是「新需求規劃 / 範圍界定 / 規格 / 任務拆解」、「Java 8→21、Boot 2→3 版本升級遷移」或「對 lion-service 做資安掃描、產資安報告」，**不屬本維護範本職責** → 明確提示使用者切換對應 prompt-setup（見 CLAUDE.md『跨 prompt-setup 職責路由』表），不進 domain 定位、不臆測代答。
>
> **反方向是本職**：使用者拿資安報告（`security-report/<日期>/`，由 `prompt-setup 資訊安全 lion-service` 產出）來要求修某條 finding → 這是 bug fix，照本範本流程做，L 層至少 L1（見 `rules/development-workflow.md` §資安 finding 修復）。

### 三步定位流程（含 L 層預判）

1. **查 `rules/modules.md` 索引**
   - 比對使用者「業務關鍵字」欄位到索引表，鎖定**最窄的 domain 列**
   - 該列的「對應目錄」= grep / Read 的範圍上限，後續步驟**禁止**擴大出這個目錄
   - 該列「業務知識」欄有 domain 名 → 讀團隊的業務知識正本（`git show origin/developing:.claude/skills/business/<domain>/SKILL.md`，見 `rules/modules.md` §業務知識正本）；讀不到就告知使用者，**不憑印象補業務規則**
   - **立即預判 L 層**：從該列「風險」欄讀出 L1 / L2 / L3，輸出給使用者確認（例：`預判 L 層：L1（金額/結算）`），並寫入後續 spec §「風險評估」— planner 只確認不得降級，若有升級理由直接在 plan §5 說明。

2. **索引表找不到匹配 → 委派 Explore agent（quick 模式）**
   - 不要主 agent 親自全 repo grep
   - Explore briefing：`以關鍵字 {K1, K2} 搜 cp-service / single-wallet-service / collector-service / upload-service 的 service/*、controller/*、job/*，回最可能的 domain 目錄 + ≤ 5 個關鍵檔案路徑。不回原始 grep 行。` ≤ 300 字
   - 收到回覆後補 `rules/modules.md` 新增該 domain 列（後續需求可直接查表）

3. **跨 domain 需求（2 個以上 domain 都相關）**
   - 主 agent 列出涉及的 domain 清單（例：`lottery` + `rebate`）
   - 每個 domain 獨立 grep，結果合併在 plan §1 Investigation

---

## Agent 清單與路由

| Agent | 主要職責 | 觸發時機 |
|-------|---------|---------|
| **code-reviewer** | 程式碼品質、安全性、可維護性 | 寫完程式碼後第一輪審查 |
| **java-reviewer** | Spring Boot 框架模式深度審查 | Java 程式碼變更（Controller/Service/DAO 等） |
| **business-reviewer** | 業務邏輯正確性 | 涉及金額/金額異動/訂單/狀態機/整合 |
| **security-reviewer** | 安全漏洞偵測 | 涉及驗證、加密、使用者輸入、對外 API、回調 |
| **database-reviewer** | MySQL/SQL/Schema 審查 | 寫 SQL、Flyway 遷移、Schema 設計 |
| **build-error-resolver** | Java/Maven 建置錯誤修正 | `mvn compile` 失敗 |
| **refactor-cleaner** | 死碼清理、重複消除 | 移除未使用程式碼、合併重複邏輯 |
| **tdd-guide** | 測試驅動開發 | 新功能、Bug 修正（測試先行） |
| **planner** | 實作計畫拆解 | 已確定方案，要拆步驟 |
| **architect** | 架構設計、技術權衡 | 評估技術方案、選型 |

---

## planner agent 特殊原則

### OQ 自答 → 必確認（禁止推測）

planner 產出 OQ 前，**必須先嘗試自答**，不要把可自驗的問題丟給 user：

| OQ 類型 | planner 處置 |
|---------|------------|
| 可用 Grep / Glob / Read 驗證（例：檔案是否存在、方法簽名、enum 值、DAO 路徑、test/ 目錄結構） | **自答鎖定**，直接寫入 plan §7 ✅，**不列 OQ 給 user** |
| 需業務判斷（金額語意、狀態機含義、結算規則、已結算是否回溯、UI 顯示位置） | **必列 OQ**，**嚴禁推測** — 有疑問一律問 user 確認 |
| 跨模組 / 跨 repo 假設（admin API 資料流、第三方 webhook 格式、是否已有 JSON 反序列化目標） | 若 Grep 能驗證 → 自答；若涉及外部系統行為 → 必列 OQ |

**硬規則：**
- 列 OQ 前須在 plan §1 Investigation 記錄已嘗試哪些驗證步驟（grep pattern / 讀過哪個檔案 / ls 過哪個目錄）
- 光「我猜」「依慣例應該...」**不算自答**
- OQ 選項必列 planner 建議（A/B/C），建議理由 ≤ 2 句話

### OQ 決議必回寫 plan（硬規則）

planner 或主 agent 收到 user 對 OQ 的決議後：

1. **保留原始 OQ 文字並加刪除線**：原 OQ 描述改為 `~~原始問題文字~~`，決議另起一行標 `✅ <決議內容>`，**不刪除原文**（git history + reviewer 需看到決策過程）
2. 若決議影響 §2 檔案清單 / §3 實作步驟 / §5 風險 → **連帶 edit 這些章節**
3. 僅存在 chat 對話中的決議**不算數** — 下次 session 或 reviewer 讀 plan 時看不到

**違反此規則的後果：**
- OQ 未回寫 plan → 視同未決議，不得進 Step 3 測試 / Step 4 review
- Reviewer 讀 plan §7 看到 ⏳ 待決但實作已完成 → Counts 列 block 擋合入

---

## 主動啟用（無需使用者提示）

> **L 層判定優先於情境觸發**（見 `rules/development-workflow.md` §Step 3）。reviewer 強度要與變更風險匹配，避免對 L3 pure wiring 派多 reviewer 浪費 token。

### 依 L 層決定 reviewer 數

| L 層 | 範圍 | reviewer 配置 |
|------|------|---------------|
| **L3** | config 欄位 / DTO / i18n JSON / pure refactor / typo / 純 wiring | **code-reviewer × 1**（輕掃，不派 java-reviewer） |
| **L2** | 一般 service / controller / 跨模組整合（非金額 / 非狀態機） | **code-reviewer** + 擇一領域 reviewer（java / security / database） |
| **L1** | 金額 / 餘額 / 結算 / 狀態機 / 併發 / 冪等 / 第三方對接 / **包網商隔離（platformId）** / **filter 與放行清單** / **賠率、限額、封盤、開獎寫入** | **code-reviewer** + **java-reviewer** + 必要領域 reviewer（business / security / database），平行啟動 |

### 依情境追加（與 L 層疊加）

| 情境 | 追加 reviewer |
|------|---------------|
| 涉及金額 / 訂單 / 狀態機 / 整合 | **business-reviewer** |
| 涉及使用者輸入 / 驗簽 / 回調 / 加密 / `*Filter` / 放行清單 / 白名單 | **security-reviewer** |
| 查詢、匯出、快取 key、排程批次會碰到 `platformId` | **security-reviewer**（隔離，`checks/platform-isolation.md`） |
| 涉及 SQL / Flyway / Schema | **database-reviewer** |
| 複雜功能需求 | **planner** |
| 架構決策 / 技術選型 | **architect** |
| `mvn compile` 失敗 | **build-error-resolver** |

### 判定原則
- **先看 L 層再看情境**：L3 pure wiring 即使碰到「情境：Java 程式碼變更」也不再自動加 java-reviewer
- 有疑問升級不降級：L2 / L3 邊界模糊 → 取 L2 配置
- reviewer 太多反而稀釋焦點：同一個 PR 派超過 3 個 reviewer 時，重新評估是不是拆 MR 更好

### 派遣前 frontmatter 必讀（硬規則）

主 agent 派 reviewer 前**必須**：

1. **讀 spec/plan §0 frontmatter `l_tier` 欄位** — 單一事實來源；缺欄視同 L1
2. **對照上表**選 reviewer 組合，禁止靠「情境感覺」覆蓋
3. **記錄派遣決策**：`[reviewer 派遣] l_tier=L3 → code-reviewer × 1`

| 違反情況 | 處置 |
|---------|------|
| L3 但派 ≥ 2 reviewer | warning；須說明理由 |
| L1 但只派 code-reviewer | **必須補派** business + security + database |
| 無 `l_tier` 欄 | **禁止派 reviewer** — 補 frontmatter 先 |

**例外：** 實作命中 L1 觸發詞（金額 / 結算 / platformId / Filter / 賠率）→ 取較高層配置，於派遣訊息註明升級理由。

### L1 的 business / security reviewer 用最強模型（硬規則）

L1 派 `business-reviewer` 或 `security-reviewer` 時，Agent 呼叫**必須帶 `model: "opus"`**。
理由：這兩類 reviewer 漏判的代價是錢與跨包網商資料外洩，不是風格問題；省模型費用在這裡不划算。

### 依模組追加（lion 模組既有規範，與上表疊加）

| 改動位置 | 必派 |
|---------|------|
| cp-service `controller/internal/` | code-reviewer + security-reviewer（內部介面被其他服務直接呼叫，簽名改了會斷） |
| cp-service `controller/third/`、single-wallet `filter/SingleWalletSignFilter.java`、任何 `*Filter.java` / 放行清單 | security-reviewer（驗簽 / IP 白名單 / 放行分支，`checks/filter-bypass.md`） |
| cp-service `service/funds/` `service/recharge/` `service/rebate/`、任何金額異動 | business-reviewer + security-reviewer |
| cp-service `job/service/*` 排程業務 | business-reviewer（重跑會不會重複扣款 / 發獎 / 結算） |
| cp-service `playcom` / `lottery` / `randomodds`、開獎結果寫入 | business-reviewer + security-reviewer（賠率與開獎，見 `rules/security.md` §彩票） |
| single-wallet `service/balance/`、`service/singlewallet/impl/*` | business-reviewer + security-reviewer + database-reviewer |
| single-wallet `context/SingleWalletContext.java`、`@SingleWalletType` 機制、`aspect/*` | architect + code-reviewer（改骨幹 / 切面範圍） |
| single-wallet `constants/RespStateEnum.java`、collector `CollectorController` 回傳格式 | business-reviewer（對接合約變動，回歸所有廠商 / 上游） |
| collector `GameCodeDictionary` / `NationType` / `CateCode`、`service/validation/*` | business-reviewer + code-reviewer（全站列舉 / 所有來源） |
| `cp-flyway/`、`zz_document/script/changelog/` | database-reviewer |

---

## 平行執行

獨立的 agent 呼叫**務必**在同一則訊息中平行啟動，不要循序等待。

---

## 主 agent context 保護（何時委派 Explore agent）

主 agent 親自 Grep / Glob / find 會將結果載入**自己**的 context；若搜尋結果量大，應委派 **Explore agent**（它有獨立 context，只回彙整結論）。

| 情境 | 主 agent 自做 | 委派 Explore agent |
|------|-------------|------------------|
| 明確檔案 + 明確字串（單檔驗證） | ✅ `grep -n xxx file` | — |
| 預期 ≤ 10 行結果的精準 grep | ✅ | — |
| 跨多檔搜尋 / 預期 > 10 行結果 | — | ✅ |
| 多關鍵字組合、需判斷「是否已有類似實作」 | — | ✅ |
| 「XxxBO 在哪些 caller 使用」類探查 | — | ✅ |
| 「報表流程從 API 到 DAO 的資料流」類追蹤 | — | ✅ |

### Explore agent briefing 要求

- **thoroughness**：`quick`（1-2 次搜尋）/ `medium`（3-5 次）/ `very thorough`（全面）
- **回傳格式**：只回**結論**（例：「找到 N 處 caller，主要在 X/Y/Z package；資料流為 A → B → C」），**不回原始 grep 行**
- **字數上限**：`quick` ≤ 300 字 / `medium` ≤ 800 字 / `thorough` ≤ 1500 字

### Multi-Explore 結果不一致時的交叉驗證

同時派 ≥ 2 個 Explore agent，回來的**關鍵路徑**（controller / API path / class FQN / domain 目錄）**不一致**時，**禁止**憑直覺選邊，必須交叉驗證。

**不一致訊號（任一命中）：**
- BE Explore 回的 controller path 與 FE Explore 回的 API call URL 對不上
- 同需求找到兩個 domain / module（例：`activity` vs `activity2`）
- 同一概念對應兩組 model / VO（欄位不同）

**交叉驗證 protocol（主 agent 親自）：**

1. **以 FE 的 axios URL 為錨**（FE 是真實 caller）：
   ```bash
   grep -rn "agentline/report/list" cp-service/src/main/java/ | grep -iE "RequestMapping|PostMapping"
   ```
2. 反推到實際 controller class + method
3. 比對兩個 Explore 結果，判定哪邊是 noise（舊代碼 / 不同 caller）
4. 結果寫進 plan §1 Investigation

**例外：** 兩個結果互補不衝突（BE 找到 service，FE 找到 component，透過明確 API URL 串接）→ 不需交叉驗證。

---

## 多角度分析（常見組合）

| 任務 | Agent 組合 |
|------|-----------|
| 新第三方服務對接 | **business-reviewer** + **security-reviewer** + **architect** |
| 金額異動流程變更 | **business-reviewer**（狀態機）+ **security-reviewer**（併發）+ **database-reviewer**（SQL） |
| 共用元件重構 | **code-reviewer** + **refactor-cleaner** + **tdd-guide** — 注意回歸風險影響多個整合 |
| 訂單抓取邏輯 | **business-reviewer**（去重/狀態）+ **database-reviewer**（ES 查詢） |
| 新增 / 修改 filter、放行清單、登入檢查 | **security-reviewer**（`checks/filter-bypass.md`）+ **code-reviewer** |
| 新查詢 / 匯出 / 報表介面 | **security-reviewer**（跨 platformId）+ **database-reviewer**（分片鍵、筆數上限） |

---

## 子 Agent 規範傳遞

子 Agent **不繼承父 context**、**不會自動讀 skills**（rules 會自動注入）。每個 sub-agent 啟動時 system prompt + rules + briefing 都要完整傳入；多 reviewer 平行若 briefing 不精準，會重複讀同一批大檔案 → context 大量消耗。**派子 Agent 必須自包含**：spec/plan 路徑、規範摘要、Harness Output Contract 提醒、diff 片段。

### Briefing 必含項目

| 項目 | 說明 |
|------|------|
| **spec/plan 路徑 + 章節編號** | ✅ `specs/xxx_plan.md §2 §7` / ❌ 把 spec/plan 全文貼進 prompt |
| **checklist 章節 + check 檔** | ✅ `rules/reviewer-checklists.md §business-reviewer` + 「標 🔬 的項目先 Read 對應 `checks/*.md`」/ ❌ 把 checklist 或 check 全文貼進 prompt |
| **diff 片段** | ✅ 貼 `git diff` 輸出（含行號） / ❌ 只丟檔名讓 agent 自己 full read（> 300 行尤其關鍵） |
| **聚焦範圍** | 平行 reviewer 各自分工（見下表），避免完全重疊讀同一批檔 |
| **規範摘要** | 從 rules 抄必要條文進 prompt（rules 自動注入但摘要更聚焦） |
| **Harness Output Contract** | 提醒輸出 Status / Summary / Counts / Next actions / Artifacts |

**Briefing 總長度目標 ≤ 500 字**（排除 user 提供的原始需求貼文）。原則：給**任務目標 + 查資料的位置**，不用抱整箱資料進門。

### 平行 reviewer 分工聚焦

| reviewer | 聚焦面向 | 忽略 |
|---------|---------|------|
| `code-reviewer` | 結構 / 命名 / 死碼 / 重複邏輯 | 業務邏輯細節 |
| `java-reviewer` | 分層 / Spring 模式 / 事務 / Lombok | 業務規則正確性 |
| `business-reviewer` | 狀態機 / 金額 / 冪等 / 業務流程 / 斷線防禦 | 語法風格 |
| `security-reviewer` | 驗簽 / 輸入驗證 / 機密 / Log 脫敏 / Token 相容 / **platformId 隔離** / **filter 放行分支** | 結構分層 |
| `database-reviewer` | SQL 拼接 / ShardingSphere / 索引 / 兩條 SQL 軌 | Controller / VO |

### 規範摘要對照（按任務挑）

| 任務類型 | 必抄條文 |
|---------|----------|
| 金額/餘額審查 | `BigDecimal` + `RoundingMode.DOWN`、`SELECT FOR UPDATE` + 事務、`orderNo` 冪等、流水寫入順序 |
| 整合審查 | 金額同上、API Key 從 `*ConfigCache`、驗簽、參考 `api-connector-builder` skill |
| SQL 審查 | ShardingSphere 4.0.1、DAO 走 framework_v3（**lion 沒有 MyBatis**，注入面是 `SqlUtil` / 字串拼接）、新 migration 用時間戳（`rules/flyway-migration.md`）、changelog 是否同步不得自判 |
| 安全與穩定性審查 | 機密不硬編碼、驗簽或 IP 白名單、錯誤訊息脫敏、platformId 只取自 resolver（`rules/platform-isolation.md`）、不新增副檔名 / 子字串放行（`rules/security.md` §filter 防線）、Token 向後相容（`rules/stability.md`） |
| 資料物件命名 | VO/SO/BO/Query/Record/Event（見 [`patterns.md`](./patterns.md) §8），禁 DTO/Request/Entity；共享物件放 `lion-common` |
| i18n 異動 | 一律走 `scripts/i18n.py`；**禁 Edit / Write i18n 檔** — 詳見 `rules/i18n.md` |

### reviewer briefing 模板（複製即用）

```
# 任務
Review <feature 名稱>，聚焦 <分工項目>，產出 Harness Output Contract。

# 變更範圍（精準行號 + diff）
<file>:<L_start>-<L_end>
```diff
<git diff 片段>
```

# 相關規範（指路，不貼全文）
- Checklist：rules/reviewer-checklists.md §<reviewer 名>；標 🔬 的項目先 Read 對應 checks/*.md
- Severity：rules/severity-rubric.md；Artifacts 每條標 [SEVERITY|c=NN]
- 金額：BigDecimal + RoundingMode.DOWN
- <其他必要條文>

# 輸出格式
最後一段必須是 Harness Output Contract：Status / Summary / Counts / Next actions / Artifacts
```

---

## Harness Output Contract（reviewer / resolver / 執行類 agent 必須遵守）

下列 agent 的**最後一段**必須輸出固定區塊：

```
---
**Status:** approve | warning | block
**Summary:** {一句話總結結果 ≤ 80 字}
**Counts:** CRITICAL=N HIGH=N MEDIUM=N LOW=N
**Next actions:**
- [ ] {動作 — 指明誰改哪個檔做什麼}
**Artifacts:**
- {file}:{line} — {issue} | fix: {fix}
```

**Artifacts 每條前綴 `[SEVERITY|c=NN]`**（例：`[HIGH|c=90] cp-service/.../XxxService.java:120 — ...`）。分級與 confidence 上限一律依 `rules/severity-rubric.md`，reviewer 不得自訂標準。

**Status 判定：** 依 `rules/severity-rubric.md` §3 —— 只有 confidence ≥ 85 的 finding 進入判定；CRITICAL ≥ 1 → `block`；HIGH ≥ 1 或累計 MEDIUM ≥ 5 → `warning`；其餘 → `approve`。confidence < 85 的照列 Artifacts，但不擋合入。小寫英文，不翻譯，不用 emoji。

### 主 agent 對 reviewer finding 的判斷責任（不盲從）

reviewer 的 finding 是**待驗證的假設**，不是待執行的命令。套用前 —— 尤其防禦性 / future-proofing / 風格類 —— 先驗「**現在**是否真的適用」：風險現在存在嗎（grep 第二個 caller）、前提是否已被別處保證（caller 已有 `@Transactional`）、套用的代價（冗餘註解、反覆 churn）。

CRITICAL 與明確 bug 類照修，不在此列。誤報 / 漏報記到 `evals/findings/`（團隊跨人累積，價值在彙總）。

**套用範圍：**

| Agent 類型 | 版本 |
|-----------|------|
| Reviewer（code / java / security / database / business） | 完整版（5 欄位） |
| build-error-resolver | Resolver 變體（`fixed:` / `remaining:` 取代 `fix:`） |
| tdd-guide / refactor-cleaner | 輕量版（Status / Summary / Counts） |
| planner / architect / spec-review | 豁免 |

輕量版格式：`Status` / `Summary` / `Counts`（依 agent 語義填 Counts，省略 Next actions / Artifacts）。

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

---

## 相關資源

| 主題 | 位置 |
|------|------|
| Agent 實作定義 | `.claude/agents/*.md` |
| 開發流程（研究 / 規劃 / TDD / 審查） | `rules/development-workflow.md` |
| Git 操作（提交 / 分支 / MR） | `rules/git-workflow.md` |
| 金額 / RoundingMode / filter 防線 / 彩票 | `rules/security.md` |
| 包網商隔離 | `rules/platform-isolation.md` |
| 分級標準 / reviewer 檢查項 / 原子檢查 | `rules/severity-rubric.md`、`rules/reviewer-checklists.md`、`checks/` |
| 分層 / DI / 整合 / 資料物件 | `rules/patterns.md` |
| 格式 / 命名 / Log / Lombok | `rules/coding-style.md` |
| 業務 domain 索引（domain 定位用） | `rules/modules.md` |
| Eval 回歸紀錄 | `evals/README.md` |
