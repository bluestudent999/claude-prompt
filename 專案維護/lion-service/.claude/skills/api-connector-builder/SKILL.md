---
name: api-connector-builder
description: 依照目標 repo 現有整合模式，建置新的 API 連接器或 Provider。用於新增整合時對齊既有架構，而非發明第二套架構。
origin: ECC direct-port adaptation
version: "1.1.0"
---

# API 連接器建置器

用於新增符合 repo 原生整合風格的介面，而非僅建立通用 HTTP 客戶端。

核心原則是對齊宿主 repo 的模式：

- 連接器檔案配置
- 設定 schema
- 認證模型
- 錯誤處理
- 測試風格
- 註冊 / 發現機制

## 適用時機

- 「對接新的第三方服務商 XXX」
- 「照現有寫法新增一家簡訊 / 支付 / 遊戲供應商」
- 「為這個第三方 API 建立新的整合」
- 「建一個符合 repo Provider 風格的實作」

## 防護欄

- repo 已有整合架構時，不要發明新的架構
- 不要只從第三方服務商文件出發；先從 repo 內現有連接器開始
- 如果 repo 預期包含註冊機制、測試和文件，不要只寫傳輸層程式碼就停手
- 如果 repo 有較新的模式，不要盲目複製舊連接器的寫法

## 工作流程

### 1. 學習既有風格

檢視至少 2 個現有連接器 / Provider，並記錄：

- 檔案配置
- 抽象邊界
- 設定模型
- 重試 / 分頁慣例
- 註冊掛載點
- 測試 fixture 與命名

### 2. 界定目標整合範圍

僅定義 repo 實際需要的介面：

- 認證流程
- 關鍵實體
- 核心讀寫操作
- 分頁與速率限制
- Webhook 或輪詢模式

### 3. 依 repo 原生分層建置

典型分層：

- 設定 / schema
- 客戶端 / 傳輸層
- 對應層（mapping）
- 連接器 / Provider 進入點
- 註冊機制
- 測試

### 4. 對照來源模式驗證

新連接器在 codebase 中應看起來理所當然，而非從其他生態系移植過來。

## 參考結構（lion 實況）

> lion **沒有統一的 Provider 註解框架**（repo 內查無 `@ThirdPartyComponent` 之類），不同模組依業務性質採用不同模式。新整合**先選最接近的既有模式**，照同類實作寫，**不要發明第二套**。先讀該模組的 `CLAUDE.md`（`cp-service/CLAUDE.md`、`single-wallet-service/CLAUDE.md`、`collector-service/CLAUDE.md`，都在 repo 內）。

### 模式 A — 註解 + Context 路由（**single-wallet-service**，金額敏感度最高）

適用：廠商單一錢包的交易類型（下注 / 結算 / 取消…）。

```text
com.lc.single.wallet/
  service/singlewallet/impl/
    SingleWalletRoundBetService.java        # @SingleWalletType(EnumClass.TranType.SINGLE_WALLET_ROUND_BET)
    AbstractSingleWalletService.java        # 共用金額流程
    ...
  context/
    SingleWalletContext.java                # ApplicationRunner 啟動掃描，Map<TranType, SingleWalletService>
  controller/third/
    ThirdController.java                    # 入口，依 TranType 從 context 取對應 service
  filter/
    SingleWalletSignFilter.java             # 驗簽（+ PlatformSignVerifier）
  constants/
    RespStateEnum.java                      # 回廠商的狀態碼 = 對接合約
```

- 新增交易類型：照 `single-wallet-service/CLAUDE.md` §新增一種交易類型 SOP；`TranType` 在 lion-common `EnumClass`（跨 repo）
- **禁止 switch / if-else 路由交易類型**，一律 `@SingleWalletType` 註冊
- 回廠商**一律 HTTP 200、錯誤碼在 body**；`RespStateEnum` 改動要回歸所有廠商
- 金額流程（鎖 → 事務 → 鎖定行 → 驗 → 扣 / 加 → 寫流水 → commit → 釋放鎖；冪等判定在寫流水前）照同類 service，**不得跳步**

### 模式 B — `service/third*` + `controller/third/`（**cp-service**）

適用：第三方遊戲、支付、平台對接。

