# 開發工作流程

> 開發流程層規範（環境準備、研究、規劃、TDD、審查）。git 操作（提交格式、分支、PR）詳見 [git-workflow.md](./git-workflow.md)。
> **團隊所有成員必須遵循此流程。**

---

## 需求提交格式（使用者端）

**軟性格式**（非硬性表單）。使用者提需求時建議用 5 欄位模板（需求類型 / 需求簡述 / 業務關鍵字 / 觸發情境 / 預期結果 / 備註）；缺欄位不擋工，由 `spec-review` skill 以 `⏳` 標出並補問。

### 欄位用途對照

| 欄位 | Claude 端用途 |
|------|------------|
| **需求類型** | 決定 Step 1 gate 路由：新功能 / 修改 → `spec-review`；bug fix（非業務邏輯）→ 跳過 `spec-review`；純重構 → 跳過 `spec-review` + `tdd-guide`；typo / 單行 config → 整個流程省略（見 `rules/agents.md` §何時繞過） |
| **需求簡述** | 交叉驗證需求類型（動詞「新增」→ 新功能、「修正」→ bug fix）；不一致時以此為準並回問 |
| **業務關鍵字** | 觸發 L 層判定（金額 / 餘額 / 狀態機 → L1）與 reviewer 路由（business / security / database） |
| **觸發情境** | 定位受影響的 Controller / Service / 頁面 → Step 0 研究重用的 Grep 起點 |
| **預期結果** | 寫入 spec §「驗收條件」；對應後續 Test Plan |
| **備註** | deadline 影響 Sequencing；ticket 連結用於追溯與 MR description |
| **附圖**（選填） | Jira / Slack / 截圖數量；附圖含紅框 / 標註等視覺資訊**對需求理解關鍵**時，在備註明示「需看圖才能準確判斷」 |

### 缺欄位時的處置

| 缺欄位 | Claude 處置 |
|-------|-----------|
| 需求類型缺 | 以「需求簡述」動詞推測；推測不確定時預設走 `spec-review` gate（寧可多一步確認，不可跳過業務 gate） |
| 業務關鍵字缺 | 以需求簡述關鍵詞 grep repo 補推測，草稿標 `⏳ 請確認涉及模組：A / B / C` |
| 觸發情境缺 | planner 於 plan §1 Investigation grep 常見進入點（controller / job）；仍不確定 → 列 OQ |
| 預期結果缺 | **必問** — 沒有可觀察變化等於無法驗收，不得進 Step 2 規劃 |
| 備註缺 | 視為無特殊限制，Sequencing 依預設最小切分 |

---

## 功能實作工作流程

### Step -1：環境 preflight（每個 session 第 1 次動工前）

避免邊做 task 邊踩環境坑。cx-sports-v2 使用 Java 8。**分兩層執行**，避免 `mvn compile` 慢 / 內部私服 dep 拉不到之類的問題拖慢每次 session 起動。

#### L1 Fast — JDK 對齊（必跑，< 5 秒）

```bash
# 1. JDK 對齊（Java 8；注意 /usr/libexec/java_home -v 1.8 可能指到 JavaAppletPlugin，無 javac）
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk1.8.0_261.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
javac -version 2>&1 | grep "1.8" || { echo "[preflight L1] JDK 未對齊"; exit 1; }
```

> JDK 路徑依本機實際安裝版本調整；重點是 `javac -version` 必須回 1.8.x。
> `/usr/libexec/java_home -v 1.8` 在 macOS 有時指到 `JavaAppletPlugin.plugin/Contents/Home`（只有 JRE 無 javac），**不要依賴它**。

#### L2 Offline Compile — 可選（只在以下情境跑）

跑 L2 的時機（符合任一條）：
- 剛 `git pull` 帶進大量 commit
- 這次 task 要改 `pom.xml` / 新增 dependency
- 跨 JDK 版本切換本機
- 上個 session 遺留 build 失敗未修

```bash
# 只 compile 當前模組 main（不編譯 test，不 also-make），用本地 ~/.m2 cache 不連網
mvn -pl <module> compile -o -q
```

#### 硬規則

| 失敗情境 | 處置 |
|---------|------|
| L1 失敗（JDK 未對齊） | **必修，不動工** — 編譯器版本不符會讓 IDE 錯誤訊號誤導 |
| L2 失敗（dep 缺，例：`was not found`） | **不阻塞 Edit work**，記 warning；push 前再處理。**注意：dep 缺時 IDE diagnostic 會顯示大量錯誤，不要依賴這些訊號做判斷** — 靠 Grep + 人工讀 code 驗證，commit 前真 compile 才是最終防線 |
| L2 失敗（實際 code 編譯錯） | **必修** — 代表 HEAD 本身壞掉，疊上去的改動無效 |
| L2 未跑（不符時機清單） | **允許** — session 末或 commit 前再驗一次即可 |

