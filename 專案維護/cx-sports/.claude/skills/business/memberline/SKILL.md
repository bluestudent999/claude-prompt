---
name: business-memberline
description: 會員代理返佣線（全民代理）— 流水佣金 / 充值佣金 / 首充佣金 / 後台加扣 / 佣金錢包轉余額錢包。涵蓋 UserCommission 餘額樂觀鎖、UserCommissionRecord 審核狀態機、黑白名單、平台 / 充值雙方案、每日結算排程。涉及 memberline / 全民代理 / 會員佣金 / 流水佣金 / 充值返佣 / 佣金錢包 時載入。
origin: project
status: ready
---

# 會員代理返佣線（Memberline）

`memberline` domain 是「全民代理」返佣機制，會員可透過邀請**直屬**下級獲得返佣（無多層分潤，見「分配模型」段），並將佣金錢包餘額轉入主錢包。包含 4 個獨立的佣金來源、雙方案配置（流水方案 + 充值方案）、審核流程與黑白名單。

---

## 適用時機

- 新增 / 修改佣金計算規則（流水百分比、充值百分比、上限）
- 調整審核流程（自動 / 人工、最小金額閾值、白名單）
- 修改佣金錢包轉入主錢包邏輯（稽核流水、手續費）
- 調整每日結算排程或統計報表
- 黑 / 白名單功能變更
- 審查涉及 memberline 的 PR

---

## 邊界與名詞對照（避免與 agent 體系混淆）

> ⚠️ **memberline ≠ agent (DL/ZDL)**。雖然 UI 標籤、config key、Controller 命名都帶「Agent」字樣，但 memberline 是「**會員（HY）拉下級**」的返佣機制，**與正規代理體系（DL / ZDL）完全獨立**。

### memberline 涉及的角色

`UserInfoEnum.ROLE_TYPE` 共 10 種，memberline 只涉及 **`HY`（会员）**：

| code | desc | 參與 memberline？ |
|------|------|----------------|
| **`HY`** | 会员 | ✅ **唯一**參與角色 — 所有 HY 預設可拉下級獲返佣，不需後台分配權限 |
| `DL` / `ZDL` | 代理 / 总代理 | ❌ 屬 agent 體系，走獨立的 `service/agent/` |
| MANAGE / BOSS / ADMIN / ZZH / MTS / SZZH / ROBOT | 各種後台 / 風控 / 子帳號 | ❌ |

`MergeDataAsyncService` L316/L360 證據：只有 `ROLE_TYPE.HY` 設 `memberQueryCode`；`DL` 只設 `queryCode`。

### sport repo 有 5 個獨立的「Agent」概念

| 詞 | 路徑 | 屬於 |
|----|------|------|
| `代理 / DL` | `service/agent/`、`controller/agent/` | **agent 體系**（非本 skill） |
| `ZDL 總代理` | 同上 | **agent 體系** |
| `agent-front` 子專案 | `lion-frontend/agent-front/` | **agent 體系**（DL/ZDL 用前台） |
| `agentline` UI | `admin-frontend/components/agentline/`（含 commission / commissionPlan） | **agent 體系**（代理線管理，**非 memberline**） |
| **`memberline / 全民代理`** | `service/memberline/`、`components/memberline/` | **本 skill** |

### 易混淆名詞速查

| 看到的名詞 | 實際對應 |
|-----------|---------|
| 「全民代理」 | **memberline 系統**（看似有「代理」但與 DL/ZDL 無關） |
| `MemberAgentController`（前台） | **memberline 系統**（「Member」+「Agent」= 會員代理 = 全民代理） |
| `ALL_AGENT_FLAG` / `ALL_AGENT_MAIN_SWITCH` config | **memberline 開關**（「ALL_AGENT」= 全民代理） |
| `agentline` UI 的 commission | **agent 體系**（非 memberline） |
| `agent-front` | **agent 體系** |
| **「白名單」** | ⚠️ 在 memberline 範圍內有**兩個截然不同**的意義 — 見下表 |

### 「白名單」兩種完全不同意義

| 語境 | 實際對應 | 來源檔案 / 設定 |
|------|---------|--------------|
| **路徑層白名單**（HTTP / 鑑權層） | URI 被列入 `uri.white.list / list2` → 跳過某些 filter 預檢 | `application.yml` L867-；`controller/front/whitelist/` 子包；路徑前綴 `/api/front/wl/...` |
| **業務層白名單**（佣金審核層） | 用戶佣金審核自動通過 | `member_commission_whitelist` 表；`MemberCommissionWhitelistService.isInWhitelist`；用於 DAILY_COMM / 充值佣金自動審核分支 |

兩者完全獨立 — 路徑層白名單是給「前端未完整鑑權態」用，業務層白名單是給「免審核佣金」用。讀程式碼時看到 `whitelist` 字眼，先看上下文來自哪邊。

### 資料路徑分離

| 軸線 | memberline | agent (DL/ZDL) |
|------|-----------|----------------|
| 用戶鏈欄位 | `member_query_code`（只含 HY 鏈） | `query_code`（含 DL/ZDL 全鏈） |
| 佣金錢包 | `user_commission` 表 | `agent_*` 系列 |
| 結算流程 | `UserCommissionService` / `RechargeCommissionService` | `AgentSettleReportService` / `AgentWithdrawService` |
| 開關 | `ALL_AGENT_FLAG` + `ALL_AGENT_MAIN_SWITCH` | 各代理層級獨立 |

**修改 memberline 時若不確定影響範圍**：先確認改的是 `service/memberline/` 還是 `service/agent/`；若涉及 admin UI 改動，確認是 `components/memberline/` 還是 `components/agentline/`。

---

## 兩層開關 gating（所有 memberline 觸發點共用）

memberline 所有觸發點都依賴**兩層 config 開關**才會跑，**任一為 NO 即跳過/拋錯**：

| Config Key | scope | 預設 | 取值方式 |
|-----------|------|------|---------|
| `ALL_AGENT_MAIN_SWITCH` | 全局（per `ServiceConst.PLAT_ID`） | NO | `configService.getConfig(PLAT_ID, ALL_AGENT_MAIN_SWITCH, NO)` |
| `ALL_AGENT_FLAG` | 平台級（per `platformId`） | NO | `configService.getConfig(platformId, ALL_AGENT_FLAG, NO)` |

### 各觸發點 gating 對照

