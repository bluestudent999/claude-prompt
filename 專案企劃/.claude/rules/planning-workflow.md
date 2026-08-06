# 企劃工作流程 (Planning Workflow)

> 本文規範專案企劃(PM / BA / Delivery Planner)的生命週期:需求釐清、商業邏輯設計、規格撰寫、**任務拆解與排程**、審查與交付。
> 所有企劃人員及 AI 企劃 Agent 必須遵循此流程。

---

## 企劃生命週期(6 步)

```
Step 1 需求收斂 (PM)
   → Step 2 商業邏輯設計 (PM/BA)
   → Step 3 規格書產出 (BA)
   → Step 3.5 任務拆解與排程 (Delivery Planner)   ← 新增:防開發端上下文爆炸
   → Step 4 審查 (spec-reviewer,獨立角色)
   → Step 5 轉交開發
```

---

### Step 1:需求收集與模糊釐清 (Requirement Gathering) — PM

- 接收使用者的原始需求(零散想法、一句話、或會議紀錄)。
- **釐清目標 (Why)**:確認商業價值與使用者痛點。需求不明確時,列出 Open Questions (OQ) 向利害關係人提問(OQ 生命週期見 `rules/handoff-contract.md` §4)。
- **邊界確認 (Scope)**:界定「要做什麼」與「不包含什麼(Out of Scope)」。
- **產出**:Product Brief(格式見 `agents/product-manager.md` 與 `handoff-contract.md` §3.1)。
- **上下文**:原始需求若 > 300 行,依 `rules/context-discipline.md` §2 分段讀,勿全文灌入。

---

### Step 2:商業邏輯與流程設計 (Business Logic Design) — PM → BA

- **Mental Model Check**:在產出詳細規格前,先產出一段 ≤ 100 字的摘要與核心流程(User Flow),與團隊初步對焦,確認方向沒走偏再展開。
- 辨識主要角色 (Roles)、資料流向 (High-level Data Flow) 與關鍵業務規則。
- **例外情境挖掘**:不要只想 Happy Path,列出潛在邊界條件、異常狀態,以及如何應對。

---

### Step 3:規格書產出 (Spec & Acceptance Criteria) — BA

- 依 `rules/spec-standard.md` 撰寫規格文件(調用 `business-analyst` agent)。
- 格式採 `Markdown (.md)`,便於版本控制;需分享非技術人員時再導出 HTML(見 spec-standard §3)。
- **撰寫驗收條件 (AC)**:採 BDD Given/When/Then,或條列式可測試條件。**每條 AC 給編號**(AC-1, AC-2…),供 Step 3.5 切片對映。
- **可切片性硬要求**:規格分節分條撰寫,讓下游任務能單獨引用(見 spec-standard §1.7)。

---

### Step 3.5:任務拆解與排程 (Task Breakdown & Sequencing) — Delivery Planner ★新增

> **這一步是企劃防止「開發 AI 上下文不夠」的關鍵。** 詳細標準見 `rules/task-planning.md`。

- 調用 `delivery-planner` agent,把 Spec 拆成一顆顆有邊界的 **TASK**,產出 Task Backlog。
- 每顆 TASK 必含:`Required Spec Sections`(只需讀哪幾節)、`Scope 邊界`、`Depends On`、`Context Budget`、`對應 AC`。
- 建 DAG 依賴圖,標出可平行分支與建議實作順序。
- **硬規則**:估為 `L`(大)的 TASK 必須再拆;每條 Spec AC 至少被一顆 TASK 覆蓋。
- **邊界**:只切**業務層**任務,不碰技術實作步驟(那是開發 planner 的 How)。

---

### Step 4:審查 (Review) — spec-reviewer(獨立角色)

> 對應根 `CLAUDE.md` Principle 4(職責分離):審查必須是獨立角色,產出者不自審放行。

- 調用 `spec-reviewer` agent,審查 Brief / Spec / Backlog 的完整性、無歧義性、切片與依賴健全性,產出 Harness Output Contract(Status / Counts / Next actions)。
- 將規格交利害關係人(PO、業務端)確認商業邏輯;交技術主管做可行性評估(Technical Feasibility Review)。
- **Baseline 閘門**(硬規則):必須同時滿足
  - (a) 無 `⏳ 待決` OQ(見 `handoff-contract.md` §4),且
  - (b) spec-reviewer Status = `approve`,且
  - (c) 利害關係人顯式確認。
- 三者齊備才打上 Baseline 標記;任一未達 → 回對應 Step 收斂。

---

### Step 5:轉交開發 (Handoff to Development)

- 將 Baseline 後的 **Spec + Task Backlog** 一併交付開發團隊。
- 開發 planner 依 Backlog **逐一取單顆 TASK**,對照其 `Required Spec Sections` 只載入相關規格切片,再產出技術設計書(`plan/task-xxx-plan.md`,How 層由開發負責)。
- 企劃產出的 Business Spec 描述**業務邏輯與介面互動**,不涉及資料庫表結構或模組依賴設計;但**任務切分、依賴、範圍邊界由企劃負責**(這是 Step 3.5 補齊的交接層)。
- 開發期間,PM 持續跟進,協助解答業務邏輯疑問;技術性 OQ(`➡️ defer-to-dev`)交開發 planner 的 OQ 系統決議。

---

## 相關規則

| 主題 | 位置 |
|------|------|
| 規格結構與切片約定 | `rules/spec-standard.md` |
| 任務拆解 / backlog / DAG / Context Budget | `rules/task-planning.md` |
| 交接資料契約 / OQ 生命週期 | `rules/handoff-contract.md` |
| 上下文與 token 紀律 | `rules/context-discipline.md` |