**Commit 前必跑**：`mvn -pl <module> compile -q`（去掉 `-o`，真正驗 HEAD），確保送出的 code 可編譯。

---

### Step 0：研究與重用（任何新實作前的強制步驟）

- **先看倉庫內**：Grep 搜尋 `connector/impl/` 有無類似實作，多個第三方整合中很可能已有
- **再搜尋 GitLab**：`glab repo search` / `glab api /search?scope=blobs&search=<keyword>` 尋找組織內現有實作和模式
- **查閱函式庫文件**：使用 Context7 MCP 確認 API 行為和版本細節
- **決策矩陣**：完全匹配 → **採用**｜部分匹配 → **擴展包裝**｜多個弱匹配 → **組合**｜找不到 → **自建**

> 大檔案讀取策略（> 300 行禁 full read）見 [`coding-style.md`](./coding-style.md) §6。

#### 0a. 資料流向驗證（涉及「設定 / 第三方欄位 / per-venue / per-platform」必做）

**硬規則：** 涉及「要存到哪、從哪讀」的設計決策，spec 未確認前必跑下列驗證並把證據貼進 spec 的「影響範圍」章節（否則 JSON blob vs 獨立欄位判斷錯誤 → 整個 Phase 0-3 做兩遍）：

```bash
# 1. DB 欄位（snake_case） — 看 mapper XML 怎麼 select / update
grep -rn "<column_name>" --include="*.xml" -l

# 2. 對應 POJO / VO / Record（PascalCase） — 看類別長怎樣
grep -rn "<PascalCasePojo>" --include="*.java" -l

# 3. 判斷是否 JSON blob — 有 JSON.parseObject / TypeHandler 就是
grep -rn "JSON.parseObject\|TypeHandler" --include="*.java" | grep -i "<domain>"

# 4. 最終確認欄位清單 — 讀 mapper XML 前後 2 行
grep -rn "<column_name>" --include="*.xml" -A 2 -B 2
```

**判定方式：**
- 找到 `JSON.parseObject(record.getXxxInfo(), ...)` 或 `TypeHandler` → **JSON blob 模式**，新增欄位改 POJO 即可，**不需 DDL**
- 只看到一般 `<result column="..." property="..."/>` → **獨立欄位模式**，新增欄位需 Flyway migration

**spec 必寫明：** 「影響範圍」章節須明確標示 `per-venue 存 JSON blob（PlatformCostSchemeThirdInfo），不需 DDL` 或相反，**鎖定後續實作路徑**，避免 planner / 執行者走錯方向。

#### 0b. JSON 反序列化目標完整搜尋（涉及 DB `text` / `json` 欄位時必做）

若 Step 0a 判定為 **JSON blob 模式**，必須列出**所有**反序列化目標類別（同一 JSON 可能有多個 BO/VO 讀取）。**三組 pattern 缺一不可**，漏了泛型用法會導致新增欄位在部分 API 讀到 null：

```bash
# pattern 1：.class 指定型別（最常見）
grep -rn "JsonUtil.toList.*XxxBO.class\|JsonUtil.toObject.*XxxVO.class" cx-sport-app-service

# pattern 2：TypeReference 泛型（集合 / 泛型巢狀時必用 — .class pattern 抓不到）
grep -rn "TypeReference<.*XxxBO\|TypeReference<.*XxxVO" cx-sport-app-service

# pattern 3：Fastjson / Gson 的 parseObject / fromJson
grep -rn "parseObject(.*XxxBO\|parseArray(.*XxxBO\|fromJson(.*XxxBO" cx-sport-app-service
```

**硬規則：**
- 列出所有反序列化目標類別後，**每個都要加對應欄位**
- 在 plan §1 Investigation 紀錄本次找到的反序列化目標清單
- 寫入端與讀取端**成對確認**（例：寫入的 Service 不寫此 JSON → 加了欄位可能用不到，寫入側必須同步補）

---

### Step 1：規格確認（涉及業務邏輯時的強制步驟）

