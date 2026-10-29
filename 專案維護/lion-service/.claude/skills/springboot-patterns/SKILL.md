---
name: springboot-patterns
description: Spring Boot 架構模式 + Java 8 編碼重點 — REST API、分層 Service、DAO、Lombok、例外、非同步、雙層 Cache、Spring Cloud Stream Kafka、日誌。適用於 lion-service 後端開發（Java 8 / Spring Boot 2.0.2 / Spring Cloud Finchley）。
origin: ECC
---

# Spring Boot 開發模式（含 Java 8 編碼重點）

可擴展、生產等級服務的 Spring Boot 架構與 API 模式。本 skill 同時涵蓋 lion-service 對 Java 8 編碼的特化要求；通用 Java 寫法（命名、`final`、Optional 觀念、Streams 簡短、Log 等級）見 `rules/coding-style.md`。

## 啟用時機

- 以 Spring MVC 建置 REST API
- 規劃 controller → service → DAO 分層
- 設定非同步處理、快取、Kafka（Spring Cloud Stream）
- 新增驗證、例外處理或分頁
- 寫 Service / Controller / DAO 時對齊本專案 Lombok / DI / 例外 / 日誌慣例

## Java 8 編碼重點（本專案 baseline）

> 通用部分（命名、`final`、Optional、Streams 簡短）見 `rules/coding-style.md`，本節只列**本專案 Java 8 + Lombok 特化**或**容易踩坑**的點。

### Lombok：`@Data` 而非 `@Value`

本專案 SO / Query / BO / VO / Record **一律 `@Data`**，不要用 `@Value`（會與 Jackson 反序列化與 framework_v3 DAO 反射映射的 setter 慣例衝突）。

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
// ✅ 可能為 null 的查詢結果包 Optional，pipeline 用 map / orElseThrow
//    （MysqlBaseDao.get(PK) 回傳 T 或 null；BusinessException 用 int code，見 rules/coding-style.md §7）
return Optional.ofNullable(userInfoDao.get(id))
    .map(UserVO::from)
    .orElseThrow(() -> new BusinessException(
        ErrorCodesEnum.UserService.USER_NOT_FOUND.code, ErrorCodesEnum.UserService.USER_NOT_FOUND.desc));

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
- SO / VO 用 `@Data`（Jackson 需要 setter）

## REST API 結構

回應信封用 framework_v3 既有的 `RespBean<T>` / `RespListOtherBean<T, O>` 等（**不自製** `ApiResponse`，`rules/patterns.md` §4）；登入者與 platformId 由 resolver 注入（`UserIdWithPlatformId` / `PlatformId` / `TokenInfo`），**不從 SO 取**（`rules/platform-isolation.md`）。

```java
@RestController
@RequestMapping("/api/admin/market")
@RequiredArgsConstructor
public class MarketController {
  private final MarketService marketService;

  @RequestMapping("/list")
  public RespBean<PageData<MarketVO>> list(MarketQuery query, UserIdWithPlatformId uid) {
    return new RespBean<>(marketService.list(query, uid.getPlatformId()));
  }

  @PostMapping("/create")
  public RespBean<MarketVO> create(@Valid @RequestBody CreateMarketSO so, UserIdWithPlatformId uid) {
    return new RespBean<>(marketService.create(so, uid.getPlatformId()));
  }
}
```

- 實際路徑前綴、`@RequestMapping` / `@PostMapping` 用法、回傳型別 → **對齊同 controller 子目錄既有寫法**（cp-service `controller/` 依角色分 `admin/ front/ agent/ boss/ manage/ third/ internal/ …`）

## DAO 模式（本專案框架）

**lion 沒有 MyBatis，也不用 `JpaRepository`。** DAO 繼承 framework_v3（`com.cx.framework.dao.*`）的抽象基類：