| 觸發點 | 全局開關檢查 | 平台開關檢查 | NO 時行為 |
|--------|------------|------------|----------|
| **transferIn** | `ValidateService.validateCommissionTransfer` L59 | 同方法 L58 | 拋 `COMMISSION_TRANSFER_FAILED` |
| **充值佣金** | `RechargeCommissionService.calcRechargeCommission` L149 | 同方法 L152 | `return`（靜默跳過，不拋錯） |
| **DAILY_COMM 結算** | `MemberLineSettleJobService.handleEvent` L46（**Job 層**） | `UserCommissionService.statCommission` L71-73（**Service 層**） | log + skip |

**結構差異**：transferIn / 充值佣金的兩層開關**集中在單一方法**；DAILY_COMM 的兩層**分散在 Job 層 + Service 層**（Job 先擋全局、Service 再擋平台），改 statCommission 時注意這個分層。

### 修改前自檢

新增 memberline 觸發點（如新增一個業務事件觸發佣金發放）時，**必須**：
1. 入口先檢查兩層開關，否則繞過 gating 直接寫 record，平台關掉全民代理時還會發佣金 → 帳務漏洞
2. 統一錯誤碼策略 — 用戶觸發拋 `COMMISSION_TRANSFER_FAILED`；系統觸發 silent return + log

---

## 分配模型（全 type 都是「直屬上下級單層」）

> ⚠️ 整個 memberline **沒有多層分潤**。所有佣金類型只在「投注者 ↔ 投注者的直屬上級」之間流動，祖父輩不會分到孫子的投注佣金。

| 情境 | 結果 |
|------|------|
| A → B → C（A 是 B 的直屬上級，B 是 C 的直屬上級），C 投注 | 只有 B 拿到佣金 |
| C 投注（隔代） | A **不會**因為 C 投注而拿佣金 |
| B 自己投注 | A 拿佣金（B 是 A 的直屬下級） |

**`memberQueryCode` 多層結構的實際用途：**
- `memberLineLevel`：報表 group by 看「平台付給第 N 層 HY 多少佣金」（見規則 8）
- `topUpperId`：追溯頂層 HY
- **錢的流向只在直屬上下級之間** — 多層結構僅用於分析統計

---

## 子系統概覽

memberline 由四種獨立佣金來源組成，**共用**同一張 `user_commission_record` 紀錄表（以 `type` 區分）：

| 佣金類型（`type`） | 來源 | 受益人 | 主 Service | 觸發 |
|--------|------|--------|------------|------|
| `0` DAILY_COMM 每日流水佣金 | 直屬下級當日有效投注總和 × commRate（金額階梯）| **直屬上級 1 人**（不逐層） | `UserCommissionService.statCommission` → `calPeriodUserCommission` | `MemberLineSettleJobService` 每日排程 |
| `1` ADMIN_COMM 後台加扣 | 管理員手動加扣 | 後台指定用戶 | `UserCommissionRecordService.save` | 後台 Controller |
| `2` FIRST_RECH_COMM 首充佣金獎勵 | 下級首次充值 × 首充百分比 | **rechUser 的直屬上級 1 人**（不逐層） | `RechargeCommissionService.calcRechargeCommission` | `UserRechService` 充值成功後 |
| `3` RECH_COMM 充值佣金獎勵 | 下級非首次充值 × 充值百分比 | **rechUser 的直屬上級 1 人**（不逐層） | `RechargeCommissionService.calcRechargeCommission` | 同上 |

> **轉入余額錢包不存 record**：DB column comment（`UserCommissionRecord.java` type 欄位上方）提及「`4:转入余额钱包`」但 `TYPE` enum 只定義到 type=3，**type=4 未實作**；`transferIn` 走 `UserMoneyChange` + `TranType.MEMBER_COMM_TRANSFER` 寫到 `user_bill`，不再寫 user_commission_record。

---

## 領域概念

### 核心實體

| 實體 | 說明 | 對應資料表 |
|------|------|-----------|
| `UserCommission` | 用戶佣金錢包餘額（每用戶單列，pk = user_id） | `user_commission` |
| `UserCommissionRecord` | 佣金紀錄（含審核狀態 / 金額 / 層級 / 期間） | `user_commission_record` |
| `MemberCommissionPlan` | 平台流水佣金方案（per platform + currency） | `member_commission_plan` |
| `MemberLevelCommission` | 流水佣金等級階梯（per plan） | `member_level_commission` |
| `RechargeCommissionConfig` | 充值佣金方案（per platform + currency） | `recharge_commission_config` |
| `MemberGameProduct` | 計入佣金的遊戲廠商範圍（per plan） | `member_game_product` |
| `MemberCommissionBlackUser` | 黑名單（流水不計 or 佣金不發） | `member_commission_black_user` |
| `MemberCommissionWhitelist` | 白名單（佣金免審核） | `member_commission_whitelist` |
| `MemberDailyStatReport` | 每日彙總報表（per platform + user + date） | `member_daily_stat_report` |

### 關鍵欄位語義（UserCommissionRecord）

- **`type`**：0 流水 / 1 後台 / 2 首充 / 3 充值（見 `TYPE` enum）
- **`status`**：審核狀態 0 PENDING / 1 CHECKED / 2 REJECT / 4 AUTO（**`3` 未實作** — enum 註解掉，全 repo 無 `setStatus(3)`；DB 不會有此值；「重新審核」是動作而非狀態 — 見狀態機段）
- **`memberLineLevel`**：會員代理層級，**最頂層 = 1，往下遞增**
- **`commission`**：實際派發佣金（`BigDecimal`），可能被 `maxCommissionLimit` 截斷
- **`netCommission`**：**應發**佣金（截斷前）— 新版 code `calPeriodUserCommission` 中 `bo.setNetCommission(commission)` 直接相等；僅在 `maxCommissionLimit` 截斷時兩者不同（`commission` = 截斷後實派，`netCommission` 保留截斷前值）。**模型欄位 Javadoc 寫「= 團隊佣金 − 下級總團隊佣金」對應舊版（version=0）的真實計算公式；新版 code 改成直接相等，舊資料的 netCommission 可能有獨立值**
- **`subCommission` / `lineCommission` / `betAmountReward`**：新版（version=1）DB **存 0**；舊版（version=0）資料**可能有實際值**。新邏輯不要用這些欄位，前端報表透過 L565 補回 `lineCommission = netCommission`（見規則 11）
- **`validBetAmount`** — 跨 type 語意不同：
  - `DAILY_COMM`：upper 自己當日有效投注（若 upper 也下注）— `calPeriodUserCommission` L232；不參與 commission 計算，僅 record 顯示
  - `FIRST_RECH_COMM` / `RECH_COMM`：**硬編碼 = 0**（`initCommissionRecordSO` L289 `setValidBetAmount(BigDecimal.ZERO)`）
