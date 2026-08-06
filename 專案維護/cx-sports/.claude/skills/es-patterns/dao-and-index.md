# DAO 結構與索引管理

## 1. DAO 繼承結構

```
AbstractBaseEsDao                          <- 基類（framework）
  |- AbstractEsSingleIndexDao<T>           <- 單索引（不分區）
  |- AbstractEsPartitionByDateDao<T>       <- 按日期分區索引（主流）
  +- AbstractEsPartitionByDateWithSpecialPatternDao<T>  <- 特殊分區策略
```

### 選擇依據

| 場景 | 基類 | 範例 |
|------|------|------|
| 時間序列、資料量大、需要按月/日分區 | `AbstractEsPartitionByDateDao` | 投注記錄、日報表、登入日誌 |
| 資料量小、不需分區 | `AbstractEsSingleIndexDao` | 平台報表、遊戲設定 |
| 動態路由到特殊索引 | `AbstractEsPartitionByDateWithSpecialPatternDao` | 特殊聚合索引 |

**90% 場景用 `AbstractEsPartitionByDateDao`。**

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

| 方法 | 用途 |
|------|------|
| `save(T)` / `saveAll(Collection<T>)` | 寫入（單筆 / 批量，自動按 5MB 分批 flush） |
| `update(T)` / `update(List<T>)` | 更新文檔 |
| `updateByQuery(QueryBuilder, Map<String,Object>)` | 按條件批量更新 |
| `delete(T)` / `deleteById(String)` | 刪除 |
| `queryAll(QueryBuilder)` | SCROLL 全量查詢 |
| `queryAll(String[], QueryBuilder)` | 指定索引查詢 |
| `queryForPage(QueryBuilder, Pageable)` | 分頁查詢（簡單場景） |
| `queryAggregations(String[], QueryBuilder, AggregationBuilder...)` | 聚合查詢 |
| `getIndexesByDate(Date, Date)` | 按日期範圍取得索引名陣列 |
| `getAggBucketSort(PageBean, List<FieldSortBuilder>)` | 聚合分頁排序 |

---

## 4. Client 設定

| 項目 | 值 |
|------|-----|
| Client 類型 | TransportClient（PreBuiltXPackTransportClient） |
| ES 版本 | 6.8.22 / 7.17.18 |
| Spring Data ES | 3.2.12.RELEASE |
| 部署模式 | Master（寫）+ Slave（讀）雙叢集 |
| 安全認證 | XPack Security（SSL + user auth） |

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

> 索引主要在 `cx-sport-common` `com.lc.sports.bean.es.*` 定義；業務模組需要新索引時，**先確認是否該放 cx-sport-common**（共享）還是模組私有 `bean/es/`。
>
> 取得本專案實際索引清單：
> ```bash
> grep -rn "@Document\|indexName" cx-sport-common/src/main/java/com/lc/common/bean/es/
> ```
>
> 命名慣例（沿用既有）：
> - **分區索引**：以 `yyyyMM` 後綴（透過 `AbstractEsPartitionByDateDao` 自動切表）
> - **單索引**：直接用業務名稱（小寫底線分隔）
> - **特殊分區**：`AbstractEsPartitionByDateWithSpecialPatternDao` — 自訂分區策略

---

## 7. 新增 ES 功能 Checklist

1. **定義 Model**：在 ES bean 目錄新增 class，加 `@EsPartitionByDate` 或 `@EsWithSingleIndex`
2. **建立 DAO**：在 DAO 對應目錄新增 class，繼承對應基類
3. **加 `@Repository`**：確保被 Spring 掃描
4. **不要 override `getTemplate()`**：讓 Aspect 自動處理讀寫分離（詳見 [rw-split.md](rw-split.md)）
5. **查詢方法**：用 `BoolQueryBuilder` + filter 組合，聚合用 `queryAggregations`（詳見 [query.md](query.md)）
6. **跨索引**：分區 DAO 用 `getIndexesByDate(start-3, end+3)` 取索引範圍
7. **金額轉換**：聚合結果 `BigDecimal.valueOf(sum.getValue()).setScale(3, RoundingMode)`
8. **分頁聚合**：用 `getAggBucketSort` + `Cardinality` 取總數
