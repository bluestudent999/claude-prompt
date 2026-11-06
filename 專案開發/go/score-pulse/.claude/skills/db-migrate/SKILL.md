---
name: db-migrate
description: 建立與驗證 golang-migrate migration——時間戳版本、up/down 成對、租戶表判定並回寫 rules、月分區範例（賠率歷史與導流記錄改存 ES，不建表）、對 compose 環境套用、gorm/gen 重產、驗證器。要新增或改資料表時使用。
---

# db-migrate — 建立 migration

**用法：** `/db-migrate <snake_case_name>`

規則見 `rules/db-migration.md`。已套用的 migration **不可修改**；要改就開新的一支。

---

## Step 1 · 先判定表的歸屬

| 問 | 答 | 動作 |
|----|----|----|
| 同一列資料會不會屬於不同業主？ | 會 | 租戶表：必有 `platform_code VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL`（業主代碼，D20）+ 索引；唯一鍵是 `(platform_code, xxx)` |
| | 不會 | 共用表 |
| 它只增不改？ | 是 | append-only：不給 UPDATE/DELETE 路徑；大量寫入考慮分區 |

**回寫**（同一個 commit）：`rules/architecture.md` §4 的「擁有的表」與 `rules/tenant-isolation.md` §2 的兩欄；`scripts/arch-check.sh` 檔頭的 `TENANT_TABLES` / `APPEND_ONLY_TABLES` 與 `scripts/tenant-check.sh` 的 `TENANT_MODELS` / `SHARED_MODELS`。

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
  platform_code VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  member_id    BIGINT NOT NULL,
  target_type  TINYINT NOT NULL COMMENT '1 match 2 league 3 team 4 player',
  target_id    BIGINT NOT NULL,
  created_at   DATETIME(3) NOT NULL,
  UNIQUE KEY uk_fav (platform_code, member_id, target_type, target_id),
  KEY idx_fav_target (target_type, target_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
```

append-only 月分區（範例沿用既有的 `operate_log`；賠率歷史與導流記錄依 D29 改存 ES，**不建表**，見 `rules/es-store.md`）：

```sql
CREATE TABLE operate_log (
  id            BIGINT NOT NULL AUTO_INCREMENT,
  platform_code VARCHAR(20) NOT NULL,
  scope         VARCHAR(16) NOT NULL,
  -- …其餘欄位見 migrations/20261104081233_create_operate_log.up.sql
  created_at    DATETIME(3) NOT NULL,
  PRIMARY KEY (id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin
PARTITION BY RANGE COLUMNS (created_at) (
  PARTITION p202611 VALUES LESS THAN ('2026-12-01'),
  PARTITION p202612 VALUES LESS THAN ('2027-01-01'),
  PARTITION pmax    VALUES LESS THAN (MAXVALUE)
);
-- 每月由排程 job（core/job）REORGANIZE pmax 新增下月分區；第一期不 DROP 任何分區
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
  grep -qiE "CREATE TABLE\s+\`?(odds_history|redirect_click|redirect_impression|visit_log)\b" "$up" && { echo "FAIL D29：這張表改存 ES，不建 MySQL 表：$up"; rc=1; }
  for t in login_log operate_log; do
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
