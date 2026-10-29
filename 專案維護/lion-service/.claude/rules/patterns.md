---
paths:
  - "**/*.java"
---
# Java 設計模式（lion-service，Java 8）

> 應用層級的組織規範：分層、依賴注入、例外策略、整合模式、併發、非同步、資料物件。
> 單行程式碼風格（格式、命名、Lombok、Log）見 [coding-style.md](./coding-style.md)。
>
> 新程式碼請對齊以下規則；既有程式碼違反的不強制重構。

---

## 0. 生態位置

`lion-service` 是 lion 生態的**業務服務集合**，依賴以下共享層（sibling repo，都在本 repo 之外）：

| 共享層（package 前綴） | 提供 |
|----------------------|------|
| `com.cx.framework.*`（framework_v3） | `exception.BusinessException` / `DaoException`、`utils.*`（DateUtil、JsonUtil…）、DAO 抽象（`MysqlBaseDaoImpl` / `SqlUtil` / `AbstractBaseEsDao` / `AbstractEsPartitionByDateDao`） |
| `com.lc.common.*`（lion-common） | 領域模型、資料物件 `bean.vo|so|bo|event|query`、共用 DAO `dao.*`（含 `*EsDao` / `*Dao`）、快取 `cache.*`、常數與列舉（含 `EnumClass.TranType`）、`UserMoneyService.changeMoney*` |
| `com.lc.lion.settle.*`（lion-core） | **結算服務**（獨立 repo，`settle-service` 模組）— 訂單結算、派彩計算 |

本服務模組（根 pom `<modules>`）：`cp-service` / `single-wallet-service` / `collector-service` / `upload-service`；另有 `cp-flyway`（同 repo、不在 reactor）。

**原則：** SO / VO / BO / Query / Event / 領域模型 / DAO / Cache 一律放 `lion-common`（詳見 §8 共享物件放置原則）；服務內部業務邏輯放本專案。

---

## 1. 分層規範

| 層級 | 職責 | 禁忌 |
|------|------|------|
| **Controller** | 參數驗證、回應包裝；依角色目錄分流；platformId / 登入者經 resolver 參數取得（`UserIdWithPlatformId` / `PlatformId` / `TokenInfo`） | 不放業務邏輯；不從 SO 取 platformId 當授權依據（`rules/platform-isolation.md`） |
| **Service** | 業務邏輯、交易邊界（`@Transactional`） | 不直接操作 HTTP |
| **Job / Scheduler / Quartz** | `job/scheduler/` 只寫觸發、業務放 `job/service/*`；單節點用 `job/quartz/`；冪等設計 | 不直接寫業務；金額排程不得吞例外 |
| **DAO** | 資料存取，繼承 framework_v3 基類（`MysqlBaseDaoImpl` / ES 基類），SQL 用 `SqlUtil` 組 | 不直接暴露 model 給 Controller；SQL 不拼接使用者輸入 |
| **Cache** | 雙層架構：Redis（跨節點） + `CacheService<V>`（Guava + Kafka 失效通知）；見 §6.5 | 不用 Spring `@Cacheable`；不跨服務直接讀其他服務快取 |

Controller 子目錄慣例（以 `cp-service` 為代表，依角色分）：

```
controller/
├── admin/        # 後台管理端
├── front/        # 前端玩家端
├── agent/  agentline/   # 代理端 / 代理線
├── station/      # 站點
├── boss/  manage/  thirdmanage/   # 總控 / 控制中心（依設計跨包網商，權限要求更高）
├── commerce/  center/  quest/  tag/
├── internal/     # 被其他服務直接 HTTP 呼叫；改簽名前 grep 所有 RestTemplate / Feign caller，絕不掛前端可達路由
└── third/        # 第三方回調，必驗簽 / IP 白名單
```

---

## 2. 依賴注入

**新程式碼：建構子注入** `@RequiredArgsConstructor` + `private final`

```java
@Slf4j
@Service
@RequiredArgsConstructor
public class UserBetAddService {
    private final UserMoneyDao userMoneyDao;
    private final ThirdOrderEsDao thirdOrderEsDao;
}
```

