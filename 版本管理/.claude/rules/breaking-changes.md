# 已知 Breaking Change 清單（Java 17/21 + Spring Boot 3）

> 直接跳躍升級時，breaking change 會一次全湧出。本檔是**已知雷區的查表**——盤點（Step 0）對照本表標風險，回歸（Step 4）對照本表重點驗。
> **使用方式：** 不是每條都會命中；盤點時 grep 對應 pattern，命中才列入 plan §6 風險點。
> **時效提醒：** 本表為通用基線，具體版本的官方 release notes / migration guide 仍以 `compat-researcher` 查證為準。

---

## A. Java 8 → 17/21

| # | 變更 | 偵測 pattern | 修法 |
|---|------|------------|------|
| A1 | **強封裝 JDK 內部 API**（JEP 403） | 反射存取 `sun.*` / `jdk.internal.*`；runtime `InaccessibleObjectException` | 移除內部 API 用法；無法移除則加 `--add-opens`（治標） |
| A2 | **JAXB / JAX-WS / activation 移出 JDK** | `import javax.xml.bind` 編譯找不到 | 加 `jakarta.xml.bind-api` + `jaxb-runtime` 依賴 |
| A3 | **Nashorn JS 引擎移除**（JDK 15） | `getEngineByName("nashorn")` 回 null | 改 GraalVM JS 或移除腳本用法 |
| A4 | **CMS GC 移除**（JDK 14） | 啟動參數 `-XX:+UseConcMarkSweepGC` → 啟動失敗 | 改 `-XX:+UseG1GC`（預設）或 ZGC，清啟動腳本/Dockerfile |
| A5 | **其他移除的 GC/JVM 旗標** | `-XX:+UseParNewGC` 等 | 清除過時 JVM 參數 |
| A6 | **`finalize()` 標記移除** | override `finalize()` | 改 `java.lang.ref.Cleaner` / try-with-resources |
| A7 | **Security Manager 標記移除**（JDK 17） | `System.setSecurityManager` / policy 檔 | 移除（多數應用不需） |
| A8 | **強制 UTF-8 預設**（JDK 18+） | 依賴平台預設編碼的 `FileReader` / `new String(bytes)` | 明確指定 `StandardCharsets.UTF_8`（行為差異常見來源） |
| A9 | **日期/Locale 資料源變更**（CLDR） | 日期格式化字串、`String.format` 含 locale | 回歸驗證格式化輸出，必要時鎖 locale |
| A10 | **`Runtime.exec(String)` 解析變更** | 用單字串呼叫外部程序 | 改用 `String[]` 陣列形式 |

**Java 9-21 新特性（升級後*可選*採用，非必須）：** record、sealed、switch pattern matching、text block、`var`。升級期**預設不主動引入**（行為等價優先），除非為修 breaking change 所需。採用範圍見 `coding-style.md`。

---

## B. Spring Boot 2.x → 3.x（框架核心）

| # | 變更 | 偵測 pattern | 修法 |
|---|------|------------|------|
| B1 | **javax → jakarta** | 見 `jakarta-migration.md` | OpenRewrite jakarta recipe |
| B2 | **設定屬性改名/移除** | `application*.yml` 中舊屬性 | `config-migrator` + spring-boot-properties-migrator（見 `boot3-config-migrate`） |
| B3 | **`spring.redis.*` → `spring.data.redis.*`** | grep `spring.redis` | 改前綴 |
| B4 | **`spring.factories` auto-config 棄用** | `META-INF/spring.factories` 含 `EnableAutoConfiguration` | 改 `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` |
| B5 | **trailing slash 匹配預設關閉** | `@RequestMapping` 依賴 `/path` 與 `/path/` 等價 | 顯式設定或調整 client，**易在 runtime 才發現** → 回歸重點 |
| B6 | **`@ConstructorBinding` 移動/收斂** | `@ConstructorBinding` 在 `@ConfigurationProperties` 上 | Boot 3 不需標在 class 上（建構式注入預設） |
| B7 | **Actuator 端點路徑/預設曝露變更** | `/actuator/*` 自訂、`management.endpoints` | 確認端點曝露白名單，health group 行為 |
| B8 | **`server.servlet.*` / multipart 屬性** | 部分屬性改名 | properties-migrator 報告 |
| B9 | **logging date format 預設變更** | log 比對 | 影響 log 解析，回歸記錄 |

