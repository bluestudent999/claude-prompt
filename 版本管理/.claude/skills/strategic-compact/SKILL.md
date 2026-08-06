---
name: strategic-compact
description: 在升級階段的邏輯間隔點建議手動 /compact，在 Phase 之間保留關鍵上下文，而非依賴任意自動壓縮。升級碰大量檔案，context 壓力高。
---

# 策略性壓縮 Skill（升級期）

升級會碰大量檔案（盤點 grep、recipe diff、編譯錯誤、reviewer 輸出），context 累積快。在 Phase 邊界主動 `/compact`，比讓自動壓縮在 Phase 中途亂砍好。

## 升級期的壓縮時機

| 階段轉換 | 壓縮？ | 原因 |
|----------|--------|------|
| 盤點 → 計畫 | 是 | 盤點 grep 結果龐大；inventory.md / plan 是濃縮輸出，已落檔 |
| 計畫 → 自動遷移 | 是 | plan 在檔案中；釋放 context 給 recipe diff 審查 |
| 自動遷移 → 編譯收斂 | 視情況 | 編譯錯誤需參考剛遷移的改動則保留；錯誤獨立則壓 |
| 編譯收斂 → 回歸 | 是 | 編譯細節不影響回歸判定；保留 plan + diff 清單即可 |
| reviewer 後 → 修復 | 視情況 | reviewer 輸出已讀取重點後可壓 |
| Phase 中途 | 否 | 遺失 namespace 遷移狀態、檔案路徑代價高 |

## 觸發提醒（suggest-compact.sh）

`PreToolUse(Edit|Write)` 掛 `suggest-compact.sh`，依工具呼叫次數提醒（預設 50 次，之後每 25 次）。Hook 告訴你*何時*，由你決定*是否*。

升級專屬的「該壓了」訊號：
- 已整讀 ≥ 3 個實作檔（含 > 300 行）
- recipe diff 審查完、已 commit
- reviewer 已輸出 ≥ 2 個
- 已跑 ≥ 5 次跨檔 grep（盤點階段尤其多）

## 壓縮前先落檔

升級的關鍵狀態要在壓縮前寫入檔案，不靠對話記憶：
- inventory.md（盤點結果）
- plan §1 版本鎖定表、§6 風險點
- 每個 Phase 的 commit hash（可二分）
- reviewer Final Status + CRITICAL/HIGH 清單

## 壓縮後保留 vs 遺失

| 保留 | 遺失 |
|------|------|
| CLAUDE.md / rules（自動注入） | recipe diff 原始內容 |
| TodoWrite 任務清單 | 已讀檔案內容 |
| upgrade/ 下的 inventory.md / plan | grep 原始輸出 |
| Git 狀態（commit / 分支） | 中途 reviewer 長文 |

## 設定
環境變數 `COMPACT_THRESHOLD`（預設 50）。執行方式：提示 user `/compact`，可加摘要如 `/compact 接下來專注編譯收斂，保留 plan §4 與 recipe commit hash`。