- **一般功能需求 / Bug 修復** → 使用 **`spec-review`** skill（內部走 Phase A → F，注意與本檔 Step 編號不同層級）
- **業務 grounding 完成後務必先過 Mental Model Check**（spec-review §Phase B）— 100 字現況摘要 sanity gate；10 秒換掉 300 行 spec 重寫成本
- 與 PO / 相關人員確認業務邏輯，**規格未確認前不寫程式碼**
- 規格存 `plan/YYYY-MM-DD_<功能名>_spec.md`
- **CONFIRM gate 硬規則**（spec-review §Phase E）：必須**同時**滿足 (a) 所有 ⏳ 已決議 + (b) 開發者顯式 CONFIRM 才能進 Step 2 — 沒有 ⏳ ≠ 自動通過

#### Mental Model Check 一次到位（spec-review skill 的第一輪摘要規則）

spec-review skill 要求在寫完整 spec 前先輸出 ≤100 字現況摘要等使用者確認。**第一輪摘要就必須包含**：

1. **資料結構真相**（引用 Step 0a 的 grep 證據）：例「per-venue tipRatio 存 `PlatformCostSchemeThirdInfo` JSON blob，不是獨立欄位」
2. **關鍵檔案清單**（5-10 個最相關、帶路徑）：例「settle 流程走 `PlatformSettleReportV2Service.calThirdOrderFee`，不是 `SportBillDao`」
3. **架構決策**（鎖定實作方向）：例「新欄位加在 POJO，無 DDL」

若使用者回「架構錯了」 → 回 Step 0 §0a 重新 grep，**不要進第二輪摘要直接寫 spec**（避免上下文重新傳遞兩次）。

---

### Step 2：規劃

- 使用 **planner** agent 建立實作計畫，產出 `plan/YYYY-MM-DD_<功能名>_plan.md`
- 識別依賴項與風險，拆分為多個階段
- plan 內保留 **Open Questions** 區段（planner 調查時發現、spec 沒答的**技術**問題；業務問題禁止留在 plan）
- **開發者回答 OQ 後才進 Step 3**

**回流硬規則（plan → spec 不單向）：**

- **業務漏洞回流**：planner 動工後若發現 spec 漏業務規則（例：spec 沒提退款情境、狀態機漏一條合法轉換）→ **暫停 plan**，回 Step 1 補 spec、重 CONFIRM、再進 Step 2。**禁**在 plan 內偷補業務邏輯。
- **L 層覆寫回流**：若 planner 認定 spec 的 L 層應升級（例：spec 寫 L2 但發現會動到金額計算 → 應升 L1）→ **不要**在 plan 中悄悄升 L 層，回 Step 1 改 spec 模板（影響測試強度與 reviewer 派遣）、重 CONFIRM、再進 Step 2。
- 詳細流程見 `agents/planner.md` §進 planner 前的硬規則。

**plan.md 必含章節：**

| 章節 | 內容 | 用途 |
|------|------|------|
| § 1 Investigation | 動筆前的假設驗證（SQL 行為、DAO 簽名、cache 語意、**資料流向**— 見 Step 0 §0a） | 避免基於錯誤假設實作 |
| **§ 2 Architecture Changes（要改的檔案清單）** | 每個檔案：類型（新增 / 修改）、路徑、一句話描述 | **本次 MR 變更的單一事實來源**，Step 5 MR description 直接引用此表，不重寫 |
| § 3 Implementation Steps | 分階段拆解，含 sub-step | TDD agent / 執行者的指引 |
| § 4 Test Plan | spec R1-Rn 對應哪個測試案例 | 覆蓋率對照 |
| § 5 Risk Callouts | 已知風險點 + 緩解 | 給 reviewer 做焦點審查 |
| § 6 Sequencing | commit 粒度 / 可平行步驟 | 避免切太大不好 review |
| § 7 Open Questions | 留給開發者決議的選項 | 決議後鎖入文件，不再只存在 chat |
| § 8 Success Criteria | 合入前自檢清單 | Step 5 commit 前對照 |

**硬規則：**
- § 2 必須維持與實作同步 — 開發中若新增或改變檔案清單，**回頭更新 § 2**，不要只改 code
- OQ 決議後必須在 plan 文件內鎖定（如 OQ1 位置、OQ2 跨平台守衛），不能只存 chat 對話

---

### Step 3：測試實作（務實版）

詳見 [`testing.md`](./testing.md) — L1/L2/L3 分層定義、整合測試基座、技術債過渡規則。