---

## C. Spring Security 5 → 6（高風險，行為差異多）

> Security 是升級回歸的**頭號雷區**——錯了會「能啟動但鑑權行為變了」，編譯不會擋。命中即列 plan §6 並排整合測試。

| # | 變更 | 偵測 pattern | 修法 |
|---|------|------------|------|
| C1 | **`WebSecurityConfigurerAdapter` 移除** | extends `WebSecurityConfigurerAdapter` | 改 `SecurityFilterChain` @Bean + `WebSecurityCustomizer` |
| C2 | **`authorizeRequests()` → `authorizeHttpRequests()`** | grep `authorizeRequests` | 改新 API + lambda DSL |
| C3 | **`antMatchers/mvcMatchers` → `requestMatchers`** | grep `antMatchers` | 改 `requestMatchers` |
| C4 | **路徑匹配預設改 `MvcRequestMatcher`** | 路徑授權規則 | 確認 matcher 語義，**易誤放行/誤擋** → 整合測試必驗 |
| C5 | **`@EnableGlobalMethodSecurity` → `@EnableMethodSecurity`** | grep `EnableGlobalMethodSecurity` | 改註解（`prePostEnabled` 預設 true） |
| C6 | **`AuthenticationManager` 組裝方式變更** | 自訂 `configure(AuthenticationManagerBuilder)` | 改 @Bean 暴露 |

---

## D. Hibernate 5 → 6 / JPA（隨 Boot 3）

| # | 變更 | 偵測 pattern | 修法 |
|---|------|------------|------|
| D1 | **方言自動偵測，明確 dialect 多餘/改名** | `hibernate.dialect` 指定舊方言類 | 移除顯式 dialect 或改新類名 |
| D2 | **HQL 行為收嚴** | 自訂 HQL / JPQL（隱式 join、布林比較） | 回歸驗證查詢結果 |
| D3 | **`@Type` / UserType API 變更** | 自訂 `@Type` | 改 Hibernate 6 的 `@JdbcTypeCode` / 新 UserType |
| D4 | **identifier 序列預設變更** | `GenerationType.AUTO` + 序列 | 確認主鍵生成策略未變（**資料正確性** → 必驗） |
| D5 | **`javax.persistence` → `jakarta.persistence`** | 見 jakarta-migration | recipe |

> 本專案若用 **MyBatis / MyBatis-Plus 而非 JPA**，則 C/D 多數不適用；改重點關注 MyBatis starter 對 Boot 3 的 starter artifact 變更（見 `version-matrix §3`）與 mapper 掃描設定。

---

## E. 必須「換庫」而非「升版」的依賴

| 舊庫 | 狀態 | 替代 | 工程量 |
|------|------|------|--------|
| **springfox-swagger 3** | ❌ 不支援 Boot 3 | **springdoc-openapi 2.x** | 註解 `@Api*` → `@Tag/@Operation/@Schema`、設定類重寫——**非機械，需排工時**，列 OQ 確認是否本次處理 |
| **Spring Cloud Sleuth** | 併入 Micrometer Tracing | `micrometer-tracing` + bridge | 觀測性配置重寫 |
| 過舊的 `commons-*` / 反射庫 | 可能不支援 JDK 17 強封裝 | 升版或替換 | 視 A1 命中情況 |

---

## F. 回歸重點清單（給 regression-reviewer）

升級 diff 審查時，下列「編譯過但行為可能變」的點**必查**：

1. **字元編碼**（A8）：檔案讀寫、`getBytes()`、`new String(byte[])` 是否顯式 UTF-8。
2. **trailing slash**（B5）：對外 API 路徑相容性。
3. **Security 路徑匹配**（C4）：授權規則是否語義等價（整合測試打受保護端點）。
4. **時間/序列化**（A9 / Jackson 版本）：日期格式、JSON 欄位順序/格式。
5. **主鍵生成**（D4）：升級後寫入的 ID 策略是否與升級前一致。
6. **NPE / Optional 行為**：Boot 3 部分 API 回傳空集合 vs null 的差異。
