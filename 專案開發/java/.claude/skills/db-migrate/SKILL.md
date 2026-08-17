---
name: db-migrate
description: 產生新的 Flyway migration（依 expand-contract 策略）並在乾淨環境驗證。任何 DB schema 變更時使用。
---

# db-migrate

新增一個安全、向後相容的資料庫遷移。

## 步驟

1. 用 `date +%Y%m%d%H%M%S` 產生時間戳版本號，委派 `migration-author` subagent 撰寫 `V<YYYYMMDDHHMMSS>__<description>.sql`，放 `src/main/resources/db/migration`（見 `rules/flyway-migration.md`）。
2. 確認遵循 expand-contract（先 expand、後 contract）、無正式環境破壞性變更、不破壞 `audit_log` 的 append-only 性質。
3. 用本地 `compose.yaml` 或 Testcontainers 驗證能在**乾淨資料庫**一次套用。
4. **跑版本號驗證器**（`rules/flyway-migration.md` §7）；若尚未實作，先實作它——那是 §7 明訂的必要交付項。
5. 回報新增檔案、變更摘要、**rollback 註記與風險等級**、驗證器結果。

高風險變更（資料搬移、收緊約束）需明確標示要人工 review。
