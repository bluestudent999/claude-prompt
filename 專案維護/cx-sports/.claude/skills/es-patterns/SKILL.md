---
name: es-patterns
description: sport Elasticsearch DAO 模式 — sport-framework 抽象基類、ES 6.8.22 與 7.17.18 並用、主從讀寫切換、索引命名與分區策略。新增 ES DAO / 索引時載入。
origin: ECC adapted
---

# Elasticsearch 模式（ES 6.8.22 / 7.17.18 並用）

sport 同時依賴 ES 6.8.22 與 7.17.18 — 不同模組依 client 設定切換版本，主從讀寫透過 Aspect 切換讀副本 / 寫主庫。新 DAO 對齊所在模組的 aspect，不要混用。

ES Model 與基底 DAO 主要放在 **`cx-sport-common`**（`com.lc.sports.bean.es.*` / `com.lc.sports.dao.*EsDao`），業務模組只在自己的 `dao/` 寫繼承類。

---

## 子文件索引

| 文件 | 內容 | 何時參考 |
|------|------|---------|
| [dao-and-index.md](dao-and-index.md) | DAO 繼承結構、索引定義（註解）、新建 DAO 模式、Client 設定、索引設計、新增 Checklist | 新建 DAO / 索引、選擇基類 |
| [query.md](query.md) | BoolQueryBuilder 查詢、聚合模式、聚合分頁、跨索引查詢、金額精度、查詢優化 | 寫查詢邏輯、效能調優 |
| [rw-split.md](rw-split.md) | 主從讀寫分離 Aspect 機制、ThreadLocal 運作原理、`getTemplate()` 反模式 | 新建 DAO、排查讀寫問題 |