- **`totalValidAmount`** — 跨 type 語意不同：
  - `DAILY_COMM`：佣金基數 = upper 的**直屬下級**當日有效投注總和（不含 upper 自身）— `calPeriodUserCommission` L215-217
  - `FIRST_RECH_COMM` / `RECH_COMM`：**該筆充值金額** `userRech.actualMoney`（`initCommissionRecordSO` L296）
- **`commRate`** — 跨 type 語意不同：
  - `DAILY_COMM`：金額階梯命中的百分比（`MemberLevelCommission.commRate`，見規則 10）— `computeCommission` L388
  - `FIRST_RECH_COMM` / `RECH_COMM`：充值方案的 `firstRechargePercentage` / `rechargePercentage`（`initCommissionRecordSO` L298）
- **`maxCommissionLimit`**：每日最高佣金上限（記錄當下配置值，避免方案後續異動造成歷史紀錄失真）
- **`version`**：0 舊版 / 1 新版。**新產生紀錄一律 = 1**（`UserCommissionService.createBasic` L304 + `RechargeCommissionService.initCommissionRecordSO` L301 都 hardcoded `VERSION.NEW`，全 repo 無 `setVersion(OLD)`）；**0 只可能是改版前 DB 歷史資料**。新舊版欄位語義差異見「已廢除欄位」描述與規則 11
- **`statDate`**：報表日期（DAILY_COMM 為結算日；充值類為充值日）

### 關鍵欄位語義（MemberCommissionPlan）

- **`commissionType`**：1 AUTO 自動 / 2 REVIEW 審核（流水佣金的派發類型）
- **`commMinReview`**：自動派發審核最小金額（金額 < 此值且方案是 REVIEW 仍可自動派）
- **`betAmountMultiple`**：佣金提領所需流水比例倍數（0 = 不需稽核）
- **`maxCommissionLimit`**：每日最高佣金
- **`minCommissionTransfer`**：佣金提領最小金額
- **`feePercentage`**：稽核未通過時的手續費（0~100，整數）
- **`minAccumulateRecharge`**：佣金轉余額錢包前 **30 天累計最小充值額**

### 關鍵欄位語義（RechargeCommissionConfig）

- **`firstRechargeSwitch` / `rechargeSwitch`**：開關（0 關 / 1 開）
- **`firstRechargePercentage` / `rechargePercentage`**：百分比（`BigDecimal`）
- **`maxFirstRechargeAmount` / `maxRechargeAmount`**：單筆上限
- **`dailyMaxFirstRechargeAmount` / `dailyMaxRechargeAmount`**：單日上限
- **`dailyMaxAutoReview`**：充值佣金單日最大自動審核**筆數**（超過轉人工審核）
- **`commissionType`**：同 plan，1 AUTO / 2 REVIEW
- **`filterRechType`**：充值方式過濾（不計入返佣的充值類型）

---

## 審核狀態機（UserCommissionRecord.STATUS）

> ⚠️ **`value=3 RETRIAL` 未實作**：enum 一開始就被註解掉（`UserCommissionRecord.java:182`），全 repo 沒有任何 `setStatus(3)`。**DB 中不會有 `status=3` 紀錄**。DDL / VO Javadoc 仍寫「3:重新审核」是**設計文檔殘留**，**「重新審核」是動作而非狀態**（見下方 `retrial`）。

```
                 ┌──── retrial ────┐
                 ▼                 │
            PENDING (0) ──┬──► CHECKED (1)
                          │
                          ├──► REJECT (2)
                          │
                          └──► (繞過審核) ──► AUTO (4)
```

| 從 | 到 | 觸發 | 注意 |
|----|-----|-----|------|
| `PENDING` | `CHECKED` | `UserCommissionRecordService.confirm` | 派金額用 `changeMoneyLock(addTotal=true)` 寫入 user_commission 並累加 totalCommission |
| `PENDING` | `REJECT` | `reject` / `batchReject` | 不發金額；可後續 `retrial` 回到 PENDING |
| **`REJECT`** | **`PENDING`** | **`retrial`** | **動作而非新狀態** — 把 status 從 2 改回 0（CAS by oriStatus=REJECT），不寫 3；之後再走一般審核流程才到 CHECKED |
| `PENDING` | `AUTO` | 系統自動派發 | 條件見「自動審核規則」 |

**`retrial` 完整流程**（`UserCommissionRecordService.retrial` L380-392）：
1. 檢查 userId 是否在 `COMMISSION_LIMIT` 黑名單 → 是則拋 `BusinessException(3514, "佣金黑名单用户，无法重新审核")`（`USER_IN_BLACK_LIST_CANT_RETRIAL`）
2. `setStatus(PENDING)` + `setOriStatus(REJECT)`
3. `updateRecordStatus(SO)` → `UPDATE user_commission_record SET status=0 WHERE id=? AND status=2`（以 oriStatus CAS 保護重複觸發）

UI 觸發：`UserCommissionRecord.vue:132` `v-if="scope.row.status == 2"` — 只對 REJECT 紀錄顯示「重新審核」按鈕。

**刪除狀態列表（`deleteStatusList`）：** `PENDING` + `REJECT`，僅這兩態的紀錄可被刪除。

**派發冪等保護：** `successStatus()` 回傳 `[CHECKED, AUTO]`，前端 / 報表查「已派發」一律用此列表；切勿手動列舉，避免漏判 AUTO。

**查詢端不需處理 `status=3`：** `UserCommissionRecordDao` 所有 status filter 走 `query.getStatus()` / `query.getStatusList()` 動態傳入，無硬編碼；因 DB 不會有 3，過濾條件不需排除。

---

## 自動審核規則

> ⚠️ DAILY_COMM 與充值佣金（FIRST_RECH_COMM / RECH_COMM）是**兩條獨立流程**，分支邏輯不同。**所有金額比較用 `netCommission`（應發），不是 `commission`（實派）**。

### DAILY_COMM 流水佣金分支（UserCommissionService L104-136）

