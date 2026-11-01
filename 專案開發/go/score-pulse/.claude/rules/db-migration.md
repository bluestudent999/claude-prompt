# DB migration（golang-migrate，D6a）

> MySQL 8 是唯一主庫。schema 的唯一真相是 `migrations/`；gorm model 由 schema 反向產生（`cmd/gen`），**不是**反過來。
> 版本號用時間戳，對齊公司 Java 範本的 Flyway 慣例：永遠遞增、不會撞號、不需協調。

---

## 1. 檔案與命名

```
migrations/
├── 20261109100000_create_operator.up.sql
├── 20261109100000_create_operator.down.sql
├── 20261109101500_create_match.up.sql
├── 20261109101500_create_match.down.sql
└── ...
```

| 規則 | 說明 |
|------|------|
| 檔名 | `<YYYYMMDDHHMMSS>_<snake_case>.up.sql` 與同名 `.down.sql`，**成對** |
| 版本 | 建檔當下的 UTC 時間（`date -u +%Y%m%d%H%M%S`）；`/db-migrate` 會產生 |
| 一檔一事 | 一張表、或一組相關索引、或一次資料修正；不要一個檔建五張表 |
| 描述 | 動詞開頭：`create_`、`add_column_`、`add_index_`、`alter_`、`seed_`；**不出現 ticket 編號**（ticket 編號寫在檔頭註解） |
| 檔頭 | `-- ticket: S1-T1` + 一行目的 |
| 已套用的 migration **不可改** | 要修就新開一個版本；改了已套用的檔，別人的 DB 與你的會永久分岔 |
| down | 必須能真的回滾（`DROP TABLE IF EXISTS`、`DROP INDEX`、反向 `ALTER`）；資料修正類的 down 可以是 no-op，但要註明 |

---

## 2. 新表前先決定三件事

| 問題 | 回寫到 |
|------|--------|
| 它是租戶表嗎（同一列會不會屬於不同業主）？ | `tenant-isolation.md` §2 的對應欄；租戶表第一欄是 `operator_id BIGINT NOT NULL` |
| 哪個功能包擁有它（唯一的寫入者）？ | `architecture.md` §4 |
| 它是 append-only 嗎（I5、I10）？ | 是 → 註解寫明，`/arch-check` 會掃 UPDATE／DELETE |

沒有回寫這兩份規則的新表，`arch-guard` 判 HIGH。

---

## 3. 表設計規則

| 規則 | 說明 |
|------|------|
| 主鍵 | `id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT`；供應商 id 另存 `provider_id`，不當主鍵 |
| 字元集 | `utf8mb4` / `utf8mb4_0900_ai_ci`（名稱比對不分大小寫）；需要區分大小寫的欄位（token）用 `utf8mb4_bin` |
| 時間 | `DATETIME(3)`，**一律 UTC**，欄位名 `*_at`；`created_at`、`updated_at` 每表必有 |
| 金額、賠率 | `DECIMAL(12,4)`；不用 FLOAT／DOUBLE |
| 布林 | `TINYINT(1)`，欄位名 `is_*` |
| 狀態 | `TINYINT` + 註解列出每個值；或 `VARCHAR(16)` 字串碼，**二選一全專案一致**（採用預設：字串碼，可讀） |
| 外鍵 | **不建 FOREIGN KEY 約束**（公司慣例）；關聯完整性由應用層與測試保證；但要建對應索引 |
| 索引 | 租戶表的複合索引**以 `operator_id` 開頭**：`idx_member_op_phone (operator_id, phone)`；唯一鍵同理 `uk_member_op_account (operator_id, account)` |
| 全平台唯一 | 只有真正全平台唯一的欄位（專屬域名）才是單欄唯一鍵 |
| 軟刪除 | 預設不用；需要「停用」用狀態欄；真正要保留歷史的表（operator、member）用 `deleted_at` 且查詢經 gorm 預設 scope |
| 註解 | 每欄 `COMMENT`，中文可 |
| 保留字 | 不用 `match`、`order`、`key` 當表名或欄名 → 表名用 `match_info`（與 architecture §4 的 `match` 對應） |

---

## 4. `odds_history` 分區（I5、D6）

```sql
CREATE TABLE odds_history (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  match_id BIGINT NOT NULL,
  company_id INT NOT NULL,
  market VARCHAR(8) NOT NULL,
  stage VARCHAR(4) NOT NULL,
  v1 DECIMAL(12,4) NOT NULL, v2 DECIMAL(12,4) NOT NULL, v3 DECIMAL(12,4) NOT NULL,
  score_h TINYINT NULL, score_a TINYINT NULL,
  provider_ts DATETIME(3) NOT NULL,
  created_at DATETIME(3) NOT NULL,
  PRIMARY KEY (id, provider_ts),
  KEY idx_oh_match (match_id, company_id, market, provider_ts)
) PARTITION BY RANGE COLUMNS (provider_ts) (
  PARTITION p202611 VALUES LESS THAN ('2026-12-01'),
  PARTITION p202612 VALUES LESS THAN ('2027-01-01'),
  PARTITION pmax    VALUES LESS THAN (MAXVALUE)
);
```

