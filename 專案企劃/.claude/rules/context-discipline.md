# 上下文與 Token 紀律 (Context Discipline)

> 本文規範企劃階段的上下文管理。企劃階段要吞的東西一點都不小(會議紀錄、舊規格、競品資料、大型 Jira 票),若源頭不控上下文,汙染會一路傳到開發。
> 對應根 `CLAUDE.md` Principle 2(Token 效率)。與兄弟工作區(開發 / 維護 / 版本管理)的 context 紀律看齊。

---

## 1. 最小化讀取(硬規則)

- **只讀當前階段需要的東西**。PM 讀原始需求;BA 讀 Brief;delivery-planner 讀 Spec;reviewer 讀被指定的文件 — 各守其分,不越級通讀。
- 需要探索大量既有資料(舊規格庫、多份會議紀錄)時,**委派 Explore agent**(獨立 context,只回結論),不要主 agent 親自全讀把結果灌進自己的 context。
- **禁止**為了「求穩」把整個 `plan/` 目錄或整份長文檔一次讀進來。

---

## 2. 長輸入讀取策略(硬規則)

當單一輸入檔(會議逐字稿、舊規格、匯出的需求文件)> 300 行:

- **禁止一次性 Full Read**(不帶 `offset` / `limit` 的 Read)。
- 流程:
  1. 先 `grep -n` 定位關鍵段落(決策、需求、限制條件的關鍵字)行號。
  2. 在對話中保留簡短「行號索引」摘要。
  3. 用 `Read(offset, limit)` 只讀需要的段落。
- **例外**:結構性小檔(< 300 行的 spec、模板)、需逐條對照的 AC 清單。

---

## 3. Strategic Compact(階段切換時壓縮)

企劃是多階段流程(需求 → Brief → Spec → Backlog → Review),每次階段切換是天然的壓縮點。

### 觸發時機(符合任一即建議 `/compact` 或呼叫 `strategic-compact` skill)

- 完成一個生命週期階段,準備進下一階段(如 Brief 定案 → 進 Spec)。
- 當前 session 工具調用次數達 50 次或其倍數(由 `strategic-compact` hook 自動提醒)。
- 已整讀輸入文件 ≥ 3 份(含 > 300 行者)。
- 經歷 ≥ 2 輪 spec-reviewer 審查與修訂反覆。

### 壓縮時的保留 / 清除

| 保留 | 清除 |
|------|------|
| 當前階段的產出結論(Brief / Spec / Backlog 路徑與摘要) | 已讀過的原始需求逐字稿細節 |
| 已決議的 OQ 與 Scope 邊界 | 中途 grep 的原始結果 |
| 尚未決議的 `⏳` OQ 清單 | reviewer 的長篇審查輸出(只留 Status/Counts/修正項) |

---

## 4. 產出本身也要控上下文(下游友善)

企劃產出**是開發 AI 的輸入**,所以企劃有義務讓產出「好載入」:

- **規格可切片**:Spec 依 `spec-standard.md` §1.7 分節分條,讓每顆 TASK 只需引用其中幾節。
- **Backlog 標 Required Spec Sections**:見 `task-planning.md`,直接告訴開發 AI「只讀這幾節」。
- **避免文字牆**:用表格、條列、Mermaid 取代長段敘述 — 同樣資訊,更少 token,更好定位。
- **交接走路徑不走貼文**:下游 Agent 給「文件路徑 + 章節編號」,不把全文貼進 prompt(見 `handoff-contract.md`)。

---

## 5. 委派 Explore agent 的時機

| 情境 | 主 agent 自做 | 委派 Explore |
|------|-------------|-------------|
| 讀單一指定文件的某段 | ✅ | — |
| 掃多份舊規格找「是否已規劃過類似功能」 | — | ✅ |
| 從一大包會議紀錄抽取需求要點 | — | ✅ |
| 跨多份文件比對術語 / 範圍是否一致 | — | ✅ |

Explore briefing 要求:指定 thoroughness(quick/medium/thorough)、**只回結論不回原始行**、字數上限(quick ≤ 300 / medium ≤ 800 / thorough ≤ 1500 字)。

---

## 6. 相關

| 主題 | 位置 |
|------|------|
| strategic-compact 實作 | `.claude/skills/strategic-compact/` |
| 任務切片(防開發端上下文爆炸) | `rules/task-planning.md` |
| 交接契約(走路徑不走貼文) | `rules/handoff-contract.md` |
