---
name: ux-audit-eval
description: 度量已產出 UX 報告的證據完整性與 Issue 品質（evidence-coverage / 四欄位齊全 / 有證據 Issue 數 / 例外留痕 / 登入審計）。調整推理或評估邏輯後、提交涉審計輸出的變更前使用。
---

# ux-audit-eval

評估 UX 審計報告的品質，作為調整前後的依據與退出閘門檢核。

## 步驟

1. 委派 `ux-evidence-auditor` subagent 對 `reports/` 下最新（或指定）報告做度量。
2. 彙整輸出：
   - **evidence-coverage**（有證據 Issue 佔比，須 = 100%）
   - **four-field-completeness**（四欄位齊全佔比，須 = 100%）
   - **evidenced-issue-count**（E1 須 ≥ 3）
   - **failure-trace**（每類例外是否留痕）
   - **login-audit**（是否成功審計登入後頁面，E1 AC-E1-3）
   - **regressions**（退步案例）
3. 逐項對照當前階段退出閘門（E1 見 Backlog AC-E1-1~4）標 ✅ / ❌。

## 判定

- 出現任一「無證據 Issue」或四欄位缺漏 → **不通過**（違反產品最高紅線，須修正才可提交）。
- 若需「反覆迭代直到達標」，改用 workflow `quality-loop`（依當前 E-Phase 判定閘門）。

提醒：**沒有度量不要改推理/評估邏輯** —— 本 skill 是變更前後的客觀依據。
