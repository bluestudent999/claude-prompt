---
paths:
  - "**/*.java"
---
# Java 設計模式（sport 子專案共通，Java 8）

> 應用層級的組織規範：分層、依賴注入、例外策略、整合模式、併發、非同步、資料物件。
> 單行程式碼風格（格式、命名、Lombok、Log）見 [coding-style.md](./coding-style.md)。
>
> 新程式碼請對齊以下規則；既有程式碼違反的不強制重構。

---

## 0. 生態位置

`sport` 是 lion 生態的**業務服務集合**，依賴以下共享層：

| 共享層（package 前綴） | 提供 |
|----------------------|------|
| `com.cx.framework.*`（sport-framework） | `exception.BusinessException` / `DaoException`、`utils.*`（DateUtil、CollectionUtils、StringUtil）、基礎 DAO 抽象類 |
| `com.lc.sports.*`（cx-sport-common） | 領域模型 `bean.model.*`、資料物件 `bean.vo|so|bo|event|query`、共用 DAO `dao.*`（含 `*EsDao` / `*Dao`）、快取 `cache.*`、常數與列舉 |
| `cx-sport-settle-rule.*`（cx-sport-settle-rule） | **結算服務**（獨立 repo，`settle-service` 模組）— 訂單結算、派彩計算 |

本服務模組：`cx-sports-v2` / `cx-sport-single-wallet-service` / `Flyway`。

**原則：** SO / VO / BO / Query / Event / 領域模型一律放 `cx-sport-common`（詳見 §8 共享物件放置原則）；服務內部業務邏輯放本專案。

---

## 1. 分層規範

| 層級 | 職責 | 禁忌 |
|------|------|------|
| **Controller** | 參數驗證、回應包裝；Admin / Front / Internal / Station 依目錄分流 | 不放業務邏輯 |
| **Service** | 業務邏輯、交易邊界（`@Transactional`） | 不直接操作 HTTP |
| **Job / Scheduler / Quartz** | 排程任務，冪等設計 | 不直接寫業務，委派給 Service |
| **DAO** | 資料存取，繼承框架基類（MyBatis-Plus `BaseMapper` / ES 基類） | 不直接暴露 Entity 給 Controller |
| **Cache** | 雙層架構：Redis（跨節點） + `CacheService<V>`（Guava + Kafka 失效通知）；見 §6.5 | 不用 Spring `@Cacheable`；不跨服務直接讀其他服務快取 |

Controller 子目錄慣例（以 `cx-sports-v2` 為代表）：

```
controller/
├── admin/     # 後台管理端
├── front/     # 前端用戶端
├── station/   # 站點 / 代理端
├── agent/     # 代理端
├── internal/  # 內部服務呼叫
└── third/     # 第三方回調
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
throw new BusinessException("ERR_CODE", "user friendly message");  // 業務規則違反
throw new DaoException("query failed", e);                           // 資料存取錯誤
```

**全域處理：** 各服務模組有自己的 `GlobalExceptionHandler`（`@RestControllerAdvice`），例如：
`cx-sport-single-wallet-service/.../handler/GlobalExceptionHandler.java`。新訊息碼與回應格式對齊既有處理器。

**禁忌：**
- ❌ 自製新的 RuntimeException 子類（沿用框架；除非業務情境明確獨立，例如 `BusinessResponseException`）
- ❌ `catch (Exception e) { /* 吞掉 */ }`（見 `coding-style.md` §語法偏好）

---

## 4. API 回應信封

使用**框架層 / common 層既有回應信封**，**不自製新的 `ApiResponse` / `Response` class**。新 Controller 端點參考同模組既有 Controller 的回傳型別對齊（`com.lc.sports.bean.vo.*` 或模組內 `*VO`）。

---

## 5. 第三方服務整合

`cx-sports-v2` 與 `cx-sport-single-wallet-service` 大量對接第三方遊戲廠商 / 支付 / 鏈上。本專案**未採統一 `@ThirdPartyComponent` 註解框架**，常見寫法：

