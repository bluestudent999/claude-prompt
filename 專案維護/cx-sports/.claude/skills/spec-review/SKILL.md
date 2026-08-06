---
name: spec-review
description: 規格預審。開發前產出結構化規格文件讓 PO 確認業務邏輯，確保開發方向正確再動手寫程式碼。
origin: template
---

# 規格預審（Spec Pre-Review）

開發前產出結構化規格文件，讓 PO / 相關人員在寫程式碼前確認業務邏輯。

## 啟用時機

- 新增功能需求
- 修改現有業務邏輯
- 涉及金額、狀態機、外部整合的任何變更
- Bug 修復（涉及業務規則時）

> **領域特化的規格預審**（如第三方整合、特定業務流程）請建立對應的業務 skill（由 `business-template` 複製改名），本 skill 提供通用骨架。

## 內部 Phase 編號說明

> spec-review skill 內部使用 **Phase A–F** 編號（避免與 `rules/development-workflow.md` 的 Step -1/0/1/.../5 混淆 — dev-workflow 的 Step 1 = 啟動本 skill；本 skill 內部的 phase 是執行細節）：
>
> - **Phase A**：業務面 Grounding（產草稿前）
> - **Phase B**：Mental Model Check（grounding 完 → 寫 spec 前的 gate）
> - **Phase C**：產出規格草稿
> - **Phase D**：開發者確認
> - **Phase E**：Wait-for-CONFIRM gate（解鎖進 planner）
> - **Phase F**：開發中追溯

## 需求輸入解析（Phase A 之前）

檢查使用者提交的需求是否符合 `rules/development-workflow.md` §需求提交格式（使用者端）的 **6 欄位模板**（需求類型 / 需求簡述 / 業務關鍵字 / 觸發情境 / 預期結果 / 備註）：

| 情況 | 處置 |
|------|------|
| 6 欄位齊全 | 依「需求類型」決定是否啟動本 skill（新功能 / 修改 → 啟動；bug fix 非業務邏輯 / 純重構 / typo → 可跳過，直接進 planner 或更後段）；啟動則進 Step 0 業務面 Grounding |
| 缺 **預期結果** | **必問使用者** — 沒有可觀察變化無法驗收，不得產 spec 草稿 |
| 缺 **需求類型** | 以「需求簡述」動詞推測（新增 → 新功能、修正 → bug fix、改成 → 修改）；推測不確定時**預設啟動本 skill**（寧可多一步確認，不可跳過業務確認） |
| 缺其他欄位（業務關鍵字 / 觸發情境 / 備註） | 依原則 2「直接產出，不先提問」填草稿，對應位置標 `⏳ 待確認：<原因>` |
| 需求完全自由格式（無欄位標記） | 嘗試從自由文本抽取 6 欄位，抽不到的項目全部標 `⏳` |

**目的**：讓 spec 草稿的 `⏳` 標記對應到明確的需求欄位缺口，PO 補問有具體對象。

### Anti-pattern：先寫完整 spec 才回頭精簡（禁止）

❌ 收到需求 → grep 完 → 寫完整 spec（A_full）→ 發現是 L3 → 回頭刪段
✅ 收到需求 → 5 秒 gate 判定 → L3 直接用 micro-spec（C）→ 30 行內完工

**L3 micro-spec 訊號（任一命中即走 C）：**

| 訊號 | 例 |
|------|------|
| 只有 UI 顯示變動（無資料流） | 加 column / 改 label |
| 純 i18n key 改值 | 翻譯修正 |
| 純 config 值調整 | 開關 / 閾值 |
| 既有共用組件加 prop | detail 彈窗加 header |
| 改 enum 字面（不改寫入端） | 顯示新狀態 |
| 純 wiring 補洞（API 已回傳，FE 沒接） | 既有欄位對接 |

事後發現低估 → 升級為 lite 或 full，**不要事前先寫 full 預防**。

## 原則