> ⚠️ **本專案實況：** `@Resource` 與 `@Autowired` 欄位注入仍大量存在（舊程式碼）。既有寫法不強制重構，新類別朝建構子注入收斂。

---

## 3. Exception 策略

使用框架層 `com.cx.framework.exception.*`：

```java
throw new BusinessException(ErrorCodesEnum.Xxx.YYY.code, ErrorCodesEnum.Xxx.YYY.desc);  // 業務規則違反（見 coding-style.md §7）
throw new DaoException("query failed", e);                           // 資料存取錯誤
```

**全域處理：** 各服務模組有自己的 `GlobalExceptionHandler`（`@RestControllerAdvice`），例如：
`single-wallet-service/.../handler/GlobalExceptionHandler.java`。新訊息碼與回應格式對齊既有處理器。

**禁忌：**
- ❌ 自製新的 RuntimeException 子類（沿用框架；除非業務情境明確獨立，例如 `BusinessResponseException`）
- ❌ `catch (Exception e) { /* 吞掉 */ }`（見 `coding-style.md` §語法偏好）

---

## 4. API 回應信封

使用**框架層 / common 層既有回應信封**，**不自製新的 `ApiResponse` / `Response` class**。新 Controller 端點參考同模組既有 Controller 的回傳型別對齊（`com.lc.common.bean.vo.*` 或模組內 `*VO`）。

---

## 5. 第三方服務整合

`cp-service` 與 `single-wallet-service` 大量對接第三方遊戲廠商 / 支付 / 鏈上 / 簡訊。本專案**未採統一 `@ThirdPartyComponent` 註解框架**，常見寫法：

- **Connector / Service 風格：** `ThirdApiSerice`（拼字是既有命名，別糾正）、`ThirdGameApiService`、`OnChainPayService` 等直接以 Spring Service 注入，依廠商代碼路由；簡訊 provider 在 `sms/impl/`
- **single-wallet：** `@SingleWalletType` + `SingleWalletContext` 自動註冊交易類型，**禁止 switch 路由**；回廠商一律 HTTP 200、錯誤碼在 body；`RespStateEnum` 是對接合約
- **collector：** 走 `SourceProxyService`，不直接打 HTTP；新遊戲代碼必登記 `GameCodeDictionary`
- **HTTP 呼叫：** `RestTemplate` 與 framework_v3 `ApachePoolingHttpClientUtil` 都常見（各約 20+ 檔）——**對齊同模組同類對接用的那一個**，不要在同一條對接裡混用（collector 例外：一律走 `SourceProxyService`）
- **設定來源：** `provider` / `thirdApi` / `onChainPay` 相關資料表，透過 `*ConfigCache` 預載入
- **回調：** `/third/*` Controller，驗簽後委派 Service 處理

新對接流程見 `api-connector-builder` skill（本專案版本 — 需依本服務慣例客製）。

---

## 6. 併發與鎖

| 場景 | 機制 |
|------|------|
| **金額異動 / 餘額扣減 / 錢包結算** | 分散式鎖 + `@Transactional` + DB `SELECT ... FOR UPDATE`（見 `single-wallet-service` 各 `AbstractSingleWalletService` 子類；8 步順序見 `rules/security.md`） |
| **訂單去重 / 冪等** | 唯一鍵（`orderNo` / ES 唯一索引） |
| **排程併發保護** | 若需單節點執行，採 `quartz` cluster 或 Redis SETNX 包裝 |
| **API 限流** | 視模組採 Sentinel / Gateway 層處理（非每服務必備） |

**禁忌：**
- ❌ 用 `synchronized` 做跨節點業務鎖（叢集環境無效）
- ❌ 金額扣減不加 DB 鎖只靠快取判斷

---

## 6.5 快取（雙層架構）

本 repo **不使用** Spring `@Cacheable` / `@CacheEvict`。兩層分工：

| 層 | 技術 | 用途 |
|----|------|------|
| **L1：Redis** | Lettuce + `RedisTemplate`（cp-service / single-wallet）；collector-service 用 Jedis + `RedisUtil` | 跨節點共享：分散式鎖、Session、排行榜、大容量暫存；key 要帶 platformId 維度 |
| **L2：`CacheService<V>`** | Guava `LoadingCache` + Spring Cloud Stream Kafka 失效通知（`lion-common` 提供基類） | 每節點本地：讀多寫少的配置 / 字典 / 預載資料 |

