---
name: business-agent
description: 代理領域 — 代理設定、月結算報表（申請/審核/駁回）、代理提款、轉帳記錄、投注站統計、RP 報表。涉及代理、佣金、分紅、代理提款、代理結算時載入。**不含 agentline（代理線）**。
origin: project
status: ready
---

# 代理（Agent）

`agent` domain 包含代理的月結算報表生命週期、代理提款申請審核、轉帳記錄查詢、投注站日報統計、代理 RP（Revenue Per）報表。

**⚠️ 不含 agentline（代理線）**：`agentline` 相關表（`agent_recharge_rebate`…）與 service 獨立，不在此 skill 範圍。

---

## 適用時機

- 修改代理月結算計算邏輯（分紅比例、有效會員門檻、平台費用）
- 代理提款申請 / 審核流程修改
- 代理設定（AgentConfig / AgentSettleConfig）新增欄位
- 投注站統計報表調整
- 代理 RP 報表邏輯調整

---

## 領域概念

### 核心實體

| 實體 | 說明 | 對應資料表 |
|------|------|-----------|
| `AgentConfig` | 代理設定（有效會員目標、平台費用比例、門檻 JSON blob） | `agent_config` |
| `AgentSettleConfig` | 結算參數（費用比例、未結算代理名單等） | `agent_settle_config` |
| `AgentSettleReport` | 月結算報表（輸赢、純盈利、佣金計算） | ES 索引（`AgentSettleReportEsDao`） |
| `AgentTransfer` | 代理轉帳記錄 | `agent_transfer` |
| `AgentWithdraw` | 代理提款申請 | `agent_withdraw` |

### AgentConfig 關鍵欄位

- **`platCost`**：平台抽成百分比
- **`platMoneyCost`**：出入款費用/資金風險百分比
- **`platOperateCost`**：行政費用百分比
- **`agentRebateCost`**：代理反水比例
- **`agentCostConfgs`**：盈利門檻分紅設定（**JSON blob**），反序列化為 `List<AgentCostConfig>`
  - `profitStart` / `profitEnd` / `dividendRatio`（按盈利區間取分紅比例）
- **`agentValidBetConfigs`**：有效投注門檻設定（**JSON blob**）
- **`agentThirdValidBetConfigs`**：三方有效投注門檻設定（**JSON blob**）
- **`agentGoldUsers`**：金牌代理帳號（逗號分隔）
- **`filterDlName`**：排除統計的代理帳號

---

## 狀態機

### 月結算報表（`AgentSettleStatus` in `EnumClass`）

```
排程生成報表
   ↓ settleStatus=UNSETTLE(0)
apply(dlId) — 代理申請結算
   ↓ settleStatus=APPLYING(1)
accept(id, opUser) — 後台審核通過
   ↓ settleStatus=SETTLED(2) → 建立 AgentWithdraw 提款申請
或
reject(id, ...) — 後台駁回
   ↓ settleStatus=REJECTED(3)

EXPIRED(4) — 已過期（逾期未申請）
```

| 值 | 常數 | 說明 |
|----|------|------|
| 0 | `UNSETTLE` | 未申請結算 |
| 1 | `APPLYING` | 代理已申請，等待後台審核 |
| 2 | `SETTLED` | 審核通過，已結算 |
| 3 | `REJECTED` | 駁回 |
| 4 | `EXPIRED` | 已過期（每月1號凌晨04:00 Job 觸發時，上月所有非 SETTLED 狀態報表自動標為 EXPIRED） |

**重結算**：`resettle(platformId)` 透過 `QuartzEvent` 重新觸發 `agentSettleReportJobService` Job，重新計算指定平台的上月報表並覆寫 ES。上月所有非 `SETTLED` 狀態的報表會被重算（含 `APPLYING` / `REJECTED` / `EXPIRED`）。

### 代理提款（`RechDrawEnum.WithdrawCheckStatus`，與一般用戶提款共用）

```
add() → NOT_ACCEPT(1) → accept() → THROUGH(3)
                             ↓
                        NOT_THROUGH(4)
CANCEL(5) / LOCK(6) / STATION_AUDIT(7)
```

| 值 | 常數 | 說明 |
|----|------|------|
| 1 | `NOT_ACCEPT` | 未受理 |
| 2 | `ACCEPT` | 處理中 |
| 3 | `THROUGH` | 提款通過 |
| 4 | `NOT_THROUGH` | 提款不通過 |
| 5 | `CANCEL` | 撤銷 |
| 6 | `LOCK` | 鎖定 |
| 7 | `STATION_AUDIT` | 投注站審核中 |

---

## 月結算金額公式