1. **先規格，後程式碼** — 規格未確認前，不產出任何實作程式碼
2. **直接產出，不先提問** — 依需求與文件**直接填完規格草稿**，待確認項目以 `⏳` 標在文件中
3. **白話優先** — 規格文件讓非技術人員也能看懂
4. **完整列舉** — 所有業務規則、邊界條件、異常處理都必須列出
5. **影響透明** — 明確標示會改動哪些模組、影響哪些下游
6. **不確定就明示** — 不確定的欄位寫 `⏳ 待查證：原因`，**禁止以聽起來合理的內容填空**（避免幻覺型規格）

## Phase A：業務面 Grounding（產草稿前）

在動筆前，先做 5 分鐘的**業務面**勘查，確認規格不與現有業務語義衝突：

1. **先定位 domain（硬規則，優先於其他步驟）**：
   - 查 `rules/modules.md` 索引，以「業務關鍵字」欄位比對，鎖定**最窄的 domain 列**
   - 後續步驟 3 / 4 的 `Grep` 範圍**限縮在該 domain 對應目錄內**（例：需求涉及結算 → 只 grep `cx-sport-app-service/.../service/settle/`）
   - 索引表找不到匹配 → **委派 Explore agent（quick）**搜全 repo，回收結論後補 `rules/modules.md`（下次省搜）
   - 該 domain 有完整 skill（欄位 ✅）→ 同時載入 `<domain>-business-knowledge` skill
   - 記錄於 plan §1 Investigation：`domain = <X>，對應目錄 = <path>，grep 範圍 = 該目錄內`
2. **Jira 票卡背景**（若需求來自 Jira 票）：透過 Jira MCP 取得票卡內容、子票、相關連結，把驗收條件 / 業務背景擷取進規格「需求背景」

   **附圖存取性硬規則：**
   - Jira MCP / Slack MCP 取得的 attachment 只有 metadata（檔名 / id / 尺寸）+ ADF tree 文字，**Claude 看不到圖片內容**
   - 票卡含附圖（attachment / mediaSingle / inline image）→ 必在 Phase B Mental Model Check **明示**：
     ```
     [附圖告知] 此票含 N 張附圖（檔名：image-X.png, image-Y.png）
     - Claude 看不到圖片內容（MCP 不提供 binary）
     - 將以文字 + 已知 wiring 推測；如圖中含紅框 / 標註等視覺資訊**對需求判斷關鍵**，請開發者：
       (a) 用文字描述紅框內容（位置 / 標的欄位 / 期望變化），或
       (b) 確認文字描述已涵蓋圖中所有資訊
     ```
   - 附圖內容如為「紅框標位置」/「Before/After 對照」/「UI mock」→ **不問清楚禁止寫 spec**
   - 純裝飾性圖（流程示意 / logo / 截圖佐證）→ 可標「圖為佐證，文字已足夠」並進 Phase B
3. `Grep` 相似業務動詞 / 欄位名 / API 路徑，找出可能重疊的現有功能（**範圍限於 Phase A 步驟 1 定位的 domain 目錄**）
4. **反射 / 映射工具 grep**（避免誤判 dead code — 本專案大量用反射 wire VO 欄位）：
   - `MapUtils.mapToObject` / `MapUtils.mapToList`
   - `BeanUtils.copyProperties` / `PropertyUtils.setProperty`
   - `ObjectMapper.convertValue` / `ObjectMapper.readValue`
   - `ModelMapper`（若有）/ MapStruct 生成類
   - Jackson `@JsonProperty` 自定義名稱
   > **特別提醒：** 只 grep explicit setter 名（如 `setCustomerServiceTg`）找不到使用點時，**一定要加 grep 上述反射工具確認**，否則很容易誤判 dead code（曾踩過 TEST-1 就是）。
4. **i18n 語系檢查**（若需求涉及前端可見文字）：
   ```bash
   ls <frontend>/src/i18n/config/
   # 對每個 locale 檢查 components/ 是否有本需求要動的 JSON：
   for lang in en tl tw vi zh; do
     test -f <frontend>/src/i18n/config/$lang/components/<target>.json \
       && echo "$lang ✅" || echo "$lang ❌ skip（index.js 是否 import 也要看）"
   done
   ```
   結果填進 spec §4 i18n 表；**實際無 JSON / 未 import 的 locale 要 skip，不要硬補**。
