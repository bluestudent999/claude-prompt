# Checks — 原子檢查項

> 每個 check 檔 = 一條可執行的檢查：**grep 指令 + 判定規則 + severity + confidence 上限 + 反例 + fix 方向**。
>
> **與 `rules/reviewer-checklists.md` 的分工**：checklist 是「該 reviewer 要看哪些面向」的清單（給派遣用）；check 檔是「怎麼查、查到算幾級」的執行細節（給 reviewer 執行用）。
>
> **severity / confidence 標準**：一律依 [`../rules/severity-rubric.md`](../rules/severity-rubric.md)。
>
> **reviewer 使用方式**：briefing 指到本目錄的特定 check，reviewer 自行 Read 後照做。不要把 check 全文貼進 briefing。

| Check | 適用 reviewer | 主要 severity |
|---|---|---|
| [bigdecimal-rounding](bigdecimal-rounding.md) | business | CRITICAL |
| [idempotency-orderno](idempotency-orderno.md) | business | CRITICAL / HIGH |
| [state-machine-transition](state-machine-transition.md) | business | CRITICAL / HIGH |
| [transactional-remote-call](transactional-remote-call.md) | java / business | HIGH |
| [silent-failure](silent-failure.md) | code / java | HIGH / MEDIUM |
| [platform-isolation](platform-isolation.md) | security / business / database | CRITICAL / HIGH |
| [filter-bypass](filter-bypass.md) | security / code | CRITICAL / HIGH |

> 後兩條是 lion 特有：包網商隔離（單平台測不出）與 filter 放行分支（已發生過實際入侵）。

## 新增 check 的最低要求

依 `severity-rubric.md` §4：標預期 severity、附「為什麼會出事」、設 confidence 上限、context-dependent 的要列表。
