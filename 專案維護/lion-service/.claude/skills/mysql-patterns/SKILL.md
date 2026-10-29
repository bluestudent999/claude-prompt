---
name: mysql-patterns
description: lion-service MySQL 模式 — framework_v3 MysqlBaseDaoImpl + SqlUtil 的 DAO 風格（無 MyBatis）、ShardingSphere 4.0.1 主從 + user_money 分庫 + 欄位加密、HintManager 強制主庫、cp-flyway 遷移、餘額異動。新增 DAO / migration / 動到金額時載入。
origin: template
---

# MySQL 模式（lion-service 專用）

> 通用 MySQL 知識（索引原理、資料型別、EXPLAIN 欄位含義）AI 本來就會，本 skill 只記**本專案特有**的規則與陷阱。詳細審查用 `database-reviewer` agent。

## 啟用時機

- 新增 DAO 類別 / Flyway 遷移
- 設計業務資料表 schema
- 排除 ShardingSphere 相關問題
- 金額異動 / 餘額扣減涉及資料庫鎖

---

## 1. 資料存取風格（專案硬規則）

**lion 沒有 MyBatis**（cp-service / single-wallet-service 0 個 mapper、0 個 mapper XML、0 個 `@Mapper`；根 pom 只在 dependencyManagement 出現）。**不要寫 mapper / XML，也不要引入 MyBatis / JPA。**

**MySQL DAO 繼承 framework_v3 的 `com.cx.framework.dao.MysqlBaseDaoImpl<T, PK>`**，SQL 用 `SqlUtil<T>` 鏈式組裝、參數一律走 `?` 綁定：

```java
// 以 lion-common com.lc.common.dao.user.UserMoneyDao 為例（節錄）
@Repository
@ConditionalOnProperty(name = "config.enabled.datasource", havingValue = "true")
public class UserMoneyDao extends MysqlBaseDaoImpl<UserMoney, Long> {

    public List<UserMoney> queryByMoney(String minMoney, String maxMoney, Long platformId) {
        return buildSelectWhere()
                .andEqual("platform_id", platformId)
                .addSqlAndArgs(" and money >= ?", minMoney)
                .addSqlAndArgs(" and money <= ?", maxMoney)
                .queryList();
    }
}
```

- 基類（`MysqlBaseDao`）提供 `save` / `update` / `updateObject` / `get` / `queryByFieldName` / `queryByIds` / `deleteById` / `insertIntoOnDuplicateUpdate` 等，自訂查詢用 `buildSelect()` / `buildSelectWhere()` / `buildUpdate()` / `buildSQL(sql, args...)` 起頭
- 分頁用 `SqlUtil.queryPage(PageBean)`
- ES DAO 基類（`AbstractEsPartitionByDateDao` 等）見 `skills/es-patterns/SKILL.md`

**SQL 注入面（lion 的真實風險點）：** 不是 MyBatis 的字串替換，而是**字串拼接進 `addSql(...)` / `buildSQL(...)` / 手寫 `"update " + ...`**。
- 使用者輸入**只能**經 `addSqlAndArgs` / `addArgs` / `equal` / `andIn` / `andLike*` 等綁定參數進入 SQL
- 排序欄位、表名、欄位名若來自請求 → 白名單映射，不得直接拼接
- `getTableName()` 這類框架提供的值拼接可以；請求參數拼接一律禁止

**禁用清單：**
| 禁用 | 原因 |
|------|------|
| MyBatis mapper / XML、`@Mapper` | lion 未用；新增會造成第二套資料存取 |
| `JpaRepository` / `CrudRepository` | 專案未用 |
| `@OneToMany` / `@ManyToOne` 關聯查詢 | ShardingSphere 分片環境限制 |
| Service 內直接寫 JDBC / `JdbcTemplate` | 違反分層，放 DAO |

**新 DAO 放哪：** 依團隊共享物件原則，預設放 **lion-common**（`com.lc.common.dao.<domain>.*`，跨 repo，lion-common 先發版，見 `skills/cross-repo-commit/SKILL.md`）；純模組內使用才放模組 `dao/`，PR 說明理由。動手前先在 lion-common `dao/` 找有沒有現成 DAO。

**所有業務查詢帶 `platform_id`**（包網商隔離，`rules/platform-isolation.md`）；boss / manage 類跨包網商入口除外。

---

## 2. ShardingSphere 4.0.1（`datasource-gamedbn.yml`）