```
讀取同 platform + user + statDate + DAILY_COMM 的既有紀錄
  └─ 若 status ∈ successStatus()（CHECKED / AUTO） → SKIP（冪等保護）
  └─ 否則：
       isAutoType       = plan.commissionType == AUTO
       isBelowMinReview = plan.commissionType == REVIEW && netCommission < commMinReview
       isWhitelistUser  = whitelistUserIds.contains(userId)

       if (isAutoType || isBelowMinReview || isWhitelistUser)
           → auto(recordSO)                          // status = AUTO，commission 保留實派金額
       else
           → commission = 0                          // ⚠️ PENDING 時 commission 被覆寫為 0，netCommission 保留
             status     = PENDING
```

**重點：**
- DAILY_COMM **沒有** `dailyMaxAutoReview` 機制（那是充值佣金獨有）
- 白名單條件不限於 REVIEW 模式，AUTO 模式下白名單也走同一分支（結果一樣）
- 已派發 skip 是冪等保護 — 重跑結算 job 不會重複派錢

### 充值佣金分支（RechargeCommissionService L230-276）

```
isBlackList      = blackUserService.isCommissionLimit(upperUserId)   // 黑名單 type=1
isAutoType       = config.commissionType == AUTO
isBelowMinReview = config.commissionType == REVIEW && netCommission < commMinReview

if (isBlackList) {
    → 寫一筆 status=REJECT 紀錄，remark="黑名单"             // ⚠️ 不是「不寫」，是 REJECT
}
else if (isInWhitelist(upperUserId)) {
    // 白名單分支：完全繞過審核邏輯，唯一阻擋是單日上限
    if (checkRewardExceeds(...))
        → 寫一筆 status=REJECT 紀錄，remark="超过单日最高奖励限额"
    else
        → auto(recordSO)，remark="白名单"                    // status = AUTO
}
else {
    // 一般用戶分支
    isOverMax = checkOverAutoMax(config, recordSO, now)
    if ((isAutoType || isBelowMinReview) && !isOverMax) {
        if (checkRewardExceeds(...))
            → 寫一筆 status=REJECT 紀錄，remark="超过单日最高奖励限额"
        else {
            → auto(recordSO)
            if (type == RECH_COMM)                           // ⚠️ 僅 RECH_COMM 累計，FIRST_RECH_COMM 不計
                rechCountLimitRedisCache.set(platformId, userId, now)
        }
    } else {
        → commission = 0
          status     = PENDING
    }
}
```

**`checkOverAutoMax` 行為細節（L305-320）：**
- **只對 `RECH_COMM (type=3)` 計數**；`FIRST_RECH_COMM (type=2)` 直接 return false（不受筆數限制）
- `dailyMaxAutoReview` **null 或 ≤ 0 視為「不限制」**（return false），**不是「禁止自動」**
- 計數來源：`MemberLineRechCountLimitRedisCache.get(platformId, userId, date)`，累計達 `dailyMaxAutoReview` 才返 true

**黑白名單互斥**：先檢黑、再檢白、最後一般用戶。同用戶同時在黑白名單時**黑名單優先 → REJECT**。

---

## 金額限制檢查（RechargeCommissionService.checkRewardExceeds）

充值佣金計算後驗證**單筆 + 單日**雙重上限：

| 類型 | 單筆上限欄位 | 單日上限欄位 |
|------|------------|------------|
| 首充（FIRST_RECH_COMM） | `maxFirstRechargeAmount` | `dailyMaxFirstRechargeAmount` |
| 一般充值（RECH_COMM） | `maxRechargeAmount` | `dailyMaxRechargeAmount` |

**超過的處置：直接寫一筆 `status=REJECT` 紀錄（remark="超过单日最高奖励限额"），不是截斷到上限**。白名單與一般用戶分支都走這條規則，差異只在「白名單繞過 `isOverMax` / `isAutoType` / `isBelowMinReview`」。

> 流水佣金（DAILY_COMM）的每日上限是 `MemberCommissionPlan.maxCommissionLimit`，於 `statCommission` 計算時截斷並寫入 `UserCommissionRecord.maxCommissionLimit`（**記錄當下配置值，方案後續變更不回溯**）— 流水這條是**截斷**，與充值的 **REJECT** 行為不同。

---

## 佣金錢包 → 主錢包轉入流程（`UserCommissionMoneyService.transferIn`）

```
1. validateService.validateCommissionTransfer(platformId)   — 檢查 ALL_AGENT_MAIN_SWITCH（全局）+ ALL_AGENT_FLAG（平台），任一 NO → COMMISSION_TRANSFER_FAILED
2. 取 UserInfo (cache)
3. 取 MemberCommissionPlan (per platform + currency)
4. hasRechargePeriod(plan, uid)                              — 檢查 30 天累計充值 ≥ minAccumulateRecharge
5. 取 UserCommission.commission；若 = 0 → INSUFFICIENT_BALANCE
6. 若 commission < plan.minCommissionTransfer → BELOW_MIN_AMOUNT
7. 產 orderNo（OrderNoGenerator.genOrderNo(MEMBER_COMM_TRANSFER)）
8. 若 plan.betAmountMultiple > 0：
     寫 WithdrawCheck（status=0, type=MEMBER_COMM_TRANSFER, feePercentage, validCheckPercentage）
9. changeMoneyLock(userCommission.negate(), isAddTotal=false)  — 樂觀鎖扣除佣金錢包
10. userMoneyService.changeMoney(MEMBER_COMM_TRANSFER, addMoney, lock=false)
       — 主錢包入帳（內部走 SELECT FOR UPDATE）+ 寫 user_bill
```

**整段在 `@Transactional` 內**，任一步驟失敗整筆回滾。

---

## 餘額異動（UserCommissionMoneyService.changeMoney）

> ⚠️ **與主錢包（UserMoney）不同：UserCommission 用「樂觀鎖 CAS」，不用 SELECT FOR UPDATE。** 因為佣金寫入頻率低（每日批次 + 充值即時），衝突少。

### 鎖策略對比

| 方法 | 鎖類型 | SQL 行為 |
|------|--------|---------|
| `changeMoney(uc, isLock=false, addTotal)` | 無鎖 | `UPDATE user_commission SET commission = commission + ?` |
| `changeMoneyLock(uc, addTotal)` | 樂觀鎖（CAS） | `UPDATE user_commission SET commission = commission + ? WHERE commission = oriCommission`，`updateNum != 1` → 拋 `MONEY_CHANGED` |