**硬規則：**

- 新增共用 cache → **放 `lion-common/cache/<domain>/`**；僅本服務用 → 本模組 `cache/`
- 繼承 `com.lc.common.service.cache.CacheService<V>`（帶參數用 `CacheServiceWithArgs`），實作 `cacheName()` / `loadFunc()` / `getCacheTimeoutMinute()`
- `cacheName()` 從 `EnumClass.SystemCacheNames` 取常數 — **必登記**
- 需啟動預載的實作 `CacheInitLoading` 介面；`CacheInitRunner` 啟動時會掃描執行
- **寫 DB 後必呼 `cacheService.invalidate(key)`**（Kafka Stream 通知所有節點清本地 cache；漏呼 → 其他節點讀 stale 資料）
- Cache `loadFunc` 查資料用 `HintManager.getInstance().setMasterRouteOnly()` 強制主庫
- 禁手寫 `ConcurrentHashMap` / Caffeine 當 cache — 用 `CacheService<V>` 才有自動失效 / 預載 / 統計

詳細實作見 `springboot-patterns` skill §【本專案】快取。

---

## 7. 非同步與排程

- **排程：** cp-service `job/` 下 100+ 類：`job/scheduler/`（多節點觸發）、`job/quartz/`（需單節點執行）、`job/service/*`（業務委派）
- **非同步：** `@Async` + `@EnableAsync`
- **Spring 內部事件：** `ApplicationEventPublisher` + `@EventListener`（見 `event/listener/*Listener` 類別）— 同 JVM 內異步
- **跨服務訊息（Kafka，透過 Spring Cloud Stream）：** 本 repo 用 **`spring-cloud-starter-stream-kafka`（Finchley）**，**不是**直接用 `spring-kafka`。經典模式：
  - Channel 介面：`event/input/XxxInput.java`（含 `@Input` 方法） / `event/output/XxxOutput.java`（含 `@Output` 方法）
  - 發送：`@EnableBinding(XxxOutput.class)` + `MessageChannel`（見 `event/emitter/*Emitter` 繼承 `AbstractQuartzNotifyEmitter`）
  - 接收：`@EnableBinding(XxxInput.class)` + `@StreamListener(XxxInput.CHANNEL_NAME)`（見 `event/listener/*Listener`）
  - binder 名 `kafka-server`，設定在 `application.yml` 的 `spring.cloud.stream.binders.kafka-server`
  - `destination` 命名不統一（`user-notice-event`、`activity-event-v2`、`activity-system-*-event`…），新 binding **對齊同 domain 既有命名**
  - **`group` 決定「誰收到」，選錯就出事（紅線）：**

    | group 寫法 | 語意 | 用在 | 選錯的後果 |
    |---|---|---|---|
    | `${anonymous.group.name}`（每節點各自一個 group） | **廣播**：每台都收到 | 本地快取失效通知（`CacheService.invalidate`）這類「每台都要做」的事 | 改成固定 group → 只有一台清快取，其他台讀 stale 資料 |
    | 固定名稱（例：`activity-event-group`、`bet-event-group`） | **競爭消費**：同一則只有一台處理 | 寫 DB、動金額、發獎這類「只能做一次」的事 | 改成每節點 group → **每台各處理一次 = 重複扣款 / 重複發獎** |

    新 binding 先判斷是哪一類，照抄同類既有 binding 的寫法；判不出 → 問使用者
  - **不要**改用 `@KafkaListener` / `KafkaTemplate` — 本 repo 未導入 `spring-kafka`，會找不到依賴

**規則：** Handler 必須**冪等**（排程 / Spring Event / Stream Listener 都可能重送），搭配 `orderNo` 或業務唯一鍵去重。

---

## 8. 資料物件分層（VO / SO / BO / Query / Record / Event / Config）

本專案**不用** `DTO` / `Request` / `Entity`（或極少），資料物件以以下後綴分類：

