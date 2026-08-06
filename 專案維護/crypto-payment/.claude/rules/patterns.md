---
paths:
  - "**/*.java"
---
# 設計模式（crypto-payment，Java 21 / Spring Boot 3.1.2）

> 應用層級組織規範：分層、依賴注入、例外、回應信封、整合、併發、快取、DAO / Migration。
> 單行程式碼風格（格式、命名、Log）見 [coding-style.md](./coding-style.md)。金額 / 私鑰 / 驗簽見 [security.md](./security.md)。
>
> 新程式碼對齊以下規則；既有程式碼違反的不強制重構。

---

## 1. 分層

| 層 | 職責 | 禁忌 |
|----|------|------|
| **Controller** | 參數驗證、回應包裝；`manage`/`center`/`system`/`thirdparty` 依目錄分流 | 不放業務邏輯 |
| **Service** | 業務邏輯、交易邊界（`@Transactional`）；`platform`/`user`/`system`/`setting` 分域 | 不直接操作 HTTP |
| **Job**（Quartz / `@Scheduled`） | 排程任務，**冪等設計** | 不寫業務，委派 Service |
| **Event** | Kafka & Spring event listeners | Handler 必須冪等 |
| **Filter / Resolver** | SignFilter 驗簽、webhook、IP、platform/auth/locale 解析 | 不放業務邏輯；SignFilter 改動須確認 |
| **Repository（DAO）** | 資料存取；ShardingSphere 5.4 自動讀寫分離 | 不手動路由；不暴露 Entity 給 Controller |
| **Cache** | Redis-backed | 寫 DB 後須失效（見 §6） |

Controller 子目錄：`manage/`（`/api/manage/*`）、`center/`（`/api/center/*`、`/api/platform/*`）、`system/`、`thirdparty/`（`/api/thirdparty/*` webhook）。

---

## 2. 依賴注入

**一律建構子注入**（`@RequiredArgsConstructor` + `private final`），**禁 `@Autowired` 欄位注入**。

```java
@Slf4j
@Service
@RequiredArgsConstructor
public class DepositService {
    private final UserWalletRepository userWalletRepository;
    private final ChainLogService chainLogService;
}
```

---

## 3. 例外策略

- 使用既有**自訂 exception 類**，**禁裸 `throw new RuntimeException(...)`**
- 全域處理走既有 `@RestControllerAdvice`（`GlobalExceptionHandler`）；新錯誤碼與回應格式對齊既有處理器
- **禁 `catch (Exception e) {}` 吞例外**（見 `coding-style.md`）

## 4. API 回應信封

- 一律用既有 **`BaseResponse<T>`** 包裝，**禁回傳裸物件 / 自製新 `Response` class**
- 新 Controller 端點參考同目錄既有 Controller 的回傳型別對齊

---

## 5. 第三方整合（鏈 / webhook / provider）

- **鏈 client：** BSC/ETH 用 **Web3j**、TRON 用 **Trident**、BitcoinJ 用於對應鏈——**不可混用 client**
- **webhook provider（QuickNode / Tatum）：** 走 `/api/thirdparty/*`，驗簽後委派 service 解析 chain log
- **設定來源：** provider / chain / token / vendor 相關 config 表，透過 `*ConfigCache` 預載
- 新對接流程見 `api-connector-builder` skill 與 `blockchain-wallet` skill

## 6. 併發、鎖與快取

| 場景 | 機制 |
|------|------|
| 金額 / 餘額 / 入帳 / 歸集 | DB `SELECT ... FOR UPDATE` + `@Transactional`（見 `security.md` §5） |
| 入款 / 訂單去重 / 冪等 | 唯一鍵（txHash / orderNo / nonce） |
| 排程單節點執行 | Quartz cluster 或 Redis SETNX |

**快取（Redis / Jedis）：**
- 讀多寫少的 config / 字典用 `*ConfigCache` 預載
- **寫 DB 後必須在同事務內或緊接其後失效 / 更新對應 Redis key**（漏失效 → 讀 stale）
- **禁用 `synchronized` 做跨節點鎖**

---

## 7. 非同步與訊息

- **排程：** `@Scheduled` / Quartz（`job/`）；需單節點執行用 Quartz cluster
- **非同步：** `@Async` + `@EnableAsync`
- **Spring 內部事件：** `ApplicationEventPublisher` + `@EventListener`（同 JVM 異步）
- **Kafka（原生 Apache Kafka）：** 本專案用**原生 Kafka**，**不是** Spring Cloud Stream——不要用 `@EnableBinding`/`@StreamListener`/`@Input`/`@Output`；沿用 repo 既有 producer/consumer 慣例（動 Kafka 前先 grep 既有 listener 寫法對齊）
- **規則：** 所有 handler（排程 / event / Kafka）必須**冪等**，搭配 txHash / orderNo / nonce 去重

---

## 8. DAO 風格與 DB Migration

- **DAO：** `repository/` 下，搭配 MyBatis + **ShardingSphere 5.4** 主從分片；`#{param}` 參數化（見 `security.md` §6）
- **禁忌：** 不在 Service 寫原生 JDBC；不手動指定讀/寫庫（ShardingSphere 自動）
- **Flyway（`crypto-payment-flyway` 模組）：**
  - schema 變更一律新增版號檔（`V1_0_x__description.sql`）
  - **禁改既有 migration 檔**——已套用的檔改了會導致 checksum 衝突
  - 新增欄位遵循安全演進（見 `stability.md` §Schema Evolution）

詳細實作見 `mysql-shardingsphere5` skill。

---

## 9. 資料物件

- Controller 輸入用 `@Valid` 驗證的請求物件；回應包 `BaseResponse<T>`
- 沿用 repo 既有命名慣例（動手前 grep 同目錄既有物件對齊，勿自創新後綴體系）

---

## 相關資源

| 主題 | 位置 |
|------|------|
| 格式 / 命名 / Log / 語法偏好 | `rules/coding-style.md` |
| 私鑰 / AES-GCM / HMAC / platform_id / 金額 | `rules/security.md` |
| 冪等 / 防重放 / 鏈重組 / Schema 演進 | `rules/stability.md` |
| Spring Boot 3 架構（快取、事件、排程） | `springboot3-patterns` skill |
| DAO / ShardingSphere 5.4 / Flyway | `mysql-shardingsphere5` skill |
| 錢包 / 私鑰 / 鏈 client / 入款 / 歸集 | `blockchain-wallet` skill |
| 新鏈 / webhook provider 對接 | `api-connector-builder` skill |
