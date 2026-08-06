---
name: springboot-patterns
description: Spring Boot 架構模式 + Java 8 編碼重點 — REST API、分層 Service、DAO、Lombok、例外、非同步、雙層 Cache、Spring Cloud Stream Kafka、日誌。適用於 cx-sports-v2 後端開發。
origin: ECC
---

# Spring Boot 開發模式（含 Java 8 編碼重點）

可擴展、生產等級服務的 Spring Boot 架構與 API 模式。本 skill 同時涵蓋 cx-sports-v2 對 Java 8 編碼的特化要求；通用 Java 寫法（命名、`final`、Optional 觀念、Streams 簡短、Log 等級）見 `rules/coding-style.md`。

## 啟用時機

- 以 Spring MVC 建置 REST API
- 規劃 controller → service → repository 分層
- 設定 Spring Data JPA 或非同步處理
- 新增驗證、例外處理或分頁
- 寫 Service / Controller / DAO 時對齊本專案 Lombok / DI / 例外 / 日誌慣例

## Java 8 編碼重點（本專案 baseline）

> 通用部分（命名、`final`、Optional、Streams 簡短）見 `rules/coding-style.md`，本節只列**本專案 Java 8 + Lombok 特化**或**容易踩坑**的點。

### Lombok：`@Data` 而非 `@Value`

本專案 Request / Response / BO / VO **一律 `@Data`**，不要用 `@Value`（會與 MyBatis / Jackson 反序列化的 setter 慣例衝突）。

### Streams：用 `Collectors.toList()` 不要 `.toList()`

本專案是 Java 8，**沒有** Java 16+ 的 `Stream.toList()`：

```java
// ✅ Java 8
list.stream().filter(...).collect(Collectors.toList());

// ❌ Java 16+ 才有，本專案編譯不過
list.stream().filter(...).toList();
```

- 方法參考優先：`.map(Order::getTotal)` 比 lambda 可讀
- Stream pipeline > 3-4 步驟 → 改寫迴圈或抽方法
- 不在 stream 操作中產生副作用（log、DB 寫入）

### Optional：不當欄位 / 不當參數

```java
// ✅ 查詢回傳 Optional，pipeline 用 map / orElseThrow
return userDao.findById(id)
    .map(UserVO::from)
    .orElseThrow(() -> new BusinessException("USER_NOT_FOUND", "user not found"));

// ❌ 不要當欄位
private Optional<String> name;

// ❌ 不要當參數
public void process(Optional<String> name) { ... }  // 改成 overload 或 nullable
```

- **禁止**先 `isPresent()` 再 `get()` — 一律走 `map` / `flatMap` / `orElseThrow`

### 例外處理

- 業務錯誤拋框架 `BusinessException`
- `catch` **至少 `log.error`**，不要靜默吞例外

### 不可變性（受限）

- 純值物件可用 `@Value` + `final` 欄位（少數 constants/config 場景）
- Request / Response 用 `@Data`（Jackson 需要 setter）

## REST API 結構

```java
@RestController
@RequestMapping("/api/markets")
@Validated
class MarketController {
  private final MarketService marketService;

  MarketController(MarketService marketService) {
    this.marketService = marketService;
  }

  @GetMapping
  ResponseEntity<Page<MarketResponse>> list(
      @RequestParam(defaultValue = "0") int page,
      @RequestParam(defaultValue = "20") int size) {
    Page<Market> markets = marketService.list(PageRequest.of(page, size));
    return ResponseEntity.ok(markets.map(MarketResponse::from));
  }

  @PostMapping
  ResponseEntity<MarketResponse> create(@Valid @RequestBody CreateMarketRequest request) {
    Market market = marketService.create(request);
    return ResponseEntity.status(HttpStatus.CREATED).body(MarketResponse.from(market));
  }
}
```

## DAO 模式（本專案框架）

**本專案不使用 `JpaRepository`**。DAO 繼承 `com.cx.framework.dao.*` 底下的抽象基類（sport-framework 提供）：

```java
// MySQL
@Repository
public class UserMoneyDao extends BaseMapper<UserMoney, Long> {
  // 基類提供 save / find / update / delete / page
}

// Elasticsearch（按日分區索引 — 時間序列主流場景）
import com.cx.framework.dao.AbstractEsPartitionByDateDao;

@Repository
public class ThirdDailyReportEsDao extends AbstractEsPartitionByDateDao<ThirdDailyReport> {
  // 基類提供 save / find / query / page
}
```

