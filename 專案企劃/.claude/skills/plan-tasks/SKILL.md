---
name: plan-tasks
description: 把已定案的 Business Spec 拆成 Task Backlog(Required Spec Sections / DAG / Context Budget),調用 delivery-planner。防止開發 AI 因任務過大而上下文爆炸時使用。
---

# plan-tasks — 任務拆解與排程

調用 `delivery-planner` agent,依 `rules/task-planning.md` 把 Spec 拆成一顆顆有邊界的業務 TASK,產出 Task Backlog。

## 啟用時機
- 已有 BA 的 Business Spec(編號化 Flow/R/AC)。
- 準備交付開發前,要先切好工單。

> **這是防止開發 AI 上下文不夠的關鍵步驟** — 開發端拿到切好的 TASK,而非一坨大 Spec。

## 流程
1. **接 Spec**:取得 spec.md 路徑;確認 Flow/R/AC 已編號、可切片(否則退回 BA 依 spec-standard §1.7 重整)。
2. **委派 delivery-planner**:傳 Spec 路徑 + 章節編號。
3. **產出** `plan/<功能>/backlog.md`:任務表 + Mermaid DAG + Sequencing。
4. **雙向覆蓋檢查**:每條 AC 被覆蓋(無漏)、每顆 TASK 對映 AC(無孤兒)。

## 每顆 TASK 必含
`Task ID` / 一句話目標 / **`Required Spec Sections`**(只讀哪幾節) / `Scope 邊界`(業務語言) / `Depends On` / **`Context Budget`**(S/M/L) / 對應 AC。

## 硬規則
- **L 必拆**:估為 L 的 TASK 不得直接交付;拆不動標 `⚠️ 大顆粒` + 理由。
- **只切業務層**:不寫 class/method/package/DB(那是開發 planner 的 How,越界訊號見 `task-planning.md` §5)。
- **DAG 無環**:成環 = 切分錯,重切。
- **Spec 有業務漏洞 → 退回 BA**,不在 Backlog 偷補。

## 完成輸出
Backlog 路徑、TASK 顆數與尺寸分布、可平行分支、`➡️ defer-to-dev` 技術 OQ 清單。建議接著跑 `/review-req` 審查後打 Baseline。
