---
name: api-connector-builder
description: 依照目標 repo 現有整合模式，建置新的 API 連接器或 Provider。用於新增整合時對齊既有架構，而非發明第二套架構。
origin: ECC direct-port adaptation
version: "1.1.0"
---

# API 連接器建置器（crypto-payment）

用於新增符合 repo 原生整合風格的介面，而非僅建立通用 HTTP 客戶端。
本專案的整合面主要有兩類：**鏈上 webhook 供應商**（QuickNode / Tatum）與**區塊鏈客戶端**（Web3j / Trident）。

核心原則是對齊宿主 repo 的模式：

- 連接器檔案配置
- 設定 schema（config 表 + setting 層）
- 認證 / 驗簽模型
- 錯誤處理與冪等
- 測試風格（JUnit 5）
- 註冊 / 發現機制

## 適用時機

- 「接一個新的鏈上 webhook 供應商」
- 「照現有 Provider 模式新增第三方對接」
- 「支援新的鏈 / 新的鏈上客戶端」
- 「建一個符合 repo Provider 風格的實作」

## 防護欄

- repo 已有整合架構時，不要發明新的架構
- 不要只從供應商文件出發；先從 repo 內現有連接器（`controller/thirdparty/`、`service/setting/`、既有 chain client）開始
- 不要只寫傳輸層就停手 — repo 預期包含設定來源、驗簽、冪等、註冊、測試
- **不可混用鏈客戶端**：BSC / ETH 走 Web3j，TRON 走 Trident，各鏈分開
- webhook 入款**必須冪等**：同一鏈上交易重送不可重複入帳

## 工作流程

### 1. 學習既有風格

檢視至少 2 個現有連接器 / Provider，並記錄：

- 檔案配置（`controller/thirdparty/`、`service/setting/`、`service/system/`）
- 抽象邊界（webhook 接收 vs 鏈上讀寫）
- 設定模型（config 表欄位 → `*ConfigCache` → setting 層）
- 重試 / 分頁 / 輪詢慣例
- 驗簽掛載點（`filter/`、webhook handler）
- 測試 fixture 與命名（既有 QuickNode webhook 測試、HMAC 驗簽測試）

### 2. 界定目標整合範圍

僅定義 repo 實際需要的介面：

- 認證 / 驗簽流程（webhook 簽名、IP 白名單）
- 關鍵實體（chain log / tx / wallet / deposit event）
- 核心讀寫（讀鏈上餘額 / 送交易 / 接 webhook 通知）
- 輪詢 vs webhook 模式
- 速率限制 / 供應商配額

### 3. 依 repo 原生分層建置

典型分層：

- 設定 / schema（config 表 + `service/setting/`）
- 客戶端 / 傳輸層（Web3j / Trident / webhook 接收 controller）
- 對應層（chain log → 內部 BO / VO）
- 連接器 / Provider 進入點
- 驗簽 + 冪等處理
- 測試

### 4. 對照來源模式驗證

新連接器在 codebase 中應看起來理所當然，而非從其他生態系移植過來。

## 參考結構（crypto-payment 實況）

> 本專案**未採統一 Provider 註解框架**；webhook 供應商與鏈客戶端依性質分屬不同層。新整合**先選最接近的既有模式**，照其慣例寫，**不要發明第二套**。

### 模式 A — 鏈上 webhook 供應商接收（QuickNode / Tatum）

適用：外部供應商主動推送鏈上事件（入款偵測）。

```text
com.lion.crypto/
  controller/thirdparty/
    XxxWebhookController.java     # /api/thirdparty/* 入口，先驗簽 / IP 白名單
  filter/
    (webhook 驗簽掛載點)          # 簽名 / HMAC 驗證
  service/system/
    ChainLogService.java          # 解析 chain log → 匹配錢包(帶 platform_id) → 入帳
  service/setting/
    (vendor 設定：供應商 key / URL / 簽名密鑰)
  event/
    (入帳後觸發下游 Kafka event)
```

入款流程：webhook 收到 → 驗簽 → 解析 chain log → 匹配錢包 → 入帳用戶 → 觸發下游 Kafka event。**冪等**依交易唯一鍵（tx hash + log index）。

### 模式 B — 區塊鏈客戶端（Web3j / Trident）

適用：主動讀鏈 / 送交易（餘額查詢、歸集 sweep、出款）。

```text
com.lion.crypto/
  service/user/ | service/system/
    (呼叫鏈客戶端：Web3j for BSC/ETH、Trident for TRON、BitcoinJ)
  service/setting/
    (chain 設定：RPC endpoint、gas、confirmations、最小歸集門檻)
  utils/
    (25 個工具類 — 新增前先查是否已有；含 AES-GCM 私鑰加解密)
```

- **鏈專屬 client 不可混用**：BSC/ETH → Web3j 4.9.4、TRON → Trident 0.10.0、BTC → BitcoinJ
- 送交易需用私鑰簽名：私鑰解密（AES-GCM）僅在記憶體，用後即棄，禁落地 / 禁入日誌

### 共用慣例（兩模式皆適用）

- **設定來源**：config 資料表 + `service/setting/` 讀取 + `*ConfigCache`（Redis 預載），**不硬編碼** API key / secret / RPC URL
- **DI**：新類別用建構子注入（`@RequiredArgsConstructor` + `private final`），**禁 `@Autowired` 欄位注入**
- **回應**：一律 `BaseResponse<T>` 包裝；例外用既有自訂 exception，禁裸 `RuntimeException`
- **事務**：改狀態的 service 方法必須 `@Transactional`；DB 寫入後同事務內或緊接更新 Redis
- **DAO**：走既有 `repository/` DAO 風格；ShardingSphere 5.4 自動讀寫分離，不手動路由
- **多租戶**：所有查詢帶 `platform_id`，跨平台存取 = critical bug
- **驗簽不繞過**：`/api/pay/*` 走 SignFilter；`/api/thirdparty/*` webhook 驗簽 / IP 白名單
- **日誌**：`@Slf4j` + SLF4J，訊息英文，禁記私鑰 / key / 簽章原文

## 品質檢查清單

- [ ] 對齊 repo 內現有的整合模式（webhook 接收 or 鏈客戶端）
- [ ] 設定從 config 表 + `*ConfigCache` 讀取，無硬編碼
- [ ] 認證 / 驗簽（webhook 簽名 / IP 白名單 / HMAC）明確定義
- [ ] 入款冪等（tx hash + log index 去重）
- [ ] 鏈客戶端未混用（Web3j / Trident 分鏈）
- [ ] 私鑰處理走 AES-GCM，未落地 / 未入日誌
- [ ] 所有查詢帶 platform_id
- [ ] 測試風格與 repo 一致（JUnit 5 + Mockito）
- [ ] 如 repo 預期，文件 / 範例已更新

## 相關 Skill

- `springboot-security`（私鑰 / HMAC / 驗簽 / 金額）
- `springboot-tdd`（JUnit 5 測試骨架、既有 webhook / HMAC 測試範本）
