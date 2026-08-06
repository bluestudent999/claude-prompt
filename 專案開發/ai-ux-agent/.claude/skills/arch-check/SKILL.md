---
name: arch-check
description: 跑架構守門檢查（管線/分層邊界 + 非 RPA + 證據紀律 + E-Phase 範圍），回報違規。驗證接縫、提交前檢查架構合規時使用。
---

# arch-check

執行 AI UX Platform 的架構守門檢查並回報結果。

## 步驟

1. 若專案有架構測試，於根目錄執行：`pytest -q -m architecture`。
2. 靜態掃描核心紅線（可用 grep / import-linter）：
   - **Core / Domain 純淨**：`core` / `domain` 內是否 `import playwright` / LLM SDK / `requests` / `httpx` / `os`·檔案 I/O。
   - **依賴反轉**：推理 / 瀏覽器 / 報告落地是否都走 Port，未在 Core 直接 new Adapter 或呼叫 SDK。
   - **證據紀律**：產生 Issue 的路徑是否都連結真實 Observation（無「無證據 Issue」）。
   - **E-Phase 範圍**：是否越界實作後續階段能力（E1 不做 A11y/Network/Perf、HTML、排程、多 Agent）。
3. 解讀結果：
   - **綠燈 / 全通過** → 回報 `PASS`。
   - **紅燈 / 有違規** → 逐條說明：違反哪條邊界、涉及哪些檔案、**如何修**。
4. 需要更深入的 diff 邊界審查時，委派 `arch-guard` subagent。

只回報，不自行修改程式碼。