- **Connector / Service 風格：** `ThirdApiSerice`、`ThirdGameApiService`、`OnChainPayService` 等直接以 Spring Service 注入，依 `gameFirm` / `providerCode` 路由
- **HTTP 呼叫：** 以 `RestTemplate`
- **設定來源：** `provider` / `thirdApi` / `onChainPay` 相關資料表，透過 `*ConfigCache` 預載入
- **回調：** `/third/*` Controller，驗簽後委派 Service 處理

新對接流程見 `api-connector-builder` skill（本專案版本 — 需依本服務慣例客製）。

---

## 6. 併發與鎖

| 場景 | 機制 |
|------|------|
| **金額異動 / 餘額扣減 / 錢包結算** | DB `SELECT ... FOR UPDATE`（悲觀鎖，見 `cx-sport-single-wallet-service` 各 `AbstractSingleWalletService` 子類）+ 事務 |
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
| **L1：Redis** | Lettuce（預設）+ `RedisTemplate` / `cx-sport-app-service/util/RedisUtil` | 跨節點共享：分散式鎖、Session、排行榜、大容量暫存 |
| **L2：`CacheService<V>`** | Guava `LoadingCache` + Spring Cloud Stream Kafka 失效通知（`cx-sport-common` 提供基類） | 每節點本地：讀多寫少的配置 / 字典 / 預載資料 |

**硬規則：**

- 新增共用 cache → **放 `cx-sport-common/cache/<domain>/`**；僅本服務用 → 本模組 `cache/`
- 繼承 `com.lc.sports.service.cache.CacheService<V>`，實作 `cacheName()` / `loadFunc()` / `getCacheTimeoutMinute()`
- `cacheName()` 從 `EnumClass.SystemCacheNames` 取常數 — **必登記**
- 需啟動預載的實作 `CacheInitLoading` 介面；`CacheInitRunner` 啟動時會掃描執行
- **寫 DB 後必呼 `cacheService.invalidate(key)`**（Kafka Stream 通知所有節點清本地 cache；漏呼 → 其他節點讀 stale 資料）
- Cache `loadFunc` 查資料用 `HintManager.getInstance().setMasterRouteOnly()` 強制主庫
- 禁手寫 `ConcurrentHashMap` / Caffeine 當 cache — 用 `CacheService<V>` 才有自動失效 / 預載 / 統計

詳細實作見 `springboot-patterns` skill §【本專案】快取。

---

## 7. 非同步與排程

- **排程：** `@Scheduled` 廣泛用於 `job/` / `schedule/` / `scheduler/` 目錄（cx-sports-v2 有 100+ Quartz / Scheduler 類別）；Quartz 用於需單節點執行的場景（`cx-sports-v2/job/quartz/`）
- **非同步：** `@Async` + `@EnableAsync`
- **Spring 內部事件：** `ApplicationEventPublisher` + `@EventListener`（見 `event/listener/*Listener` 類別）— 同 JVM 內異步
- **跨服務訊息（Kafka，透過 Spring Cloud Stream）：** 本 repo 用 **`spring-cloud-starter-stream-kafka`（Finchley）**，**不是**直接用 `spring-kafka`。經典模式：
  - Channel 介面：`event/input/XxxInput.java`（含 `@Input` 方法） / `event/output/XxxOutput.java`（含 `@Output` 方法）
  - 發送：`@EnableBinding(XxxOutput.class)` + `MessageChannel`（見 `event/emitter/*Emitter` 繼承 `AbstractQuartzNotifyEmitter`）
  - 接收：`@EnableBinding(XxxInput.class)` + `@StreamListener(XxxInput.CHANNEL_NAME)`（見 `event/listener/*Listener`）
  - binder 名 `kafka-server`，設定在 `application.yml` 的 `spring.cloud.stream.binders.kafka-server`
  - bindings 命名慣例：`<domain>-<subdomain>-<event>-event`，`group` 預設與 `destination` 同名
  - **不要**改用 `@KafkaListener` / `KafkaTemplate` — 本 repo 未導入 `spring-kafka`，會找不到依賴

