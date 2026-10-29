# DAO 結構與索引管理

## 1. DAO 繼承結構

```
com.cx.framework.dao（framework_v3）
AbstractBaseEsDao                          <- 基類
  |- AbstractEsSingleIndexDao<T>           <- 單索引（不分區）
  |- AbstractEsPartitionByDateDao<T>       <- 按日期分區索引（主流）
  |- AbstractEsPartitionByDateWithSpecialPatternDao<T>  <- 特殊分區策略
  +- AbstractEsPartitionDao<T extends IPartition>       <- 按分區號（非日期）
```

### 選擇依據

| 場景 | 基類 | 範例 |
|------|------|------|
| 時間序列、資料量大、需要按月/日分區 | `AbstractEsPartitionByDateDao` | 投注記錄、日報表、登入日誌 |
| 資料量小、不需分區 | `AbstractEsSingleIndexDao` | 平台報表、遊戲設定 |
| 動態路由到特殊索引 | `AbstractEsPartitionByDateWithSpecialPatternDao` | 特殊聚合索引 |

**多數場景用 `AbstractEsPartitionByDateDao`**（lion-common + lion-service 既有約 32 個；單索引約 17 個；後兩種目前無人用，要用先問使用者）。

---

## 2. 索引定義（ES Model 註解）

### 按日期分區 — `@EsPartitionByDate`

```java
@EsPartitionByDate(
    indexPrefix = "cp_user_bet_",           // 索引前綴
    indexType = "userbet",                  // type（ES 6.x 需要）
    dateGetter = "getTurnDate",             // 日期欄位的 getter
    idGetter = "getUniqNo",                // ID 欄位的 getter（upsert 用）
    datePattern = "yyyyMM",                 // 分區粒度：yyyyMM（月）或 yyyyMMdd（日）
    version = "v1"                          // 索引版本後綴
)
@Data
public class UserBet {
    private String uniqNo;          // ID
    private Date turnDate;          // 分區日期欄位
    private Long userId;
    private Long platformId;
    private BigDecimal betMoney;
    // ...
}
// 產生索引名：cp_user_bet_202406_v1
```

### 單索引 — `@EsWithSingleIndex`

```java
@EsWithSingleIndex(
    index = "cp_game_daily_report",
    indexType = "gamedailyreport",
    idGetter = "getId",
    version = "v1"
)
@Data
public class GameDailyReport {
    private String id;
    private Long gameId;
    private Date date;
    private BigDecimal betMoney;
    // ...
}
// 產生索引名：cp_game_daily_report_v1
```

---

## 3. DAO 實作模式

### 新建 DAO

```java
@Repository
@Slf4j
public class UserBetDailyStatEsDao extends AbstractEsPartitionByDateDao<UserBetDailyStat> {
    // 自訂查詢方法...
}
```

```java
@Repository
public class GameDailyReportEsDao extends AbstractEsSingleIndexDao<GameDailyReport> {
    // 自訂查詢方法...
}
```

### 核心繼承方法

> 兩個基類的簽名**不同**：按日期分區的方法多半要帶 `String[] indexes` 或 `Date start, Date end`；單索引的不用。寫之前打開 framework_v3 對應基類確認簽名，不要憑印象。

| 方法 | `AbstractEsPartitionByDateDao` | `AbstractEsSingleIndexDao` |
|------|------|------|
| 寫入（單筆 / 批量，批量按 5MB 分批 flush） | `save(T)` / `saveAll(Collection<T>)` | 同左 |
| 更新 | `update(List<T>)` | `update(T)` / `update(List<T>)` |
| 條件批量更新 | `updateByQuery(Date, Date, QueryBuilder, Map)` | `updateByQuery(QueryBuilder, Map)` |
| 刪除 | `delete(T)` / `delete(String id, Date)` / `deleteByQuery(Date, Date, QueryBuilder)` | `delete(List<T>)` / `deleteById(String)` |
| 全量查詢（SCROLL） | `queryAll(String[], QueryBuilder)` / `queryAll(Date, Date, QueryBuilder)` | `queryAll(QueryBuilder)` |
| 分頁查詢（簡單場景） | `queryForPage(String[], QueryBuilder, Pageable)` | `queryForPage(QueryBuilder, Pageable)` |
| 聚合查詢 | `queryAggregations(String[], QueryBuilder, AggregationBuilder...)` | `queryAggregations(QueryBuilder, AggregationBuilder...)` |
| 取索引名陣列 | `getIndexesByDate(Date, Date)` | — |
| 聚合分頁排序（基類 `AbstractBaseEsDao`） | `getAggBucketSort(PageBean, List<FieldSortBuilder>)` | 同左 |
| ES SQL（走 7.17.18 `x-pack-sql-jdbc`） | `jdbcBuildSelect(String...)` / `jdbcBuildSQL(String, Object...)` | `jdbcBuildSelect()` / `jdbcBuildSQL(String, Object...)` |

