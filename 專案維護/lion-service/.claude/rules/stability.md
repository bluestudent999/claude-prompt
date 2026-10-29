---
paths:
  - "**/*.java"
---
# 系統穩定性與平滑發佈 (Stability & Smooth Deployment)

> 規範系統更新、Token 異動、Session 管理等可能導致「全站使用者大面積掉線」的防護原則。
> **AI 開發時，凡涉及登入、Token、Session 或會話狀態的變更，必須嚴格遵守此規範。**

## 1. Token 與登入認證的向後相容
- **嚴禁硬性失效 (Hard Invalidation)**：更新登入服務或更改 Token 結構時，**不可**直接使得舊版 Token 失效。必須實作過渡期 (Grace Period)，支援新舊 Token 雙軌並行驗證。
- **Token 結構異動**：lion 的登入狀態經 resolver 取得（`TokenInfo` / `UserIdWithPlatformId`，快取在 lion-common 的 `TokenInfoCache`）。若新增欄位或改動驗證邏輯，需預設舊 Token / 舊快取資料可能缺乏新欄位，必須給予合理預設值或走舊版驗證降級邏輯。
- **platformId 來源不變**：調整 Token / Session 結構時，platformId 仍只能取自 resolver，不可為了相容而改成從請求 body / query 讀（見 `rules/platform-isolation.md`）。
- **無縫刷新 (Seamless Refresh)**：升級登入服務時，應確保現有使用者的 Session 不會被中斷，或能在背景平滑換發。

## 2. WebSocket
lion-service 沒有 WebSocket 模組。若改動涉及 WebSocket 連線或推送（在其他 repo），列入「跨 repo 影響清單」，斷線不得被判定為登出或觸發業務狀態變更。

## 3. 部署期間的服務可用性 (Zero-Downtime Deployment)
- **滾動更新防禦**：滾動更新時新舊版本實例會同時存在，新版寫出的資料舊版要讀得懂（反之亦然）。
- **分散式 Session**：登入狀態必須依賴跨節點快取 (Redis)，不可存在單一節點記憶體內（見 `rules/patterns.md` §6.5）。
- **結構描述演進 (Schema Evolution)**：資料庫加欄位不可鎖表，重構舊欄位需遵循「新增 → 雙寫 → 切換讀取 → 刪除舊欄位」的 4 階段安全模式（migration 規範見 `rules/flyway-migration.md`）。

## 4. AI 開發檢查清單 (Reviewer 指南)
- `security-reviewer` 或 `business-reviewer` 審查時，若發現 PR 涉及 `Token`、`Session`、`Login`、resolver（`*MethodArgumentResolver`），必須觸發「向後相容性」檢查。
- 檢查項：
  - [ ] 是否會導致舊版 APP / Web 客戶端或既有快取中的 Token 驗證失敗？
  - [ ] 是否依賴單機記憶體狀態，導致滾動更新時狀態遺失？
  - [ ] 改動後 platformId 是否仍只取自 resolver？
