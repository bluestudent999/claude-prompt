---
name: business-pay
description: 充值 / 提款支付領域 — 第三方支付對接、訂單狀態機、回調驗簽、出入金流水、單一錢包整合。涉及充值 / 提款 / 第三方支付 / 出入款時載入。
origin: project
status: skeleton
---

# 充值 / 提款（Pay）

> 🚧 **此 skill 為骨架** — 業務規則骨架由 Claude 從程式碼探索生成，狀態機細節與業務規則需 PO + 支付對接負責人補完。

`pay` domain 包含整個出入金流程：建單、推送至第三方、回調處理、加扣款、流水。L1 最高風險區 — 錯一步直接損失資金或合規問題。

## 適用時機

- 新第三方支付通道對接
- 充值 / 提款流程修改
- 回調處理 bug
- 鏈上支付調整
- 提款稽核流程調整
- 出入金對帳

## 領域概念

### 核心實體

| 實體 | 說明 | 對應資料表 |
|------|------|-----------|
| `UserRech` | 充值訂單 | `user_rech` |
| `UserWithdraw` | 提款申請 | `user_withdraw` |
| `RechCfg` | 充值通道配置 | `rech_cfg` |
| `ParamCfg` | 系統參數（充值級別、提款類型） | `param_cfg` |

### 關鍵欄位語義

- **`orderNo`**：平台訂單號（冪等鍵），全域唯一
- **`thirdOrderNo`**：第三方訂單號，回調對帳用
- **`status`（充值）**：`UserRechStatus` Enum，見下方狀態機
- **`checkStatus`（提款）**：`WithdrawCheckStatus` Enum，見下方狀態機

## 狀態機

### 充值（`UserRechStatus`）

```
UNCHECKED(1) → RECHING(4) → SUCCESS(2)
                   ↓              ↓
               FAILED(3)    AUTO_REJECT(5)
```

| 值 | 常數 | 說明 |
|----|------|------|
| 1 | `UNCHECKED` | 未處理 |
| 2 | `SUCCESS` | 充值成功 |
| 3 | `FAILED` | 充值失敗 |
| 4 | `RECHING` | 線上充值中（已推送第三方，等回調） |
| 5 | `AUTO_REJECT` | 自動駁回 |

### 提款（`WithdrawCheckStatus`）

```
NOT_ACCEPT(1) → ACCEPT(2) → THROUGH(3) → 執行出款
                    ↓            ↓
               NOT_THROUGH(4)  CANCEL(5)
               LOCK(6)
               STATION_AUDIT(7) → THROUGH / NOT_THROUGH
```

| 值 | 常數 | 說明 |
|----|------|------|
| 1 | `NOT_ACCEPT` | 未受理 |
| 2 | `ACCEPT` | 處理中（稽核中） |
| 3 | `THROUGH` | 提款通過 |
| 4 | `NOT_THROUGH` | 提款不通過 |
| 5 | `CANCEL` | 撤銷 |
| 6 | `LOCK` | 鎖定 |
| 7 | `STATION_AUDIT` | 投注站審核中 |

## 核心業務規則

### 規則 1：回調驗簽（強制）
- **What**：所有第三方回調必須驗簽 + 校驗訂單金額一致
- **Why**：防偽造回調套取資金
- **違反風險**：直接資金損失
- **作法**：驗簽邏輯在外部 Pay 微服務（`PAY_URL`），本 repo `PayNotifyService` 收到回調後呼叫 `payService.putReturnParam` 交由外部服務驗；本 repo 側做 IP 白名單過濾

### 規則 2：冪等（強制）
- **What**：同一 `(orderNo, thirdOrderNo)` 處理多次只生效一次
- **Why**：第三方會重複回調
- **違反風險**：重複加款
- **作法**：DB UNIQUE INDEX + 狀態機 WHERE 條件保護；Redis 鎖防止同訂單併發回調

### 規則 3：金額處理（強制）
- **What**：全程使用 `BigDecimal` + `RoundingMode.DOWN`，禁用 `double` 中轉
- **Why**：精度遺失 → 對帳不上
- **違反風險**：長期誤差累積、對帳無法平
- **作法**：`new BigDecimal(amountStr)`，不走 `Double.parseDouble()` 再轉

### 規則 4：狀態先行後加款（強制）
- **What**：先 UPDATE 狀態欄位，後呼叫加款，全程 `@Transactional`
- **Why**：若先加款後改狀態，rollback 後狀態回滾但流水可能已寫 → 重複加款
- **違反風險**：對帳不符或重複入帳

