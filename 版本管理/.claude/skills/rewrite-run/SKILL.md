---
name: rewrite-run
description: 跑 OpenRewrite recipe 做版本升級自動遷移（jakarta namespace、Spring Boot 3 API/屬性、Java 升級、JUnit 4→5）。一律先 dryRun 審 diff 再 run，跑完獨立 commit。批量機械遷移的主力工具。
---

# OpenRewrite 自動遷移執行

> 升級期自動遷移主力。完整規範見 `rules/openrewrite.md`，本 skill 是執行步驟備忘。

## 啟用時機

- Step 2 自動遷移（Phase B）：jakarta + Boot 3 + Java 升級。
- 任何「大批量機械改名」場景——優先 recipe，不手刻。

## 鐵則

1. **dryRun 先行**：先產 patch 審查，確認無夾帶邏輯改動，再 run。
2. **目標 JDK**：`export JAVA_HOME="$JAVA_HOME_TARGET"`。
3. **recipe 跑完獨立 commit**：與人工修復分開（可二分）。
4. **recipe 版號對齊** `version-matrix.md §0` 鎖定的目標 Boot 版本。

## 標準流程

```bash
export JAVA_HOME="$JAVA_HOME_TARGET"

# ── dryRun（不改檔）──
mvn -U org.openrewrite.maven:rewrite-maven-plugin:dryRun \
  -Drewrite.recipeArtifactCoordinates=org.openrewrite.recipe:rewrite-spring:RELEASE \
  -Drewrite.activeRecipes=org.openrewrite.java.spring.boot3.UpgradeSpringBoot_3_3

# 審查 patch：target/rewrite/rewrite.patch
#   逐檔看 diff，揪出「非機械」改動（邏輯/null 處理變更）

# ── run（確認後實際改檔）──
mvn -U org.openrewrite.maven:rewrite-maven-plugin:run \
  -Drewrite.recipeArtifactCoordinates=org.openrewrite.recipe:rewrite-spring:RELEASE \
  -Drewrite.activeRecipes=org.openrewrite.java.spring.boot3.UpgradeSpringBoot_3_3

# ── 立即獨立 commit ──
git add -A && git commit -m "chore: OpenRewrite 自動遷移 Spring Boot 3 + jakarta"
```

## 常用 recipe（對照目標版本選用）

| 目的 | activeRecipe | recipeArtifactCoordinates |
|------|-------------|--------------------------|
| Boot 3.x 全套（含 jakarta + 屬性） | `org.openrewrite.java.spring.boot3.UpgradeSpringBoot_3_3` | `org.openrewrite.recipe:rewrite-spring:RELEASE` |
| Java 21 | `org.openrewrite.java.migrate.UpgradeToJava21` | `org.openrewrite.recipe:rewrite-migrate-java:RELEASE` |
| 僅 jakarta | `org.openrewrite.java.migrate.jakarta.JakartaEE10` | `rewrite-migrate-java` |
| JUnit 4→5 | `org.openrewrite.java.testing.junit5.JUnit4to5Migration` | `org.openrewrite.recipe:rewrite-testing-frameworks:RELEASE` |

> recipe 版號（`_3_3`）與最新可用 recipe 由 `compat-researcher` 查 https://docs.openrewrite.org/recipes/java/spring 確認。

## 跑完必做（見 openrewrite.md §4）

1. `mvn compile` 看殘餘錯誤 → 交 `build-error-resolver`。
2. grep 驗 jakarta 殘留（`jakarta-migration.md §5`）。
3. 審 recipe 改的非 import 改動 → 交 `regression-reviewer`。

## 失敗處理

- recipe 解析/改壞 → 不要第三次同參數重跑。回退（`git checkout`），改人工 + 記錄到 plan §4。
- recipe 改不動的換庫項（springfox）→ 不是 recipe 範圍，走換庫流程。
