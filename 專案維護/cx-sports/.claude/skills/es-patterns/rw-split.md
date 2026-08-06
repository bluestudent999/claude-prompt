# ES 主從讀寫分離

## 1. 架構概覽

本專案 ES 採用 **Master（寫）+ Slave（讀）** 雙叢集架構，透過 `ElasticsearchTemplateAspect` 自動路由。

```
Controller / Service
       |
       v
  DAO 方法呼叫（如 queryPage / save）
       |
       v
  ElasticsearchTemplateAspect（AOP 攔截）
       |
       +-- save* / update* / delete*  --> masterElasticsearchTemplate（主庫）
       +-- 其他方法（查詢類）          --> slaveElasticsearchTemplate（從庫）
       |
       v
  AbstractBaseEsDao.getTemplate()
       |
       v
  ThreadLocal<ElasticsearchTemplate> ES_HOLDER.get()
```

## 2. Aspect 機制

### Pointcut

```java
// 攔截所有繼承 AbstractBaseEsDao 的類的方法
@Pointcut("within(com.cx.framework.dao.AbstractBaseEsDao+) && !execution(* *get*Index(..))")

// V1 版本
@Pointcut("within(com.cx.framework.dao.v1.AbstractBaseEsV1Dao+) && !execution(* *get*Index(..))")
```

### 路由邏輯

```java
@Around(value = "pointcut()")
public Object execute(ProceedingJoinPoint joinPoint) throws Throwable {
    try {
        String methodName = joinPoint.getSignature().getName();
        if (methodName.matches("^save.*|create.*|update.*|delete.*$")
            || EsHintManager.isMasterRouteOnly()
            || isCoreBusMasterOnly()) {
            // 寫操作 / 強制主庫 --> master
            AbstractBaseEsDao.getEsHolder().set(masterElasticsearchTemplate);
        } else {
            // 讀操作 --> slave
            AbstractBaseEsDao.getEsHolder().set(slaveElasticsearchTemplate);
        }
        return joinPoint.proceed();
    } finally {
        AbstractBaseEsDao.getEsHolder().remove();  // 清理 ThreadLocal
    }
}
```

### 強制走主庫的場景

| 條件 | 說明 |
|------|------|
| 方法名匹配 `save*\|create*\|update*\|delete*` | CUD 操作自動走主庫 |
| `EsHintManager.isMasterRouteOnly()` | 程式碼中手動標記強制主庫 |
| `CORE_BUS_ES_MASTER_ONLY` 配置開啟 | 核心業務（前端 API / 結算 / MTS）臨時切主庫 |

### Aspect 位置

- `cx-sport-app-service`：`com.lc.cp.aspect.ElasticsearchTemplateAspect`
- `cx-sport-single-wallet-service`：`com.lc.single.wallet.aspect.ElasticsearchTemplateAspect`

兩份邏輯類似但獨立，新模組需對齊所在模組的 Aspect。

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

### 已知受影響的 DAO（待修復）

以下 DAO 都有相同的 override 問題，繞過了讀寫分離：

- `ThirdOrderEsDao`（已修復）
- `SingleWalletTaskDao`
- `QuestRewardEsDao`
- `PlatformDailyReportEsDao`
- `ThirdGameDailyReportEsDao`
- `ThirdPlatformDailyReportEsDao`
- `ThirdPlatformDailyReportOldEsDao`
- `ThirdDailyReportEsDao`
- `GameDailyReportOldEsDao`
- `GameDailyReportEsDao`
- `UserDailyReportEsExtDao`
- `UserDailyReportOldEsDao`

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

如果查詢方法需要讀主庫（例如寫後立即讀），使用 `EsHintManager`：

```java
try {
    EsHintManager.setMasterRouteOnly();
    List<T> result = dao.queryByUserId(userId);  // 強制走主庫
} finally {
    EsHintManager.clear();
}
```
