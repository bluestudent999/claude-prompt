---
name: strategic-compact
description: 在企劃生命週期的階段切換點建議手動上下文壓縮,防範對話 Token 過長導致推導精度下降或幻覺。
---

# Strategic Compact Skill(企劃版)

> **指令呼叫:** `/strategic-compact`
> **自動觸發:** `settings.json` 的 `PreToolUse`(Edit / Write)會呼叫 `suggest-compact.sh` 定時提醒。
> **目的:** 提醒在合適時機壓縮 Context,維護推理精度。詳細紀律見 `rules/context-discipline.md`。

## 觸發時機

符合任一即建議壓縮:
- **完成一個生命週期階段**,準備進下一階段(如 Brief 定案 → 進 Spec;Spec → 進 Backlog)。這是企劃最自然的壓縮點。
- 當前 session 工具調用次數達 50 次或其倍數(由 hook 自動提醒)。
- 已整讀輸入文件 ≥ 3 份(含 > 300 行者)。
- 經歷 ≥ 2 輪 spec-reviewer 審查與修訂反覆。

## 操作方式

手動於 chat 執行:
```
/compact
```

壓縮時的**保留 / 清除**(見 `context-discipline.md` §3):

| 保留 | 清除 |
|------|------|
| 當前階段產出結論(Brief / Spec / Backlog 路徑與摘要) | 已讀原始需求逐字稿細節 |
| 已決議 OQ 與 Scope 邊界 | 中途 grep 原始結果 |
| 尚未決議的 `⏳` OQ 清單 | reviewer 長篇輸出(只留 Status/Counts/修正項) |