| 規則 | 說明 |
|------|------|
| 分區鍵 | `provider_ts` 按月 RANGE；主鍵必須含分區鍵 |
| 新增分區 | `admin` 包的排程 job（每月 20 日）執行 `ALTER TABLE ... REORGANIZE PARTITION pmax INTO (p<下月>, pmax)`；job 有 Redis 鎖（`framework-conventions.md` §7） |
| 只 INSERT | 無 UPDATE／DELETE 語句；`/arch-check` 掃 |
| 只存變動 | `persist` consumer 比對同鍵上一筆值，無變動不寫（`realtime-contract.md` §1.2） |
| 容量 | 總控監控頁顯示各分區列數與大小（`information_schema.PARTITIONS`）；第一期不刪 |
| 查詢 | 走勢查詢一律帶 `provider_ts` 範圍讓分區裁剪生效 |

其他大量寫入表（`redirect_click`、`redirect_impression`、`visit_log`、`admin_audit`）同樣按月分區，鍵是 `created_at`。

---

## 5. gorm/gen 重產

```bash
go run ./cmd/gen            # 連本機 MySQL 讀 schema，產 internal/<pkg>/model/*.gen.go
```

| 規則 | 說明 |
|------|------|
| `*.gen.go` 不手改 | 要加方法寫在同包的非 gen 檔（例 `match_info_ext.go`） |
| 表 → 包 | `cmd/gen/main.go` 維護「表名 → 功能包」對照，與 `architecture.md` §4 一致；新表要加進去 |
| 何時跑 | 每次 `migrate up` 之後；CI 會檢查 `git diff --exit-code internal/**/model/*.gen.go`，不一致即失敗 |
| 型別 | `DECIMAL` → `decimal.Decimal`；`DATETIME(3)` → `time.Time`；可空欄位 → 指標 |

---

## 6. 指令

```bash
# 起本機 MySQL（與 Redis、Kafka 一起）
docker compose -f deploy/docker-compose.yml up -d mysql redis kafka

# 套用全部
migrate -path migrations -database "mysql://root:lion@tcp(localhost:3306)/score_pulse?multiStatements=true" up

# 回滾一步 / 看版本
migrate -path migrations -database "$DSN" down 1
migrate -path migrations -database "$DSN" version

# 新建一組檔（由 /db-migrate 包裝）
migrate create -ext sql -dir migrations -format 20060102150405 create_operator
```

DSN 放環境變數 `SP_MYSQL_DSN`；不寫進腳本。

---

## 7. 驗證器（CI 與 `/db-migrate` 都跑）

| 檢查 | 失敗條件 |
|------|---------|
| 版本格式 | 檔名不符 `^\d{14}_[a-z0-9_]+\.(up|down)\.sql$` |
| 成對 | 有 up 無 down 或反之 |
| 遞增 | 新檔版本小於既有最大版本（時鐘錯或抄了舊檔名） |
| 不改已套用 | `git diff origin/developing -- migrations/` 顯示既有檔被修改 |
| 無 DROP 既有表 | up 檔出現 `DROP TABLE`（非 `IF EXISTS` 於 down） |
| 外鍵 | 出現 `FOREIGN KEY` |
| 租戶表 | 表名在 `tenant-isolation.md` §2 租戶欄，但無 `operator_id` 欄或索引不以它開頭 |
| gen 同步 | `go run ./cmd/gen` 後 `*.gen.go` 有 diff |

---

## 8. 常見坑

| 坑 | 處置 |
|----|------|
| `Dirty database version` | 上一個 migration 中途失敗；修好 SQL 後 `migrate force <上一版>` 再 `up`，**不要**直接改失敗那檔以外的東西 |
| 分區表加唯一鍵失敗 | MySQL 要求唯一鍵含分區鍵；重新設計鍵或不做唯一 |
| `multiStatements=true` 漏掉 | 一檔多句會只跑第一句 |
| 時區 | 容器 `TZ` 與 DSN 的 `loc` 一律 UTC；看到 `+08:00` 的時間就是哪一層設錯了 |
| 本機與測試環境版本分岔 | 永遠從 `developing` 拉最新 migrations 再建新檔；衝突時版本號較小者仍能套用，但要確認語意不衝突 |
| 大表加欄位 | 第一期資料量小可直接 ALTER；上線後要用 `ALGORITHM=INPLACE, LOCK=NONE` 並在離峰 |