### 流程（changeMoney with isLock）
```
1. 讀 ori UserCommission（cache 或 DAO）
2. 若 ori + change < 0 → INSUFFICIENT_BALANCE
3. 若 isLock：dao.changeMoney(userId, change, oriCommission, addTotal) 帶舊值 CAS
   否則：    dao.changeMoney(userId, change, addTotal) 直接相加
4. 註冊 TransactionSynchronizationAdapter.afterCommit
     → cacheNotifyService.notifyOne(userId, userCommissionCache)
5. log "佣金金额变更,userId,金額,餘額,信息"
```

### `addTotal` 參數
- `true` → 累加 `total_commission`（歷史總獲取佣金）— 僅在「實際派發」場景用（confirm / retrial / AUTO）
- `false` → 不動 `total_commission` — `transferIn` 扣除時用 false（不算重複入帳）

---

## 黑 / 白名單

| 表 | 用途 | 控制點 |
|----|------|--------|
| `member_commission_black_user` | 黑名單 | unique key `(user_id, type)` — 同用戶可在 type=0 + type=1 各有一列 |
| `member_commission_whitelist` | 白名單 | 一個用戶最多一列（per platform） |

### 黑名單 type 是「不同角色」限制（非攔截強度疊加）

| type | 影響「該用戶當作什麼角色」 | 攔截行為 |
|------|------------------------|---------|
| `0` BET_AMOUNT_LIMIT | **作為下級** | `calPeriodUserCommission` L182-192：該用戶投注**不計入上級的 `totalValidAmount`**（佣金基數，DAILY_COMM 流水佣金） |
| `1` COMMISSION_LIMIT | **作為上級** | (a) DAILY_COMM `calPeriodUserCommission` L240-252：計算後將該用戶 records 抽出標 `status=REJECT` 寫入 `limitRecords`；(b) 充值佣金 `calcRechargeCommission` L241-244：分支第一道直接寫 `status=REJECT`（remark="黑名单"） |

**疊加情境**：同用戶兩列（type=0 + type=1）→ 該用戶當下級時投注不算佣金基數**且**當上級時佣金不發。**兩個獨立軸線**，不是同一行為兩段攔截。

### 寫入端細節

- **單次 `save(typeList=[0, 1])` 可一次寫兩列**；`blackListCheck` 先查本次 typeList 是否已存在，已存在則拋 `BLACK_LIST_TYPE_IS_SETTING`
- **分次寫入無重複保護**：先 `save([0])` 通過 → 再 `save([1])` 時 `queryInType([1])` 找不到 → 通過 → 兩列共存（與單次寫入結果一致）
- **黑白名單雙向互斥**：
  - **加黑名單** 時若 userId 已在白名單 → 拋 `BLACK_LIST_SAVE_ERROR`（`MemberCommissionBlackUserService.blackListCheck` L82-85）
  - **加白名單** 時若 userId 已在**任一 type 的黑名單** → 拋 `WHITELIST_SAVE_ERROR`（`MemberCommissionWhitelistService.blackListCheck` L58-59，呼叫 `isInBlackList(userId, null)` — 第二參數 null = 不限 type）
  - 加白名單時若 userId 已在白名單 → 拋 `WHITELIST_IS_SETTING`（重複保護）

### 白名單行為

- DAILY_COMM：`UserCommissionService` L120 `isWhitelistUser` 觸發 → 走 AUTO（status=4）
- 充值佣金：`calcRechargeCommission` L245 第二道分支 → 繞過 `commissionType` / `commMinReview` / `dailyMaxAutoReview` 全部審核邏輯，**只受 `checkRewardExceeds`（單日上限）阻擋**

### 黑白名單分支優先順序（充值佣金分支）

充值佣金流程依序檢查 **黑 → 白 → 一般用戶**：
- 同用戶同時在黑白名單時 → 走「黑」分支 → REJECT（白名單失效）
- DAILY_COMM 流程沒有「白名單繞過黑名單」這條檢查（兩種限制各自獨立處理）— 路徑不同但結果類似

---

## 核心業務規則

### 規則 1：佣金錢包用樂觀鎖，不用悲觀鎖
- **What**：`UserCommission` 異動走 CAS（帶 `WHERE commission = oriCommission`）；**不**用 `SELECT FOR UPDATE`
- **Why**：佣金寫入頻率低（每日批次 + 充值即時），衝突少，悲觀鎖反而影響吞吐
- **違反風險**：誤加 `SELECT FOR UPDATE` 造成 user_commission 行鎖長期持有，阻塞每日結算批次

### 規則 2：金額一律 BigDecimal + RoundingMode.DOWN
- **What**：所有佣金百分比運算（`commRate * validBetAmount` / `percentage * rechargeAmount`）用 `BigDecimal.multiply().setScale(N, RoundingMode.DOWN)`
- **Why**：佣金屬於「實際入帳」金額，依 [`rules/security.md`](../../../rules/security.md) 必須 DOWN（無條件捨去），避免多給錢
- **違反風險**：累積派多錢；尤其每日批次 × N 平台 × M 用戶會放大

### 規則 3：審核狀態用 `successStatus()` 不要手列
- **What**：判定「已派發」走 `UserCommissionRecord.STATUS.successStatus()` = `[CHECKED, AUTO]`
- **Why**：AUTO 是後加的狀態，舊程式碼只判 CHECKED → 報表少算
- **違反風險**：報表與實際派發金額不一致

### 規則 4：DAILY_COMM 每日上限 snapshot 到 record（**僅 DAILY_COMM 適用**）
- **適用範圍**：**僅 DAILY_COMM**。充值類有獨立的單筆 / 單日上限機制（`maxFirstRechargeAmount` / `dailyMaxRechargeAmount` 等），**超過是 REJECT 而非截斷**（見「金額限制檢查」段），沒有「snapshot 到 record」這個設計
- **What**：`UserCommissionRecord.maxCommissionLimit` 在 `calPeriodUserCommission` L270（`records.forEach(record -> record.setMaxCommissionLimit(maxCommissionLimit))`）**從 plan 複製當下值**，不存方案 ID 後查
- **截斷邏輯（L256-265）**：`commission > maxCommissionLimit` 則 `setCommission(maxCommissionLimit)` + remark「奖励超出上限」；**`netCommission` 不動**（保留截斷前的應發值）— 兩欄位差異的唯一觸發點
- **Why**：方案上限後續調整不應影響歷史紀錄（避免追溯計算）
- **違反風險**：歷史報表金額隨方案改動而漂移，無法稽核

### 規則 5：轉入余額錢包需先做 30 天充值檢查
- **What**：`transferIn` 必先 `hasRechargePeriod(plan, uid)` 檢查近 30 天累計充值 ≥ `minAccumulateRecharge`
- **Why**：避免用戶用代理身分積佣金後直接套現（風控）
- **違反風險**：套利漏洞

