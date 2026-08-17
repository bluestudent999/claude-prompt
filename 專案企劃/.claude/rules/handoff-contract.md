# 交接資料契約 (Handoff Contract)

> 本文規範企劃鏈上各 Agent 之間的**上下文交接（Context Transfer）**與資料契約。
> 對應根 `CLAUDE.md` Principle 6（資料契約與狀態管理）:多 Agent 協作**必須**明確定義交接介面,確保資訊不遺失、不幻覺。
> **硬規則**:下游 Agent 只接收「上游的結構化產出 + 明確指定的補充上下文」,不得要求上游把整段對話或整份原始資料塞進 prompt。

---

## 1. 企劃鏈總覽

```
使用者原始需求
   │
   ▼
[product-manager] ── 產出 Product Brief ──►
   │
   ▼
[business-analyst] ── 產出 Business Spec (依 spec-standard) ──►
   │
   ▼
[delivery-planner] ── 產出 Task Backlog (依 task-planning) ──►
   │
   ▼
[spec-reviewer] ── 審查 Brief / Spec / Backlog,回 Harness Output Contract ──►
   │
   ▼ (Baseline)
開發專案 planner ── 逐一取單顆 TASK → task-xxx-plan.md (技術 How)
```

每一個 `──►` 都是一次**交接**,交接的酬載(payload)必須符合下列契約。

---

## 2. 契約總表

| 交接 | 上游產出 (Output Contract) | 下游輸入 (Input Contract) | 綁定欄位(必須對齊) |
|------|------------------------|------------------------|------------------|
| PM → BA | **Product Brief**(見 §3.1) | BA 只讀 Brief + 領域上下文 | `核心範圍 In/Out`、`成功指標`、`Open Questions` |
| BA → Delivery | **Business Spec**(見 spec-standard) | Delivery 只讀 Spec 各節 | `§1.3 User Flow`、`§1.6 AC`、`§1.5 Edge Cases` |
| Delivery → Dev | **Task Backlog**(見 task-planning) | 開發 planner 逐一取單顆 TASK | `Required Spec Sections`、`Depends On`、`Context Budget`、`AI 產出`、`人介入` |
| 任一階段 → Reviewer | 對應產出 + `Review 聚焦面向` | Reviewer 只讀指定文件 + 聚焦點 | Reviewer 回 `Status/Counts/...` |

> **反模式(禁止)**:把上一階段的完整對話貼進下一個 Agent 的 prompt。交接一律走「文件路徑 + 章節編號 + 結構化欄位」。

---

## 3. 各產出的資料結構(Schema)

### 3.1 Product Brief(PM 輸出 = BA 輸入)

必含欄位(缺任一欄 BA 應退回,見 §5):

```markdown
# [功能名稱] 高階摘要 (Product Brief)

## 1. 一句話電梯簡報
## 2. 解決的問題與商業價值
## 3. 目標受眾 (Target Audience)
## 4. 核心範圍 (Scope)
- In Scope: ...
- Out of Scope: ...
## 5. 成功指標 (Success Metrics)   # 必須可量化
## 6. Open Questions (OQ)          # 見 §4 OQ 生命週期
```

### 3.2 Business Spec(BA 輸出 = Delivery 輸入)

結構完全依 `rules/spec-standard.md`。對 Delivery 而言,**可切片性**是硬要求:每一條 AC、每一段 User Flow 都要能被單獨引用(見 spec-standard §1.7 切片約定)。

### 3.3 Task Backlog(Delivery 輸出 = 開發輸入)

結構完全依 `rules/task-planning.md`。對開發 planner 而言,每顆 TASK 是一個**自包含工作單元**:光看該 TASK 列 + 它指向的 `Required Spec Sections`,就足以開工,不需通讀整份 Spec。

**估算欄位的交接語意(§3.5)**:`AI 產出` 與 `人介入` 是**企劃層的粗量級**,不是交期承諾。
開發 planner 把技術步驟拆完、**由下而上加總**後,以開發端的數字為準;若差距顯著,回報企劃校正估算係數(task-planning §3.5.6)。

---

## 4. Open Questions (OQ) 生命週期(跨階段狀態)

OQ 是企劃鏈上唯一會**跨階段流動的狀態**,必須有明確生命週期,不可只存在對話裡。

### 4.1 OQ 狀態機

```
⏳ 待決  ──(利害關係人回覆)──►  ✅ 已決議
   │
   └──(判定為技術問題)──►  ➡️ 轉開發(標記 defer-to-dev)
```

| 狀態 | 標記 | 意義 |
|------|------|------|
| 待決 | `⏳ OQ-n` | 尚未有答案,**阻塞**下游 baseline |
| 已決議 | `✅ OQ-n` | 已有明確答案,答案回寫文件(保留原問題,不刪) |
| 轉開發 | `➡️ OQ-n (defer-to-dev)` | 純技術實作問題,企劃不決,交開發 planner |

### 4.2 OQ 分流硬規則

