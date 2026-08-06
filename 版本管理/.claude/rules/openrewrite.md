# OpenRewrite 自動遷移規範

> OpenRewrite 是升級期的**自動遷移主力**——它以 AST 重寫做語義級遷移（不是字串取代），內建 Spring Boot 3 / Java / jakarta 的官方 recipe，能正確處理 namespace 白名單、API 改名、設定遷移。
> **硬規則：可被 recipe 覆蓋的大批量機械改動，一律先跑 recipe，禁止逐檔手刻。** 手刻易漏、不一致、吃 token，且 jakarta 白名單人工極易判錯。

---

## 1. 為什麼自動遷移優先

| 手刻問題 | OpenRewrite 解法 |
|---------|-----------------|
| jakarta 白名單判錯（誤改 `javax.crypto`） | recipe 內建白名單，只改 EE 類 |
| 數百檔 import 改名漏改 | AST 全掃，一致 |
| 設定屬性改名記不全 | spring recipe 覆蓋官方屬性對照 |
| 改動量大吃 token | recipe 一次跑完，主 agent 只審 diff |

---

## 2. 標準執行流程（dryRun 先行 — 硬規則）

```bash
export JAVA_HOME="$JAVA_HOME_TARGET"   # recipe 需目標 JDK

# Step 1：dryRun（不改檔，只產生 patch 供審查）
mvn -U org.openrewrite.maven:rewrite-maven-plugin:dryRun \
  -Drewrite.activeRecipes=org.openrewrite.java.spring.boot3.UpgradeSpringBoot_3_3 \
  -Drewrite.recipeArtifactCoordinates=org.openrewrite.recipe:rewrite-spring:RELEASE

# Step 2：審查 patch
#   patch 檔：target/rewrite/rewrite.patch
#   逐檔看 diff，確認沒有「行為改動」混入（recipe 偶爾會改邏輯，例如 null 處理）

# Step 3：確認無誤後 run（實際改檔）
mvn -U org.openrewrite.maven:rewrite-maven-plugin:run \
  -Drewrite.activeRecipes=org.openrewrite.java.spring.boot3.UpgradeSpringBoot_3_3 \
  -Drewrite.recipeArtifactCoordinates=org.openrewrite.recipe:rewrite-spring:RELEASE

# Step 4：立即獨立 commit（與後續人工修復分開）
git add -A && git commit -m "chore: OpenRewrite 自動遷移 Spring Boot 3 + jakarta"
```

> **soft_deny：** `run` 前未跑 `dryRun` 審 diff 是被禁止的（見 `settings.json`）。recipe 改動量大，盲跑無法區分機械遷移與行為改動。

---

## 3. 常用 recipe 對照

| 目的 | recipe ID | artifact |
|------|-----------|---------|
| **Spring Boot 3.x 全套升級**（含 jakarta + 屬性 + API） | `org.openrewrite.java.spring.boot3.UpgradeSpringBoot_3_3`（版號依目標調整） | `rewrite-spring` |
| **Java 升級到 21** | `org.openrewrite.java.migrate.UpgradeToJava21` | `rewrite-migrate-java` |
| **僅 jakarta namespace** | `org.openrewrite.java.migrate.jakarta.JakartaEE10` | `rewrite-migrate-java` |
| **JUnit 4 → 5** | `org.openrewrite.java.testing.junit5.JUnit4to5Migration` | `rewrite-testing-frameworks` |
| **依賴版本對齊** | `org.openrewrite.maven.UpgradeDependencyVersion`（指定 groupId/artifactId/newVersion） | core |
| **移除多餘設定** | Spring recipe 內含 | `rewrite-spring` |

> recipe 版號（如 `_3_3`）要對齊 `version-matrix.md §0` 鎖定的目標 Boot 版本。最新可用 recipe 與版號由 `compat-researcher` 查 [OpenRewrite docs](https://docs.openrewrite.org/recipes/java/spring) 確認。

---

## 4. recipe 跑完一定要做的事

1. **mvn compile 看殘餘錯誤**：recipe 覆蓋 ~70-85%，剩下交 `build-error-resolver`（Step 3）。
2. **grep 驗 jakarta 殘留**：見 `jakarta-migration.md §5`，確認非白名單 javax 為 0。
3. **審 recipe 改的「非 import」改動**：recipe 有時會改邏輯（如 deprecated 方法替換可能語義微調）——這些**不是純機械**，要 regression-reviewer 看。
4. **不要 recipe 改 + 人工改混在同一 commit**：commit 分開，方便 `git bisect` 二分出問題來源。

---

## 5. recipe 不該/不能做的

- **不要靠 recipe 做業務重構**——recipe 只做版本遷移。
- **不要對 recipe 改不動的「換庫」項目硬套 recipe**（springfox→springdoc 沒有完整自動 recipe，需人工，見 `breaking-changes.md §E`）。
- **設定檔遷移**：yml/properties 屬性遷移優先用 `spring-boot-properties-migrator`（runtime 報告，見 `boot3-config-migrate` skill），recipe 為輔。
- recipe 失敗（解析不了 / 改壞）→ 不要第三次重跑同參數，回退該 recipe，改人工 + 記錄到 plan。
