---
name: eval-m1
description: 跑 M1 對齊 golden set 評估並出指標報告（accuracy / false-auto / auto-rate）。調整對齊模型後或定期品質盯場時使用。
---

# eval-m1

評估 M1 實體對齊品質。

## 步驟

1. 委派 `alignment-evaluator` subagent 執行 golden set 評估。
2. 彙整輸出：
   - **accuracy**、**false-auto rate**、**auto-rate**
   - 是否達北極星：accuracy ≥ 0.98、false-auto ≤ 0.001
   - 退步（regression）案例與可能原因
3. 若需「反覆迭代直到達標」，改用 workflow `m1-quality-loop`。

提醒：**沒有度量不要調模型**——本 skill 是調整前後的依據。
