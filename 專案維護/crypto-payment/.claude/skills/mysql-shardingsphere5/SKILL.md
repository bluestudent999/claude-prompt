---
name: mysql-shardingsphere5
description: crypto-payment 資料層模式 — MySQL 8 + ShardingSphere 5.4 讀寫分離、DAO 風格、Flyway migration（只增不改）、參數化查詢、platform_id 過濾、金額精度。新增查詢 / migration 時載入。
---

# 資料層模式（MySQL 8 + ShardingSphere 5.4）

> 動手前先 grep `repository/` 既有 DAO 對齊實際持久化框架與寫法（勿臆造框架）。

## ShardingSphere 5.4 讀寫分離

- **自動讀寫分離，不要手動指定讀/寫庫**——寫走主庫、讀走從庫由 ShardingSphere 路由
- **主從延遲陷阱**：剛寫入後立即讀，從庫可能還沒同步 → 需「讀自己剛寫的」時，在同事務內讀，或強制走主庫（依既有 hint 慣例）
- 5.x 設定與 4.x 不同（`rules:` / `readwrite-splitting:` 結構），改設定前先看既有 `application*.yml`

## DAO / 查詢

- DAO 在 `repository/`，搭配專案既有持久化框架
- **參數化查詢**：綁定參數，**禁字串拼接 SQL**；若用 MyBatis 一律 `#{param}`，**禁 `${param}`**（動態表名 / 排序欄位需白名單校驗）
- **每個查詢 / 更新都要有 `platform_id`（或等價 platform 範圍）過濾**（見 `rules/security.md` §2）
- 分頁用既有 pagination 慣例

## 金額精度

- DB 金額欄位用 `DECIMAL`（足夠精度，鏈上 decimals 大）；Java 端一律 `BigDecimal` + `RoundingMode.DOWN`（見 `rules/security.md` §5）
- 入款 / 交易唯一性：`txHash` / `orderNo` 加**唯一約束**（DB 層冪等保護）

## Flyway Migration（`crypto-payment-flyway` 模組）

- schema 變更**一律新增版號檔**：`crypto-payment-flyway/src/main/resources/db/migration/V1_0_x__description.sql`
- **禁改既有 migration 檔**——已套用的檔改了 checksum 衝突，整個 migration 失敗
- 命名遵循既有版號序列（先 `ls` 看最大版號往後接）
- **執行 migration 需明確確認**，Agentic 任務**禁自動跑 flyway:migrate**
- 加欄位不鎖表；重構欄位走「新增 → 雙寫 → 切讀 → 刪舊」（見 `rules/stability.md`）

```sql
-- V1_0_7__add_confirm_count_to_deposit.sql
ALTER TABLE deposit_record ADD COLUMN confirm_count INT NOT NULL DEFAULT 0 COMMENT '鏈上確認數';
```

## 快取一致性

- 寫 DB 後同事務內或緊接失效 / 更新對應 Redis key（見 `springboot3-patterns` skill）

## 相關

- 私鑰 / 金額 / platform_id → `rules/security.md`
- 分層 / 快取 / Kafka → `springboot3-patterns` skill
- 入款 / 歸集資料流 → `blockchain-wallet` skill