### 規則 6：佣金提領流水稽核走 WithdrawCheck
- **What**：`betAmountMultiple > 0` 時 transferIn 須寫一筆 `WithdrawCheck`（status=0, type=MEMBER_COMM_TRANSFER）
- **Why**：提款稽核機制統一走 `withdraw_check` 表，type 區分來源（充值 / 活動 / 佣金轉入）
- **違反風險**：用戶提佣金後可立即提款，繞過流水要求

### 規則 7：充值返佣單日筆數限制走 Redis 計數
- **What**：自動審核次數透過 `MemberLineRechCountLimitRedisCache` 累計，超過 `dailyMaxAutoReview` 轉 PENDING
- **Why**：防止單日連續充值大量自動派發造成風險集中
- **違反風險**：充值佣金洪峰不受控

### 規則 8：memberLineLevel 是「upper 自己在頂層往下數的絕對深度」
- **What**：`UserCommissionRecord.getMemberLevel(userId, memberQueryCode)` 從 `memberQueryCode` 找 userId 的 index 當層級
- **memberQueryCode 格式**：`MergeDataAsyncService` 從 self 沿 upperId 往上爬，用 `Deque.addFirst` 反向拼，最終得到 `"/topUserId/.../upperUserId/selfUserId/"` — **頂層在前、自己在最後，前後都有斜線**。`split("/")` 會拆出 `["", "topId", ..., "selfId"]`（leading "" 佔 index 0，trailing 空字串被 Java 預設 trim 掉），所以 index 從 **1** 起算
- **語意**：值是**絕對深度**（從頂層 HY 算起）— **與 sub 無關**
  - `1` = 頂層 HY 自己（`upperId = 0`）
  - `2` = 頂層的下一級 HY
  - `N` = 第 N 層 HY（鏈尾自己）
  - `0` = **userId 不在 memberQueryCode 中**（fallback；理論上不該發生，傳錯參數或 DL/ZDL 用戶才會出現）
- **呼叫端 pattern 都一樣**：`getMemberLevel(upperUser.userId, upperUser.memberQueryCode)` — **用 upper 自己的 userId + upper 自己的 memberQueryCode**，**不是 sub 的 queryCode**。一筆 record 的 `userId`（收佣金的上級）、`memberLineLevel`（該上級的絕對深度）、`subId`（產生佣金的下級）一致對應同一個 upper
- **邊界**：
  - `memberQueryCode == null` → **NPE**（method 無 null guard）— 呼叫前確認 user 是 `ROLE_TYPE.HY`（`MergeDataAsyncService` L360 只對 HY 設 memberQueryCode；DL / ZDL 為 null）
  - 頂層 HY 的 `memberQueryCode = "/topUserId/"` → `getMemberLevel` 回 `1`（正常）
- **Why**：報表可依 `memberLineLevel` 直接 group by 看「平台付給第 N 層 HY 多少佣金」，不需 join user 表追溯層級
- **違反風險**：
  - 把 `memberLineLevel` 誤解為「sub 相對 upper 的距離」→ 報表 / 分析錯誤
  - 用 sub 的 memberQueryCode 算 → 得到 sub 的深度而非 upper 的深度
  - 對 DL / ZDL 用戶呼叫 → NPE

### 規則 9：所有佣金類型都只發直屬上級 1 人（無多層分潤）
- **What**：
  - **充值佣金（FIRST_RECH_COMM / RECH_COMM）**：`calcRechargeCommission` 取 `rechUser.upperId` 算單一 upper 的金額，寫一筆 record，**無 loop**
  - **DAILY_COMM**：`calPeriodUserCommission` 用 `groupingBy(UserCommissionRecordBO::getUpperId)` 分組，**每個 upper 只看自己直屬下級的有效投注總和**；upper 自己被加到 `settleResultBOs` 但**不會回頭再進下一輪 grouping**（祖父輩不會獲得孫子的分潤）
- **百分比 / 階梯設定都無階梯（按代理層）**：
  - 充值方案只有 `firstRechargePercentage` / `rechargePercentage` 各一組
  - DAILY_COMM 的 `MemberLevelCommission` 是**金額階梯**（見規則 10），非代理層級階梯
- **多層結構僅用於分析**：`memberLineLevel` group by 報表、`topUpperId` 追溯頂層；錢只在直屬上下級流動
- **不觸發的情境**：
  - 充值佣金：`ALL_AGENT_MAIN_SWITCH` / `ALL_AGENT_FLAG` 關 / `rechUser.upperId == 0` / `rechUser.userType == DL` / 充值方式在 `filterRechType`
  - DAILY_COMM：直屬下級在「流水限制」黑名單（type=0）→ 該下級的投注被排除；自己在「佣金限制」黑名單（type=1）→ 計算後標 REJECT 但仍寫 record
- **Why**：產品設計上採單層分潤；多層需求需走獨立設計，**不能**在現有 Service 加 loop
- **違反風險**：
  - 誤以為祖父輩拿得到孫子的佣金 → 客服 ticket / 預期金額對不上
  - 修改 `calcRechargeCommission` 或 `calPeriodUserCommission` 時誤加 loop → 重複發放
  - 用 sub 的視角寫報表 SQL（join 多層）→ 多算金額

### 規則 10：MemberLevelCommission 是「金額階梯」非「代理層級階梯」
- **What**：`memberLevelCommissions.sort(Comparator.comparing(MemberLevelCommission::getBetAmount))` 按 `betAmount` 排序，`computeCommission` 用 `bo.totalValidAmount`（直屬下級投注總和）對照階梯找 `commRate`
- **欄位意義**：
  - `bet_amount`：達到此金額門檻可享的 commRate
  - `comm_rate`：對應百分比
  - `name`（銅牌 / 銀牌 / 金牌之類）：給管理員看的金額等級名稱
- **計算公式**（L390-391）：
  ```
  commission = totalValidAmount × commRate / 100
               .divide(100, 4, HALF_UP)    // 中間值 4 位
               .setScale(2, DOWN)          // 最終 DOWN 到 2 位（符合 security.md 金額入帳 DOWN 規則）
  ```
- **Why**：投注額階梯獎勵越投越多的下級網絡，與代理層級無關
- **違反風險**：
  - 誤以為 commRate 隨層級遞減（多層分潤模型常見設計）→ 報表 / 分析錯誤
  - 改 `computeCommission` 時誤加「按 memberLineLevel 取階梯」邏輯 → 與現有資料不相容