```java
// MySQL（lion-common com.lc.common.dao.user.UserMoneyDao 節錄）
@Repository
public class UserMoneyDao extends MysqlBaseDaoImpl<UserMoney, Long> {
  public List<UserMoney> queryByMoney(String minMoney, String maxMoney, Long platformId) {
    return buildSelectWhere()
        .andEqual("platform_id", platformId)
        .addSqlAndArgs(" and money >= ?", minMoney)
        .queryList();
  }
}

// Elasticsearch（按日分區索引 — 時間序列主流場景）
@Repository
public class ThirdDailyReportEsDao extends AbstractEsPartitionByDateDao<ThirdDailyReport> {
  // 基類提供 save / queryAll / queryAggregations / queryForPage / getIndexesByDate
}
```

- MySQL 層 DAO → `MysqlBaseDaoImpl<T, PK>` + `SqlUtil` 鏈式組 SQL、參數走 `?` 綁定，搭配 ShardingSphere 4.0.1（`skills/mysql-patterns/SKILL.md`）
- ES 層 DAO → `AbstractEsPartitionByDateDao` / `AbstractEsSingleIndexDao`（`skills/es-patterns/SKILL.md`）
- **不寫** mapper / XML；**不用** `JpaRepository` / `CrudRepository`
- 共享 DAO 優先放 **lion-common**（`com.lc.common.dao.<domain>.*`，跨 repo）

## Service 層與交易

```java
@Slf4j
@Service
@RequiredArgsConstructor  // 新程式碼建議建構子注入
public class MarketService {
  private final ExternalRecordDao externalRecordDao;

  @Transactional(rollbackFor = Exception.class)
  public ThirdOrder create(CreateOrderSO so, Long platformId) {
    ThirdOrder order = ThirdOrder.from(so, platformId);
    externalRecordDao.save(order);
    return order;
  }
}
```

> **DI 風格：** 新程式碼用 `@RequiredArgsConstructor` 建構子注入；既有程式碼大量 `@Resource` 欄位注入（cp-service 4000+ 處）並存，不強制重構。詳見 `rules/patterns.md` §2。
> **事務：** 交易內不得呼叫外部 API；同類自呼叫會讓 `@Transactional` 失效（`checks/transactional-remote-call.md`）。

## 請求 / 回應物件與驗證

lion **不用 `DTO` / `Request` / `Response` 命名**：請求 → `SO` / `Query`，回應 → `VO` / `Record`（`rules/patterns.md` §8）；共享的放 lion-common。一律 **`@Data`**，不用 `@Value`（`@Value` 只用在少數 constants / config）：

```java
@Data
public class CreateMarketSO {
  @NotBlank @Size(max = 200) private String name;
  @NotBlank @Size(max = 2000) private String description;
  @NotNull private Date endDate;
  @NotEmpty private List<String> categories;
  // 不放 platformId 當授權依據（由 resolver 取得）
}

@Data
public class MarketVO {
  private Long id;
  private String name;
  private Integer status;

  public static MarketVO from(Market market) {
    MarketVO vo = new MarketVO();
    vo.setId(market.getId());
    vo.setName(market.getName());
    vo.setStatus(market.getStatus());
    return vo;
  }
}
```

## 例外處理

**本專案使用框架層例外**（framework_v3 `com.cx.framework.exception.*`：`BusinessException` / `DaoException` / `ParaException` / `PermissionException` / `UnauthorizedException`）：

```java
import com.cx.framework.exception.BusinessException;

// Service 拋業務例外：int code + message，code 登記在 lion-common ErrorCodesEnum（rules/coding-style.md §7）
throw new BusinessException(
    ErrorCodesEnum.UserService.MUST_AN_AGENT.code,
    ErrorCodesEnum.UserService.MUST_AN_AGENT.desc);
```

- **`new BusinessException("STRING_CODE", "msg")` 編譯不過**（沒有 `(String, String)` constructor）
- 例外轉回應的機制各模組不同：cp-service 走 `config/WebExceptionResolver` + `controller/ErrorController`；single-wallet 有 `handler/GlobalExceptionHandler`（`@RestControllerAdvice`，回廠商一律 HTTP 200、錯誤碼在 body）；collector 有 `handler/BigoCallbackExceptionHandler`。**新增端點沿用所在模組的機制，不要另加 `@ControllerAdvice`**
- **不要自製新的 Exception class**，沿用框架例外
- `catch` 內**至少 `log.error`**，不要吞例外（`checks/silent-failure.md`）

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

