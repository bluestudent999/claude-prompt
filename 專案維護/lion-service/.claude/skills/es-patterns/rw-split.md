# ES 主從讀寫分離

## 1. 架構概覽

lion-service ES 採用 **Master（寫）+ Slave（讀）** 雙叢集架構，透過 `ElasticsearchTemplateAspect` 自動路由。**兩個模組的 aspect 行為不同**：

| 模組 | Aspect | 讀操作走哪 |
|------|--------|-----------|
| cp-service | `com.lc.cp.aspect.ElasticsearchTemplateAspect` | Slave（從庫）；`CORE_BUS_ES_MASTER_ONLY` 開啟時 `controller.front` 下的請求改走主庫 |
| single-wallet-service | `com.lc.single.wallet.aspect.ElasticsearchTemplateAspect` | **一律 Master**（程式碼註解：單錢包都先使用主庫）；`CORE_BUS_ES_MASTER_ONLY` 由 `ConfigCache` 讀取 |

```
Controller / Service
       |
       v
  DAO 方法呼叫（如 queryForPage / save）
       |
       v
  ElasticsearchTemplateAspect（AOP 攔截）
       |
       +-- save* / create* / update* / delete*  --> masterElasticsearchTemplate（主庫）
       +-- 其他方法（查詢類）                    --> cp-service: slaveElasticsearchTemplate / single-wallet: master
       |
       v
  AbstractBaseEsDao.getTemplate() / getJdbcTemplate()
       |
       v
  ThreadLocal ES_HOLDER / JDBC_TEMPLATE_HOLDER
```

## 2. Aspect 機制

### Pointcut

```java
// 攔截所有繼承 AbstractBaseEsDao 的類的方法
// 排除 *get*Index(..)：避免 getIndex / getQueryIndex 的 finally 提前清掉 ThreadLocal
@Pointcut("within(com.cx.framework.dao.AbstractBaseEsDao+) && !execution(* *get*Index(..))")

// cp-service 另有：前台 API 的核心業務攔截（決定是否臨時切主庫）
@Pointcut("execution(* com.lc.*.controller.front..*(..))")
```

### 路由邏輯（cp-service 版）

```java
@Around(value = "pointcut()")
public Object execute(ProceedingJoinPoint joinPoint) throws Throwable {
    try {
        String methodName = joinPoint.getSignature().getName();
        if (methodName.matches(CUD_PATTERN)   // "^save.*|create.*|update.*|delete.*$"
            || EsHintManager.isMasterRouteOnly()
            || isCoreBusMasterOnly()) {
            AbstractBaseEsDao.getEsHolder().set(masterElasticsearchTemplate);
            AbstractBaseEsDao.getJdbcTemplateHolder().set(new JdbcTemplate(masterEsDataSourceManager.getDataSource()));
        } else {
            AbstractBaseEsDao.getEsHolder().set(slaveElasticsearchTemplate);
            AbstractBaseEsDao.getJdbcTemplateHolder().set(new JdbcTemplate(slaveEsDataSourceManager.getDataSource()));
        }
        return joinPoint.proceed();
    } finally {
        AbstractBaseEsDao.getEsHolder().remove();          // 清理 ThreadLocal
        AbstractBaseEsDao.getJdbcTemplateHolder().remove();
    }
}
```

### 強制走主庫的場景

| 條件 | 說明 |
|------|------|
| 方法名匹配 `save*\|create*\|update*\|delete*` | CUD 操作自動走主庫 |
| `EsHintManager.isMasterRouteOnly()` | 程式碼中手動標記強制主庫（用法見 §5） |
| `CORE_BUS_ES_MASTER_ONLY` 配置 = 1 | cp-service：只影響 `controller.front` 下的請求；single-wallet：讀本來就走主庫 |

### 新增模組 / 新 aspect

只有 cp-service 與 single-wallet-service 有這個 aspect；collector-service / upload-service 若要用 ES DAO，**沒有 aspect 時 `getTemplate()` 會拿到 null**——先問使用者要對齊哪一份，不要自己寫第三套路由。

---

## 3. 父類 ThreadLocal 機制

`AbstractBaseEsDao` 透過 ThreadLocal 提供 template：

```java
public abstract class AbstractBaseEsDao {
    protected static final ThreadLocal<ElasticsearchTemplate> ES_HOLDER = new ThreadLocal<>();

    protected ElasticsearchTemplate getTemplate() {
        return getEsHolder().get();  // 從 ThreadLocal 取得 Aspect 設定的 template
    }
}
```

**重點**：子類 DAO **不需要也不應該** override `getTemplate()`，Aspect 會在每次 DAO 方法呼叫前自動設定正確的 template。

---

## 4. 反模式：override getTemplate()

### 問題

```java
// X 反模式 — 繞過讀寫分離
@Repository
public class ThirdOrderEsDao extends AbstractEsPartitionByDateDao<ThirdOrder> {

    @Resource
    private ElasticsearchTemplate elasticsearchTemplate;  // 固定注入一個

    @Override
    protected ElasticsearchTemplate getTemplate() {
        return elasticsearchTemplate;  // 所有操作都打同一個 ES，無讀寫分離
    }
}
```

**後果**：
- 查詢和寫入都打到同一個 ES 實例，失去主從分離
- 主庫承受不必要的讀壓力
- Aspect 的路由邏輯完全被繞過

### 正確做法

```java
// O 正確 — 不 override，讓 Aspect 處理
@Repository
public class ThirdOrderEsDao extends AbstractEsPartitionByDateDao<ThirdOrder> {
    // 不需要注入 ElasticsearchTemplate
    // 不需要 override getTemplate()
    // Aspect 自動處理讀寫分離
}
```

### 已知 override `getTemplate()` 的 DAO

以下 DAO 自行注入 `ElasticsearchTemplate` 並 override `getTemplate()`，繞過了 aspect（實查於撰寫時；動到前先確認現況，**是否修正要問使用者**——有些可能是刻意固定叢集）：

- lion-common：`dao/user/MyFavoriteEsDao`、`dao/user/UserThirdBillDao`、`dao/thirdsinglewallet/ThirdSingleWalletTransactionDao`
- cp-service：`dao/QuestBehaviorRecordEsDao`

新 DAO **不得**再加入這份清單。

### 另一個常見錯誤：直接引用 field

即使沒有 override `getTemplate()`，在 DAO 方法中也不要直接用注入的 field：

```java
// X 直接用 field — 繞過 Aspect
Client client = elasticsearchTemplate.getClient();

// O 走 getTemplate() — 讓 Aspect 決定用哪個 template
Client client = getTemplate().getClient();
```

---

## 5. 查詢方法命名注意

Aspect 根據**方法名**判斷走主庫還是從庫。自訂查詢方法命名時注意：

```java
// 這些方法名會被路由到主庫（匹配 save* / update* / delete*）
public void saveWithCustomLogic(...)    // --> master
public void updateStatus(...)           // --> master
public void deleteExpired(...)          // --> master

// 這些方法名會被路由到從庫
public List<T> queryByUserId(...)       // --> slave
public PageData<T> findByDate(...)      // --> slave
public long countByPlatform(...)        // --> slave
```

如果查詢方法需要讀主庫（例如寫後立即讀），使用 framework_v3 的 `EsHintManager`（`getInstance()` 綁 ThreadLocal、實作 `AutoCloseable`；前一個沒清掉會 `IllegalStateException`）：

```java
try (EsHintManager hint = EsHintManager.getInstance()) {
    hint.setMasterRouteOnly();
    List<T> result = dao.queryByUserId(userId);  // 強制走主庫
}
```