```
純盈利（netProfit）     = 實際輸赢（winMoney）+ 平台費用（platformCost）
平台費用（platformCost） = winMoney × platformCostPercent
平台費用比              = platCost + platMoneyCost + platOperateCost（+ activityCostRate 若設定）

代理佣金（agentDividend）      = netProfit × agentDividendPercent
                                （agentDividendPercent 依 netProfit 落在 agentCostConfgs 哪個區間）
有效投注返水（agentValidDividend）= validBetMoney × agentValidPercent

總計（total）= agentDividend + historyDividend
             + agentRebateMoney + historyRebateMoney
             + agentValidDividend + historyValidDividend
             + 三方 agentValidDividend + 三方 historyValidDividend
```

**注意**：`netProfit > 0` 才具備分紅資格；若全部分紅（`totalDividend` + `totalValidDividend` + `totalThirdDividend`）均為 0 且 `netProfit > 0`，`apply()` 拋出 `BusinessException(AGENT_REPORT_DIVIDEND_VALID_FAIL)`，代理**不可申請結算**（非自動通過）。

---

## 核心業務規則

### 規則 1：結算報表冪等保護
- **What**：`apply` 呼叫前先檢查 `settleStatus == UNSETTLE`，`accept` / `reject` 前檢查 `== APPLYING`
- **Why**：防止重複申請或重複審核
- **違反風險**：代理收到重複提款金額

### 規則 2：金額全程 BigDecimal
- **What**：`netProfit`、`agentDividend`、`total`、`applyMoney` 全部 `BigDecimal`
- **Why**：佣金計算涉及百分比乘法，精度遺失直接影響出款金額
- **違反風險**：代理對帳不符

### 規則 3：門檻 JSON blob 禁直接修改欄位
- **What**：`agentCostConfgs` / `agentValidBetConfigs` / `agentThirdValidBetConfigs` 是 JSON blob，修改設定只能整包 JSON 寫回，不能加獨立 DB 欄位
- **Why**：設計為 per-platform 的動態 config，不走 DDL 異動
- **違反風險**：新 DDL 欄位加了但舊 JSON 讀取邏輯繞過它

### 規則 4：提款申請單筆限制
- **What**：`add()` 前先查 `NOT_ACCEPT` / `ACCEPT` 狀態的申請筆數，若已有進行中訂單，不可重複申請
- **Why**：防止代理同時提交多筆待審提款
- **違反風險**：多筆同金額提款

### 規則 5：幣別換算走 CurrencyService
- **What**：`accept` 時呼叫 `currencyService.sysCurrencyExchangeToCurrency` 換算提款金額
- **Why**：代理幣別可能與系統幣別不同
- **違反風險**：提款金額幣別錯誤

---

## 相關檔案（grep 起點）

- Service：`cx-sport-app-service/src/main/java/com/lc/cp/service/agent/`
  - `AgentSettleReportService` — 結算核心（apply / accept / reject / resettle）
  - `AgentWithdrawService` — 代理提款申請審核
  - `AgentTransferService` — 轉帳記錄查詢
  - `AgentConfigService` — 代理設定 CRUD
  - `AgentSettleConfigService` — 結算參數 CRUD
  - `StationStatisticService` — 投注站日報統計
- Service（report）：`cx-sport-app-service/src/main/java/com/lc/cp/service/report/AgentRPReportService` — RP 報表
- Service（user）：`cx-sport-app-service/src/main/java/com/lc/cp/service/user/AgentChangeService` — 代理異動
- Controller（admin）：`cx-sport-app-service/.../controller/agent/`
- Controller（sport agent）：`cx-sport-app-service/.../com/lc/sports/controller/agent/`
- DAO（MySQL）：`cx-sport-app-service/src/main/java/com/lc/common/dao/agent/`
  - `AgentConfigDao`、`AgentWithdrawDao`、`AgentTransferDao`
- DAO（ES）：`cx-sport-app-service/src/main/java/com/lc/common/dao/agent/AgentSettleReportEsDao`
- VO/SO：`cx-sport-app-service/src/main/java/com/lc/common/bean/vo/agent/`、`/bean/so/agent/`
- Enum：`EnumClass.AgentSettleStatus`（lib/cx-sport-common）
- Job：`cx-sport-app-service/.../job/service/statistic/AgentSettleReportJobService`（月結算排程觸發）

---

## 對接其他模組

| 對接模組 | 方式 | 資料流 |
|---------|------|--------|
| `report（AgentRPReport）` | `AgentRPReportService` | 三方訂單 / 體育注單 → 計算代理 RP 貢獻 |
| `currency` | `CurrencyService.sysCurrencyExchangeToCurrency` | 提款時換算幣別 |
| `user` | `AgentChangeService` | 代理上下級異動 |
| ES | `AgentSettleReportEsDao` | 結算報表讀寫 |

---

## 相關 Agent 與 Skill

- 結算金額公式修改 → L1，`code-reviewer` + `java-reviewer` + `business-reviewer`
- 代理提款審核流程 → L1，加 `business-reviewer`
- AgentConfig JSON blob 新增欄位 → L2，確認反序列化目標（見 Step 0 §0b）
- ES 索引結構調整 → 加 `es-patterns` skill