**本專案全面使用 Lombok `@Slf4j`**（700+ 個檔），**不要**手寫 `LoggerFactory.getLogger()`（專案 0 處）。

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

> **lion 紅線：** 認證 filter 曾因 `.do` 副檔名放行被實際入侵。新增 / 修改 `*Filter` = L1；**禁止新增副檔名 / 子字串 / `contains` 型放行**，放行用精確路徑、比對前正規化、檢查失敗必 `return`（`rules/security.md` §filter 防線、`checks/filter-bypass.md`）。下例只示範 log filter 骨架，不含放行邏輯。

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

lion 的分頁走 framework_v3 `PageBean`（入參）+ `PageData<T>`（回傳）：MySQL 用 `SqlUtil.queryPage(PageBean)`，ES 用基類 `queryForPage(...)`。Spring Data `PageRequest` 只零星出現，**不要**當新端點的範本；`pagehelper` 只在根 pom dependencyManagement，程式碼沒用。

```java
public PageData<MarketVO> list(MarketQuery query, Long platformId) {
  return marketDao.buildSelectWhere()
      .andEqual("platform_id", platformId)
      .addSql(" order by id desc")
      .queryPage(query.getPageBean(), MarketVO.class);
}
```

- 排序欄位若來自請求 → 白名單映射，不得直接拼進 SQL（`skills/springboot-security/SKILL.md`）

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
              │   CacheService<V> (lion-common)      │  ← 讀多寫少的配置
              │   Guava LoadingCache + Kafka         │    / 字典 / 預載資料
              │   （每節點一份本地 cache）            │
              └─────────────────────────────────────┘
                              ↕
              ┌─────────────────────────────────────┐
              │   MySQL / ES（資料源）               │
              └─────────────────────────────────────┘
```

### 第一層：Redis

- **底層 driver：** cp-service / single-wallet-service 走 lion-common 的 `config/RedisLettuceConfig`（**Lettuce** `5.0.4`，支援 Sentinel）；lion-common 另有 Jedis 版 `config/RedisConfig`；**collector-service 用自己的 Jedis `config/RedisConfig` + `util/RedisUtil`**
- **開發者 API：**
  - 通用：`RedisTemplate` / `StringRedisTemplate`（對齊同模組既有注入的 bean 名）
  - 封裝好的 Redis 快取類：lion-common `com.lc.common.redis.*`（依 domain 分子包）、cp-service `redis/`
  - 分散式鎖：lion-common `com.lc.common.redis.RedisLock`（`lock` / `unLock`，依 `ServiceName` 分群）
  - **不要**直接 `new Jedis()` 或 `jedisPool.getResource()`
- **Key 命名：** 用常數（lion-common `constants/RedisKey`；collector 用自己的 `constants/RedisKey`），**不要**在業務碼裡散落字串 literal；**key 要帶 platformId 維度**（`rules/platform-isolation.md`）
- **應用場景：** 分散式鎖、Session、跨節點共享狀態、排行榜、大容量暫存

### 第二層：CacheService<V>（Guava + Kafka 失效通知）

位置：**lion-common `com.lc.common.service.cache.CacheService`**（全生態共用的基類；帶參數版 `CacheServiceWithArgs<V, ARGS>`）

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

lion-common `com.lc.common.cache.CacheInitRunner`（`CommandLineRunner`）啟動時掃描所有 `CacheInitLoading` bean 依序 `initLoading()`。**例外會被吞掉（只 `log.error` + `printStackTrace`）——服務照常啟動，但該 cache 沒預熱**，第一次讀才 lazy load；預熱失敗不會有人發現，`initLoading()` 內要自己把失敗原因 log 清楚。

#### 跨節點失效（**這就是為什麼本 repo 用 Spring Cloud Stream Kafka**）

`CacheService` 基類本身 `@EnableBinding(CacheInput.class)`，channel `input10000` 綁 topic `cache-refresh`，**group 用 `${anonymous.group.name}`（`host:app:port`，每個節點一個 group）** → 每個節點都收得到，才做得到「全節點失效」。

各節點的 Guava cache 獨立，**資料變動時必須通知所有節點失效**：

```java
// 變動 DB 後，通知所有節點清除本地 cache 對應 key
payConfigCache.invalidate(payConfigId.toString());
//     ↓ 內部呼叫 CacheNotifyService.notifyOne(key, cacheName)
//     ↓ 透過 CacheOutput（@EnableBinding, Kafka）發 event
//     ↓ 所有節點的 CacheService<V> base 有 @StreamListener(CacheInput.CACHE_INPUT)（input10000 / cache-refresh）
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