### 規則 11：跨版本報表查詢必須指定 `version=1`
- **What**：新版（v1）DB 存 `lineCommission=0` / `subCommission=0` / `betAmountReward=0`；前端 VO 在 `UserCommissionRecordService.java:565` 用 `if (memberCommQuery.getVersion() == 1) vo.setLineCommission(record.getNetCommission())` 才把 lineCommission 補回
- **不指定 version 的查詢行為**：
  - `UserCommissionRecordDao` 用 `.andEqual("version", query.getVersion())` — null 時框架不加 WHERE → **回傳所有版本（新舊混合）**
  - L565 `if (memberCommQuery.getVersion() == 1)` 對 null 不成立 → **新版資料的 lineCommission 永遠保留 DB 原值 0**
  - 結果：`totalCommAmount += vo.getLineCommission()` 把新版加總成 0，**只算到舊版的 lineCommission**
- **正確用法**：
  - 看新版資料 → query 帶 `version=1`，補值生效
  - 看舊版資料 → query 帶 `version=0`，直接讀 DB 原值
  - **禁止 version=null 的混合查詢**（除非報表明確要全期間且能各自處理新舊邏輯）
- **Why**：改版時保留舊資料完整性（不 backfill），代價是查詢端必須明確選版本
- **違反風險**：
  - 新版報表 `lineCommission` 加總為 0 → QA / PO 反映「為什麼今天結算的佣金總額是 0？」
  - 跨版本聚合用同一加總邏輯 → 舊版有值、新版 0，數字不一致

---

## 快取設計

### L2 CacheService（Guava + Kafka 失效）
| Cache | 用途 | 失效時機 |
|-------|------|---------|
| `UserCommissionCache` | 用戶佣金錢包餘額 | `changeMoney` 後 `afterCommit` 透過 `cacheNotifyService.notifyOne` 刷新 |
| `MemberCommissionPlanCache` | 平台流水佣金方案 | 後台修改方案後 invalidate |
| `RechargeCommissionConfigCache` | 平台充值佣金方案 | 同上 |

### Redis Cache
| Class | Key 格式 | 用途 |
|-------|---------|------|
| `MemberDailyStatReportRedisCache` | `<KEY>:YYYYMMDD:platformId:userId` | 每日報表暫存 |
| `UserCommLevelRedisCache` | `<KEY>:YYYYMMDD:platformId:userId` | 用戶當日所屬等級（避免結算重算） |
| `MemberLineRechCountLimitRedisCache` | `<KEY>:platformId:userId:YYYYMMDD` | 充值返佣自動審核當日筆數 |
| `MemberDailyVipCountRedisCache` | `<REG_KEY/RECH_KEY>:platformId:YYYYMMDD` | 註冊 / 充值人數彙總 |
| `MemberMonthStatReportRedisCache` | per platform + user + month | 月報表 |
| `UserCommMonthRedisCache` | per user + month | 月匯總供前台查詢 |

---

## 排程

| Job | Service | 用途 |
|-----|---------|------|
| `MemberLineSettleJobService` | 觸發 `UserCommissionService.statCommission` | 每日結算流水佣金，遍歷各 platform 與 statDate |

充值佣金為即時觸發（充值成功 → `RechargeCommissionService.calcRechargeCommission`），非排程。

---

## 常見錯誤模式

### 錯誤 1：用 SELECT FOR UPDATE 改寫 changeMoney
- **症狀**：每日結算批次與用戶 transferIn 相互阻塞，CPU 等待飆高
- **原因**：誤套主錢包（UserMoney）的悲觀鎖規範
- **修正**：UserCommission 用樂觀鎖 CAS；`updateNum != 1` 拋 `MONEY_CHANGED` 由上層 retry 或回滾

### 錯誤 2：報表只統計 status=CHECKED
- **症狀**：報表金額 < 實際派發金額
- **原因**：忽略 `AUTO`（自動派發也是已發放）
- **修正**：用 `successStatus()` 取得 `[CHECKED, AUTO]` 列表查詢

### 錯誤 3：方案改動後歷史報表金額變化
- **症狀**：昨日報表今天看金額對不上
- **原因**：報表查詢未用 `UserCommissionRecord.maxCommissionLimit` snapshot 值，跑去 join 當前方案
- **修正**：報表一律讀 record 上的 snapshot 欄位（maxCommissionLimit / commRate）

### 錯誤 4：使用新版不再寫入的欄位
- **症狀**：新功能算錯，或新版 record 上這些欄位都是 0
- **原因**：誤用 `subCommission` / `lineCommission` / `betAmountReward` — 新版（version=1）DB 存 0；只有舊版（version=0）歷史資料可能有值
- **修正**：用 `commission`（實派）+ `netCommission`（應發）；流水獎勵走 `commRate`；報表查新版資料時前端依 L565 補回 `lineCommission = netCommission`（見規則 11）

### 錯誤 5：transferIn 漏寫 WithdrawCheck
- **症狀**：開了 betAmountMultiple 但用戶轉入後可直接提款
- **原因**：條件判斷時用 `betAmountMultiple == 0`，但欄位可能為 `null`（早期資料）
- **修正**：用 `Objects.nonNull(plan.getBetAmountMultiple()) && !plan.getBetAmountMultiple().equals(Switch.no.getValue())`

### 錯誤 6：層級 index 取錯
- **症狀**：佣金發給錯誤的上線
- **原因**：手動切 `memberQueryCode` 而沒走 `getMemberLevel`
- **修正**：呼叫 `UserCommissionRecord.getMemberLevel(userId, memberQueryCode)`

### 錯誤 7：誤以為佣金會發給多層上級
- **症狀**：QA / PO 反映「為什麼 A 充值（或投注），A 的上上級 C 沒拿到佣金？」
- **原因**：把「全民代理 = 多層分潤」的概念套到 memberline；實際上**整個系統都是單層分潤**（見規則 9）— 充值與流水佣金都只發直屬上級
- **修正**：跟需求方確認預期；若真要多層，**不能**加 loop 改 `calcRechargeCommission` 或 `calPeriodUserCommission`（會影響既有計算 + 與 ES 報表 / `member_daily_stat_report` 資料模型不相容）— 應走獨立的「多層分潤」需求重新設計