6. 對照 CLAUDE.md 與 `business-template` 衍生 skill 的領域規則
7. 列出可能受影響或可延伸的既有 use case
8. **若發現現成功能**：在規格「需求背景」標註 reference（避免重複造輪、或明確說明為何要另起新流程）

> 找不到相關項目也要記錄「已搜尋 XXX 無結果」，證明做過 grounding。

> ⚠️ **本 Phase 只做業務面**：套件結構、檔案位置、模式範例等**實作面 grounding** 由 planner agent 在規格確認後負責，不在此處展開（避免污染規格的業務純度）。

### 多義詞雙軌解讀（Mental Model Check 前掃描）

PO 用語含多義詞時，不同解讀的 scope 可能差到一整個 L 層。主 agent 擅自選邊容易整版 spec 走錯方向。

**多義詞清單（命中任一即啟動雙軌解讀）：**

| 多義詞 | 解讀 A | 解讀 B |
|--------|--------|--------|
| 用戶 / user | 紀錄所屬使用者（business owner） | 操作的後台帳號（admin） |
| 操作 / operator | 後台執行者 | 系統觸發（cron / event） |
| 時間 | 業務時間（結算週期、建立時間） | 系統操作時間（update / audit） |
| 狀態 / status | 紀錄 enum value | 流程狀態（pending / approved） |
| 詳情 / detail | read-only 顯示全欄位 | 可編輯欄位（CRUD） |
| 顯示 / 列出 | 純 UI 加欄位（既有資料） | 開新查詢端點（需 BE） |

**處置：**
- 命中 → Mental Model Check 必含雙軌對照表 + `⏳ 請確認意圖`
- 未命中 → 進原本 100 字摘要
- PO 已在「預期結果」明確表態 → 跳過
- **禁止**主 agent 自行選擇解讀後直接寫 spec

## Phase B：Mental Model Check（grounding 完 → 寫 spec 前的 gate）

**硬規則：** grounding 完成後，**先丟一段 ≤100 字的現況摘要給開發者確認再展開 spec 全文**。

格式：
```
我讀完後對現況的理解（請確認對不對，再展開 spec）：
- 需求核心：{一句話}
- **L 層判定：** L1 / L2 / L3 — {一句話依據，例：動到金額計算 → L1}
- 現有實作位置：{檔案:行號}
- 關鍵 pattern / wiring：{反射 / 顯式 setter / cache / ...}
- 已知陷阱：{例：@JsonInclude(NON_NULL) / type=1 is reflection filter}
- Scope 邊界（我理解的 in/out）：...
```

**L 層判定是必填欄位**，不得省略。開發者若在此確認或修正 L 層，後續 spec 全文、planner、reviewer 配置全部以此為準。

等開發者回「對」或修正後，**才動手寫完整 spec**。

**什麼情況可以跳過：**
- Bug 修復（用模板 B） — 現象 / 預期 / 重現步驟本身就是 model
- 單行改動 — 不值得

**什麼情況必須做：**
- 跨 repo 變更
- 涉及共享層（cx-sport-common / sport-framework）
- 涉及反射 / 快取 / 事件 / 排程的 wiring
- 開發者的一句話描述 + Jira 票卡含糊 / 留白很多

## 待確認事項的處理方式

Claude 不先問問題，而是：

1. **直接填完規格草稿** — 能推測的欄位依最佳判斷填入；不確定的欄位標 `⏳ 待確認` 並列出選項
2. **集中在「待確認事項」章節** — 每項給編號（如 7-1、7-2），列出：
   - 問題本身（一句話）
   - 可能選項（若有）
   - Claude 的建議選項（若有合理判斷）
3. **開發者可二擇一回覆方式**：
   - **CLI 回覆**：「7-1 選 A、7-2 答：xxx、7-3 跳過」
   - **文件修改**：直接編輯 spec 文件後回「已更新規格」
4. **全部確認後即可開工** — 開發者回覆「規格已確認」後，Claude 進入 planner 階段

## 規格文件模板

根據需求類型 + **L 層判定**選擇對應模板，產出後存放在專案根目錄 `plan/` 資料夾。

### 先選 L 層（依 `rules/development-workflow.md` §Step 3b）

