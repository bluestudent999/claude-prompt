# 版本相容矩陣（單一事實來源）

> **本檔是整個升級的版本權威來源。** 所有 Java / Spring Boot / Spring Framework / 第三方依賴的版本，以本檔為準。
> **硬規則：** 個別模組 `pom.xml` **禁止**散落寫死版本號；版本一律走根 `pom.xml` 的 `<properties>` 或 `spring-boot-dependencies` BOM 統一管理。改版本 → 改本檔 + 改根 pom，不在子模組偷改。

---

## 0. 升級目標總表（開工先填）

| 項目 | 來源（升級前） | 目標（升級後） | 鎖定理由 |
|------|--------------|--------------|---------|
| **Java** | `<填：8>` | `<填：21 LTS>` | LTS、與 SDRP 目標棧對齊 |
| **Spring Boot** | `<填：2.7.x>` | `<填：3.x 最新穩定>` | — |
| **Spring Framework** | 5.3.x（隨 Boot 2.7） | 6.x（隨 Boot 3） | Boot 拉動，不單獨指定 |
| **Spring Cloud** | `<填：2021.0.x>` | `<填：2023.0.x / 2024.0.x>` | 必須對齊 Boot 3，見 §2 |
| **Maven** | `<填>` | `≥ 3.6.3`（Boot 3 plugin 需求） | — |
| **建置 JDK** | 8 | 17 或 21（≥ Boot 3 下限） | — |

> **填寫硬規則：** 開工第一件事是把上表「來源」欄用 `mvn help:effective-pom` / `java -version` 確認後填實，**禁止憑記憶填**。目標欄由使用者於 UPGRADE 工單決議。

---

## 1. Spring Boot 3 的硬性版本下限（不可違反）

| 約束 | 值 | 後果 |
|------|----|----|
| **最低 Java** | **17** | Boot 3.x 在 Java 8 下**無法啟動/編譯** |
| **Jakarta EE** | **9+**（`jakarta.*` namespace） | `javax.*` 企業 API 全數失效，見 `jakarta-migration.md` |
| **Servlet** | **5.0+**（Tomcat 10） | Servlet API 從 `javax.servlet` → `jakarta.servlet` |
| **Hibernate** | **6.x** | HQL / 方言 / `@Type` 用法變更 |

> Spring Boot 3.0 下限 Java 17；3.2+ 支援 Java 21。本專案目標 Java 21 → Boot 取 **3.2 以上**（在 §0 鎖定確切版本）。

---

## 2. Spring Cloud 對齊（最易踩雷）

Spring Cloud 版本**必須**與 Spring Boot release train 對齊，**錯版會出現 `NoSuchMethodError` / context 啟動失敗**：

| Spring Boot | 相容 Spring Cloud | 備註 |
|-------------|------------------|------|
| 2.7.x | 2021.0.x | 升級前現況 |
| 3.0.x / 3.1.x | 2022.0.x | — |
| 3.2.x | 2023.0.x | — |
| 3.3.x / 3.4.x | 2024.0.x | 目標候選 |

> **硬規則：** Spring Cloud 版本由 `dependency-analyzer` 對照[官方相容表](https://spring.io/projects/spring-cloud#overview)決定，**禁止**沿用舊 train。

---

## 3. 第三方依賴 — jakarta + Spring 6 相容版本門檻

> 下表是**常見會被 Boot 3 卡住**的依賴。實際版本由 `compat-researcher` agent 查證後回填（**禁止**憑記憶寫版本），填入根 pom `<properties>`。

| 依賴 | 升級前 | jakarta/Boot3 相容下限 | 遷移要點 |
|------|--------|----------------------|---------|
| **springfox-swagger**（若用） | 3.x | ❌ **不相容 Boot 3** | **必須換成 `springdoc-openapi`（2.x）**——非升版而是換庫，見 `breaking-changes.md` |
| **springdoc-openapi**（若已用） | 1.x | 2.x | 1.x 對 Boot 2、2.x 對 Boot 3 |
| **MyBatis-Spring-Boot-Starter** | 2.x | **3.0.x+** | starter 3.x 才支援 Boot 3 |
| **MyBatis-Plus** | 3.5.x | `mybatis-plus-spring-boot3-starter`（3.5.7+） | Boot 3 專屬 starter artifact |
| **ShardingSphere** | `<填>` | 5.3.x+（確認 jakarta 相容版本） | 配置 DSL 可能變更，需回歸 |
| **Hibernate Validator** | 6.x（javax.validation） | 8.x（jakarta.validation） | `javax.validation` → `jakarta.validation` |
| **Flyway** | `<填>` | 9.x+（Boot 3 管理） | DB driver / baseline 行為確認 |
| **Lombok** | `<填>` | 1.18.30+（支援 JDK 17/21） | 舊版在新 JDK 編譯失敗 |
| **MapStruct**（若用） | `<填>` | 1.5.5+ | annotation processor 順序 |
| **Jackson** | 隨 Boot 2.7 | 隨 Boot 3（不單獨指定） | 由 BOM 管理 |
| **JUnit** | 4 / 5 | 5（Jupiter） | 見 `verification.md` |
| **SnakeYAML** | 1.x | 2.x（Boot 3 管理） | YAML 解析行為微調 |

---

## 4. Java SE 內建移除 / 變更（影響編譯的 JDK 變更）

| 項目 | 移除/變更版本 | 影響 | 替代 |
|------|-------------|------|------|
| **JAXB**（`javax.xml.bind`） | JDK 11 起已移除出 JDK | 編譯找不到 | 加 `jakarta.xml.bind-api` + `jaxb-runtime` 依賴 |
| **JAX-WS / activation** | JDK 11 起移除 | — | 加對應 jakarta 依賴 |
| **Nashorn JS 引擎** | JDK 15 移除 | `ScriptEngine` js 失效 | GraalVM JS 或移除用法 |
| **CMS GC** | JDK 14 移除 | `-XX:+UseConcMarkSweepGC` 啟動失敗 | 改 G1 / ZGC（清 JVM 參數） |
| **`Thread.stop/suspend/resume`** | 逐步移除/拋例外 | — | 重構執行緒控制 |
| **`finalize()`** | 標記移除 | warning | 改 `Cleaner` / try-with-resources |
| **Security Manager** | JDK 17 標記移除 | warning | 通常移除相關設定 |

> 完整修法見 `breaking-changes.md §Java`。

---

## 5. 版本回填檢查（plan 必含）

升級 plan §1 必須包含一張「版本鎖定確認表」，逐列標註：

```
| 依賴 | 現況版本(effective-pom 證據) | 目標版本(compat 查證來源) | 寫入位置(根 pom property 名) | 狀態 |
```

- **現況版本**：`mvn help:effective-pom` 或 `mvn dependency:tree` 輸出為證，不是 `pom.xml` 的字面值（可能被 BOM 覆寫）。
- **目標版本**：附 `compat-researcher` 查證來源連結。
- 任何一列「目標版本」未查證 → 列為 OQ，**禁止**直接升。
