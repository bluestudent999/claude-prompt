---
name: mysql-patterns
description: MySQL 模式模板。涵蓋 DAO 風格、主從分片（如 ShardingSphere）、Flyway 遷移、餘額/庫存鎖。套用時依實際版本與中介層客製。
origin: template
---

# MySQL 模式（sport 專用）

> 通用 MySQL 知識（索引原理、資料型別、EXPLAIN 欄位含義）AI 本來就會，本 skill 只記**本專案特有**的規則與陷阱。詳細審查用 `database-reviewer` agent。

## 啟用時機

- 新增 DAO 類別 / Flyway 遷移
- 設計業務資料表 schema
- 排除 ShardingSphere 相關問題
- 金額異動 / 餘額扣減涉及資料庫鎖

---

## 1. 資料存取風格（專案硬規則）

**DAO 繼承 `com.cx.framework.dao.*` 抽象基類**（sport-framework 提供）：

```java
// MySQL
@Repository
public class UserMoneyDao extends BaseMapper<UserMoney, Long> {
  // 基類提供 save / find / update / delete / page（搭配 MyBatis mapper-starter + pagehelper）
}

// Elasticsearch（按日分區索引，主流 90% 場景）
import com.cx.framework.dao.AbstractEsPartitionByDateDao;

@Repository
public class ThirdDailyReportEsDao extends AbstractEsPartitionByDateDao<ThirdDailyReport> {
  // 基類提供 save / find / query / page
}
```

ES DAO 基類詳細選擇見 `es-patterns` skill。

**禁用清單：**
| 禁用 | 原因 |
|------|------|
| `JpaRepository` / `CrudRepository` | 專案未用 |
| `@OneToMany` / `@ManyToOne` 關聯查詢 | ShardingSphere 分片環境限制 |
| `JOIN FETCH` | 同上 |
| Service 內直接寫 JDBC | 違反分層 |

新增 DAO 優先放 `cx-sport-common`（`com.lc.sports.dao.*`），參考既有 `UserMoneyDao`、`ThirdDailyReportEsDao`。

---

## 2. ShardingSphere 主從分片（重要）

### 讀寫分離鐵律

- **寫永遠走主庫，讀走從庫**（預設自動路由）
- **寫後立即讀必須強制主庫**（否則碰上主從延遲會讀不到）

```java
@Transactional  // 同交易內的讀取自動走主庫
public UserDto getUserAfterUpdate(Long userId) {
  userDao.updateStatus(userId, 1);
  return userDao.findById(userId);  // 主庫
}
```

### 分片規則

- **分片鍵選擇**影響查詢效率，跨分片查詢會很慢
- **`INSERT` 必須包含分片鍵欄位**（否則路由不到）
- **避免跨分片 JOIN**（因此才禁用 `@OneToMany` 等關聯查詢）

---

## 3. Flyway 遷移（`db/migrations/`）

### 命名與位置

- 版本：`V1.x.x__description.sql`（例：`V1.3.0__add_order_index.sql`）
- 位置：`Flyway` 模組 `src/main/resources/db/migration/`
- Flyway 版本依 `Flyway/pom.xml` 為準

### 大表 DDL 必備

```sql
-- 大表加索引避免鎖表（MySQL 5.7 InnoDB）
ALTER TABLE orders
  ADD INDEX idx_status (status),
  ALGORITHM=INPLACE, LOCK=NONE;
```

**遷移鐵律：**
- **絕不修改已執行的遷移檔**（Flyway 會 checksum 驗證）
- **新增檔案一律用時間戳版本號**：`V<YYYYMMDDHHMMSS>__<description>.sql`（`date +%Y%m%d%H%M%S`）；既有語意版號檔保留不動 —— 見 `rules/flyway-migration.md`
- 大表 DDL 必加 `ALGORITHM=INPLACE, LOCK=NONE`
- 先加欄位（給 `DEFAULT`）再加索引，分開遷移
- 線上大表 DDL 前先估行數與業務低峰期

---

## 4. 餘額鎖（業務關鍵）

金額異動扣減餘額用 **`SELECT ... FOR UPDATE` 悲觀鎖**，包在 `@Transactional` 事務內：

```sql
START TRANSACTION;
SELECT balance FROM user_money WHERE user_id = 123 FOR UPDATE;
UPDATE user_money
  SET balance = balance - 100
  WHERE user_id = 123 AND balance >= 100;  -- CAS 條件避免超扣
COMMIT;
```

流程：驗餘額 → 鎖定行 → 扣減 → 寫流水，全部在同一事務。參考 `cx-sport-single-wallet-service` 各 `AbstractSingleWalletService` 子類。

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

- **統一用 `DECIMAL(16,2)`**，禁用 `FLOAT` / `DOUBLE`
- 對應 Java 層 `BigDecimal`
- 詳細 RoundingMode 規則見 `rules/security.md`

---

## 7. 游標分頁（避免大 OFFSET）

```sql
-- ❌ 慢：OFFSET 越大越慢
SELECT * FROM orders ORDER BY id LIMIT 20 OFFSET 100000;

-- ✅ 快：游標分頁
SELECT * FROM orders WHERE id > #{lastId} ORDER BY id LIMIT 20;
```

業務紀錄量大時，報表/查詢必用游標分頁。

---

## 8. 本專案常見陷阱

| 陷阱 | 問題 | 解法 |
|------|------|------|
| `SELECT *` | 回表、傳輸多餘資料 | 只選需要的欄位 |
| 隱式型別轉換 | `WHERE varchar_col = 123` 全表掃描 | `WHERE varchar_col = '123'` |
| `COUNT(*)` 大訂單表 | 全表掃描 | 快取計數或用 ES 聚合 |
| 未包含分片鍵 | ShardingSphere 跨所有分片查 | `WHERE` 必含分片鍵 |
| 寫後立即讀但沒 `@Transactional` | 主從延遲讀不到 | 同交易內或強制主庫 |
| 長交易 | 持有 `FOR UPDATE` 過久阻塞 | 交易內不做外部 API 呼叫 |
| 大表修改遷移檔 | Flyway checksum 失敗 | 寫新 `V` 檔案修正（時間戳版本號） |

---

## 相關資源

- Agent：`database-reviewer` - 完整資料庫審查工作流程
- Skill：`springboot-patterns` - Spring Boot 架構模式（DAO 與 Service 層）
- Skill：`business-template` - 金額異動 Redis 鎖與狀態機
- Rule：`rules/security.md` - 金額 RoundingMode 規範
