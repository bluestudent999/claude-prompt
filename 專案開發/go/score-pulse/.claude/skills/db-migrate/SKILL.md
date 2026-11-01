---
name: db-migrate
description: 建立與驗證 golang-migrate migration——時間戳版本、up/down 成對、租戶表判定並回寫 rules、odds_history 月分區範例、對 compose 環境套用、gorm/gen 重產、驗證器。要新增或改資料表時使用。
---

# db-migrate — 建立 migration

**用法：** `/db-migrate <snake_case_name>`

規則見 `rules/db-migration.md`。已套用的 migration **不可修改**；要改就開新的一支。

---

## Step 1 · 先判定表的歸屬

| 問 | 答 | 動作 |
|----|----|----|
| 同一列資料會不會屬於不同業主？ | 會 | 租戶表：必有 `operator_id BIGINT NOT NULL` + 索引；唯一鍵是 `(operator_id, xxx)` |
| | 不會 | 共用表 |
| 它只增不改？ | 是 | append-only：不給 UPDATE/DELETE 路徑；大量寫入考慮分區 |

**回寫**（同一個 commit）：`rules/architecture.md` §4 的「擁有的表」與 `rules/tenant-isolation.md` §2 的兩欄；`skills/arch-check/arch-check.sh` 檔頭的 `TENANT_TABLES` / `APPEND_ONLY_TABLES`。

## Step 2 · 建檔

```bash
migrate create -ext sql -dir migrations -format 20060102150405 add_favorite
ls migrations | tail -2      # 20261120103000_add_favorite.up.sql / .down.sql 成對
```

`down.sql` 必須能還原 `up.sql`；不要寫 `-- noop`。

## Step 3 · 範例

租戶表：

```sql
CREATE TABLE favorite (
  id           BIGINT PRIMARY KEY AUTO_INCREMENT,
  operator_id  BIGINT NOT NULL,
  member_id    BIGINT NOT NULL,
  target_type  TINYINT NOT NULL COMMENT '1 match 2 league 3 team 4 player',
  target_id    BIGINT NOT NULL,
  created_at   DATETIME(3) NOT NULL,
  UNIQUE KEY uk_fav (operator_id, member_id, target_type, target_id),
  KEY idx_fav_target (target_type, target_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
```

append-only 月分區（`odds_history`，D6）：

```sql
CREATE TABLE odds_history (
  id         BIGINT NOT NULL AUTO_INCREMENT,
  match_id   BIGINT NOT NULL,
  company_id INT NOT NULL,
  market     VARCHAR(8) NOT NULL,
  stage      VARCHAR(4) NOT NULL,
  o1 DECIMAL(10,4) NOT NULL, o2 DECIMAL(10,4) NOT NULL, o3 DECIMAL(10,4) NOT NULL,
  score_h TINYINT NULL, score_a TINYINT NULL,
  changed_at DATETIME(3) NOT NULL,
  PRIMARY KEY (id, changed_at),
  KEY idx_oh_lookup (match_id, company_id, market, stage, changed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin
PARTITION BY RANGE COLUMNS (changed_at) (
  PARTITION p202611 VALUES LESS THAN ('2026-12-01'),
  PARTITION p202612 VALUES LESS THAN ('2027-01-01'),
  PARTITION pmax    VALUES LESS THAN (MAXVALUE)
);
-- 每月由排程 job（platform/job）REORGANIZE pmax 新增下月分區；第一期不 DROP 任何分區
```

## Step 4 · 套用與重產 model

```bash
docker compose -f deploy/docker-compose.yml up -d mysql
export DB_URL="mysql://$MYSQL_USER:$MYSQL_PASSWORD@tcp($MYSQL_HOST:$MYSQL_PORT)/$MYSQL_DB?multiStatements=true"
migrate -path migrations -database "$DB_URL" up
migrate -path migrations -database "$DB_URL" down 1 && migrate -path migrations -database "$DB_URL" up   # down 可還原
go run ./cmd/gen && git status --short internal/*/model/                                                 # 重產，只有預期的 model 變動
```

## Step 5 · 驗證器

```bash
bash - <<'SH'
set -u; rc=0
for up in migrations/*.up.sql; do
  v="$(basename "$up" | cut -d_ -f1)"; echo "$v" | grep -qE '^[0-9]{14}$' || { echo "FAIL 版本格式：$up"; rc=1; }
  [ -f "${up%.up.sql}.down.sql" ] || { echo "FAIL 缺 down：$up"; rc=1; }
  grep -qiE '^\s*DROP TABLE' "$up" && { echo "FAIL up 內 DROP 既有表：$up（要刪表先開 OQ）"; rc=1; }
  for t in odds_history admin_audit redirect_click redirect_impression visit_log; do
    grep -qiE "^\s*(UPDATE|DELETE FROM)\s+$t\b" "$up" && { echo "FAIL append-only 表被改：$t in $up"; rc=1; }
  done
done
git diff --name-only HEAD -- migrations/ | grep -v "$(git diff --name-only --diff-filter=A HEAD -- migrations/)" | grep -q . && { echo "FAIL 修改了已存在的 migration"; rc=1; }
[ $rc -eq 0 ] && echo "migration 驗證 PASS"; exit $rc
SH
```

## 回報

```
migration：20261120103000_add_favorite（租戶表 / 共用表 / append-only）
rules 回寫：architecture §4、tenant-isolation §2、arch-check.sh 常數
gen：internal/member/model/favorite.gen.go 新增
驗證器：PASS
```
