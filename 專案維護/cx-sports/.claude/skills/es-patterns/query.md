# 查詢與聚合模式

## 1. 查詢模式（BoolQueryBuilder）

### 標準篩選組合

```java
BoolQueryBuilder bqb = QueryBuilders.boolQuery();

// filter — 精確篩選（不計分、快速）
bqb.filter(QueryBuilders.termQuery("platformId", platformId));
bqb.filter(QueryBuilders.termQuery("testFlag", 0));
bqb.filter(QueryBuilders.rangeQuery("statDate").gte(startTime.getTime()).lte(endTime.getTime()));

// terms — 多值匹配
bqb.filter(QueryBuilders.termsQuery("gameId", gameIds));

// wildcard — 前綴匹配（queryCode 階層查詢）
bqb.filter(QueryBuilders.wildcardQuery("queryCode", queryCode + ServiceConst.WILDCARD));

// mustNot — 排除
bqb.mustNot(QueryBuilders.termsQuery("status", cancelledStatusList));
```

### 常用 QueryBuilder

| Builder | 用途 | 範例 |
|---------|------|------|
| `termQuery` | 精確匹配單值 | `termQuery("userId", 123)` |
| `termsQuery` | 匹配多值 | `termsQuery("gameId", ids)` |
| `rangeQuery` | 範圍查詢 | `rangeQuery("date").gte(start).lte(end)` |
| `wildcardQuery` | 萬用字元 | `wildcardQuery("queryCode", code + "*")` |
| `existsQuery` | 欄位存在 | `existsQuery("dlName")` |

### 日期查詢注意

ES 中日期以 **毫秒時間戳** 儲存，查詢時用 `date.getTime()`：

```java
bqb.filter(QueryBuilders.rangeQuery("statDate")
    .gte(query.getStartTime().getTime())
    .lte(query.getEndTime().getTime()));
```

---

## 2. 聚合模式

### 基本聚合：Terms + Sum

```java
// 按 gameId 分組，統計投注金額
TermsAggregationBuilder groupGameId = AggregationBuilders.terms("groupGameId")
    .field("gameId").size(50000);
SumAggregationBuilder betMoneySum = AggregationBuilders.sum("betMoneySum")
    .field("lineBetMoney");
groupGameId.subAggregation(betMoneySum);

// 執行
Aggregations aggs = queryAggregations(
    getIndexesByDate(DateUtil.getDiffDate(startTime, -3), DateUtil.getDiffDate(endTime, 3)),
    queryBuilder, groupGameId
).getAggregations();

// 解析
Terms groupByGameIdAgg = aggs.get("groupGameId");
for (Terms.Bucket bucket : groupByGameIdAgg.getBuckets()) {
    Long gameId = Long.valueOf(bucket.getKeyAsString());
    Sum betMoney = bucket.getAggregations().get("betMoneySum");
    BigDecimal value = BigDecimal.valueOf(betMoney.getValue())
        .setScale(3, RoundingMode.HALF_UP);
}
```

### Cardinality（去重計數）

```java
CardinalityAggregationBuilder betUserCount = AggregationBuilders.cardinality("betUserCount")
    .field("userId")
    .precisionThreshold(40000);  // 精度閾值

groupGameId.subAggregation(betUserCount);

// 解析
Cardinality cardinality = bucket.getAggregations().get("betUserCount");
long distinctUsers = cardinality.getValue();
```

### 多層聚合（巢狀）

```java
// userId -> gameId 兩層
TermsAggregationBuilder groupByUserId = AggregationBuilders.terms("groupByUserId")
    .field("userId").size(500);
TermsAggregationBuilder groupByGameId = AggregationBuilders.terms("groupByGameId")
    .field("gameId").size(50);

groupByUserId.subAggregation(
    groupByGameId
        .subAggregation(AggregationBuilders.sum("sumBetMoney").field("lineBetMoney"))
        .subAggregation(AggregationBuilders.sum("sumWinMoney").field("lineWinMoney"))
);
```

### Filter 聚合（條件子聚合）

```java
FilterAggregationBuilder filterBetUser = AggregationBuilders.filter("filterBetUser",
    QueryBuilders.rangeQuery("betNum").gt(0));
filterBetUser.subAggregation(
    AggregationBuilders.cardinality("distinctUser").field("userId"));
```

### 常用 AggregationBuilder

| Builder | 用途 |
|---------|------|
| `terms()` | 分組（GROUP BY） |
| `sum()` | 加總 |
| `cardinality()` | 去重計數（COUNT DISTINCT） |
| `filter()` | 條件子聚合 |
| `dateHistogram()` | 日期直方圖 |

---

## 3. 聚合分頁模式

ES 聚合無法用常規 `from/size`，需用 `BucketSortPipelineAggregationBuilder`：

```java
// 排序條件
List<FieldSortBuilder> sortBuilders = new ArrayList<>();
sortBuilders.add(SortBuilders.fieldSort("betMoneySum").order(SortOrder.DESC));

// 分頁（框架方法）
BucketSortPipelineAggregationBuilder aggBucketSort = getAggBucketSort(
    query.getPageBean(), sortBuilders);

// 加到主聚合
groupByUserId.subAggregation(aggBucketSort);

// 總數用 cardinality
CardinalityAggregationBuilder countTotal = AggregationBuilders.cardinality("countTotal")
    .precisionThreshold(50).field("userId");

// 執行
SearchResponse response = queryAggregations(indexes, bqb, groupByUserId, countTotal);

// 解析總數
Cardinality countByUserId = response.getAggregations().get("countTotal");
int totalCount = (int) countByUserId.getValue();
```

