# javax → jakarta Namespace 遷移規範

> Spring Boot 3 / Jakarta EE 9+ 最大的 breaking change：企業 API 的 package 從 `javax.*` 改為 `jakarta.*`。
> **這是純機械改動，必須走 OpenRewrite recipe 自動完成（見 `openrewrite.md`），禁止逐檔手刻。** 本檔規範「哪些要改、哪些不能改、如何守門」。

---

## 1. 核心原則：不是全部 javax 都要改

最大的踩坑點：**`javax.*` 分兩類**，混為一談會把 Java SE 內建 API 也錯改成不存在的 `jakarta.*`，導致編譯爆炸。

### ✅ 要遷移（Jakarta EE，由應用伺服器/EE 規範提供）

| 舊 `javax.*` | 新 `jakarta.*` | 典型用途 |
|--------------|----------------|---------|
| `javax.servlet.*` | `jakarta.servlet.*` | HttpServletRequest、Filter、Servlet |
| `javax.persistence.*` | `jakarta.persistence.*` | JPA `@Entity` `@Id` `@Column` |
| `javax.validation.*` | `jakarta.validation.*` | `@NotNull` `@Valid` Bean Validation |
| `javax.annotation.*`（部分） | `jakarta.annotation.*` | `@PostConstruct` `@PreDestroy` `@Resource` |
| `javax.transaction.*` | `jakarta.transaction.*` | `@Transactional`(JTA) |
| `javax.ws.rs.*` | `jakarta.ws.rs.*` | JAX-RS |
| `javax.xml.bind.*` | `jakarta.xml.bind.*` | JAXB（需另加依賴，見 version-matrix §4） |
| `javax.mail.*` | `jakarta.mail.*` | JavaMail |
| `javax.el.*` | `jakarta.el.*` | Expression Language |
| `javax.websocket.*` | `jakarta.websocket.*` | WebSocket |
| `javax.jms.*` | `jakarta.jms.*` | JMS |

### ❌ 不能改（Java SE 內建，永遠是 `javax.*`）— 白名單

下列是 **JDK 自帶**，**永遠保持 `javax.*`**，改成 `jakarta` 會編譯失敗：

```
javax.crypto.*          加解密（Cipher、SecretKey）
javax.net.*             SSLSocket、SocketFactory
javax.net.ssl.*         SSLContext、TrustManager
javax.sql.*             DataSource、RowSet
javax.naming.*          JNDI
javax.management.*      JMX（MBean）
javax.security.auth.*   Subject、login（注意：auth.* 是 SE，非 EE）
javax.sound.*           音訊
javax.imageio.*         圖片 IO
javax.swing.* / javax.accessibility.*   GUI
javax.xml.parsers.*     SAX/DOM parser（注意：xml.bind 才是 EE，xml.parsers 是 SE）
javax.xml.transform.* / javax.xml.xpath.* / javax.xml.namespace.*   SE
javax.lang.model.*      annotation processing
javax.tools.*           JavaCompiler
javax.script.*          ScriptEngine
```

> **判別口訣：** 與「Web 容器 / JPA / EE 規範」有關 → 遷 jakarta；與「加密 / 網路 / JDBC / JNDI / JMX / XML 解析 / GUI / 編譯器」有關 → 保留 javax。**OpenRewrite 的 jakarta recipe 已內建此白名單**，這也是必須走 recipe、不手刻的關鍵理由。

---

## 2. 遷移執行（自動優先）

```bash
# 切目標 JDK
export JAVA_HOME="$JAVA_HOME_TARGET"

# OpenRewrite jakarta 遷移（已含白名單，不會誤改 Java SE 的 javax）
# 通常包含在 spring.boot3.UpgradeSpringBoot_3_x 內，亦可單獨跑：
mvn -U org.openrewrite.maven:rewrite-maven-plugin:dryRun \
  -Drewrite.activeRecipes=org.openrewrite.java.migrate.jakarta.JakartaEE10 \
  -Drewrite.exportDatatables=true
# 審 diff（patch 檔在 target/rewrite/rewrite.patch）後再 run
```

遷移同時要在 pom 替換 **依賴座標**（不只 import）：

| 舊 artifact | 新 artifact |
|-------------|-------------|
| `javax.validation:validation-api` | `jakarta.validation:jakarta.validation-api`（多由 Boot starter 帶入） |
| `javax.servlet:javax.servlet-api` | `jakarta.servlet:jakarta.servlet-api` |
| `javax.annotation:javax.annotation-api` | `jakarta.annotation:jakarta.annotation-api` |
| `javax.xml.bind:jaxb-api` | `jakarta.xml.bind:jakarta.xml.bind-api` + `org.glassfish.jaxb:jaxb-runtime` |

> 多數由 `spring-boot-starter-*` 傳遞帶入正確的 jakarta 版本，**優先移除手動宣告的 javax artifact，讓 starter 管理**。

---

## 3. 容易遺漏的非 import 出沒點

OpenRewrite 主攻 `.java` import，下列要**人工 grep 補掃**：

```bash
# persistence.xml / orm.xml 的 schema namespace
grep -rn "javax" --include=*.xml src/main/resources

# Bean Validation 在 properties / messages 的 constraint
# spring.factories / META-INF（自訂 auto-config）
grep -rn "javax\." --include=*.factories --include=*.properties

# 字串形式的全限定名（反射 Class.forName、@ComponentScan basePackages、AspectJ pointcut）
grep -rn '"javax\.\(servlet\|persistence\|validation\|annotation\)' --include=*.java

# web.xml（若仍有）、logback 的 servlet appender
grep -rn "javax.servlet" --include=*.xml
```

---

## 4. jakarta 單向性守門（hook）

進入 Boot 3 階段（Phase B 完成）後，**禁止任何新增的非白名單 `javax.*` import**。

- `settings.json` 的 `PreToolUse(Edit|Write)` 掛 `hooks/block-new-javax-import.sh`。
- **啟用方式：** 把該 hook 內 `GUARD_ENABLED=0` 改為 `1`（Phase A/baseline 期間維持 0，避免擋到尚未遷移的存量檔案）。
- hook 比對白名單（本檔 §1），只攔截 Jakarta EE 類的 `javax.*` 新增。

---

## 5. 驗收

```bash
# 遷移後，非白名單 javax 殘留應為 0
grep -rn "import javax\." --include=*.java src/main/java \
  | grep -vE "javax\.(crypto|net|sql|naming|management|security\.auth|sound|imageio|swing|accessibility|xml\.(parsers|transform|xpath|namespace)|lang\.model|tools|script)"
# 預期：無輸出（有輸出代表漏遷或誤判，逐一確認）
```

寫入 plan §5 回歸計畫：jakarta 遷移後**必跑**涉及 Servlet Filter、JPA 實體載入、Bean Validation 的整合測試（這三類最容易因 namespace 漏遷在 runtime 才爆）。
