---
name: business-notice
description: 站內信 / 系統公告領域 — 用戶通知（UserNotice）、公告推送（PushMessage）、模板管理（UserNoticeTemp）、WebSocket 即時推送。涉及站內信、通知、系統公告、消息中心時載入。
origin: project
status: ready
---

# 站內信 / 通知（Notice）

>

`notice` domain 包含兩個子系統：
1. **UserNotice（站內信）** — 針對單一用戶的個人訊息（充值成功、提款結果、活動獎勵、KYC 結果…），寫入 `user_notice` 表，透過 WebSocket 即時推送。
2. **PushMessage（系統公告）** — 針對全平台 / 特定充值等級用戶的廣播式公告，寫入 `push_message` 表，支援分類、排序、多 Locale。

兩者共用 `notice` service 子目錄，前端呈現在「消息中心」頁面。

---

## 適用時機

- 新增通知觸發點（如新業務事件要發站內信）
- 修改通知展示類型或模板格式
- 調整公告分類（MSG_TYPE）或展現位置（PUSH_MESSAGE_TYPE）
- 調試 WebSocket 即時推送不到位問題
- 審查涉及 notice 的 PR

---

## 領域概念

### 核心實體

| 實體 | 說明 | 對應資料表 |
|------|------|-----------|
| `UserNotice` | 個人站內信（1 對 1） | `user_notice` |
| `UserNoticeTemp` | 站內信草稿模板（admin 預設，確認後批量送出） | `user_notice_temp` |
| `PushMessage` | 平台廣播公告（1 對多） | `push_message` |
| `PushMessageUser` | 用戶閱讀狀態記錄 | （關聯表） |

### 關鍵欄位語義（UserNotice）

- **`noticeType`**：`0` = 消息通知；`1` = APP 推送
- **`msgShowType`**：展現方式，見 `MessageEnum.MSG_SHOW_TYPE`
  - `1` 用戶消息中心（站內信列表）
  - `2` 右下角提醒
  - `3` 頁面中央彈窗
  - `4` APP 推送
  - `5` 新版彈窗
- **`status`**：`0` = 成功；`1` = 失敗（用於充值/提款結果通知）
- **`isRead`**：`0` = 未讀；`1` = 已讀
- **`popupType`**：彈窗業務類型，見 `MessageEnum.POPUP_TYPE`（充值/提現/反水/中獎/後台加錢/免費旋轉）
- **`popupAmount`**：彈窗金額（`BigDecimal`，搭配 `popupType` 使用）

### 關鍵欄位語義（PushMessage）

- **`type`**：展現類型（`PUSH_MESSAGE_TYPE` Enum）
  - `1` BOTTOM_CENTER — 投注區底部公告（最新消息跑馬燈）
  - `2` LOGIN_TYPE — 登入後彈窗
  - `3` NOT_LOGIN_TYPE — 未登入彈窗
- **`msgType`**：公告分類（`MSG_TYPE` Enum）
  - `1` GAME_NOTICE 遊戲公告
  - `2` HY_WELFARE 會員福利
  - `3` TRANFER_NOTICE 轉帳須知
  - `4` HOT_RECOMMEND 勁爆推薦
  - `5` NAV 導航網
  - `6` OTHER 其他
- **`messageType`**（前端分頁用，非 DB 欄位，查詢時動態 set）：
  - `0` 全部
  - `1` 系統公告
  - `2` 平台公告
  - `3` 遊戲公告
- **`rechLevels`**：目標充值等級（逗號分隔，空 = 全部）
- **`status`**：`0` = 草稿；`1` = 上線
- **`isAllRead`**：是否全體已讀（管理後台用）
- **`uniqueNo`**：冪等唯一號（刪除時用此 key，避免 ID 衝突）

---

## 模板確認流程（UserNoticeTemp）

```
admin 建立草稿 (preSaveUserNoticeTemp)
   ↓ status=0（待確認）
confirmUserNoticeTemp(id) — 取 Redis 鎖（60s TTL）
   ↓ 依 noticeType（RangeType）查對應用戶
   ↓ 批量建 UserNotice（內容依用戶語系做 i18n）
   ↓ if APP_TYPE → pushService.pushList（極光推送）
     else        → websocketService.sendUsersNoticeList（WS 推送）
   ↓ status=1（已確認，不可重複確認）
```

### 模板用戶範圍（`noticeType` / `RangeType` Enum）