---

## 4. 跨索引查詢

### getIndexesByDate

分區索引查詢**必須**指定索引範圍，避免查全部分區：

```java
// 標準用法：前後各加 3 天 buffer（避免時區邊界問題）
String[] indexes = getIndexesByDate(
    DateUtil.getDiffDate(query.getStartTime(), -3),
    DateUtil.getDiffDate(query.getEndTime(), 3)
);

SearchResponse response = queryAggregations(indexes, queryBuilder, aggs);
```

### 單索引

`AbstractEsSingleIndexDao` 自動使用 `@EsWithSingleIndex` 定義的索引名，不需手動指定。

---

## 5. 金額精度

ES 中 `BigDecimal` 存為 `double`，聚合結果需轉回 `BigDecimal`：

```java
Sum betMoneyAgg = bucket.getAggregations().get("betMoneySum");

// 報表顯示用 — HALF_UP
BigDecimal betMoney = BigDecimal.valueOf(betMoneyAgg.getValue())
    .setScale(3, RoundingMode.HALF_UP);

// 帳務用 — DOWN（無條件捨去，避免多給錢）
BigDecimal settleMoney = BigDecimal.valueOf(settleAgg.getValue())
    .setScale(3, RoundingMode.DOWN);
```

---

## 6. 查詢優化

### 6.1 filter 優先於 must

`filter` 不計分且結果可快取，精確篩選一律放 `filter`：

```java
// O 正確 — filter 不計分、可快取
bqb.filter(QueryBuilders.termQuery("platformId", platformId));
bqb.filter(QueryBuilders.rangeQuery("statDate").gte(start).lte(end));

// X 避免 — must 會計算相關性分數，浪費效能
bqb.must(QueryBuilders.termQuery("platformId", platformId));
```

### 6.2 避免前綴萬用字元

前綴 `*` 會掃描所有 term，效能極差：

```java
// X 避免 — 前綴萬用
bqb.filter(QueryBuilders.wildcardQuery("userName", "*john*"));

// O 改用 — 後綴萬用（可利用索引）
bqb.filter(QueryBuilders.wildcardQuery("queryCode", queryCode + "*"));

// O 更好 — prefix query
bqb.filter(QueryBuilders.prefixQuery("queryCode", queryCode));
```

### 6.3 大量 terms 優化

`terms` 值超過 1000 個時，考慮拆分查詢或改用 `bool filter`：

```java
// terms 超過 1000 值 — 效能下降
bqb.filter(QueryBuilders.termsQuery("userId", hugeUserIdList));

// O 拆分為多次查詢合併結果
Lists.partition(hugeUserIdList, 500).forEach(batch -> {
    // 分批查詢
});
```

### 6.4 索引範圍控制

分區索引查詢**必須**縮小索引範圍，避免掃描不必要的分區：

```java
// O 精確控制索引範圍（前後 buffer 依業務需求調整）
String[] indexes = getIndexesByDate(
    DateUtil.getDiffDate(query.getStartTime(), -1),
    DateUtil.getDiffDate(query.getEndTime(), 1)
);

// X 避免 — 不指定索引或用萬用字元匹配所有分區
// 會掃描所有月份索引，資料量大時極慢
```

### 6.5 回傳控制

#### 不需要 hits 時設 size(0)

純聚合查詢不需要文檔內容：

```java
SearchRequestBuilder request = client.prepareSearch(indexes)
    .setQuery(bqb)
    .setSize(0)  // 只要聚合結果，不要 hits
    .addAggregation(aggs);
```

#### _source filtering

只取需要的欄位，減少網路傳輸和記憶體：

```java
SearchRequestBuilder request = client.prepareSearch(indexes)
    .setQuery(bqb)
    .setFetchSource(new String[]{"userId", "betMoney", "statDate"}, null);
```

### 6.6 聚合優化

#### terms size 設合理上限

```java
// O 依業務設定合理 size
TermsAggregationBuilder groupByGame = AggregationBuilders.terms("groupByGame")
    .field("gameId")
    .size(200);  // 遊戲數量有限，200 足夠

// X 避免 — 盲目設超大值
    .size(Integer.MAX_VALUE);  // 佔用大量記憶體
```

#### Cardinality precision_threshold

```java
// 精確計數（值 < 40000 時幾乎 100% 準確）
AggregationBuilders.cardinality("distinctUser")
    .field("userId")
    .precisionThreshold(40000);

// 粗略估算（報表顯示用，不需極高精度）
AggregationBuilders.cardinality("approxCount")
    .field("userId")
    .precisionThreshold(100);
```

### 6.7 深度分頁問題

`from + size` 超過 10000 時效能急劇下降：

```java
// X 深度分頁 — from 越大越慢
request.setFrom(50000).setSize(20);  // ES 預設會拒絕 from+size > 10000

// O 聚合分頁 — 用 BucketSort（框架已支援）
BucketSortPipelineAggregationBuilder bucketSort = getAggBucketSort(pageBean, sortBuilders);

// O 文檔分頁 — 用 search_after（適合無限滾動場景）
request.searchAfter(lastSortValues);
```