- MySQL 層 DAO → 繼承 MyBatis-Plus `BaseMapper`，搭配 MyBatis `mapper-starter` + `pagehelper` + ShardingSphere
- ES 層 DAO → 繼承 `AbstractBaseEsDao` / `AbstractEsPartitionByDateDao` / `AbstractEsSingleIndexDao`（選擇依見 `es-patterns` skill）
- **不用** `JpaRepository` / `CrudRepository`
- 共享 DAO 優先放 **cx-sport-common**（`com.lc.sports.dao.*`）

## Service 層與交易

```java
@Slf4j
@Service
@RequiredArgsConstructor  // 新程式碼建議建構子注入
public class MarketService {
  private final ExternalRecordDao externalRecordDao;

  @Transactional
  public ThirdOrder create(CreateOrderRequest request) {
    ThirdOrder order = ThirdOrder.from(request);
    externalRecordDao.save(order);
    return order;
  }
}
```

> **DI 風格：** 新程式碼用 `@RequiredArgsConstructor` 建構子注入；既有程式碼大量 `@Resource` 欄位注入（420 處）並存，不強制重構。詳見 `rules/patterns.md`。

## DTO 與驗證

本專案 Request / Response DTO 統一使用 **`@Data`**（專案 732 處），不用 `@Value`（144 處主要在 constants/config）：

```java
@Data
public class CreateMarketRequest {
  @NotBlank @Size(max = 200) private String name;
  @NotBlank @Size(max = 2000) private String description;
  @NotNull @FutureOrPresent private Instant endDate;
  @NotEmpty private List<String> categories;
}

@Data
public class MarketResponse {
  private Long id;
  private String name;
  private MarketStatus status;

  public static MarketResponse from(Market market) {
    return new MarketResponse(market.getId(), market.getName(), market.getStatus());
  }
}
```

## 例外處理

**本專案使用框架層例外**（`com.cx.framework.exception.*`），**不使用** `@ControllerAdvice` 統一處理：

```java
import com.cx.framework.exception.BusinessException;
import com.cx.framework.exception.DaoException;

// Service / Provider 拋業務例外
throw new BusinessException("ERR_CODE", "user friendly message");

// DAO 層拋資料例外
throw new DaoException("query failed", e);
```

- `BusinessException` — 業務規則違反（餘額不足、狀態不對等），Controller 層會統一攔截回應
- `DaoException` — 資料存取錯誤
- **不要自製新的 Exception class** 或 `@ControllerAdvice`，沿用框架機制
- `catch` 內**至少 `log.error`**，不要吞例外

## 非同步處理

需要在設定類別上加入 `@EnableAsync`。

```java
@Service
public class NotificationService {
  @Async
  public CompletableFuture<Void> sendAsync(Notification notification) {
    return CompletableFuture.completedFuture(null);
  }
}
```

## 日誌記錄（SLF4J + Lombok）

**本專案全面使用 Lombok `@Slf4j`**（378 處），**不要**手寫 `LoggerFactory.getLogger()`（專案 0 處）。

```java
import lombok.extern.slf4j.Slf4j;

@Slf4j
@Service
public class ReportService {

  public Report generate(Long marketId) {
    log.info("generate_report marketId={}", marketId);
    try {
      // 邏輯
    } catch (Exception ex) {
      log.error("generate_report_failed marketId={}", marketId, ex);
      throw ex;
    }
    return new Report();
  }
}
```

Log 等級規範見 `rules/coding-style.md`（訊息英文 / `info`+`error` 為主 / `warn` 限系統級告警 / 禁 `debug`+`trace`）。

## Middleware / Filter

```java
@Slf4j
@Component
public class RequestLoggingFilter extends OncePerRequestFilter {

  @Override
  protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
      FilterChain filterChain) throws ServletException, IOException {
    long start = System.currentTimeMillis();
    try {
      filterChain.doFilter(request, response);
    } finally {
      long duration = System.currentTimeMillis() - start;
      log.info("req method={} uri={} status={} durationMs={}",
          request.getMethod(), request.getRequestURI(), response.getStatus(), duration);
    }
  }
}
```

## 分頁與排序

```java
PageRequest page = PageRequest.of(pageNumber, pageSize, Sort.by("createdAt").descending());
Page<Market> results = marketService.list(page);
```

## 具容錯能力的外部呼叫

