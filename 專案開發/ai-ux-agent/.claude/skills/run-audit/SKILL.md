---
name: run-audit
description: 端到端跑一次 UX 審計（開站 → 觀察 → 推理 → 評估 → 報告），對指定目標產出報告並落地資料夾。展示 demo、驗證一鍵可重跑（E1 AC-E1-4）時使用。
---

# run-audit

執行一次完整的 UX 審計管線並落地報告。

## 前置

- 目標站與 Persona 已由 Backlog / OQ 指定（E1 預設 `https://sports-2.cxsport.net/`，Persona = Visitor + 已登入使用者）。
- 登入憑證由**環境變數 / `.env`** 提供（未提供則僅跑 Visitor 範圍，見 security-audit §1）。

## 步驟

1. **確認階段與範圍**：讀 `plan/` 確認當前 E-Phase 與可用能力（E1 = 雲端 API、單 Task 串行、Markdown、Screenshot+DOM）。
2. **執行管線**：跑專案的審計入口，依序 `Browser → Observation → Reasoning → Evaluation → Report`。
   - 觀察證據落地磁碟；每個 Issue 連結真實 Observation。
   - 可預期例外（登入失敗 / Session 逾時 / 憑證缺失 / API 逾時 / 目標站不可達）**留痕不靜默**。
3. **落地報告**：輸出到可設定資料夾（預設 `./reports/YYYY-MM-DD/`），E1 為 Markdown。
4. **回報**：報告路徑、Issue 數（含各 Severity 分佈）、是否成功審計登入後頁面、是否有例外留痕。
5. **可重跑驗證**：確認同一指令可重複執行得到報告（Task 可重複，§12）。

## 完成後

若要度量此次報告的證據品質與退出閘門達成度，接著跑 `/ux-audit-eval`。
