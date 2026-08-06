# 任務拆解與排程標準 (Task Breakdown & Sequencing)

> 本文規範企劃階段如何把一份 Business Spec 拆成**一顆顆有邊界、有依賴、大小可控的 TASK**,並產出 Task Backlog。
> **這一層是企劃防止「開發 AI 上下文爆掉」的關鍵**:開發端拿到的是切好的工單,而不是一坨大 Spec。
> 由 `delivery-planner` agent 執行;產出經 `spec-reviewer` 審查後打 Baseline。

---

## 0. 為什麼需要這一層

開發 AI 的上下文會爆,幾乎都源於**輸入單位太大**(不是對話太長,那是 `context-discipline.md` 的事):

- 單顆任務觸及太多檔案 / 模組 → 一次要載入的程式碼超過視窗
- 任務沒有對映「只需讀哪段規格」→ AI 被迫通讀整份 Spec
- 任務沒有排序 → AI 不知道先做哪顆,一次抓一堆進上下文

**企劃層的職責**:切出**業務層級**的 TASK(feature / story 顆粒),不碰技術實作步驟(那是開發 planner 的 How)。切得好,開發 AI 每顆任務都能在單一乾淨的上下文裡完成。

---

## 1. 一顆好 TASK 的三大準則

### 1.1 垂直切片 + 單一職責 (Vertical Slice, Single Responsibility)
- 一顆 TASK 只交付**一個可獨立驗收的業務結果**。
- **禁止**把「資料結構 + API + 畫面 + 通知」全塞進一顆 TASK。
- 對照開發專案紅線:「一個 TASK 只做一件事」— 但**在企劃階段就先切好**。

### 1.2 對映最小規格切片 (Minimal Spec Slice)
- 每顆 TASK 必須標明 `Required Spec Sections`:完成它只需讀 Spec 的哪幾節 / 哪幾條 AC。
- 這是**上下文預算的核心欄位** — 讓開發 AI 精準載入,而非通讀。

### 1.3 尺寸受控 (Context Budget)
- 每顆 TASK 標一個尺寸級別(見 §3)。
- **硬規則**:預估為 `L`(大)的 TASK **必須再拆**,不得直接交付開發。

---

## 2. Task Backlog 格式(delivery-planner 產出)

存放於企劃專案的 `plan/<功能>/backlog.md`(或 Spec 文件末段)。結構如下:

```markdown
# Task Backlog: <功能名稱>

**對應 Spec:** plan/<功能>/spec.md
**Baseline:** ⏳ 未定案 / ✅ vN (YYYY-MM-DD)
**Delivery Planner:** delivery-planner agent

## 依賴關係圖 (DAG)

​```mermaid
graph TD
    T1[TASK-1 建立帳號資料模型] --> T2[TASK-2 註冊流程]
    T1 --> T3[TASK-3 登入流程]
    T2 --> T4[TASK-4 註冊成功通知]
​```

## 任務清單

| Task ID | 一句話目標 | Required Spec Sections | Scope 邊界(業務語言) | Depends On | Context Budget | 對應 AC |
|---------|-----------|----------------------|--------------------|-----------|---------------|--------|
| TASK-1 | 定義帳號核心資料與狀態 | §1.4 R1–R3、§1.5 | 僅帳號本體;不含通知/金流 | — | S | AC-1, AC-2 |
| TASK-2 | 使用者可完成註冊 | §1.3 Flow-A、§1.6 AC-3~5 | 註冊表單 + 驗證;不含第三方登入 | TASK-1 | M | AC-3, AC-4, AC-5 |
| TASK-3 | 使用者可登入 | §1.3 Flow-B、§1.6 AC-6~7 | 帳密登入;不含 SSO | TASK-1 | M | AC-6, AC-7 |
| TASK-4 | 註冊成功寄出歡迎通知 | §1.3 Flow-A step5、§1.5 通知失敗 | 僅通知;通道細節交開發 | TASK-2 | S | AC-8 |

## 建議實作順序 (Sequencing)
1. TASK-1(無依賴,最先)
2. TASK-2 ‖ TASK-3(皆僅依賴 TASK-1,可平行)
3. TASK-4(依賴 TASK-2)

## Open Questions
- ✅ OQ-1: 是否支援第三方登入? → 本期 Out of Scope(PM 決議 2026-07-01)
- ➡️ OQ-2 (defer-to-dev): 通知走 Email 或站內信? → 技術問題,交開發 planner
```

