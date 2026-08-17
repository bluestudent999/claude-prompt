# 架構規範：六角架構 + Spring Modulith

> **這條規範的目的不是「架構好看」，是讓框架升級的衝擊被限縮在最外層。**
> 本專案已經因為 Boot 版本問題吵過一輪（`locked-decisions.md` §3）。這套架構的價值就是：下次再吵，**Domain 一行都不用改**。

---

## 1. 三層與依賴方向（不可逆）

```
[ Infrastructure / Adapter ]  ← Spring Boot、JPA/JDBC、HTTP client、Web、排程
            │ 依賴
            ▼
[ Application ]               ← Use Case、Ports（inbound/outbound）、事務邊界
            │ 依賴
            ▼
[ Domain ]                    ← 純 Java。零框架。
```

**依賴只能由外往內。** Domain 不知道 Application 存在，Application 不知道 Infrastructure 存在。

### Domain 層：零框架依賴（硬規則）

**只允許**：`record`、`enum`、`sealed interface`、value object、純函式、`java.*` 標準庫（`BigDecimal`、`BigInteger`、`Optional`、`time`）。

**嚴格禁止**任何 import：

| 禁止 | 說明 |
|------|------|
| `org.springframework.*` | 含 `@Component`、`@Service`、`@Transactional`、`ApplicationEvent`、**Modulith 的 `@ApplicationModule*` 也不行** |
| `jakarta.persistence.*` | `@Entity`、`@Column`、`@Id` —— Domain 物件不是 JPA Entity |
| `jakarta.validation.*` | 驗證規則用純 Java 表達，不用註解 |
| `com.fasterxml.jackson.*` | 序列化是 Adapter 的事 |
| `lombok.*` | 用 `record` 就不需要 |
| 任何 I/O、HTTP、DB、時鐘、亂數 | 走 Port 注入 |

> **判定三問**（任一為「是」→ 必須走 Port，不得留在 Domain）：
> ① 它做 I/O 或碰外部資源嗎？② 它會隨環境（本機／CI／正式）換實作嗎？③ 它引入非確定性（網路、時間、亂數）嗎？

**Domain 該裝什麼**：本專案的 Domain 是**不變量的家**——確認深度計算、地址正規化規則、冪等鍵組成、金額精度換算、事件型別與狀態流轉、租戶歸屬規則。這些是公司的核心資產，跟 Spring 幾版無關。

### Application 層：Use Case 與 Ports

- **Inbound Port**：Use Case 介面（`ScanBlockRangeUseCase`、`PullEventsUseCase`）。由 Adapter（Controller、排程）呼叫。
- **Outbound Port**：Application **宣告需要什麼能力**，由 Infrastructure 實作。
  - `BlockRepositoryPort`、`EventRepositoryPort`、`WatchlistPort`、`ChainRpcPort`、`AdvisoryLockPort`、`ClockPort`
- **事務邊界在這一層**（`@Transactional` 標在 Application 的實作類別上，不在 Domain）。
- 允許 `org.springframework.transaction.*` 與 DI 註解；**不允許** JPA、HTTP、具體 driver。

### Infrastructure / Adapter：框架污染隔離區

所有髒活都在這裡：`@RestController`、Spring Data Repository、JSON-RPC HTTP client、Flyway、`@Scheduled`、Security Filter、Micrometer。

- **實作 Outbound Ports**，並負責 **Entity ↔ Domain Model 映射**（兩者是不同的型別，不要共用一個類別）。
- 這一層是**唯一**會因為 Boot 3.5 → 4.x 而需要改動的地方。

---

## 2. Ports 是規格，不是可選的抽象

**每一個通往外部世界的方向都必須有 Port，即使目前只有一個實作。** 這不是「預留擴充」，而是**依賴反轉本身**——它是這套架構能兌現「升級只改 Adapter」的唯一機制。

> **不要用「現在只有一個實作」質疑 Port。** 判準不是實作數量，而是**它隔離的變動源是否已知**（`coding-style.md` §8）。
> Boot 版本、JPA↔JDBC、HTTP client、DB —— 這些變動源都**已知會發生**，本專案已經為其中一項吵過一輪決策。