**規則：** Handler 必須**冪等**（排程 / Spring Event / Stream Listener 都可能重送），搭配 `orderNo` 或業務唯一鍵去重。

---

## 8. 資料物件分層（VO / SO / BO / Query / Record / Event / Config）

本專案**不用** `DTO` / `Request` / `Entity`（或極少），資料物件以以下後綴分類：

| 後綴 | 用途 | 典型位置 |
|------|------|---------|
| **`VO`** (View Object) | 回應給前端 / API 呼叫者的展示物件 | `bean/vo/`、`com.lc.sports.bean.vo.*` |
| **`SO`** (Search Object / Summary Object) | 查詢條件封裝、聚合統計結果；Service 層跨層傳遞 | `bean/so/`、`com.lc.sports.bean.*.so.*` |
| **`BO`** (Business Object) | 業務邏輯中間態物件（計算過程） | `bean/bo/`、`com.lc.sports.bean.*.bo.*` |
| **`Query`** | 查詢參數物件（Controller/Service 接收查詢條件） | `bean/query/<domain>/` |
| **`Record`** | 第三方原始業務紀錄對應物件 | `third/*` 相關套件 |
| **`Event`** | 事件訊息（Spring Event / Spring Cloud Stream Kafka） | `bean/event/`、`event/` |
| **`Config`** | Spring 設定類別 + 第三方配置物件 | `config/` |
| **領域模型** | 存入 ES / MySQL 的模型 | `com.lc.sports.bean.model.<domain>.*` |

### 判定原則

```
外部輸入（API / Form 參數）
  → Query（查詢條件） or VO（回傳）

Service 層 / 跨層傳遞
  → SO（查詢聚合）or BO（業務中間態）

領域模型（存入 ES / MySQL）
  → com.lc.sports.bean.model.<domain>.* class

事件訊息
  → Event（Spring 事件 或 Spring Cloud Stream Kafka）

第三方 API 回應解析
  → Record 或第三方專屬 bean
```

### 禁忌

- ❌ **不用 `DTO` 後綴**（本專案慣例不同）
- ❌ **不用 `Request` 後綴**（API 輸入用 `Query` 或直接參數）
- ❌ **不用 `*Entity` / `*PO`**（DAO 風格不配對 ORM Entity）
- ❌ **不隨意新增後綴**（如 `Dto`、`Params`、`Pojo`）

### 共享物件放置原則（2026-04-22 更新）

**硬規則：** SO / VO / BO / Query / Record / Event / 領域模型一律放 `cx-sport-common`（`com.lc.sports.bean.*`），**不再依「跨服務 vs 僅本服務」拆分**。

理由：經驗上搬移的成本遠大於直接放 common 的輕微重複；共享避免後續當真有跨服務需求時又要搬一次。

| 物件類型 | 位置 |
|---------|------|
| SO / VO / BO / Query / Record / Event | `cx-sport-common/.../bean/<category>/<domain>/` |
| 領域模型（Model，存 MySQL / ES） | `cx-sport-common/.../bean/model/<domain>/` |
| 框架級別工具 / 基底類 | `sport-framework` |
| 純本模組內部中介物件（如 Controller → Service 的 ad-hoc DTO） | 本模組 `bean/*` — **例外允許，但需在 PR description 說明為何不適合放 common** |

**新開流程：** 新 SO/VO → 先在 cx-sport-common 建檔 → 送 cx-sport-common MR → 發版 → bump 本 repo `pom.xml` 版本 → 再開 sport feature MR。

---

## 8.5 系統參數（Config 表 + 反射映射前端 VO）

> 重要專案慣例，L3 wiring 類需求最常踩這裡。

**儲存機制：** 所有「系統參數」都走通用 `config` 資料表（string key-value + `platform_id` + `type` + `is_show` 等欄位），**不是獨立欄位**。管理員於後台新增 / 修改時由 `ConfigService.saveOrUpdateConfigList` 寫入，key = `cfgName`（camelCase 字串）。

**反射填 VO（前端 API 讀取路徑）：**

