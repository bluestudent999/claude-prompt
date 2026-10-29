---
name: es-patterns
description: lion-service Elasticsearch DAO 模式 — framework_v3 抽象基類（AbstractBaseEsDao / AbstractEsPartitionByDateDao）、ES 6.8.22 與 7.17.18 並用、ElasticsearchTemplateAspect 主從讀寫切換、索引命名與分區策略。新增 ES DAO / 索引時載入。
origin: ECC adapted
---

# Elasticsearch 模式（ES 6.8.22 / 7.17.18 並用）

lion-service 的 ES 存取走 framework_v3（`com.cx.framework.dao.*`）的抽象 DAO：
- **6.8.22**：`PreBuiltXPackTransportClient`（TransportClient）+ spring-data-elasticsearch 3.2.12，DAO 的 `getTemplate()` 走這條
- **7.17.18**：只用在 `x-pack-sql-jdbc`（ES SQL 走 JDBC，對應 DAO 的 `jdbcBuildSQL` / `jdbcBuildSelect*` 與 `getJdbcTemplate()`）

主從讀寫由 `ElasticsearchTemplateAspect` 切換，**cp-service（`com.lc.cp.aspect`）與 single-wallet-service（`com.lc.single.wallet.aspect`）各一份、行為不同**（single-wallet 讀也走主庫），新 DAO 對齊所在模組的 aspect，見 [rw-split.md](rw-split.md)。

ES Model 與多數 ES DAO 放在 **`lion-common`**（`com.lc.common.bean.es.*` / `com.lc.common.dao.<domain>.*`）；依團隊「新增共享物件放 lion-common」原則，新 ES Model / DAO 預設也放 lion-common（跨 repo，見 `skills/cross-repo-commit/SKILL.md`），模組私有才放模組 `dao/`，並在 PR 說明理由。

**ES 查詢一律帶 `platformId` 維度**（包網商隔離，見 `rules/platform-isolation.md`）；跨包網商的查詢只限 boss / manage 類入口。

---

## 子文件索引

| 文件 | 內容 | 何時參考 |
|------|------|---------|
| [dao-and-index.md](dao-and-index.md) | DAO 繼承結構、索引定義（註解）、新建 DAO 模式、Client 設定、索引設計、新增 Checklist | 新建 DAO / 索引、選擇基類 |
| [query.md](query.md) | BoolQueryBuilder 查詢、聚合模式、聚合分頁、跨索引查詢、金額精度、查詢優化 | 寫查詢邏輯、效能調優 |
| [rw-split.md](rw-split.md) | 主從讀寫分離 Aspect 機制、ThreadLocal 運作原理、`getTemplate()` 反模式 | 新建 DAO、排查讀寫問題 |