```java
public <T> T withRetry(Supplier<T> supplier, int maxRetries) {
  int attempts = 0;
  while (true) {
    try {
      return supplier.get();
    } catch (Exception ex) {
      attempts++;
      if (attempts >= maxRetries) {
        throw ex;
      }
      try {
        Thread.sleep((long) Math.pow(2, attempts) * 100L);
      } catch (InterruptedException ie) {
        Thread.currentThread().interrupt();
        throw ex;
      }
    }
  }
}
```

## 【本專案】快取（雙層架構）

本 repo 是 **Redis + Guava LoadingCache 雙層架構**，**不是** Spring `@Cacheable`。兩層角色不同，搞混會造成錯誤：

```
              ┌─────────────────────────────────────┐
              │   Redis（跨節點共享狀態）             │  ← 分散式鎖、Session、
              │   jedis / lettuce + RedisTemplate    │    排行榜、大容量資料
              └─────────────────────────────────────┘
                              ↕
              ┌─────────────────────────────────────┐
              │   CacheService<V> (cx-sport-common)      │  ← 讀多寫少的配置
              │   Guava LoadingCache + Kafka         │    / 字典 / 預載資料
              │   （每節點一份本地 cache）            │
              └─────────────────────────────────────┘
                              ↕
              ┌─────────────────────────────────────┐
              │   MySQL / ES（資料源）               │
              └─────────────────────────────────────┘
```

### 第一層：Redis

- **底層 driver：** 預設 **Lettuce**（`lettuce-core 5.0.4`，見 `spring.redis.lettuce.pool` 設定）；`cx-sport-app-service/config/RedisConfig.java` 另用 **Jedis + RedisSentinel**（支援 Redis 哨兵模式）
- **開發者 API：**
  - 通用：`RedisTemplate` / `StringRedisTemplate`
  - 收集類工具：`cx-sport-app-service/util/RedisUtil.java`
  - **不要**直接 `new Jedis()` 或 `jedisPool.getResource()`
- **Key 命名：** 用常數（例：`cx-sport-app-service/constants/RedisKey.java`），**不要**在業務碼裡散落字串 literal
- **應用場景：** 分散式鎖（Redis SETNX）、Session、跨節點共享狀態、排行榜、大容量暫存

### 第二層：CacheService<V>（Guava + Kafka 失效通知）

位置：**`cx-sport-common/src/main/java/com/lc/common/service/cache/CacheService.java`**（全生態共用的基類）

#### 典型實作

```java
@Component
public class PayConfigCache extends CacheService<PayConfigBO> {

    @Resource private PayService payService;

    @Override protected String cacheName() {
        return EnumClass.SystemCacheNames.payConfigCache.getCacheName();   // 必登記
    }

    @Override protected Function<String, PayConfigBO> loadFunc() {
        return k -> payService.loadPayConfig(Long.valueOf(k));             // cache miss 時載入
    }

    @Override protected long getCacheTimeoutMinute() {
        return FIVE_MINUTE;   // 基類常數：ONE_MINUTE / FIVE_MINUTE / HALF_HOUR / ONE_HOUR / ONE_DAY / ONE_YEAR
    }
}
```

取值：`payConfigCache.getByCache(key)` / `getByCacheWithoutException(key)` / `getListByCache(keys)` / `forceGetWithoutCache(key)`（繞過 cache）

#### 預設值（基類）
- 初始容量 100、最大容量 10000、過期 `expireAfterWrite`（子類指定分鐘）、`recordStats()`（有 cache hit/miss 統計）

#### 啟動預載（`CacheInitLoading`）

需啟動時載入的 cache 實作 `CacheInitLoading` 介面：

```java
@Component
public class GameCache extends CacheService<Map<Long, Game>> implements CacheInitLoading {
    @Override public void initLoading() { /* 預熱 */ }
}
```

`cx-sport-common/cache/CacheInitRunner.java`（`CommandLineRunner`）啟動時掃描所有 `CacheInitLoading` bean 依序 `initLoading()`。**錯誤會讓所有服務啟動失敗**（見 cx-sport-common CLAUDE.md 高風險熱區）。

#### 跨節點失效（**這就是為什麼本 repo 用 Spring Cloud Stream Kafka**）

各節點的 Guava cache 獨立，**資料變動時必須通知所有節點失效**：

```java
// 變動 DB 後，通知所有節點清除本地 cache 對應 key
payConfigCache.invalidate(payConfigId.toString());
//     ↓ 內部呼叫 CacheNotifyService.notifyOne(key, cacheName)
//     ↓ 透過 CacheOutput（@EnableBinding, Kafka）發 event
//     ↓ 所有節點的 CacheService<V> base 有 @StreamListener(CacheInput.CACHE_INPUT)
//     ↓ 收到 event 後比對 cacheName，invalidate 本地 Guava cache
```

