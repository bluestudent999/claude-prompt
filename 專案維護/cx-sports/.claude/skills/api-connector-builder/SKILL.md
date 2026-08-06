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
- 「照現有 Provider 模式新增 RG 第三方服務商」
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

## 參考結構（sport 實況）

> sport **未採統一 `@ThirdPartyComponent` Provider 註解框架**；不同模組依業務性質採用不同模式。新整合**先選最接近的既有模式**，照其慣例寫，**不要發明第二套**。

### 模式 A — 註解 + Context 路由（**cx-sport-single-wallet-service**）

適用：同類交易但有多種變體（下注 / 結算 / 取消）。

```text
com.lc.single.wallet/
  service/singlewallet/impl/
    SingleWalletRoundBetService.java        # @SingleWalletType(SINGLE_WALLET_ROUND_BET)
    SingleWalletSettleService.java          # @SingleWalletType(SINGLE_WALLET_SETTLE)
    ...
  context/
    SingleWalletContext.java                # ApplicationRunner 啟動掃描，map<交易類型, Service>
  controller/third/
    ThirdController.java                    # 入口，依 tranType 從 context 取對應 service
  filter/
    SingleWalletSignFilter.java             # 驗簽
  constants/
    RespStateEnum.java                      # 回廠商的狀態碼（合約）
```

新增交易類型：見 `cx-sport-single-wallet-service/CLAUDE.md` §新增交易類型 SOP。

### 模式 B — `service/third*` 直注入（**cx-sports-v2**）

適用：cx-sports-v2 大量第三方支付 / 遊戲 / 鏈上服務。

```text
com.lc.cp/
  service/third*/
    ThirdApiSerice.java / ThirdGameApiService.java / OnChainPayService.java ...
    （以 gameFirm / providerCode 路由）
  controller/third/
    XxxThirdController.java                  # 廠商回撥（必驗簽 / IP 白名單）
  cache/
    XxxConfigCache.java                      # 預載入第三方設定（API key / URL 等）
```

設定來源：`provider` / `thirdApi` / `onChainPay` 相關資料表，**不硬編碼**。

### 共用慣例（兩模式皆適用）

- DI：新類別用 `@RequiredArgsConstructor` + `private final`
- HTTP：cx-sports-v2 走 `RestTemplate`
- 資料物件：Req → `Query`、Resp → `VO` / `Record`（**禁 `DTO` / `Entity`**，見 `rules/patterns.md` §8）
- DAO：繼承 MyBatis-Plus `BaseMapper` 或 `AbstractEsPartitionByDateDao`，**不用 `JpaRepository`**
- 跨服務共享 bean → 放 `cx-sport-common`

## 品質檢查清單

- [ ] 對齊 repo 內現有的整合模式
- [ ] 設定驗證已實作
- [ ] 認證與錯誤處理明確定義
- [ ] 分頁 / 重試行為符合 repo 慣例
- [ ] 註冊 / 發現機制完整
- [ ] 測試風格與宿主 repo 一致
- [ ] 如 repo 預期，文件 / 範例已更新

## 相關 Skill

- `springboot-patterns`
- `business-template`