| L 層 | 範圍 | 用哪個模板 | 預估 spec 長度 |
|------|------|-----------|---------------|
| **L3** | config 欄位 / DTO / i18n / pure refactor / typo / wiring | **模板 C（micro-spec）** | ≤ 80 行 |
| **L2** | 一般 service / controller / 跨模組整合（非金額 / 非狀態機） | **模板 A 精簡版**（可刪 Pre-mortem、Success Criteria） | 100-200 行 |
| **L1** | 金額 / 餘額 / 結算 / 狀態機 / 併發 / 冪等 / 第三方對接 | **模板 A 完整版** | 200+ 行 |
| — | Bug 修復 | **模板 B** | 依複雜度 |

**硬規則：** L 層不能自由選；依既有定義 + 該檔案 §Step 3b 判定。疑問升級不降級（L2 / L3 邊界 → 取 L2）。

---

### §0 修正紀錄段（spec 改版時必加）

- 第一版 spec **不需要** §0
- spec **改版時必加**，置於 §1 之前，每次改版**新增一列**不覆寫
- 改版後 `status` 重置為 `pending` 直到再次 CONFIRM
- 改版超過 v3 → 回頭檢查 grounding 是否不足

```markdown
## 0. 修正紀錄

| 版本 | 日期 | 內容 | 為何改 |
|---|---|---|---|
| v1 | YYYY-MM-DD | 原始草稿 | （第一版） |
| v2 | YYYY-MM-DD | 改 scope = Y | v1 domain 選錯 |
```

「為何改」必明寫，**禁寫**「重做」「依使用者意見調整」等空話。v 號 ≥ 3 → spec 結尾加反思段。

---

### 模板 A：功能需求 / 邏輯變更（L1 完整版 / L2 精簡版）

檔名：`plan/{日期}_{功能簡稱}_spec.md`

