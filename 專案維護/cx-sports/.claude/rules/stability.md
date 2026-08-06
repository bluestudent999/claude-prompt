---
paths:
  - "**/*.java"
  - "**/*.js"
  - "**/*.vue"
---
# 系統穩定性與平滑發佈 (Stability & Smooth Deployment)

> 規範系統更新、Token 異動、WebSocket 斷線等可能導致「全站使用者大面積掉線」的防護原則。
> **AI 開發時，凡涉及登入、Token、WebSocket 狀態或會話管理的變更，必須嚴格遵守此規範。**

## 1. Token 與登入認證的向後相容
- **嚴禁硬性失效 (Hard Invalidation)**：更新登入服務或更改 Token 結構時，**不可**直接使得舊版 Token 失效。必須實作過渡期 (Grace Period)，支援新舊 Token 雙軌並行驗證。
- **Token 結構異動**：若新增 JWT Claim 或改動 Token 驗證邏輯，需預設舊客戶端發送的 Token 可能缺乏新欄位，必須給予合理預設值或走舊版驗證降級邏輯。
- **無縫刷新 (Seamless Refresh)**：升級登入服務時，應確保現有連線使用者的 Session 不會被中斷，或能在背景透過 Refresh Token 平滑換發。

## 2. WebSocket 連線與斷線重連機制
- **斷線不等於「登出」或「離線」**：部署更新會導致服務重啟，WebSocket (WS) 必然斷開。**嚴禁**將 WS 斷線事件直接判定為「使用者登出」或「立刻踢出遊戲」。
- **重連寬限期 (Reconnect Window)**：WS 斷開後，應保留狀態機或 Session 至少 3-5 分鐘的寬限期。客戶端必須具備指數退避 (Exponential Backoff) 的自動重連機制。
- **狀態恢復 (State Recovery)**：重連成功後，後端必須能根據先前的 Token 或 Session ID 恢復使用者狀態，而非強迫使用者重新走一次完整登入流程。

## 3. 部署期間的服務可用性 (Zero-Downtime Deployment)
- **藍綠/滾動更新防禦**：在 Kubernetes 等容器環境下進行滾動更新時，新舊版本 POD 會同時存在。
- **分散式 Session**：登入狀態或 WebSocket 中繼訊息必須依賴 L1 跨節點快取 (Redis)，不可存在單一節點記憶體內（見 `patterns.md §6.5`）。
- **結構描述演進 (Schema Evolution)**：資料庫加欄位不可鎖表，重構舊欄位需遵循「新增 → 雙寫 → 切換讀取 → 刪除舊欄位」的 4 階段安全模式。

## 4. AI 開發檢查清單 (Reviewer 指南)
- `security-reviewer` 或 `business-reviewer` 審查時，若發現 PR 涉及 `Token`、`Session`、`Login`、`WebSocket`，必須觸發「向後相容性與斷線防禦」檢查。
- 檢查項：
  - [ ] 是否會導致舊版 APP/Web 客戶端驗證失敗？
  - [ ] WebSocket 斷開時，是否會觸發非預期的業務狀態變更（例如：自動強制結算、自動登出）？
  - [ ] 是否依賴單機記憶體狀態，導致滾動更新時狀態遺失？