| 層級 | 範圍 | 執行 |
|------|------|------|
| **L1** | 金額 / 餘額 / 結算 / 狀態機 / 併發 / 冪等 | `@SpringBootTest` 整合測試，**強制** |
| **L2** | 一般 service / controller | 可選 |
| **L3** | config / DTO / refactor / typo | 不寫 |

有疑問升級。L1 無基座時，MR description 必附技術債追蹤段（格式見 `testing.md §3d`）。

---

### Step 4：程式碼審查（分兩階段）

#### 4a. 增量審查（寫完大塊就做，不等全部完工）

每寫完**一個主要組件**（service method、複雜 DAO 查詢、安全敏感的 controller）就先丟 1 個合適的 reviewer。好處：
- HIGH 問題還沒擴散到下游（controller / test / i18n）前就修
- 避免整包做完才發現要大改

**時機對照表**（Phase 結束即丟）：

| 完成時機 | 優先送 reviewer | 目的 |
|---------|---------------|------|
| 資料結構完成（SO/VO/BO 欄位新增） | 略（L3 性質，合併到 4b） | — |
| 核心計算邏輯完成（金額 / 狀態機 / 結算 / 報表） | **business-reviewer + java-reviewer** | 早抓 RoundingMode / 語意漂移 / NPE |
| 驗簽 / 回調 / 使用者輸入完成 | **security-reviewer** | 早抓簽名算法 / 注入 |
| SQL / Flyway / Schema 完成 | **database-reviewer** | 早抓參數化 / 分片相容性 |
| UI / i18n 完成（FE） | 略 | 合併到 4b |

**啟動原則：** 同一 Phase 內的變更一次送 reviewer（不逐檔）；修完 CRITICAL / HIGH 後再進下一 Phase；4a Counts 保留，4b 最終時可比對 delta。

#### 4b. 最終多 reviewer 平行（commit 前）

- **code-reviewer** + 領域 reviewer（java / security / business / database）**平行**啟動（同一則訊息多個 Agent 呼叫）
- 依 [`rules/agents.md`](./agents.md) 路由表選 reviewer
- 依 **Harness Output Contract** 檢查 Status：
  - `block` → 必修
  - `warning`（HIGH > 0）→ 通常要修，至少要有決議
  - `approve` → 可進 Step 5
- 處理 CRITICAL 與 HIGH，盡量修 MEDIUM

#### 4c. Reviewer briefing（硬規則）

見 [`agents.md`](./agents.md) §子 Agent 規範傳遞（diff 片段、平行分工、規範摘要、Harness 提醒、briefing 模板）。

#### 4d. Reviewer 後評估 Context Compact（進 Step 5 前必評估）

Reviewer 輸出 + 主 agent 讀 reviewer + 寫修復 + 再驗 = 大量 context 累積。**任一觸發條件符合即建議 compact**（主 agent 無法直接測 token 數，改看以下可觀察代理指標）：

| 觸發條件 |
|---------|
| 已整讀實作檔案 ≥ 3 個（含 > 300 行的檔案） |
| Reviewer 已完成輸出 ≥ 2 個（各含 Artifacts / Next actions） |
| 中途已做過 ≥ 1 輪修復（修完又重跑 reviewer） |
| 已跑過 ≥ 5 次跨檔 Grep / Glob |
| 不確定時 → 主動向使用者詢問「是否已接近 context 上限、建議 compact」 |

**執行方式：** 提示使用者 `/compact` 或調用 `strategic-compact` skill。
- **保留**：Spec/Plan 路徑與摘要、最終 diff 檔案清單、Reviewer Final Status、CRITICAL/HIGH 修復清單
- **清除**：已讀實作細節、Grep 原始結果、中途 reviewer 輸出長文

---

### Step 5：提交與推送

- 詳見 [git-workflow.md](./git-workflow.md)
- commit 訊息：conventional commit
- MR 到 `developing` 分支，描述含：
  - 測試計畫（手動 QA 步驟 + L1 整合測試對應 spec 規則；若有 3d 技術債必附追蹤段）
  - **Release note**：權限範圍擴張、i18n 新 key、設定異動
  - 追蹤 ticket（若有 follow-up MEDIUM/LOW issue）
  - **AIDD metrics**（觀察用，不阻擋合入）— 見下方模板

#### AIDD metrics 模板（MR description 必附段落）

> **目的：** 累積 10-20 個 MR 後形成基線，回答「哪個 step 最耗 token / OQ 解決幾輪 / reviewer 抓真問題的命中率」。**僅觀察用，不作合入條件。**