| 後綴 | 用途 | 典型位置 |
|------|------|---------|
| **`VO`** (View Object) | 回應給前端 / API 呼叫者的展示物件 | `bean/vo/`、`com.lc.common.bean.vo.*` |
| **`SO`** (Search Object / Summary Object) | 查詢條件封裝、聚合統計結果；Service 層跨層傳遞 | `bean/so/`、`com.lc.common.bean.*.so.*` |
| **`BO`** (Business Object) | 業務邏輯中間態物件（計算過程） | `bean/bo/`、`com.lc.common.bean.*.bo.*` |
| **`Query`** | 查詢參數物件（Controller/Service 接收查詢條件） | `bean/query/<domain>/` |
| **`Record`** | 第三方原始業務紀錄對應物件 | `third/*` 相關套件 |
| **`Event`** | 事件訊息（Spring Event / Spring Cloud Stream Kafka） | `bean/event/`、`event/` |
| **`Config`** | Spring 設定類別 + 第三方配置物件 | `config/` |
| **領域模型** | 存入 ES / MySQL 的模型 | `lion-common` 的 model 套件（依同 domain 既有位置） |

### 判定原則

```
外部輸入（API / Form 參數）
  → Query（查詢條件） or VO（回傳）

Service 層 / 跨層傳遞
  → SO（查詢聚合）or BO（業務中間態）

領域模型（存入 ES / MySQL）
  → lion-common 的 model class（對齊同 domain 既有位置）

事件訊息
  → Event（Spring 事件 或 Spring Cloud Stream Kafka）

第三方 API 回應解析
  → Record 或第三方專屬 bean
```

### 禁忌

- ❌ **不用 `DTO` 後綴**（本專案慣例不同）
- ❌ **不用 `Request` 後綴**（API 輸入用 `Query` 或直接參數）
- ❌ **不用 `*Entity` / `*PO`**（DAO 走 framework_v3，不配對 ORM Entity）
- ❌ **不隨意新增後綴**（如 `Dto`、`Params`、`Pojo`）

### 共享物件放置原則（2026-04-22 更新）

**硬規則：** SO / VO / BO / Query / Record / Event / 領域模型 / DAO / Cache 一律放 `lion-common`（`com.lc.common.*`），**不再依「跨服務 vs 僅本服務」拆分**。

理由：經驗上搬移的成本遠大於直接放 common 的輕微重複；共享避免後續當真有跨服務需求時又要搬一次。

| 物件類型 | 位置 |
|---------|------|
| SO / VO / BO / Query / Record / Event | `lion-common/.../bean/<category>/<domain>/` |
| 領域模型（Model，存 MySQL / ES）/ 共用 DAO / Cache | `lion-common`（對齊同 domain 既有位置） |
| 框架級別工具 / 基底類 | `framework_v3` |
| 純本模組內部中介物件（如 Controller → Service 的 ad-hoc DTO） | 本模組 `bean/*` — **例外允許，但需在 PR description 說明為何不適合放 common** |

**新開流程（團隊慣例：不動版本號）：** 根 pom `common.version` 固定 `1.1`、`framework.version` 固定 `3.1`，變更同版號覆寫。

```
lion-common MR → mvn install（本機驗）→ deploy 覆寫同版號 → 開 lion-service feature MR
```

- **Breaking change**（刪欄位 / 移類別 / 改方法簽名）仍不動版號，但要**先確認所有下游**（lion-service / lion-core / lion-manage…）都改完能編譯，再一起 deploy、一起合入；否則下游會編譯失敗
- 跨 repo 順序與 MR 交叉引用見 `cross-repo-commit` skill

---

## 8.5 系統參數（Config 表 + 反射映射前端 VO）

> 重要專案慣例，L3 wiring 類需求最常踩這裡。

**儲存機制：** 所有「系統參數」都走通用 `config` 資料表（string key-value + `platform_id` + `type` + `is_show` 等欄位），**不是獨立欄位**；以 platformId 分家（`configCache.getByCache(platformId)`）。管理員於後台新增 / 修改時由 `ConfigService.saveOrUpdateConfigList` 寫入，key = `cfgName`（camelCase 字串）。

**反射填 VO（前端 API 讀取路徑）：**

`cp-service/src/main/java/com/lc/cp/service/setting/ConfigService.java` `getFrontConfig()`：