`cx-sports-v2/src/main/java/com/lc/cp/service/setting/ConfigService.java` `getFrontConfig()`：

```java
Map<String, Object> configMap = ...  // 篩選 type=1 && isShow=0 的 config
FrontConfigVO frontConfigVO = MapUtils.mapToObject(configMap, FrontConfigVO.class);
```

`MapUtils.mapToObject` 透過 Jackson `convertValue` 反射把 configMap 的 key 映射到 VO 同名欄位。**VO 欄位名必須 = config 表 cfgName**（camelCase 嚴格一致）。

**新增 / 修改系統參數欄位標準流程：**

1. `cx-sport-common` → `FrontConfigVO.java` 新增 `private String <cfgName>;`（Javadoc 註明中文意義）— Lombok `@Data` 自動產 accessor
2. `lion-frontend/admin-frontend` → `SystemParam.vue` 相關 `configs` 初始化加 `<cfgName>: {cfgName:"<cfgName>", cfgValue:"", cfgDesc:"<中文>", type:1, isShow:0}`
   - **`type:1, isShow:0` 是反射 wire 過濾條件，寫錯整個 wire 不作用**
3. 後台 UI 加對應 `el-row`（label / v-model / saveOrUpdate / 權限碼 `v-has`）
4. `admin-frontend/src/i18n/config/{zh,en,vi,tl}/components/system.json` 各補 `cfgName` key（先 `ls` 確認 locale 目錄是否有 system.json；無 import 的 locale 跟現狀對稱即可）
5. `admin-frontend/script/importJson/zh.json` 同步補 key
6. **後端 `ConfigService.java` 不用改** — 反射自動處理
7. DB schema 不用 migration — `config` 表首次保存時自動 insert

**常見陷阱：**

| 陷阱 | 症狀 |
|------|------|
| grep 找不到 `setXxxCfg` → 誤判 dead code | 反射映射不走 explicit setter 呼叫；要 grep `MapUtils.mapToObject` / `BeanUtils.copyProperties` / `ObjectMapper.convertValue` |
| `FrontConfigVO` 加了欄位但 `type` / `isShow` 寫錯 | API response 缺欄位 |
| 類別標 `@JsonInclude(NON_NULL)` → 未存值時 response 不含 key | 正常行為，不是空字串。QA R3 驗收時注意 |
| cx-sport-common 版本是否 bump | 看團隊慣例 — 同版號 overwrite 省 MR 但犧牲追溯性；bump 版本要多一個下游 pom bump MR |

**延伸：** 「內部服務 config」（非前端可見） → 走 `*ConfigCache` 而非反射，見 §6.5。

---

## 9. DAO 風格

- MySQL DAO：繼承 `MyBatis-Plus BaseMapper<Model, PK>`（見 `zz_document/实体类生成步骤.md`），搭配 MyBatis `mapper-starter` + `pagehelper` + **ShardingSphere** 主從分片
- ES DAO：繼承 cx-sport-common 提供的 ES 基底 DAO（類別名以模組為準），搭配 `ES 主從切換 aspect (v2 ES 6/7 並存)` 做主從切換
- **禁忌：** 不直接在 Service 裡寫 JDBC / 原生 Query；不使用 `JpaRepository`（非本專案選型）

---

## 10. 其他硬規則（跨檔引用）

- **金額 / RoundingMode：** 見 `rules/security.md`
- **時區：** 系統統一 GMT+8（依既有 `DateUtil` 慣例）

---

## 相關資源

| 主題 | 位置 |
|------|------|
| 格式 / 命名 / Log / Lombok / 語法偏好 | `rules/coding-style.md` |
| 金額 RoundingMode 場景規則 | `rules/security.md` |
| Spring Boot 架構（快取、事件、排程） | `springboot-patterns` skill |
| DAO / ShardingSphere / MyBatis | `mysql-patterns` skill |
| ES 分庫與多版本並用 | `es-patterns` skill |
| 新第三方服務對接實作 | `api-connector-builder` skill（需依本服務慣例客製） |