| OQ 類型 | 誰負責 | 處置 |
|---------|--------|------|
| 商業價值 / 範圍 / 優先級 | PM | 在 Brief 階段收斂,`⏳` → `✅` |
| 業務規則 / 狀態合法性 / 例外行為 | BA(必要時退回 PM) | 在 Spec 階段收斂,**禁止臆測填空** |
| 任務切分 / 依賴 / 排序 | Delivery | 在 Backlog 階段收斂 |
| 技術選型 / DB / API / 框架 | **不在企劃決** | 標 `➡️ defer-to-dev`,交開發 planner 的 OQ 系統 |

> **切換提示**:當 OQ 被判定為「純技術 How / 需進入實作」而標 `➡️ defer-to-dev` 時,除了轉交,還應提示使用者:若要進入實作,請切換到對應開發範本(見 `CLAUDE.md` 的「跨 prompt-setup 職責路由」表,`prompt-setup 專案開發 <java|ai-ux-agent>`)。

### 4.3 回寫硬規則(對齊開發專案慣例)

- OQ 決議後**保留原始問題文字**,另起一行標 `✅ <決議>`,不刪原文(供追溯與 reviewer 檢視決策過程)。
- 只存在對話中的決議**不算數** — 必須回寫到對應文件(Brief / Spec / Backlog)。
- **Baseline 閘門**:任一文件若仍有 `⏳ 待決` OQ,**禁止**打 Baseline、禁止轉交下游。

### 4.4 單一 OQ 書寫格式(人類可決策 — 硬規則)

> **問題根源**:OQ 常被寫成一句技術黑話或抽象名詞,利害關係人看不懂「這在問什麼、為什麼要我決、選了會怎樣」,於是卡住不決。
> **硬規則**:每一則 `⏳` OQ **必須讓非技術的利害關係人「只讀這一則就能做決定」**。缺任一必填欄 → reviewer 判缺陷(見 spec-reviewer)。

每則 OQ 必含下列欄位,用**白話**寫(專有名詞須附一句人話解釋):

```markdown
- ⏳ OQ-n:<一句話問題,白話、非技術黑話>
  - **背景(遇到什麼問題)**:什麼情境觸發這個問題?為什麼它會冒出來?(讓人知道問題從哪來)
  - **為何要決(不決會怎樣)**:這題決定了什麼?不決會卡住哪個範圍/流程/指標?(說清「決定它解決什麼問題」)
  - **選項**(每個選項一句話 + 影響/代價,讓人能比較;在傾向的那個選項後標 `(建議:一句理由)`,供參考,**不替利害關係人做決定**):
    - A) <做法> → 影響:<成本/風險/對使用者或指標的效果>
    - B) <做法> → 影響:<…> (建議:<一句理由>)
```

> 誰負責決這則 OQ,依 §4.2 分流表判定(商業/範圍 → PM、業務規則 → BA、技術 → defer-to-dev),不必在每則 OQ 內重複標註。

**判準**:寫完自問「一個不懂技術的利害關係人,讀這一則能不能直接回 A 或 B?」不能 → 重寫。

**反例 vs 正例:**

| ❌ 看不懂、無法決 | ✅ 白話、可決策 |
|------------------|----------------|
| `⏳ OQ-3:登入要不要支援 OAuth?` | `⏳ OQ-3:要不要讓使用者「用 Google/Facebook 帳號一鍵登入」?`<br>**背景**:多數新使用者卡在註冊填表就離開。<br>**為何要決**:決定本期要不要納入「第三方登入」範圍,影響上線時程與註冊轉化率指標。<br>**選項**:A) 支援 → 註冊更快、轉化可能↑,但需接外部服務、上線多約 1 週 (建議:痛點明確);B) 不支援 → 準時上線,轉化改善有限。 |

> 這條格式對 **PM 的 Brief、BA 的 Spec、delivery-planner 的 Backlog** 內所有 `⏳` OQ 一體適用。`➡️ defer-to-dev` 的技術 OQ 因交由開發端決,可只寫「問題 + 為何屬技術問題」,不必寫給利害關係人看的選項。

---

## 5. Failure Handling(交接失敗處置)

| 情況 | 下游處置 |
|------|---------|
| 上游產出缺必要欄位(如 Brief 無 Success Metrics) | **退回上游補齊**,不得自行臆造 |
| 上游產出含 `⏳ 待決` OQ | **暫停**,不進入本階段,先催決議 |
| 上游產出與更早文件矛盾(如 Spec 與 Brief scope 不符) | **停止並回報**,回上游對齊,禁止自行選邊 |
| 需要的補充上下文未提供 | 明確列出「還需要什麼」,不硬猜 |

> **核心原則**:寧可退回,不可幻覺。任何靠「聽起來合理」填補的交接,都會在下游放大成錯誤成本。

---

## 6. 相關

| 主題 | 位置 |
|------|------|
| 規格結構與切片約定 | `rules/spec-standard.md` |
| 任務拆解 / backlog / DAG | `rules/task-planning.md` |
| 上下文與 token 紀律 | `rules/context-discipline.md` |
| 企劃生命週期步驟 | `rules/planning-workflow.md` |