| RangeType | 含義 | 額外查詢條件 |
|-----------|------|-------------|
| `PARTIAL` | 指定用戶名單（`refer` = 逗號分隔 username） | `currency`（可選） |
| `ALL` | 全平台用戶 | `currency`（可選）；同時推未登入設備（`appDeviceNoLoginService`） |
| `ONLINE` | 近 1 天登入 + 現在在線 | `currency`（可選）；透過 `loginCache.getOnLineUsers` 交集 |
| `RECHLEVEL` | 指定充值等級（`refer` = rechLevel ID） | `currency`（可選） |

**isRead 規則：** `MSG_SHOW_TYPE` 為 `MESSAGE_CENTER`（1）/ `REMIND_TYPE`（2）/ `APP_TYPE`（4）時 `isRead=0`（未讀）；其他展示類型（中央彈窗等一次性）`isRead=1`（已讀）。

| 狀態值 | 含義 |
|--------|------|
| `0` | 草稿，待確認 |
| `1` | 已確認送出 |

**關鍵規則：** `confirmUserNoticeTemp` 以 `userNotice_{id}_confirmUserNoticeTemp` 為 Redis 鎖 key + `status=1` 雙重冪等，防止重複確認。

---

## 通知觸發來源對照

| 業務事件 | 觸發方法 | 誰呼叫 |
|---------|---------|--------|
| 用戶註冊 | `saveRegisterNotice` | `UserService` |
| 充值成功 | `saveRechNotice` | `UserService`（回調後） |
| 提款結果 | `saveWithdrawNotice` | `PayNotifyService`（回調後） |
| 信貸放款 | `saveLoanNotice` | `XinDaiBaRecordService` |
| 活動獎勵 | `saveActivityRewardNotice` | `ActivityRewardRecordService` |
| KYC 審核結果 | `kycResultNotice` | `UserService` |
| APP 下載活動 | `saveAppDownloadActivityNotice` | — |
| 免費旋轉 | `saveFreeSpinNotice` | `FreeSpinRecordService` |
| 獎勵駁回 | `saveAwardRejectNotice` | — |

---

## 推送鏈路

```
業務事件觸發
   │
   ▼
UserNoticeService.saveXxxNotice()
   ├─ 寫 user_notice DB
   ├─ UserNoticeRedis.saveNotice()   — Redis Hash key: {prefix}:user_notice:{userId}，TTL 12h
   │       └─ cacheNotifyService.notifyOne()  — 通知 memdb 更新緩存
   ├─ WebsocketService.sendUserNotice()   — WS 即時推送單一用戶
   └─ PushService.pushRechNotice / pushWithdrawNotice  — APP Push（充提才有）
```

**注意：** `confirmUserNoticeTemp`（批量）額外呼叫 `sendUsersNoticeList` + `pushList`（群發）。

---

## 核心業務規則

### 規則 1：Redis 快取 + WebSocket 雙通道
- **What**：每次寫入站內信，同時寫 Redis Hash `{prefix}:user_notice:{userId}`，並透過 `cacheNotifyService.notifyOne` 刷新 memdb，再 WS 推送
- **Why**：前端連線後輪詢快取，斷線重連也能取到未讀消息
- **違反風險**：漏推送（用戶看不到新消息）或快取不一致（舊消息未清除）

### 規則 0（補充）：APP Push 金鑰來源
- 極光推送（JPush）設定從 config 表讀取：`jpushUrl`（請求地址）、`jpushAppKey`（AppKey）
- 透過 `*ConfigCache` 預載，**禁硬編碼**

### 規則 2：模板確認冪等保護
- **What**：`confirmUserNoticeTemp` 必須先搶 Redis 鎖，確認後 `status=1`，同一模板禁止重複確認
- **Why**：防止批量站內信重複發送
- **違反風險**：用戶收到重複通知，影響體驗

### 規則 3：彈窗金額必用 BigDecimal
- **What**：`popupAmount` 欄位存 `BigDecimal`，`+RoundingMode.DOWN`
- **Why**：充值/提款金額顯示精度問題
- **違反風險**：前端顯示金額錯誤

### 規則 4：公告按充值等級過濾
- **What**：`PushMessage.rechLevels` 為空 = 全體；非空 = 僅對應等級用戶可見
- **Why**：VIP 專屬福利公告不應曝光給非 VIP
- **違反風險**：公告曝露給不符合資格的用戶

### 規則 5：公告 uniqueNo 為刪除鍵
- **What**：刪除 `PushMessage` 時用 `uniqueNo`，不用 `id`
- **Why**：多個 Locale 版本共用同一邏輯公告，刪一次清全部
- **違反風險**：按 id 刪只刪一個 locale，殘留其他語言版本

