---
name: plan-workflow
description: 啟動完整企劃生命週期(需求收斂 → Brief → Spec → 任務拆解 → 審查 → 交付)。收到一段新需求、要從零跑完整企劃流程時使用。
---

# plan-workflow — 完整企劃生命週期

依 `rules/planning-workflow.md` 的 6 步,把一段模糊需求一路帶到「可交付開發的 Spec + Task Backlog」。

## 啟用時機
- 收到一段全新的、尚未收斂的需求。
- 需要跑完整流程(而非只補其中一段)。

> 若只要寫規格 → 用 `/write-prd`;只要審查 → `/review-req`;只要拆任務 → `/plan-tasks`。

## 流程(逐階段委派 sub-agent)

| 步驟 | 動作 | 委派 | 產出 |
|------|------|------|------|
| Step 1 | 需求收斂、定範圍、列 OQ | `product-manager` | Product Brief |
| Step 2 | Mental Model Check(≤100 字對焦) | 主 agent | 現況摘要 |
| Step 3 | 寫規格(Flow/R/AC 編號) | `business-analyst` | Business Spec |
| Step 3.5 | 拆 TASK、標切片、建 DAG | `delivery-planner` | Task Backlog |
| Step 4 | 獨立審查 | `spec-reviewer` | Harness Output Contract |
| Step 5 | 打 Baseline、交付 | 主 agent | Baseline 標記 |

## 硬規則
- **階段閘門**:上一階段有 `⏳ 待決` OQ → 不進下一階段(見 `handoff-contract.md` §4)。
- **交接走路徑**:給下游 sub-agent 文件路徑 + 章節編號,不貼全文(見 `handoff-contract.md`)。
- **階段切換即壓縮**:每過一個 Step,依 `context-discipline.md` §3 評估 `/compact`。
- **Baseline 三條件**:無 `⏳` OQ + spec-reviewer `approve` + 利害關係人確認,缺一不可。

## 產出存放
```
plan/<功能>/
├── brief.md      # PM
├── spec.md       # BA
└── backlog.md    # delivery-planner
```

## 完成輸出
最後回報:各文件路徑、Baseline 狀態、剩餘 `⏳`/`➡️ defer-to-dev` OQ 清單。