| 情況 | 判定 |
|------|------|
| Application 宣告 `EventRepositoryPort`，Infrastructure 只有一個 JDBC 實作 | ✅ **必做**。缺了才是缺陷 |
| 鏈別 Adapter 抽象（EVM×2 + TRON，確定三個實作） | ✅ **必做** |
| Domain / Application 直接 import Spring Data `Repository` | ❌ 違反依賴方向 |
| Application 直接碰外部而**沒有** Port | ❌ **結構性設計不足** —— 這是本專案要避免的失敗模式 |
| 為 Port 再造一層 `PortFactory` / 註冊表 / 設定驅動的實作選擇 | ❌ 投機性複雜度（Port 已是接縫，再疊沒有隔離新東西） |
| 為只有兩個 URL 輪替的 Failover 造 provider 外掛框架 | ❌ 投機性複雜度（Failover 策略屬 Domain 純邏輯，provider 呼叫屬 Adapter） |

**分界線一句話：** **通往外部世界的每個方向都該有一個 Port；Port 之上不要再疊東西。**

---

## 3. Spring Modulith 模組切分

### 提議的模組（⏳ 待使用者確認，不要當定案實作）

plan 沒有定義模組邊界。以下是依「不變量的歸屬」推導的提議：

| 模組 | 職責 | 主要守護的不變量 |
|------|------|----------------|
| `chain` | 鏈別抽象、區塊／交易／Log 領域模型、確認深度計算 | I7 |
| `scanning` | 掃描區間計算、高度推進、Advisory Lock | I2、I3 |
| `attribution` | 地址正規化、watchlist、address → tenant 歸屬 | I9 |
| `event` | 事件產生、冪等鍵、`events` 表寫入 | I1、I4、I5、I6 |
| `delivery` | 拉取 API、游標、認證與租戶過濾 | I8、I10 |
| `tenant` | 租戶與訂閱者管理 | I9 |
| `reconciliation` | 每日對帳、重掃稽核 | — |
| `admin` | 維運介面 | — |

> **這是提議不是規格。** S01（專案骨架）實作前，planner **必須把模組切分列為 OQ 請使用者確認**，確認後回寫 plan 並更新本節。

### 封裝規則

- 模組根 package 為 API 面：只放要給外部用的型別（Use Case 介面、事件 record、公開的 value object）。
- 模組內部一律放 `internal` 子 package，且**類別宣告為 package-private** —— 外部模組物理上 import 不到。
- **模組間禁止直接注入彼此的 Service 或 Repository。**

---

## 4. 模組間通訊：事件解耦（但要小心 I1）

### ⚠ 最重要的一條：`@ApplicationModuleListener` 不能用在區塊寫入路徑

`@ApplicationModuleListener` 的語意是 **`@Async` + `@TransactionalEventListener(AFTER_COMMIT)` + `@Transactional(REQUIRES_NEW)`**。

也就是說：**它在原事務 commit 之後、以新事務執行。**

而 **I1 要求**：`chain_blocks` + `chain_transactions` + `events` + `chain_sync_status` 四項寫入**全成功或全失敗，在單一事務內**。

**結論（硬規則）：**

| 路徑 | 通訊方式 |
|------|---------|
| 區塊處理的四項寫入（I1 涵蓋範圍） | **同一事務、同步、透過 Outbound Port 呼叫**。❌ **不得**用 Modulith 事件跨模組拆開 |
| 可最終一致的後續動作（metrics、稽核紀錄、觸發對帳、告警） | ✅ 用 `@ApplicationModuleListener` |

> **這是把六角架構套進本專案時最容易踩的坑。** 「模組間一律用事件解耦」是通則，但 I1 是本專案的正確性定義——**不變量優先於架構通則**。
> 若模組切分導致 I1 的四項寫入落在不同模組，那是**模組切分錯了**，應把它們收攏到同一個模組（提議中的 `event` 模組），而不是用事件把事務拆開。

### 事件契約

- 跨模組事件是**純 Java `record`**，放在發布模組的 API 面（根 package），不放 `internal`。
- 事件 record **不得**攜帶 JPA Entity、Spring 型別或可變集合。

### ⚠ 兩個 Outbox，不要搞混

本專案會同時存在兩套 Outbox，**用途完全不同，不得合併**：

