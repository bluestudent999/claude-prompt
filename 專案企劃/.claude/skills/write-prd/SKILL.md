---
name: write-prd
description: 調用 BA 依當前上下文撰寫標準 Business Spec(Markdown)。已有 Product Brief 或已確認需求、要產出詳細規格書時使用。
---

# write-prd — 撰寫標準規格書

調用 `business-analyst` agent,依 `rules/spec-standard.md` 產出結構化 Business Spec。

## 啟用時機
- 已有 PM 的 Product Brief,或需求已收斂確認。
- 需要產出可切片、覆蓋 Edge Cases 的詳細規格。

> 尚未收斂需求 → 先跑 `/plan-workflow` 或 `product-manager`。

## 流程
1. **確認輸入**:取得 Product Brief 路徑(或已確認需求)。缺 `核心範圍`/`成功指標`/`OQ` 欄 → 退回 PM(見 `handoff-contract.md` §5)。
2. **委派 BA**:傳 Brief 路徑 + 領域上下文(不貼全文)。
3. **BA 產出** `plan/<功能>/spec.md`,含編號化 §1.3 Flow / §1.4 R / §1.6 AC + §1.7 切片友善分節。
4. **切片自檢**:確認 delivery-planner 能只讀某幾節就切出完整 TASK。

## 硬規則
- **只產 Markdown**:HTML 為選配,需要時另走轉檔工具(見 `spec-standard.md` §3),**不在對話裡手刻 HTML**。
- **不寫技術架構**:無 DB Schema / 框架 / API Endpoint。
- **不臆測**:盲區標 `⏳` 於文末 Pending Logic,列選項與建議。
- **每條 Flow/R/AC 編號**:供下游切片引用。

## 完成輸出
規格路徑、AC 條數、`⏳` 待確認清單(供利害關係人回覆)。建議接著跑 `/plan-tasks` 拆任務。