### 規則 5：訂單時效
- **What**：N 分鐘 / 小時內未支付自動取消
- **Why**：避免過期訂單干擾對帳

### 規則 6：通道風控
- **What**：單通道單日 / 單筆額度限制；命中限額切換通道
- **Why**：保護通道穩定性 + 風控
- **作法**：`RechCfg` / `WithdrawChannelSettingService` 管控

## 金額處理

- `BigDecimal` + `RoundingMode.DOWN`
- 充值成功加款流程：`先 UPDATE status = SUCCESS` → `再呼叫 UserMoneyService 加款` → `寫 money_log` → 通知單一錢包（Kafka Event）
- 全程 `@Transactional`，任何一步失敗整筆 rollback

## 併發控制

- **加款**：`SELECT FOR UPDATE` 鎖 `user_money`（或委派單一錢包 `TransactionService`）
- **狀態變更**：UPDATE 帶 `WHERE check_status = <expected>`，rowCount 0 = 已被別處改，直接 return
- **回調冪等**：UNIQUE INDEX `(order_no, third_order_no)`
- **Redis 鎖 key**：`pay:callback:{orderNo}`（避免同訂單併發回調）

## 安全要求

- 回調 IP 白名單（每通道獨立設定）
- 簽名密鑰存 `config` 表 / ConfigCache，**禁硬編碼至程式碼**
- 錯誤訊息對外脫敏（回傳「處理中」，勿洩漏內部狀態碼 / 異常堆疊）
- 回調日誌脫敏（密鑰 / 銀行卡號 / 姓名需 mask）
- Admin 出款操作需記錄操作人 + 操作 IP

## 相關檔案（grep 起點）

- Service：`cx-sport-app-service/src/main/java/com/lc/cp/service/`（pay / recharge / withdrawcheck）
- Controller：`cx-sport-app-service/src/main/java/com/lc/cp/controller/`
- DAO：`cx-sport-app-service/src/main/java/com/lc/common/dao/recharge/`
- 外部 Pay 微服務：`PAY_URL`（`config` 表 `ConfigKey.PAY_URL`）— 第三方 API 整合 / 驗簽邏輯在此獨立服務，不在本 repo；`PayService` 僅做 HTTP 轉發（帶 `onlineType` + 通道參數）
- 鏈上支付：`OnChainPayService`
- 單一錢包 Service：`cx-sport-single-wallet-service/.../service/singlewallet/TransactionService`

## 對接其他模組

| 對接模組 | 方式 | 資料流 |
|---------|------|--------|
| `singlewallet` | Kafka Event / 直接呼叫 | 充值成功 → 變動單一錢包餘額 |
| `user` | 直接呼叫 | 加 / 扣餘額（內部錢包情境） |
| `withdrawcheck` | service 呼叫 | 稽核通過 → 推送出款至第三方 |
| `report` | 共用 | 出入金報表 |

## 常見錯誤模式

### 錯誤 1：未驗簽就加款
- **症狀**：被偽造回調套取
- **修正**：所有 callback handler 強制走驗簽 → 才進狀態機

### 錯誤 2：加款先於狀態變更
- **症狀**：rollback 後狀態回滾但 money_log 已寫 → 對帳不上 / 重複加款
- **修正**：先 UPDATE 狀態，後加款，全程 `@Transactional`

### 錯誤 3：第三方訂單號未雙向驗證
- **症狀**：回調帶其他訂單的 thirdOrderNo → 加錯款
- **修正**：UPDATE 帶 `WHERE order_no = X AND third_order_no = Y`

### 錯誤 4：金額用 double 中轉
- **症狀**：`Double.parseDouble(amount)` → BigDecimal → 精度已失
- **修正**：直接 `new BigDecimal(amountStr)`

## 相關 Agent 與 Skill

- 強制全套 → `business-reviewer` + `security-reviewer` + `database-reviewer`
- 新通道對接 → `api-connector-builder` skill
- 規格預審 → `spec-review`

---

## 補完檢查清單（PO + 對接負責人）

- [ ] 確認 connector/impl 實際路徑與現有通道清單
- [ ] 補完充值 / 提款通道費率與結算週期
- [ ] 鏈上支付確認塊數 / 重組處理細節
- [ ] 訂單時效設定位置與自動取消 Job
- [ ] 對帳機制（每日 / 每小時對第三方）
- [ ] 失敗訂單客服處理流程
- [ ] 補完後將 `status: skeleton` 改為 `ready`