| | Modulith Event Publication Registry | `events` 表 |
|---|---|---|
| 用途 | **模組間內部事件**的最終一致性（Modulith 內建） | **對外業務事件**，下游拉取（D16 Pull-only） |
| 消費者 | 本進程內的其他模組 | 外部支付系統（不同 repo） |
| 契約 | 內部，可自由演進 | **對外契約，不可片面變更**（`event-contract.md`） |
| 誰管 | Spring Modulith | 我們自己 |

看到「既然 Modulith 有 Outbox，`events` 表是不是多餘的」這種想法 → **停手**。`events` 表是對外契約的載體，`sequence` 是下游游標的依據，兩者不可替代。

---

## 5. 邊界驗證（自動化，非人工自律）

```java
class ArchitectureTests {

    ApplicationModules modules = ApplicationModules.of(CryptoNodeApplication.class);

    @Test
    void verifyModularity() {
        modules.verify();   // 循環依賴、非法存取 internal
    }

    @Test
    void writeDocumentation() {
        new Documenter(modules).writeDocumentation();   // 產出模組圖，PR 可視化
    }
}
```

**Modulith 的 `verify()` 管模組邊界，但管不到分層。** 分層需要額外的 ArchUnit 規則：

```java
@Test
void domain_should_not_depend_on_framework() {
    noClasses().that().resideInAPackage("..domain..")
        .should().dependOnClassesThat().resideInAnyPackage(
            "org.springframework..", "jakarta.persistence..",
            "jakarta.validation..", "com.fasterxml.jackson..", "lombok..")
        .check(classes);
}

@Test
void application_should_not_depend_on_infrastructure() {
    noClasses().that().resideInAPackage("..application..")
        .should().dependOnClassesThat().resideInAPackage("..infrastructure..")
        .check(classes);
}
```

**這兩類測試進 CI，違規在編譯／測試期就被擋下**，不靠 code review 自律。

---

## 6. 相依與版本

- **Spring Modulith 是使用者核可新增的相依**（`locked-decisions.md` §3 有記錄）。D10 的「最小相依」原則仍然有效——Modulith 是例外，不是開了引入相依的口。
- Modulith 版本**由其 BOM 對齊 Boot 3.5.x**。實作 S01 時**查證當下與 Boot 3.5 相容的 Modulith 版本**，不要憑印象填版本號。
- `spring-modulith-starter-jpa` / `-jdbc`（Event Publication Registry 的持久化）依實際資料存取技術選擇，S01 決定並記錄理由。

---

## 7. 升級時的預期衝擊面（這套架構要兌現的承諾）

| 異動 | 應該只改到 |
|------|-----------|
| Boot 3.5 → 4.x | Infrastructure Adapter（+ 建置檔） |
| JPA → JDBC／JOOQ | 實作 Outbound Port 的那幾個類別 |
| 換 HTTP client | `ChainRpcPort` 的實作 |
| 換 DB | Adapter + migration |
| 日後拆微服務 | 把模組物理抽離，事件改走網路 |

> **驗收方式：** 任何一次升級或技術替換，若 diff 觸及 `..domain..`，就代表這套架構沒有兌現承諾——**那是架構 bug，要回頭修邊界**，不是「這次比較特殊」。

---

## 8. 常見誤判

| 想做的事 | 為什麼不行 |
|---------|-----------|
| Domain 物件直接當 JPA Entity（省一次映射） | 一旦如此，Domain 就被 `jakarta.persistence` 綁死，整套架構的價值歸零 |
| Domain 用 Lombok `@Data` | 用 `record`。Lombok 是編譯期相依，且 `@Data` 破壞不可變性 |
| Application 直接注入 `JdbcTemplate` | 那是 Infrastructure。宣告 Port |
| 模組 A 注入模組 B 的 Service | 用事件；若需要同步回傳值，代表模組切分需重新檢視，列 OQ |
| 為了讓 `modules.verify()` 過而把類別搬到 API 面 | 那是繞過檢查。正確做法是修依賴方向 |
| 把 `events` 表換成 Modulith 的 Event Registry | 兩者用途不同，見 §4 |
| 用 Modulith 事件串接區塊寫入的四個步驟 | 破壞 I1，見 §4 |