```markdown
### AIDD metrics
- L 層：L1（金額計算）              <!-- 從 spec §元資料 / plan §0 複製，鎖定值 -->
- Spec 輪次：1（無回流）            <!-- spec-review CONFIRM 通過幾次；含 planner / reviewer 回流次數 -->
- Plan OQ 數：3（自答 2、user 決議 1）<!-- 區分 TECH 自答 vs BIZ user 決議；BIZ 視為觸發回流 -->
- Reviewer 輪次：增量 1 + 最終 1     <!-- Step 4a 增量幾輪 + Step 4b 最終 1 輪 -->
- Reviewer findings：CRITICAL=0 HIGH=2 MEDIUM=5（已修 HIGH×2、MEDIUM×3，MEDIUM×2 follow-up） <!-- 對照 Harness Output Contract Counts -->
- 預估 token 成本：~80k（spec 10k + plan 15k + impl 30k + review 25k）  <!-- 主 agent 自估即可，標 ~k -->
- Compact 次數：0                   <!-- 4d 觸發 /compact 幾次 -->
```

**填寫硬規則：**

| 欄位 | 來源 | 不確定時 |
|------|------|---------|
| L 層 | spec / plan §0 元資料（鎖定值） | 看 spec / plan §0 直接抄；若 spec 缺值 → 回 Step 1 補 |
| Spec 輪次 | spec-review Phase E CONFIRM 通過次數 | 主 agent 從對話起算；planner / reviewer 回流計入 |
| Plan OQ 數 | plan §7 條目數 | `grep -c "^- OQ-" plan/*_plan.md` |
| Reviewer 輪次 | Step 4a 增量送出次數 + Step 4b 1 | 從 reviewer 啟動次數估算 |
| Reviewer findings | 加總所有 reviewer Harness Output Contract 的 Counts | 修復狀態：`已修 X / follow-up Y` |
| 預估 token 成本 | 主 agent 自估（不需精準） | 階段標 `~k`，無法估 → 寫 `N/A` |
| Compact 次數 | 4d `/compact` 觸發次數 | 0 = 沒壓縮過 |

**指標解讀（累積後）：**

- Spec 輪次 ≥ 3 → spec-review skill 的 grounding 不夠紮實，回頭調 Phase B Mental Model Check 摘要要求
- Plan OQ「user 決議」≥ 5 → planner 自答能力弱，或 spec 業務細節漏太多
- Reviewer findings HIGH 平均 ≥ 3 → 增量審查（4a）時機太晚，往前推
- token 成本 impl 階段 > 50% → 大檔案 full read 失控，回查 [coding-style.md §6](./coding-style.md)
- Compact 次數 ≥ 2 → SOP 自身體量過大或 task 切太粗，考慮拆 MR

**不需要做的事：**

- 不必精準計算 token（主 agent 自估即可，標 `~k` 就行）
- 不必每個 MR 都寫 — L3 micro-spec / typo fix 可省略
- 不必通過任何閾值才能合入 — 純觀察，PO / TL 之後 batch review

---

## 操作原則（工具使用硬規則）

### 工具失敗重試上限

- 同一工具用**同樣參數**失敗 ≥ 2 次 → **停手換工具**，不要第三次重試
- 典型情境：
  - `Edit` 在 `.properties` / 含 `\uXXXX` escape 的檔案失敗 → 改用 `Bash + python`（處理 bytes 層，避免傳輸層 Unicode 轉換）
  - `mvn` 編譯錯誤訊息一致 → 先解根因（環境？dep？），不要重跑
  - `git` hook 擋住 → 讀 hook 訊息找根因，**不要 `--no-verify` 繞過**

### 大檔案讀取策略（硬規則）

檔案 **> 300 行禁 full read**：先 grep 定位方法行號，再 `Read(offset, limit)` 只讀該段。第一次讀取輸出**關鍵行號索引**保留在對話。完整指令與例外見 [`coding-style.md`](./coding-style.md) §6。

### 平行化

見 [`agents.md`](./agents.md) §平行執行。獨立 tool calls 必須在同一則訊息中平行啟動。

### 子 Agent 規範傳遞

派子 Agent 的 prompt 必須**自包含**（spec/plan 路徑 + diff 片段 + 規範摘要），**不貼全文**。完整 briefing 模板與分工表見 [`agents.md`](./agents.md) §子 Agent 規範傳遞。

---

## 第三方服務對接流程

走標準 5 步流程（Preflight → spec-review → 對齊 `connector/impl/` 現有實作 → 自查整合模式 → business + security reviewer 平行審）。新對接細節見 `api-connector-builder` skill。