---

## 快取設計

| 快取層 | Key | TTL | 說明 |
|--------|-----|-----|------|
| Redis Hash | `{prefix}:user_notice:{userId}` | 12h（含隨機抖動） | 用戶未讀通知清單 |
| `PushMessageCache` | 平台維度 | 見 PushMessageCache | 平台公告快取 |
| `UserNoticeCache` | 用戶維度 | 見 UserNoticeCache | 用戶站內信快取 |

`getNoticeFromCacheAndClear`：讀取 Redis 快取後**立即清除**，由 WebSocket 連線時呼叫（一次性投遞語義）。

---

## 常見錯誤模式

### 錯誤 1：模板重複確認
- **症狀**：用戶收到重複站內信
- **原因**：未搶 Redis 鎖，或鎖過期後並發呼叫 `confirmUserNoticeTemp`
- **修正**：確認 `status=0` WHERE 條件 + Redis 鎖雙重保護

### 錯誤 2：新增通知觸發點漏 WebSocket 推送
- **症狀**：站內信寫入 DB 但用戶即時未收到
- **原因**：只呼叫 DAO 存資料，未呼叫 `websocketService.sendUserNotice()`
- **修正**：仿照 `saveRechNotice` 流程：寫 DB → 寫 Redis → WS 推送

### 錯誤 3：公告 msgType 填錯導致前端分類錯誤
- **症狀**：公告出現在錯誤的消息中心分頁
- **原因**：`msgType`（DB 欄位）vs `messageType`（前端動態查詢參數）混淆
- **修正**：`msgType` 對應 `MessageEnum.MSG_TYPE`；`messageType` 是查詢入參，不存 DB

---

## 相關檔案（grep 起點）

- Service：`cx-sport-app-service/src/main/java/com/lc/cp/service/notice/`
  - `UserNoticeService` — 站內信核心業務
  - `PushMessageService` — 公告查詢與分類邏輯
  - `PushService` — APP 推送（充提）
  - `MessageV1Service` — 舊版訊息（仍在線上使用）
  - `PushMessageUserService` — 公告閱讀狀態（前台點擊公告後呼叫 `api/front/user/message/readed` → `PushMessageUserService.readed`）
- Controller：
  - `cx-sport-app-service/.../controller/admin/UserNoticeController` — 後台管理
  - `cx-sport-app-service/.../controller/front/UserNoticeController` — 前台讀取 / 標已讀
  - `cx-sport-app-service/.../controller/center/PushMessageController`
  - `cx-sport-app-service/.../controller/front/MessageCenterController`
- DAO：`cx-sport-app-service/src/main/java/com/lc/common/dao/notice/`
- 快取：`cx-sport-app-service/src/main/java/com/lc/common/cache/notice/`
- Redis：`cx-sport-app-service/src/main/java/com/lc/common/redis/UserNoticeRedis`
- Enum：`cx-sport-app-service/src/main/java/com/lc/common/constants/enums/MessageEnum`
- Redis Key：`RedisKey.USER_NOTICE = PROJECT_PREFIX + "user_notice"`

---

## 對接其他模組

| 對接模組 | 方式 | 資料流 |
|---------|------|--------|
| `user` | 直接呼叫 | 註冊 / 充值成功 / KYC 後觸發通知 |
| `pay` | 直接呼叫 | 充值 / 提款回調後觸發通知 |
| `freespin` | 直接呼叫 | 免費旋轉發放後觸發通知 |
| `websocket` | `WebsocketService.sendUserNotice` | WS 即時推送給單一用戶 |
| `websocket` | `WebsocketService.sendUsersNoticeList` | WS 批量推送（模板確認時） |
| `push（APP）` | `PushService` | 充提結果 APP 推送 |
| `memdb` | `CacheNotifyService.notifyOne` | 通知 memdb 刷新用戶快取 |

---

## 相關 Agent 與 Skill

- 新增通知觸發點 / 模板格式變更 → L2，`code-reviewer` + `java-reviewer`
- 涉及金額彈窗（`popupAmount`）→ 升 L1，加 `business-reviewer`
- WebSocket 推送鏈路修改 → 加 `cx-sport-websocket-service` 模組範圍

---

## DB 清理

站內信 / 公告歷史資料由統一清理機制管控：

- **清理設定表**：`history_data_clear_config`
- **保留期限**：70 天
- 不需手動刪除，清理 Job 依此表設定自動執行

---