設定在各模組 `src/main/resources/datasource-gamedbn.yml`（cp-service 與 single-wallet-service 規則相同）。三件事：

| 規則 | 內容 | 紅線 |
|------|------|------|
| 主從 | `defaultDataSourceName: ms_ds0`（`ds_master` + `ds_slave0/1`，ROUND_ROBIN） | 寫後立即讀要強制主庫 |
| 分庫 | **只有 `user_money`**：`ds${0..9}`，分片鍵 `user_id`（`user_id % 10`） | `user_money` 的 SQL 必帶 `user_id`，否則廣播到 10 個庫；不得跨分片 JOIN `user_money` |
| 欄位加密 | `encryptRule`：`user_info` 的 `full_name` / `phone` / `email` / `qq` / `wechat` 等聯絡欄位 AES 加密 | 加密欄位不能做 LIKE / 範圍 / 排序；新增 PII 欄位要不要加進 `encryptRule` → 問使用者 |

### 強制主庫：`HintManager`

lion 用 ShardingSphere 原生 `org.apache.shardingsphere.api.hint.HintManager`（既有 170+ 處），**try-with-resources**：

```java
try (HintManager hintManager = HintManager.getInstance()) {
    hintManager.setMasterRouteOnly();
    return buildSelect().where().equal("user_id", userId).addSqlAndArgs(" limit 0,1").queryOne();
}
```

- 寫後立即讀、扣款前讀餘額、冪等判定（查 `orderNo` 是否已處理）→ 一律強制主庫，否則主從延遲會讀到舊值
- 不用 try-with-resources 而手動 `getInstance()` 卻漏 `close()` → ThreadLocal 殘留，後續同執行緒的讀全走主庫（或 `getInstance()` 直接拋例外）
- ES 的強制主庫是另一個類（framework_v3 `EsHintManager`），不要混用，見 `skills/es-patterns/rw-split.md`

---

## 3. Flyway 遷移（cp-flyway）

**規則正本：`rules/flyway-migration.md`**，這裡只列 lion 必知的三件事：

- 位置：**同 repo 的 `cp-flyway/src/main/resources/db/migrations/general/`**（`cp-flyway` 不在根 pom `<modules>`，reactor build 不會建它）；schema `gamedbn`；`clean-disabled: true`、`out-of-order: true`
- 版號：**新檔一律 `V<YYYYMMDDHHMMSS>__<desc>.sql`**（可帶單號：`V20261015103000__PRJ-1299_add_xxx.sql`）；既有 `V1.x.x__` 檔保留不動。lion 已實際發生過 `V1.8.0` 被三支不同 migration 重複取用、且已執行的檔被改內容 → **絕不修改已執行的遷移檔**（cp-flyway 啟動前會 `repair()`，改了不會報錯，只會讓各環境 schema 靜默不一致）
- **雙軌 SQL**（`rules/flyway-migration.md` §6）：`zz_document/script/changelog/<YYYY>/<YYYYMMDD>_<ticket>_<desc>.sql` 是手動執行 / DBA 上版對照用。**何時兩邊都寫、何時只寫一邊沒有成文規則 → 不得自行判定**：查同模組近期同類單的做法；仍判不出 → 問使用者。兩邊都寫時內容必須一致，changelog 檔首註明對應的 flyway 版號、前提、能否重跑

### 大表 DDL 必備

```sql
-- 大表加索引避免鎖表（InnoDB online DDL；實際 MySQL 版本先跟使用者 / DBA 確認）
ALTER TABLE orders
  ADD INDEX idx_status (status),
  ALGORITHM=INPLACE, LOCK=NONE;
```

- 先加欄位（給 `DEFAULT`）再加索引，分開遷移
- 線上大表 DDL 前先估行數與業務低峰期
- 動到 `user_money`（分庫）的 DDL 要確認 10 個分庫都會執行 → 問使用者 / DBA 上版方式

---

## 4. 餘額異動（業務關鍵）

**一般會員餘額異動一律走 lion-common `UserMoneyService.changeMoney*`**（同交易內改餘額 + 寫 `UserBill` 流水 + commit 後通知快取刷新），**不要自己寫 `UPDATE user_money`**。
- `changeMoneyLock(...)`：樂觀鎖版（`UPDATE ... SET money = money + ? WHERE user_id = ? AND money = ?`，更新筆數 ≠ 1 拋 `MONEY_CHANGED`）
- `changeMoney(..., isNegativeBalance)`：不加鎖版；`isNegativeBalance = false` 時會先驗餘額不足
- 選哪一個、要不要允許負餘額，對齊同類業務的既有呼叫；判不出 → 問使用者

