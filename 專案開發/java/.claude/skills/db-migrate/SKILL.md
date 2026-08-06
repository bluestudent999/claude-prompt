---
name: db-migrate
description: 產生新的 Flyway migration（依 expand-contract 策略）並在乾淨環境驗證。任何 DB schema 變更時使用。
---

# db-migrate

新增一個安全、向後相容的資料庫遷移。

## 步驟

1. 委派 `migration-author` subagent 依需求撰寫 `V{n}__{描述}.sql`，放 `src/main/resources/db/migration`。
2. 確認遵循 expand-contract（先 expand、後 contract）、無正式環境破壞性變更、不破壞 `audit_log` 的 append-only 性質。
3. 用本地 `compose.yaml` 或 Testcontainers 驗證能在**乾淨資料庫**一次套用。
4. 回報新增檔案、變更摘要、**rollback 註記與風險等級**。

高風險變更（資料搬移、收緊約束）需明確標示要人工 review。