```java
Map<String, Object> configMap = ...  // 取該 platformId 的 config，篩選 isShow=0
FrontConfigVO frontConfigVO = MapUtils.mapToObject(configMap, FrontConfigVO.class);
```

`MapUtils.mapToObject` 透過 Jackson `convertValue` 反射把 configMap 的 key 映射到 VO 同名欄位。**VO 欄位名必須 = config 表 cfgName**（camelCase 嚴格一致）。

**新增 / 修改系統參數欄位標準流程：**

1. `lion-common` → `FrontConfigVO.java` 新增 `private String <cfgName>;`（Javadoc 註明意義）— Lombok `@Data` 自動產 accessor
2. **後端 `ConfigService.java` 不用改** — 反射自動處理
3. DB schema 不用 migration — `config` 表首次保存時自動 insert
4. **前端（跨 repo，本 repo 不改）**：後台系統參數頁的設定項（含 `isShow` 等過濾欄位）、前端 i18n —— 列入 spec 的「跨 repo 影響清單」交前端 repo 處理；過濾欄位寫錯整個 wire 不作用，清單裡要寫明

**常見陷阱：**

| 陷阱 | 症狀 |
|------|------|
| grep 找不到 `setXxxCfg` → 誤判 dead code | 反射映射不走 explicit setter 呼叫；要 grep `MapUtils.mapToObject` / `BeanUtils.copyProperties` / `ObjectMapper.convertValue` |
| `FrontConfigVO` 加了欄位但前端存的 `isShow` 寫錯 | API response 缺欄位 |
| 類別標 `@JsonInclude(NON_NULL)` → 未存值時 response 不含 key | 正常行為，不是空字串。QA R3 驗收時注意 |
| lion-common 版本是否 bump | 不 bump，同版號覆寫（見 §8 新開流程） |

**延伸：** 「內部服務 config」（非前端可見） → 走 `*ConfigCache` 而非反射，見 §6.5。

---

## 9. DAO 風格

- MySQL DAO：繼承 framework_v3 `MysqlBaseDaoImpl<Model, PK>`，SQL 以 `SqlUtil`（`addSqlAndArgs` / `andEqual` / `andIn`…，值走參數綁定）組；搭配 **ShardingSphere 4.0.1** 主從分片。共用 DAO 在 `lion-common`（`com.lc.common.dao.*`）
- **lion 沒有 MyBatis**（cp-service / single-wallet-service 0 mapper、0 mapper XML；根 pom 只在 dependencyManagement 出現 mybatis）—— **不要寫 mapper / XML**，對齊同模組既有 DAO
- ES DAO：繼承 framework_v3 `AbstractBaseEsDao` / `AbstractEsPartitionByDateDao`；ES 6.8.22 與 7.17.18 並用，single-wallet 以 `ElasticsearchTemplateAspect` 做主從切換（見 `es-patterns` skill）
- **禁忌：** 不在 Service 裡寫 JDBC / 拼接 SQL；SQL 字串不得帶入使用者輸入（欄名 / 排序 / 表名要白名單）；不使用 `JpaRepository`（非本專案選型）

---

## 10. 其他硬規則（跨檔引用）

- **金額 / RoundingMode：** 見 `rules/security.md`
- **時區：** 系統統一 GMT+8（依既有 `DateUtil` 慣例）
- **新舊版並存**：`lotteryplan` vs `lotteryplanV2`、`activity` vs `activity2`、`SmsbaoService` vs `NewSmsbaoService` 等都是線上在跑 → 新功能用新版、舊版不動（見 `rules/modules.md`）

---

## 相關資源

| 主題 | 位置 |
|------|------|
| 格式 / 命名 / Log / Lombok / 語法偏好 | `rules/coding-style.md` |
| 金額 RoundingMode 場景規則 | `rules/security.md` |
| Spring Boot 架構（快取、事件、排程） | `springboot-patterns` skill |
| DAO / ShardingSphere / migration | `mysql-patterns` skill |
| ES 分庫與多版本並用 | `es-patterns` skill |
| 新第三方服務對接實作 | `api-connector-builder` skill（需依本服務慣例客製） |