---

## 4. Client 設定

| 項目 | 值 |
|------|-----|
| Client 類型 | TransportClient（`PreBuiltXPackTransportClient`），設定在各模組 `config/es/MasterElasticsearchAutoConfiguration` / `SlaveElasticsearchAutoConfiguration` |
| ES 版本 | 6.8.22（transport client / `x-pack-transport`）；7.17.18 只用於 `x-pack-sql-jdbc`（ES SQL） |
| Spring Data ES | 3.2.12.RELEASE（`elasticsearch-boot.version`） |
| 部署模式 | Master（寫）+ Slave（讀）雙叢集；`masterElasticsearchTemplate` / `slaveElasticsearchTemplate` + `masterEsDataSourceManager` / `slaveEsDataSourceManager` |
| 安全認證 | XPack Security |

---

## 5. 索引設計

### Mapping 欄位型別

| 場景 | 型別 | 說明 |
|------|------|------|
| 精確匹配（ID、狀態、代碼） | `keyword` | 不分詞，term/terms 查詢 |
| 全文搜尋 | `text` | 分詞，match 查詢 |
| 數值範圍 | `long` / `double` | range 查詢 |
| 日期範圍 | `date` | range 查詢，存毫秒時間戳 |
| 不查詢不聚合的欄位 | `enabled: false` 或不索引 | 節省儲存和索引時間 |

### 分區粒度選擇

| 粒度 | 適用場景 | 索引名範例 |
|------|---------|-----------|
| **月（yyyyMM）** | 多數場景，資料保留 6-12 個月 | `prefix_202406_v1` |
| **日（yyyyMMdd）** | 日資料量極大（>1000 萬），或需要快速刪除舊資料 | `prefix_20240601_v1` |

**原則：** 單一索引 shard 大小控制在 10-50 GB 為佳。資料量小用月分區，資料量大用日分區。

---

## 6. 現有索引清單

> ES Model 主要在 `lion-common` 的 `com.lc.common.bean.es.*` 定義（少數在 `bean/model/user`、`bean/third` 等業務目錄），ES DAO 在 `com.lc.common.dao.<domain>.*`。業務模組需要新索引時，**預設放 lion-common**（團隊共享物件原則）；只有純模組內使用才放模組 `dao/`，PR 說明為何不放 common。
>
> 取得實際索引清單（在 lion-common repo 根目錄執行）：
> ```bash
> grep -rln "@EsPartitionByDate\|@EsWithSingleIndex" src/main/java/com/lc/common/bean/
> ```
>
> 命名慣例（沿用既有）：
> - **分區索引**：`indexPrefix` + 日期（`datePattern`，預設 `yyyyMM`）+ `version`（透過 `AbstractEsPartitionByDateDao` 自動切表）
> - **單索引**：直接用業務名稱（小寫底線分隔）
> - **特殊分區**：`AbstractEsPartitionByDateWithSpecialPatternDao` — 自訂分區策略
> - `version` 只在新增 / 變更欄位時改，且需要做索引割接腳本（framework_v3 註解原意）——改 `version` 等於換索引，舊資料不會自動搬

---

## 7. 新增 ES 功能 Checklist

1. **定義 Model**：在 lion-common `bean/es/` 新增 class（模組私有才放模組內），加 `@EsPartitionByDate` 或 `@EsWithSingleIndex`；Model 帶 `platformId`
2. **建立 DAO**：在 lion-common `dao/<domain>/` 新增 class，繼承對應基類
3. **加 `@Repository`**：確保被 Spring 掃描
4. **不要 override `getTemplate()`**：讓 Aspect 自動處理讀寫分離（詳見 [rw-split.md](rw-split.md)）
5. **查詢方法**：用 `BoolQueryBuilder` + filter 組合，聚合用 `queryAggregations`（詳見 [query.md](query.md)）
6. **跨索引**：分區 DAO 用 `getIndexesByDate(start - buffer, end + buffer)` 取索引範圍（buffer 依同 DAO 既有呼叫，見 [query.md](query.md) §4）
7. **查詢帶 `platformId`**：除 boss / manage 類跨包網商入口外，查詢條件必含 `platformId`（`rules/platform-isolation.md`）
8. **金額轉換**：聚合結果 `BigDecimal.valueOf(sum.getValue()).setScale(n, RoundingMode)`，帳務用 `DOWN`（見 [query.md](query.md) §5）
9. **分頁聚合**：用 `getAggBucketSort` + `Cardinality` 取總數
10. **lion-common 有改**：lion-common 要先發版，lion-service 才能引用（`skills/cross-repo-commit/SKILL.md`）