**單據狀態鎖**：充值 / 提現等單據既有寫法是 `HintManager` 強制主庫 + `... where order_no = ? limit 0,1 for update`（見 lion-common `UserRechDao` / `UserWithdrawDao`），包在 `@Transactional` 內。

**single-wallet-service** 的金額流程（取分散式鎖 → `@Transactional` → 鎖定 → 驗餘額 / 狀態 → 扣 / 加 → 寫流水 `TransactionV2Service` → commit → 釋放鎖；冪等判定在寫流水**前**）以該模組既有 `@SingleWalletType` 實作為準，新交易類型照抄同類寫法。

交易內**不得**呼叫外部 API / 第三方（`checks/transactional-remote-call.md`）。

---

## 5. 複合索引最左前綴（訂單/金額異動必知）

```sql
-- 等值欄位在前，範圍欄位在後
CREATE INDEX idx_status_time ON orders (status, created_at);

-- ✅ 命中：WHERE status = 1 AND created_at > '...'
-- ✅ 命中：WHERE status = 1
-- ❌ 不命中：WHERE created_at > '...'（跳過最左欄位）
```

### 覆蓋索引（避免回表）

```sql
CREATE INDEX idx_cover ON orders (user_id, status, amount);
-- SELECT user_id, status, amount FROM ... WHERE user_id = ?
-- 直接從索引取，不回表
```

---

## 6. 金額欄位

- 精度**對齊既有同類欄位**（lion 既有 migration 金額欄位以 `DECIMAL(20,3)` 為主），禁用 `FLOAT` / `DOUBLE`
- 對應 Java 層 `BigDecimal`；入帳 / 出帳 / 結算 / 換匯 `RoundingMode.DOWN`
- 詳細 RoundingMode 規則見 `rules/security.md`、`checks/bigdecimal-rounding.md`

---

## 7. 游標分頁（避免大 OFFSET）

```sql
-- ❌ 慢：OFFSET 越大越慢
SELECT * FROM orders ORDER BY id LIMIT 20 OFFSET 100000;

-- ✅ 快：游標分頁
SELECT * FROM orders WHERE id > ? ORDER BY id LIMIT 20;   -- lastId 經 addSqlAndArgs 綁定
```

業務紀錄量大時，報表/查詢必用游標分頁。

---

## 8. 本專案常見陷阱

| 陷阱 | 問題 | 解法 |
|------|------|------|
| `SELECT *` | 回表、傳輸多餘資料 | 只選需要的欄位 |
| 隱式型別轉換 | `WHERE varchar_col = 123` 全表掃描 | `WHERE varchar_col = '123'` |
| `COUNT(*)` 大訂單表 | 全表掃描 | 快取計數或用 ES 聚合 |
| `user_money` 未帶 `user_id` | ShardingSphere 廣播到 10 個分庫 | `WHERE` 必含 `user_id` |
| 寫後立即讀沒強制主庫 | 主從延遲讀不到 | `HintManager.setMasterRouteOnly()` |
| `HintManager` 沒用 try-with-resources | ThreadLocal 殘留 | 一律 try-with-resources |
| 請求參數拼進 `addSql` / `buildSQL` | SQL 注入 | 改 `addSqlAndArgs` 綁定，欄位名走白名單 |
| 查詢漏 `platform_id` | 跨包網商資料外洩 | 對照 `rules/platform-isolation.md` |
| 長交易 | 持有 `FOR UPDATE` 過久阻塞 | 交易內不做外部 API 呼叫 |
| 修改已執行的遷移檔 | lion 的 cp-flyway 啟動前會 `repair()`，checksum 被默默改寫、新內容在舊環境永遠不執行（lion 實際發生過改已執行檔） | 寫新 `V` 檔案修正（時間戳版本號） |

---

## 相關資源

- Agent：`database-reviewer` - 完整資料庫審查工作流程
- Skill：`springboot-patterns` - Spring Boot 架構模式（DAO 與 Service 層）
- Skill：`es-patterns` - ES DAO 與主從讀寫
- Rule：`rules/flyway-migration.md` - migration 版號與雙軌 SQL
- Rule：`rules/platform-isolation.md` - 包網商隔離
- Rule：`rules/security.md` - 金額 RoundingMode 規範