```markdown
# {功能名稱} 規格

**日期：** YYYY-MM-DD
**負責人：** {開發者}
**狀態：** ⏳ 待確認 / ✅ 已確認 / ❌ 需修改

---

## 1. 需求背景

**為什麼要做這個？**
{用白話描述需求來源和目的}

## 2. 業務規則

### 主要邏輯

{用白話描述核心業務邏輯，非技術人員能看懂}

### 規則清單

> **L 層對應測試強度**（見 `rules/development-workflow.md` §Step 3b）：
> - **L1**（金額 / 餘額異動 / 結算 / 狀態機 / 併發 / 冪等）→ 必寫整合測試
> - **L2**（其他 service / controller）→ 可選
> - **L3**（config / DTO / refactor / typo）→ 不寫，手動 QA

| 編號 | 規則描述 | 條件 | 結果 | L 層 | 驗收方式 |
|------|----------|------|------|------|---------|
| R1 | | | | L1 / L2 / L3 | {L1: 必寫 `@SpringBootTest` 整合測試 / L2: 可選 / L3: 手動 QA} |
| R2 | | | | | |

### 狀態變化（若涉及）

```
{狀態 A} → {條件} → {狀態 B}
```

**⚠️ 狀態機檢查（若涉及）：**
- 所有合法轉換是否列出？
- 是否有非法跳轉未禁止？
- 失敗 / 取消 / 超時情境對應哪個狀態？

## 3. 邊界條件

| 情境 | 預期行為 |
|------|----------|
| {邊界情境 1} | |
| {邊界情境 2} | |

## 4. 影響範圍

### 會修改的檔案

| 檔案 / 模組 | 修改內容 |
|-------------|----------|
| | |

**⚠️ 共用元件變更必檢：** 若修改共用介面或工具，需列出回歸風險與下游影響清單。

### 影響的下游 / 整合方

| 下游 / 整合方 | 影響說明 |
|---------------|----------|
| | |

### 是否需要資料庫變更

- [ ] 新增欄位
- [ ] 修改欄位
- [ ] 新增資料表
- [ ] Migration（如 Flyway / Liquibase）

### 是否需要設定變更

- [ ] application.yml
- [ ] 外部設定中心
- [ ] Redis 快取結構

### 國際化（i18n）欄位（若涉及前端變更）

列出本次需求新增或修改的所有 i18n key，並**對應全語系翻譯**（依專案支援語系，如 zh / en / vi 等）。

| i18n key | zh | en | {其他語系} | 使用位置 |
|----------|----|----|-----------|---------|
| `m.xxx.yyy` | | | | `components/xxx.vue:N` |

**強制規則：**
- 使用者可見文字**一律走 i18n 函式**（如 `$t(...)` / `t(...)`），禁止硬編碼
- 禁止 `$t('x') || '預設中文'` 這種 fallback 模式（掩蓋翻譯缺失）
- 新增 key 必須**同一次提交補齊所有支援語系**，不得只補主要語系
- 無前端變更時明確標註「不適用」，不得留空

**Claude 產規格時的義務：**
- 若本次需求會產出任何使用者可見文字，**必須在此表列出所有新增 key 並填入各語系翻譯**
- 不確定的翻譯標 `⏳ 待確認`，不得以機器翻譯矇混或空白跳過

## 5. 異常處理

| 異常情境 | 處理方式 |
|----------|----------|
| | |

**通用硬規則（依專案客製）：**
- 金額計算必須用 `BigDecimal`，不得用 double/float
- 共享資源操作必須有鎖（Redis 鎖 / 資料庫鎖）
- 外部 API 逾時與失敗必須有重試或補償機制
- 時間統一使用 UTC 或明確時區

## 5.1 風險與複雜度

| 項目 | 評估 |
|------|------|
| 風險等級 | HIGH / MEDIUM / LOW |
| 主要風險點 | {例：金流回滾邏輯、共用元件影響範圍} |
| 預估工時 | {例：後端 6h + 測試 3h} |
| 是否需灰度 / feature toggle | ✅ / ❌ |

## 5.2 Pre-mortem（預想失敗）

> 假設這個 spec 上線兩週後出問題，最可能的三個原因是什麼？

1. {失敗情境 1 — 例：併發下未正確鎖定造成重複扣款}
2. {失敗情境 2 — 例：邊界資料未涵蓋（金額 = 0、null 使用者）}
3. {失敗情境 3 — 例：依賴的外部 API 規格變更未同步}

**對應的預防 / 監控措施：**
- {對應 1 的測試 / 監控 / alert}
- {對應 2 的處理}
- {對應 3 的處理}

## 6. 向下相容與上線安全

- 是否影響現有 API 回傳格式？
- 是否需要資料遷移？
- 是否可灰度發布？
- 是否需要功能開關（feature toggle）？
- **若涉及共享層（cx-sport-common / sport-framework）變更 → 版本 bump 策略為？**
  - (A) 正規 bump 小版本（**預設建議**，維持版本追溯性）
  - (B) 同版號 overwrite（省下游 pom bump MR，但需 Nexus 允許 overwrite + 協調所有開發節點清 ~/.m2 快取，犧牲追溯性）
  - (C) 改走 SNAPSHOT 版本（開發期；不適合正式發版）
  - Claude 建議：{擇一 + 理由；預設 A}
- **下游受影響服務 smoke 測試清單：**（若涉共享層）
  - [ ] activity-service 本地 compile + 啟動
  - [ ] manage-center 本地 compile + 啟動
  - [ ] {其他消費方}

## 7. 待確認事項

> 每項給編號，開發者可 CLI 回覆（例「7-1 選 A」）或直接改本文件

| 編號 | 問題 | 可能選項 | Claude 建議 |
|------|------|---------|------------|
| 7-1 | {具體問題} | A: {選項}<br>B: {選項} | {建議 + 理由} |
| 7-2 | {具體問題} | — | ⏳ 待填 |
```

---

### 模板 B：Bug 修復

檔名：`plan/{日期}_{bug簡稱}_fix_spec.md`