> **寫 DB 後務必呼叫 `invalidate(key)`**，否則其他節點會讀到 stale 資料。

#### ShardingSphere hint

Cache `loadFunc()` 內用 `HintManager.getInstance().setMasterRouteOnly()` 強制查主庫（避免主從延遲讀到舊資料）：

```java
@Override protected Function<String, Map<Long, Game>> loadFunc() {
    return key -> {
        try (HintManager hintManager = HintManager.getInstance()) {
            hintManager.setMasterRouteOnly();
            return gameDao.queryAll()...;
        }
    };
}
```

### 分佈

| 位置 | 內容 | 數量 |
|------|------|------|
| `cx-sport-app-service/.../com/lc/sports/cache/` | 主業務 cache（Match / League / Play / Odds / BetRank / Season 等，含 `cxsource` / `europecup` / `frontapi` / `mts` / `rc` / `singlewallet` / `trackermapping` 子目錄） | 50+ 個 |
| `cx-sport-app-service/.../com/lc/common/cache/` | 共用 cache（lion 生態殘留） | 數個 |
| `cx-sport-app-service/.../com/lc/cp/cache/` | 支付 / cp 業務 cache | 數個 |
| `cx-sport-mq-collector-service/.../com/lc/sports/cache/` | mq-collector 共用（與主業務同 package 便於共享） | 數個 |
| `cx-sport-single-wallet-service/.../com/lc/single/wallet/cache/` | 單錢包 cache（`currency` / `game` / `quest` / `third` / `impl` 子目錄，含 `CacheService` 基類 + Kafka 失效通知的 `CacheNotifyService`） | 十數個 |

**sport 沒有跨 repo 的共享 cache**：`cx-sports-v2/lib/cx-sport-common/` 目前不放 cache；新 cache 直接放所屬子專案的 `cache/<domain>/` 目錄。若為 cx-sports-v2 內部跨模組共用，可擺 `com/lc/sports/cache/`（被 app-service / mq-collector-service 共用）。

### 禁用 / 注意

- ❌ 不使用 Spring `@Cacheable` / `@CacheEvict`（0 處）
- ❌ 不手寫 `ConcurrentHashMap` 當 cache — 用 `CacheService<V>`（自動失效 + 統計 + 預載）
- ❌ 寫 DB 後不呼 `invalidate(key)` — 其他節點會讀到舊資料
- ❌ 新 cache 忘了登記 `EnumClass.SystemCacheNames` 會在執行期拋 enum lookup 錯
- ⚠️ `initLoading()` 錯誤會讓**整個服務啟動失敗**（透過 `CacheInitRunner`）— 先抓例外再決定 rethrow

## 【本專案】熔斷限流

- **本 repo（sport）目前無 Alibaba Sentinel / Bucket4j / Resilience4j / Spring Cloud Gateway**（grep `pom.xml` 與原始碼確認）
- application.yml 中的 `spring.redis.mode: standalone | sentinel | cluster` 是 **Redis Sentinel 哨兵模式**，跟限流無關
- 若要新增限流點，**先開架構討論**（不是抓既有模式套上去），可走 Filter / 切面 / Spring Cloud Gateway 上游攔截

## 【本專案】Kafka via Spring Cloud Stream

> ⚠️ 本 repo 用的是 **Spring Cloud Stream + Kafka binder**（`spring-cloud-starter-stream-kafka`，Spring Cloud **Finchley**）— **不是**直接用 `spring-kafka`。不要用 `@KafkaListener` / `KafkaTemplate`，會找不到依賴。

### 目錄慣例（`cx-sports-v2/event/` 最完整）

```
event/
├── input/        # @Input 介面（接收端 channel 宣告）
│   └── XxxInput.java           # interface with @Input("channel-name") SubscribableChannel
├── output/       # @Output 介面（發送端 channel 宣告）
│   └── XxxOutput.java          # interface with @Output("channel-name") MessageChannel
├── emitter/      # 發送端實作（@EnableBinding + 取得 MessageChannel）
│   └── XxxEmitter.java
└── listener/     # 接收端實作（@EnableBinding + @StreamListener）
    └── XxxListener.java
```

### 發送（Emitter）