### 錯誤 8：upperUser 為 null 的 NPE
- **症狀**：充值流程 NPE，trace 指向 `RechargeCommissionService.calcRechargeCommission` L188 之後
- **原因**：`rechUser.upperId` 指向已刪除 / 已停用的 user，`userService.getUserInfoByUserId(rechUper.getUpperId())` 回 null，後續 `upperUser.getUserId()` 炸
- **修正**：呼叫前 null check；不確定能不能直接 return（可能影響業務） → 走稽核 / 補上預設處理跟 PO 確認

### 錯誤 9：報表查詢未過濾 version 導致新舊版混算
- **症狀**：新版佣金 record 已寫入 DB，但前端報表 `totalCommAmount` 為 0 或遠低於預期
- **原因**：`memberCommQuery.getVersion()` 為 null → L565 補值不生效，新版 record 的 `lineCommission` 從 DB 讀回 0，加總當然是 0
- **修正**：查詢端強制帶 `version=1`；若 SO 或 query 有預設值，檢查預設是否為 null（檢查前端傳值與 Controller 接收）
- **延伸檢查**：舊版資料若混入新版報表，數字會比預期多 → 統一報表需明確切分版本，**不要假設「資料只有一種版本」**

---

## 相關檔案（grep 起點）

### Service（`cx-sport-app-service/src/main/java/com/lc/cp/service/memberline/`）
- `UserCommissionService` — 每日流水佣金主計算（`statCommission`）
- `UserCommissionRecordService` — 紀錄審核 / 查詢（`confirm` / `reject` / `retrial` / `auto`）
- `UserCommissionMoneyService` — 佣金錢包異動 + transferIn
- `RechargeCommissionService` — 充值佣金計算（即時觸發）
- `MemberCommissionPlanService` — 平台方案 CRUD
- `MemberCommissionBlackUserService` / `MemberCommissionWhitelistService` — 黑白名單
- `MemberDailyStatService` / `MemberDailyStatReportService` — 每日統計
- `MemberLineDashboardService` — 前台用戶儀表板（個人佣金摘要 / 下級概況）
- `BatchUserCommissionRecordService` — 批次處理

### Controller
- `controller/admin/memberline/` — 後台管理（UserCommissionRecord / Plan / Whitelist / BlackUser / RechargeConfig / DailyStatReport）
- `controller/front/MemberAgentController` — 前台登入用戶完整功能（7 個端點：queryPlan / overview / transferIn / queryLowerBetComm / queryFriendComm / queryLowerRechComm / queryMonth）
- `controller/front/whitelist/MemberAgentController` — 路徑層鑑權白名單版（前綴 `/api/front/wl/`，被 `application.yml uri.white.list2` 列入跳過 filter），**僅 1 個端點 queryPlan**（最小佣金方案查詢）；內部仍 `getUserInfoByCheckToken`。**與業務的「白名單用戶」是兩回事**，見「易混淆名詞」段

### DAO / Model / Bean
- `common/dao/memberline/` — 10 個 DAO 對應 10 張表
- `common/bean/model/memberline/` — 模型類
- `common/bean/vo/memberline/` — 前端展示 VO
- `common/bean/so/memberline/` — 跨層 SO
- `common/bean/bo/memberline/` — 業務中間態 BO
- `common/bean/query/memberline/` — 查詢參數

### Cache / Redis
- `common/cache/memberline/` — L2 Guava cache
- `common/redis/memberline/` — Redis cache

### Job
- `cx-sport-app-service/.../job/service/statistic/memberline/MemberLineSettleJobService` — 每日結算

### 前端
- `lion-frontend/admin-frontend/src/components/memberline/` — 13 個 Vue 元件

---

## 相關 SQL 入口

```sql
-- 用戶當前佣金錢包餘額
SELECT * FROM user_commission WHERE user_id = ?;

-- 用戶佣金紀錄（含已派發）
SELECT * FROM user_commission_record
WHERE user_id = ? AND status IN (1, 4)  -- CHECKED + AUTO
ORDER BY stat_date DESC;

-- 平台流水佣金方案 + 等級階梯
SELECT p.*, lc.bet_amount, lc.comm_rate
FROM member_commission_plan p
LEFT JOIN member_level_commission lc ON lc.plan_id = p.id
WHERE p.platform_id = ? AND p.currency = ?
ORDER BY lc.bet_amount;

-- 每日報表
SELECT * FROM member_daily_stat_report
WHERE platform_id = ? AND stat_date = ? AND user_id = ?;
```

---

## 對接其他模組

| 對接模組 | 方式 | 資料流 |
|---------|------|--------|
| `user` | 直接呼叫 | 用戶註冊 → `createUserCommission`；層級依 `memberQueryCode` 解析 |
| `recharge` | 直接呼叫 | `UserRechService` 充值成功 → `calcRechargeCommission` |
| `usermoney` | 直接呼叫 | `transferIn` 把佣金扣除 → `userMoneyService.changeMoney(MEMBER_COMM_TRANSFER)` |
| `withdraw / uw_check` | 直接呼叫 | `transferIn` 若 `betAmountMultiple > 0` → `withdrawCheckService.saveWithdrawCheck` |
| `bet` | DAO 讀 | 每日結算讀有效投注金額（透過 ES / MySQL 報表 DAO） |
| `setting (validateService)` | 直接呼叫 | `transferIn` L73 呼叫 `validateCommissionTransfer(platformId)`（`ValidateService` L57-64）— 同時檢查兩層開關：`ALL_AGENT_MAIN_SWITCH`（全局主開關，per `ServiceConst.PLAT_ID`）+ `ALL_AGENT_FLAG`（平台級，per `platformId`），**任一為 NO 拋 `COMMISSION_TRANSFER_FAILED`**。與 `calcRechargeCommission` L148-156 共用同一套 gating 機制 |

---

## 相關 Agent 與 Skill

- **L1 風險領域**（涉金額 / 狀態機 / 結算 / 樂觀鎖）→ `code-reviewer` + `java-reviewer` + `business-reviewer` 三方平行
- 涉及 SQL / 報表查詢 → 加 `database-reviewer`
- 第三方對接（充值返佣依賴充值 callback）→ 加 `security-reviewer`
- 規格預審 → `spec-review` skill
- 金額處理規範 → [`rules/security.md`](../../../rules/security.md)
- 雙層快取 → [`rules/patterns.md`](../../../rules/patterns.md) §6.5

---

## DB 清理

- `user_commission_record` 屬於金流類紀錄，**不走** `history_data_clear_config` 自動清理
- 每日報表（`member_daily_stat_report`）保留期依平台合規要求，預設長期保留