```markdown
# {Bug 描述} 修復規格

**日期：** YYYY-MM-DD
**負責人：** {開發者}
**狀態：** ⏳ 待確認 / ✅ 已確認 / ❌ 需修改
**L 層：** L1（金融 / 狀態機 / 併發 bug）/ L2（一般 service bug）/ L3（typo / config / 顯示 bug）

> **L 層判定**：bug 動到的範圍決定 L 層（不是 bug 本身嚴重度）。例：金額計算錯誤 = L1（必整合測試）；按鈕文案錯字 = L3（手動 QA）。

---

## 1. 問題描述

**現象：** {使用者看到什麼}
**預期：** {正確行為應該是什麼}
**重現步驟：** {可重現的操作}
**影響範圍：** {哪些使用者 / 場景 / 時間段受影響}

## 2. 根因分析

{用白話描述為什麼會發生}

**涉及狀態機？** {若涉及，列出狀態轉換錯誤點}
**涉及金額計算？** {若涉及，列出是否有精度遺失或未用 BigDecimal}
**涉及併發？** {若涉及，列出是否缺鎖或去重}

## 3. 修復方案

{用白話描述怎麼修}

### 會修改的檔案

| 檔案 | 修改內容 |
|------|----------|
| | |

## 4. 影響範圍

- 是否影響其他模組？
- 是否影響其他下游？
- 是否需要重跑歷史資料？
- 是否需要資料修復腳本？

## 5. 驗證方式

| 驗證項目 | 方法 |
|----------|------|
| | |

## 6. 回滾計畫

- 若修復導致新問題，如何快速回滾？
- 是否需要保留舊邏輯作為開關？

## 7. 待確認事項

| 編號 | 問題 | Claude 建議 |
|------|------|------------|
| 7-1 | | |
```

---

### 模板 C：Micro-spec（L3 pure wiring 用）

**適用：** config 欄位 / DTO / i18n / pure refactor / typo / wiring — 目標**控制在 80 行內**。

檔名：`plan/{日期}_{功能簡稱}_spec.md`

```markdown
# {功能名稱} 規格（Micro-spec）

**Jira：** {票號}
**日期：** YYYY-MM-DD
**負責人：** {開發者}
**狀態：** ⏳ 待確認 / ✅ 已確認
**L 層：** L3（pure wiring，免自動測試）

## 1. 需求（3 句話內）
{用一段話交代要改什麼 + 為什麼}

## 2. Grounding 關鍵事實
- 現有實作位置：`{file}:{line}`
- Wiring 機制：{反射 / 顯式 setter / cache / 事件}
- 已知陷阱（例：`@JsonInclude(NON_NULL)` / `type=1 is reflection filter`）：
- i18n 涵蓋語系（實測）：{例：zh ✅ / en ✅ / vi ✅ / tl ✅ / tw ❌ skip}
- 跨 repo？{是/否；若是列出各 repo}

## 3. 要改的檔案（單一事實來源）

| 類型 | Repo | 檔案 | 改什麼 |
|------|------|------|--------|
| 修改 | | | |
| 新增 | | | |

## 4. 版本 / 發版影響（若涉共享層）

- 是否改 `cx-sport-common` / `sport-framework` 等共享層？{是/否}
- 版本 bump 策略：
  - (A) bump 小版本（feature 加欄位 → 常規選項）
  - (B) 同版號 overwrite（犧牲追溯性但省 MR；需 Nexus 允許）
  - Claude 建議：{A 或 B，附理由}
- 下游受影響服務：{列出 activity-service / manage-center / ...}

## 5. 手動 QA checklist

- [ ] {驗收 1：UI / 行為 / API response}
- [ ] {驗收 2：DB 是否寫入正確}
- [ ] {驗收 3：i18n 各語系截圖}
- [ ] {驗收 4：回歸既有功能}

## 6. 待確認事項

| 編號 | 問題 | Claude 建議 |
|------|------|------------|
| 6-1 | | |
```

**Micro-spec 判斷：能塞進這 6 章節的 = 合適用 C；塞不進的 → 升級用 A。**

---

## 使用流程

### Phase C：直接產出規格（不預先提問）

Claude Code 依 **L 層 + 需求類型**選擇模板：
- **L3** pure wiring（config / DTO / i18n / pure refactor / typo） → **模板 C（micro-spec）**
- L1 金額 / 狀態機 / 併發 / 冪等 → **模板 A 完整版**
- L2 一般 service / controller / 跨模組整合（非金額 / 非狀態機） → **模板 A 精簡版**（可刪 §5.2 Pre-mortem；註：Success Criteria 在 plan 文件不在 spec）
- Bug 修復 → **模板 B**（依複雜度標 L 層）
- 領域特化需求 → 改用對應業務 skill（由 `business-template` 複製改名）

