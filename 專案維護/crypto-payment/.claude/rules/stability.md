---
paths:
  - "**/*.java"
---
# 穩定性、冪等與資料安全（crypto-payment）

> 支付平台的資金安全與可重入防護。**凡涉及入款、歸集、webhook、Kafka、狀態機、Schema 的變更必須嚴格遵守。**

## 1. 冪等（重送必然發生）

- **webhook（QuickNode/Tatum）會重送、Kafka 會重投、排程會重跑**——所有 handler 必須冪等
- 去重鍵：`txHash`（鏈上交易）/ `orderNo` / `nonce`；先查是否已處理再入帳
- **同一筆入款只能 credit 一次**——用唯一鍵 + DB 約束，不靠「應該不會重送」的假設
- 入帳前後狀態轉換走明確狀態機（pending → confirmed → credited），拒絕非法轉換

## 2. 防重放（HMAC）

- `/api/pay/*` 的 `timestamp + nonce`：**5 分鐘 replay window**，逾時拒絕、nonce 用過即拒（見 `security.md` §3）
- nonce 去重儲存要跨節點（Redis），不可存單機記憶體

## 3. 鏈上不確定性

- **區塊重組（reorg）**：入款確認需等足夠確認數（依 chain 設定）；未達確認數不可視為最終入帳
- **鏈 client 逾時 / 節點不可用**：需重試 + 退避，不可因單次失敗就標記入款失敗或漏收
- **金額精度**：不同鏈 decimals 不同，換算用 `BigDecimal`（見 `security.md` §5），禁 `double`

## 4. 部署期可用性（Zero-Downtime）

- **滾動更新**：新舊 POD 並存——服務重啟不可導致入款遺漏；未完成的入帳 / 歸集靠 DB 狀態 + 重入補償，不靠記憶體
- **分散式狀態**：session / 鎖 / nonce / cache 依賴 Redis（跨節點），不存單一節點記憶體
- **Schema Evolution（4 階段安全模式）**：加欄位不鎖表；重構舊欄位走「新增 → 雙寫 → 切換讀取 → 刪除舊欄位」；一律走 Flyway 新版號檔（見 `patterns.md` §8）

## 5. Reviewer 檢查清單

`security-reviewer` / `business-reviewer` 審查涉及 `webhook` / `deposit` / `collector` / `Kafka` / `schedule` / 金額狀態機的 PR 時，必須觸發本清單：

- [ ] webhook / Kafka / 排程 handler 是否冪等（有去重鍵 + 已處理判斷）？
- [ ] 同一筆入款是否可能被 credit 兩次？
- [ ] 是否依賴單機記憶體狀態，導致滾動更新時遺失（nonce / 鎖 / 計數）？
- [ ] 入款是否等足夠確認數才視為最終（reorg 防護）？
- [ ] Schema 變更是否走 Flyway 新版號檔、不鎖表、不改既有檔？