```text
com.lc.cp/
  service/third/            ThirdApiSerice / ThirdGameApiService / PayApiSerice / PlatformApiSerice ...
  service/thirdVoucher/  service/thirdmanage/
  controller/third/         ThirdController / PayThirdController / PlatThirdController / CGThirdController ...
  filter/                   SignFilter / PlatformSignFilter / CgThirdFilter（回調驗簽）
  cache/                    PayConfigCache 等 *ConfigCache（預載入第三方設定）
```

- **`controller/third/` 必驗簽 / IP 白名單**；新回調路徑的放行規則依 `rules/security.md` §filter 防線：**精確路徑比對，禁止新增副檔名 / 子字串 / `contains` 型放行**（lion 曾因 `.do` 放行被實際入侵，`checks/filter-bypass.md`）
- **包網商身分**：回調的 platformId 只能取自驗簽通過的商戶識別，不得直接信任 body 帶的 platformId（`rules/platform-isolation.md`）
- 設定（API key / URL / 商戶號）從資料表 + `*ConfigCache` 讀，**不硬編碼**、不進 log

### 模式 C — 抽象基類 + 多實作（**cp-service** 的同類 provider）

適用：同一種能力有多家供應商、可互換。

```text
com.lc.cp/
  sms/AbstractSmsService.java + sms/impl/*Service.java          # 簡訊 provider（十多家）
  service/pixel/connector/PixelConnector.java + connector/impl/  # 廣告像素回傳
```

- 新供應商 = 新增一個 `impl/` 子類，實作基類的 abstract 方法；**不改基類**（要改基類 → 影響所有 provider，升 L1 並找使用者確認）
- 新舊版並存（例：`SmsbaoService` vs `NewSmsbaoService`）是線上還在跑，**新功能用新版、舊版不動**

### 模式 D — 開獎資料來源（**collector-service**，`com.cx.collector.*`）

- 每個來源一個 service（`service/<country>/<source>/`），照 `collector-service/CLAUDE.md` §新增資料來源 Checklist
- HTTP **一律走 `SourceProxyService`**，不要直接呼叫 HTTP 工具（proxy 才能在原 IP 被封時切線路）
- GameCode 必登記 `GameCodeDictionary`，漏登記 → cp-service 收不到
- 無金額但**資料品質 = 金錢**（錯開獎 → 錯結算）：廠商回 200 + HTML 錯誤頁、BOM、時區（統一 GMT+8）都要處理

### 共用慣例（各模式皆適用）

- HTTP：cp-service 兩種都有（framework_v3 `ApachePoolingHttpClientUtil` 與 `RestTemplate`，各二十多個檔）→ **照同一個 package 鄰近實作用哪個就用哪個**；外部呼叫必設 timeout
- 交易內不得呼叫外部 API（`checks/transactional-remote-call.md`）
- DI：新類別用 `@RequiredArgsConstructor` + `private final`；既有類別沿用原寫法（`rules/patterns.md` §2）
- 資料物件：Req → `Query` / `SO`、Resp → `VO` / `Record`（**禁 `DTO` / `Entity`**，見 `rules/patterns.md` §8）
- DAO：framework_v3 `MysqlBaseDaoImpl` / `AbstractEsPartitionByDateDao`（**lion 沒有 MyBatis**，不寫 mapper；見 `skills/mysql-patterns/SKILL.md`）
- 跨服務共享 bean / 列舉 → 放 `lion-common`（跨 repo，`skills/cross-repo-commit/SKILL.md`）
- 對接屬 L1：`business-reviewer` + `security-reviewer`（`model: "opus"`）

## 品質檢查清單

- [ ] 對齊 repo 內現有的整合模式
- [ ] 設定驗證已實作
- [ ] 認證與錯誤處理明確定義
- [ ] 分頁 / 重試行為符合 repo 慣例
- [ ] 註冊 / 發現機制完整
- [ ] 測試風格與宿主 repo 一致
- [ ] 如 repo 預期，文件 / 範例已更新
- [ ] 回調入口驗簽 / IP 白名單完整，放行規則為精確路徑（無副檔名 / 子字串放行）
- [ ] platformId 來源正確（驗簽後的商戶識別 / resolver），不信任請求 body
- [ ] 金額：`BigDecimal` + 入帳出帳 `RoundingMode.DOWN`；同 `orderNo` 重送冪等

## 相關 Skill

- `springboot-patterns`
- `springboot-security`
- `cross-repo-commit`
