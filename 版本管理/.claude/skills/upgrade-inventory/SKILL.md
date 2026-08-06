---
name: upgrade-inventory
description: 升級前盤點整個升級面 — 掃描 javax 使用面（EE 需遷 vs SE 白名單）、棄用/移除 API、依賴版本現況、Boot 3 設定屬性、不相容庫。直接跳躍升級開工第一步，產出 upgrade/inventory.md。
---

# 升級面盤點

> 直接跳躍升級前必須知道「會炸哪裡」。本 skill 系統化盤點整個升級面，產出 `upgrade/inventory.md` 供 `upgrade-planner` 規劃。

## 啟用時機

- 升級工單開工第一步（Step 0）。
- 多模組大盤點建議改走 `upgrade-sweep` workflow（平行掃描，省主 agent context）。

## 盤點六面（逐項 grep，結果寫 inventory.md）

### 1. javax 使用面（分類 — 最關鍵）

```bash
# 全部 javax import
grep -rn "import javax\." --include=*.java src/main/java | wc -l

# 分出「Java SE 白名單」（不遷，見 rules/jakarta-migration.md §1）
grep -rn "import javax\." --include=*.java src/main/java \
  | grep -E "javax\.(crypto|net|sql|naming|management|security\.auth|sound|imageio|swing|accessibility|xml\.(parsers|transform|xpath|namespace)|lang\.model|tools|script)"

# 剩下的就是「Jakarta EE 需遷移」面（servlet/persistence/validation/annotation...）
```
→ inventory 記：EE 需遷數量（按 servlet/persistence/validation 分類）、SE 白名單數量。

### 2. 棄用 / 移除 API

```bash
grep -rn "WebSecurityConfigurerAdapter\|authorizeRequests\|antMatchers\|EnableGlobalMethodSecurity" --include=*.java   # Security 5→6
grep -rn "javax.xml.bind\|@XmlRootElement" --include=*.java                                                            # JAXB（JDK 移除）
grep -rn "finalize()\|setSecurityManager\|getEngineByName" --include=*.java                                            # Java 移除項
```
→ inventory 記命中項，對應 `breaking-changes.md` 編號。

### 3. 依賴版本現況

```bash
mvn dependency:tree 2>&1 | grep -E "spring-boot|spring-cloud|mybatis|hibernate|swagger|springfox|springdoc|shardingsphere|lombok|flyway|validator"
```
→ inventory 記高風險依賴（`version-matrix.md §3`）的現況版本。

### 4. 設定屬性面

```bash
grep -rn "spring.redis\|max-http-header-size\|pathmatch.matching-strategy" --include=*.yml --include=*.properties
grep -rln "EnableAutoConfiguration" --include=*.factories
```
→ inventory 記需遷移的設定屬性與 spring.factories 出沒點。

### 5. 不相容「換庫」庫

```bash
grep -rn "springfox\|io.swagger.annotations\|@Api\b" --include=*.java --include=*.xml
grep -rn "spring-cloud-starter-sleuth" --include=*.xml
```
→ inventory 標出需「換庫而非升版」的項（springfox→springdoc 等），標為 OQ 候選。

### 6. JVM / GC 參數

```bash
grep -rn "UseConcMarkSweepGC\|UseParNewGC\|CMSInitiatingOccupancyFraction" . --include=*.sh --include=Dockerfile --include=*.yml
```
→ inventory 記已移除的 GC 旗標（`breaking-changes.md A4`）。

## inventory.md 模板

```markdown
# 升級面盤點 — <模組> （日期）

## 來源版本現況（effective-pom 證據）
- Java: 8 / Spring Boot: 2.7.x / Spring Cloud: 2021.0.x

## 1. javax 使用面
- EE 需遷：servlet=X, persistence=Y, validation=Z（合計 N 檔）
- SE 白名單（不遷）：crypto=A, net=B …

## 2. 棄用/移除 API（對應 breaking-changes 編號）
- [C1] WebSecurityConfigurerAdapter × M 處 → U1 高風險
- [A2] javax.xml.bind × K 處

## 3. 高風險依賴現況
| 依賴 | 現況 | 需動作 |

## 4. 設定屬性
- spring.redis.* × N → spring.data.redis.*

## 5. 換庫項（OQ 候選）
- springfox 3.0 → springdoc 2.x（需 user 確認本次是否處理）

## 6. JVM/GC
- CMS GC 旗標 × P 處

## 風險層初判
- U1（命中 Security 5→6 + 換庫）
```

## 完成後

把 inventory.md 交給 `upgrade-planner` 產出分階段計畫。盤點漏項會導致 plan 不完整 → 寧可多掃一輪。