依下列資訊**一次產出完整草稿**：
- 使用者提供的需求描述
- CLAUDE.md 與專案規則中的業務規範
- 現有程式碼分析（影響範圍）
- 相關文件（若有提供）

**規則：**
- **能推測的欄位依最佳判斷填入**
- **不確定的欄位標 `⏳ 待確認`** 並在最後一節列選項
- **不先問開發者** — 有疑慮一律寫入文件
- **同步把待確認事項列到 CLI**（強制步驟）：
  - 在 Claude 的回覆訊息中以表格列出所有 `⏳` 編號、問題、選項、建議
  - 附上回覆範例，開發者可直接在 CLI 回編號答案
  - 目的：開發者不必開檔案就能看到所有問題、快速回答

### Phase D：開發者確認

開發者收到規格後，有**兩種回覆方式**：

**方式 A：CLI 回覆**
```
7-1 選 A
7-2 答：每 5 分鐘
7-3 跳過（照 Claude 建議）
```

**方式 B：直接改文件**

開發者編輯 `plan/xxx.md`，填入答案後回覆「規格已更新」或「規格已確認」。

### Phase E：開工（Wait-for-CONFIRM gate）

> ⛔ **硬性閘門**：必須**同時**滿足以下兩個條件，Claude 才能進入 planner、寫程式碼、開分支：
>
> - **(a) 所有 `⏳ 待確認` 項目已有答案**（spec 中無未決 ⏳）
> - **(b) 開發者顯式 CONFIRM**（回「規格已確認」/「proceed」/「yes」/同義詞）
>
> ⚠️ **注意**：spec 沒有任何 ⏳ 不代表自動通過 — 仍需 (b) 顯式 CONFIRM 才動工，避免「PO 還沒看過 spec 就 planner 開搞」。

收到 CONFIRM 後：
1. 將文件狀態改為 ✅ 已確認
2. 進入 **planner** agent 拆解實作步驟
3. 後續開發若規格有變更，回頭更新文件並通知開發者

### Phase F：開發中追溯（含 plan → spec 回流）

開發過程中若發現規格遺漏或需要調整：
1. 更新規格文件，標記變更處（使用 ⚠️ 或 🔄 符號）
2. 通知開發者需要再次確認
3. 確認後繼續開發

#### plan 階段觸發回流的硬規則

**planner agent 動工後若發現 spec 業務面缺漏**（例：原 spec 沒提退款情境、狀態機漏一條合法轉換、跨平台 platformId 防護沒寫）：

1. **暫停 plan**（不要在 plan 中「偷偷補上」業務規則 — 會破壞 spec 為單一事實來源）
2. 回 Phase A 補相關 grounding，回 Phase C 補 spec
3. 重走 Phase E（Wait-for-CONFIRM gate）
4. PO / 開發者確認後才回到 plan 繼續

**planner agent 動工後若認定 L 層應升級**（例：spec 寫 L2 但 plan 階段發現會動到金額計算 → 應升 L1）：

1. **不要**在 plan 中悄悄升 L 層（會跟 spec 模板選擇對不起來）
2. 回 Phase C 改 spec 模板（L2 模板 A 精簡版 → L1 模板 A 完整版，補 §5.2 Pre-mortem 等）
3. 重走 Phase E
4. CONFIRM 後才繼續 plan

## 與其他 Skill / Agent 的關係

| 階段 | 使用的 Skill / Agent |
|------|---------------------|
| ① 規格預審（一般需求 / Bug） | **spec-review**（本 skill） |
| ② 實作計畫拆解 | **planner** agent |
| ③ 實作撰寫 | 技術棧 skill（`springboot-patterns`、`mysql-patterns` 等） |
| ④ 業務領域參考 | 業務 skill（依領域，複製自 `business-template`） |
| ⑤ 程式碼審查 | **code-reviewer** + **java-reviewer** agent |
| ⑥ 業務審查 | **business-reviewer** agent |
| ⑦ 安全審查 | **security-reviewer** agent |
