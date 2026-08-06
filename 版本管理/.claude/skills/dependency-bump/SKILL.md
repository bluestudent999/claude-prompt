---
name: dependency-bump
description: 升級單一第三方依賴並查證 jakarta + Spring Boot 3 / Framework 6 相容版本。處理單一依賴卡住升級、或需確認某庫相容下限/替代庫時使用。版本一律查證不憑記憶。
---

# 單一依賴升級 + 相容查證

> 升級常卡在「某個庫不相容」。本 skill 處理單一依賴的查證 → 升版 → 驗證流程。

## 啟用時機

- 編譯/啟動因某第三方庫不相容 Boot 3 而失敗。
- plan §1 版本鎖定表需查某依賴的相容下限。
- 需評估「升版能解 vs 必須換庫」。

## 流程

```
1. 確認現況版本（不是 pom 字面值，是 effective 版本）
     mvn dependency:tree -Dincludes=<groupId>:<artifactId>
2. 查證相容版本（禁憑記憶）→ 交 compat-researcher / Context7
     - 升版能解？→ 取相容下限
     - 升版不能解？→ 換庫（見 breaking-changes.md §E）
3. 寫入根 pom <properties> / dependencyManagement（不在子模組散落）
4. mvn dependency:tree 驗無新衝突
5. mvn compile 驗編譯
```

## 判斷「升版 vs 換庫」

| 情況 | 動作 |
|------|------|
| 庫有支援 Boot 3 / jakarta 的新版 | 升版（取相容下限，對齊 version-matrix §3） |
| 庫已停止維護 / 無 Boot 3 版（springfox） | 換庫（springdoc 等），列 OQ 確認本次處理與否 |
| 庫有 Boot 3 專屬 artifact（mybatis-plus） | 換 artifact 座標（`mybatis-plus-spring-boot3-starter`） |

## 常見依賴速查（對照 version-matrix.md §3）

| 依賴 | Boot 3 動作 |
|------|------------|
| mybatis-spring-boot-starter | 升到 3.0.x+ |
| mybatis-plus | 換 `mybatis-plus-spring-boot3-starter` |
| hibernate-validator | 升 8.x（jakarta.validation） |
| lombok | 升 1.18.30+（JDK 17/21 支援） |
| springfox | **換** springdoc-openapi 2.x |
| flyway | 升 9.x+ |

## 原則

- 版本走根 pom 統一管理（`CLAUDE.md §2` 紅線）。
- 只升「為了相容必須升」的依賴，不順手升無關依賴（行為等價優先）。
- 查不到相容版本 → 列 OQ，不硬升。