### 欄位定義

| 欄位 | 說明 | 為什麼重要 |
|------|------|-----------|
| **Required Spec Sections** | 完成此 TASK 需讀的規格節 / AC 編號 | **開發 AI 只載入這幾節**,不通讀整份 Spec ← 防上下文爆炸的核心 |
| **Scope 邊界** | 用業務語言寫「包含 / 不含什麼」 | 防 Scope Creep;讓開發 AI 知道邊界在哪 |
| **Depends On** | 前置 TASK ID(可多個) | 構成 DAG;前置未完成禁止開始 |
| **Context Budget** | S / M / L 尺寸(見 §3) | L 必拆;讓 AI 每顆任務都塞得進視窗 |
| **對應 AC** | 此 TASK 交付後要驗收的 AC 編號 | 可驗收、可追溯到 Spec |

---

## 3. Context Budget 分級(尺寸標準)

> 企劃無法精算 token,改用**可觀察的業務代理指標**估算顆粒。

| 級別 | 業務訊號(估算用) | 處置 |
|------|-----------------|------|
| **S(小)** | 單一實體 / 單一畫面 / 單一規則;對映 ≤ 2 條 AC | 直接交付 |
| **M(中)** | 一條完整 User Flow;對映 3–5 條 AC;跨 1–2 個業務概念 | 直接交付 |
| **L(大)** | 跨多條 Flow / 多個業務概念;對映 > 5 條 AC;Scope 邊界一句話講不清 | **必須再拆**,禁止交付開發 |

**硬規則:**
- 任一 TASK 估為 `L` → delivery-planner 必須拆成多顆 S/M,不得直接進 Backlog。
- 拆不動的 L(業務上不可分割)→ 標 `⚠️ 大顆粒` 並在 Backlog 註明理由,提醒開發端優先 `/strategic-compact`。

---

## 4. DAG 與排序規則

1. **依賴必須無環**:TASK 依賴關係構成有向無環圖(DAG),出現環 → 表示切分錯誤,重切。
2. **前置未完成禁止開始**:對映開發專案的 Dependency Rule。
3. **標出可平行分支**:同層(依賴相同、彼此無依賴)的 TASK 標為可平行,讓開發端能獨立起 session、各自在乾淨上下文推進。
4. **關鍵路徑優先**:被最多後續 TASK 依賴的節點(如共用資料模型)排最前。

---

## 5. delivery-planner 的邊界(不越界到 How)

| ✅ 企劃層要做 | ❌ 留給開發 planner |
|-------------|-------------------|
| 切出業務層 TASK(feature/story) | 拆技術實作步驟(改哪個 class/method) |
| 標 Required Spec Sections | 指定受影響的程式檔案清單 |
| 標業務語言的 Scope 邊界 | 指定 Allowed Modules / package |
| 標 TASK 間業務依賴 | 標 commit 粒度 / 分支策略 |
| 標 Context Budget(業務尺寸) | 估 token / 測試級別 L1-L3 |

> 越界訊號:如果 delivery-planner 開始寫「新增 `XxxService.foo()`」「改 `application.yml`」,就是踩進 How,**停手**,那是開發 planner 的職責。

---

## 6. Quality Gate(delivery-planner 自檢)

Backlog 交 spec-reviewer 前,自檢:

- [ ] 每顆 TASK 都有 `Required Spec Sections`(無空白)
- [ ] 每顆 TASK 都有 `Context Budget`,且無 `L` 未拆
- [ ] 依賴關係無環,已畫 DAG
- [ ] 每顆 TASK 對映至少一條 Spec AC(無孤兒 TASK、無漏接 AC)
- [ ] 每條 Spec AC 至少被一顆 TASK 覆蓋(反向檢查,無漏)
- [ ] Scope 邊界用業務語言,未寫技術實作
- [ ] 無 `⏳ 待決` OQ(否則不得打 Baseline)

---

## 7. 相關

| 主題 | 位置 |
|------|------|
| 規格結構與切片約定(§1.7) | `rules/spec-standard.md` |
| 交接契約 / OQ 生命週期 | `rules/handoff-contract.md` |
| 上下文與 token 紀律 | `rules/context-discipline.md` |
| delivery-planner 角色定義 | `agents/delivery-planner.md` |