| 位置 | 內容 |
|------|------|
| lion-common `com.lc.common.cache.<domain>/` | **共用 cache 主體**（`activity` `agentline` `game` `lottery` `playcom` `setting` `user` … 二十多個 domain 子包） |
| cp-service `com.lc.cp.cache/` | 本模組專屬（`PayConfigCache`、`TelegramConfigCache`、`*UnSettleCache`、`*UnCheckCache` 等，另有 `quest/` `worldcup/`） |
| single-wallet-service `com.lc.single.wallet.cache/` | 單錢包專屬（如 `BalanceCache`） |

**新 cache 放哪（決議）：** 共用 → lion-common `cache/<domain>/`（跨 repo，`skills/cross-repo-commit/SKILL.md`）；僅本模組用 → 本模組 `cache/`（`rules/patterns.md` §6.5）。

### 禁用 / 注意

- ❌ 不使用 Spring `@Cacheable` / `@CacheEvict`（0 處）
- ❌ 不手寫 `ConcurrentHashMap` 當 cache — 用 `CacheService<V>`（自動失效 + 統計 + 預載）
- ❌ 寫 DB 後不呼 `invalidate(key)` — 其他節點會讀到舊資料
- ❌ 新 cache 忘了登記 lion-common `EnumClass.SystemCacheNames` 會在執行期拋 enum lookup 錯
- ❌ cache key 沒帶 platformId → A 家讀到 B 家的設定（`rules/platform-isolation.md`）
- ⚠️ `initLoading()` 失敗會被 `CacheInitRunner` 吞掉 —— 啟動成功不代表預熱成功

## 【本專案】熔斷限流

- **本 repo（lion-service）目前無 Alibaba Sentinel / Bucket4j / Resilience4j / Hystrix / Spring Cloud Gateway**（pom 查無）；Redis 設定裡的 Sentinel 是 **Redis 哨兵模式**，跟限流無關
- 既有的局部防重 / 限頻：cp-service `aspect/AccessLimitAspect`（`@AccessLimit`，lion-common annotation，Redis 鎖）—— 單一端點防重複提交優先用它
- 若要新增全站限流，**先開架構討論**（不是抓既有模式套上去）

## 【本專案】Kafka via Spring Cloud Stream

> ⚠️ 本 repo 用的是 **Spring Cloud Stream + Kafka binder**（`spring-cloud-starter-stream-kafka`，Spring Cloud **Finchley**）— **不是**直接用 `spring-kafka`。不要用 `@KafkaListener` / `KafkaTemplate`，會找不到依賴。

### 目錄慣例（cp-service `event/` 最完整；quartz 通知另在 `job/quartz/event/`）

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

### 消費者 group：廣播 vs 單一處理（**搞錯就出事**）

| 要的語意 | group 寫法（lion 既有） | 寫錯的後果 |
|---|---|---|
| **每個節點都要收到**（快取失效、本地狀態刷新） | `group: ${anonymous.group.name}`（`host:app:port`，每節點一個） | 寫成固定 group → 只有一台節點收到，其他節點讀 stale 資料 |
| **整個叢集只處理一次**（業務事件：轉帳、派獎、統計） | 固定 group 名（例：`yeb-transfer-event`、`bet-event-group`） | 寫成 anonymous → 每台節點各處理一次 → 重複扣款 / 重複發獎 |