```java
@EnableBinding(ThirdOrderOutput.class)
public class ThirdOrderQuartzNotifyEmitter extends AbstractQuartzNotifyEmitter {
    @Resource private ThirdOrderOutput thirdOrderOutput;

    @Override
    protected MessageChannel getMessageChannel() {
        return thirdOrderOutput.quartzOutput();   // 從 Output 介面取 channel
    }
}
```

### 接收（Listener）

```java
@Component
@EnableBinding(CacheInput.class)
public class GameTurnNumUnSettleCache {

    @StreamListener(CacheInput.CACHE_INPUT)   // channel 名
    public void handle(CacheEvent event) {
        // 業務（必須冪等，SCS 會重送）
    }
}
```

### application.yml 配置

```yaml
spring:
  cloud:
    stream:
      bindings:
        <channel-name>-output:
          destination: <topic-name>
          content-type: application/json
          group: <group-id>               # 慣例：group 與 destination 同名
      binders:
        kafka-server:                     # binder 名（可多 binder；本 repo 只一個）
          type: kafka
          environment:
            spring.cloud.stream.kafka.binder:
              brokers: localhost:9092
              zkNodes: localhost:2181
```

### 慣例

- Destination / topic 命名：`<domain>-<subdomain>-<event>-event`（例：`activity-system-recharge-activity-event`）
- `group` 預設等於 `destination`
- 新增 channel 時：**同時**加 `input/` 或 `output/` 介面、`emitter/` 或 `listener/` 類別、`application.yml` 的 `bindings` + `group` — 缺一不可
- Listener **必須冪等**（SCS 重試、rebalance 都會重送）；搭配 `orderNo` / 業務唯一鍵去重
- **不要混用** `@KafkaListener` / `KafkaTemplate`（那是 `spring-kafka`，本 repo 未引入）

## 背景工作

使用 Spring `@Scheduled`（`@Scheduled` 廣泛用於 `cx-sports-v2/job/scheduler/`、`cx-sport-single-wallet-service/schedule/`）或 Quartz（`cx-sports-v2/job/quartz/`，需單節點執行時用）。Handler 必須冪等（搭配 `orderNo` / 業務唯一鍵去重）。

## 可觀測性

- **Logback**（`logback-spring.xml` 在每個模組的 `src/main/resources/`）— **純文字 pattern（非 JSON）**：`%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{50} -%X{traceId}-%X{uri} %msg%n`。若要改 JSON 要全模組同步改 appender 並加 `net.logstash.logback` 依賴
- **指標**：Micrometer + Prometheus（`micrometer-registry-prometheus` 在 cx-sports-v2 / cx-sport-single-wallet-service）+ **Spring Boot Admin Client**（`spring-boot-admin-starter-client`）推送到 Admin Server
- **Tracing：** MDC 自己塞的 `traceId` / `uri`（見 logback pattern 中 `%X{traceId}`），非 Sleuth/Zipkin 自動化

## 生產預設值

- **依賴注入：** 新程式碼建議建構子注入（`@RequiredArgsConstructor`），但**本專案實況 `@Resource` 欄位注入為主（cx-sports-v2 單一模組 4000+ 處）**，既有程式碼不強制重構；`rules/patterns.md` 的硬規則僅套用於新寫的類別
- **例外處理：** 只有 `cx-sport-single-wallet-service/handler/GlobalExceptionHandler.java`（`@RestControllerAdvice`）有統一例外處理；`cx-sports-v2` **無 `@ControllerAdvice`**，靠 Controller 自己 try-catch 或 Spring 預設機制。新 Controller 若需要統一回應信封，先照 single-wallet 的 handler 寫法擴充，不要另起新格式
- **分頁：** 本專案**無統一分頁慣例**。`pagehelper 1.2.5` 有設定但程式碼 0 處呼叫；Spring Data `PageRequest` 零星出現（例：`cx-sports-v2/service/setting/MonitorHistoryService.java`）；多數端點靠 DAO 手寫 `LIMIT` + 前端送 `pageNum` / `pageSize` 參數。新增分頁端點前先看同 domain 既有 Controller 怎麼寫
- **Repository：** 專案**不使用 `JpaRepository`**，資料存取走扁平 DAO + 手寫 SQL（見 `mysql-patterns` skill）
- 為工作負載設定 HikariCP 連線池大小與逾時
- 查詢使用 `@Transactional(readOnly = true)`

**牢記**：保持 controller 精簡、service 專注、DAO 簡單，並對齊本專案既有模式而非套用通用 Spring Boot 預設。