新 channel 選哪一種 → 依「這件事做幾次才對」判斷；判不出 → 問使用者。

### application.yml 配置

```yaml
spring:
  cloud:
    stream:
      bindings:
        <channel-name>-output:
          destination: <topic-name>
          content-type: application/json
          group: <group-id>               # 依上表：廣播用 ${anonymous.group.name}，單一處理用固定名
      binders:
        kafka-server:                     # binder 名（可多 binder；本 repo 只一個）
          type: kafka
          environment:
            spring.cloud.stream.kafka.binder:
              brokers: localhost:9092
              zkNodes: localhost:2181
```

### 慣例

- Destination / topic 命名：lion 既有沒有單一慣例（`settle`、`cache-refresh`、`luzhu`、`fly-notify-event` 都有）→ 新 topic 對齊同 domain 既有命名；跨服務共用的 topic 名先問使用者（其他服務可能也在訂閱）
- Event 物件若跨服務共用 → 放 lion-common `bean/event/`
- 新增 channel 時：**同時**加 `input/` 或 `output/` 介面、`emitter/` 或 `listener/` 類別、`application.yml` 的 `bindings` + `group` — 缺一不可
- Listener **必須冪等**（SCS 重試、rebalance 都會重送）；搭配 `orderNo` / 業務唯一鍵去重
- **不要混用** `@KafkaListener` / `KafkaTemplate`（那是 `spring-kafka`，本 repo 未引入）

## 背景工作

cp-service：`job/scheduler/`（`@Scheduled`，多節點觸發，**只寫觸發**）、`job/quartz/`（需單節點執行）、`job/service/*`（業務委派）；single-wallet：`schedule/`。

- Handler 必須冪等：重跑不得重複扣款 / 發獎 / 結算（搭配 `orderNo` / 業務唯一鍵去重，`checks/idempotency-orderno.md`）
- 金額排程**不得吞例外**（`checks/silent-failure.md`）
- 跨包網商的批次：每筆處理都要帶正確 platformId，不得混算多家（`rules/platform-isolation.md`）

## 可觀測性

- **Logback**（`logback-spring.xml` 在每個模組的 `src/main/resources/`）— **純文字 pattern（非 JSON）**，部分 appender 帶 `-%X{traceId}-%X{uri}`。若要改 JSON 要全模組同步改 appender，屬架構變更
- **指標**：Micrometer + Prometheus（`micrometer-registry-prometheus` 在 cp-service / single-wallet-service / collector-service）+ **Spring Boot Admin Client**
- **Tracing：** MDC 自己塞的 `traceId` / `uri`（見 logback pattern 中 `%X{traceId}`），非 Sleuth/Zipkin 自動化

## 生產預設值

- **依賴注入：** 新程式碼建議建構子注入（`@RequiredArgsConstructor`），但**本專案實況 `@Resource` 欄位注入為主（cp-service 4000+ 處）**，既有程式碼不強制重構；`rules/patterns.md` 的硬規則僅套用於新寫的類別
- **例外處理：** 沿用所在模組的機制（見上方 §例外處理），不另起新格式
- **分頁：** framework_v3 `PageBean` + `PageData<T>`（見上方 §分頁與排序）；新增分頁端點前先看同 domain 既有 Controller 怎麼寫
- **資料存取：** 不用 `JpaRepository`、沒有 MyBatis，走 framework_v3 DAO + `SqlUtil`（見 `mysql-patterns` skill）
- 為工作負載設定 HikariCP 連線池大小與逾時
- 查詢使用 `@Transactional(readOnly = true)`

**牢記**：保持 controller 精簡、service 專注、DAO 簡單，並對齊本專案既有模式而非套用通用 Spring Boot 預設。
