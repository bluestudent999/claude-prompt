# 程式碼風格與規範（Java 21 / Spring Boot 3.5）

---

## 1. 版本基準（本範本覆蓋 plan D18）

| 項目 | 版本 |
|------|------|
| JDK | **Java 21**（LTS） |
| 框架 | **Spring Boot 3.5.x** |
| 對應 Spring Framework | **6.2** |
| Jakarta EE | **10**（`jakarta.*` 命名空間） |
| 資料庫 | PostgreSQL |

**硬規則：**

- `pom.xml` 一律以 **Boot 3.5.x BOM** 管版本，**不要逐一手動指定第三方版本**。
- **不要抄 Spring Boot 4 / Spring Framework 7 的寫法**（plan D18 與大量新文章是以 Boot 4 為前提寫的）。判準：Boot 4 移除或改名的 API 在 3.5 仍然存在；Boot 4 才有的 API 在這裡**不可用**。
- 不確定某個 API 在 3.5 是否存在 → **查 Boot 3.5 文件或直接編譯驗證**，不要憑印象。
- 想升版 → 獨立 TASK，不是順手改版本號。

---

## 2. 相依紀律（D10）

**禁止引入**：

| 套件 | 為什麼不用 |
|------|-----------|
| **web3j** | 只需要少數幾個 JSON-RPC 方法，引入整個 web3j 是過度相依；且 TRON 用不到（走 REST） |
| **任何 MQ**（Kafka / RabbitMQ / …） | `events` 表即 Outbox，下游 Pull（D16）。沒有需要 MQ 的場景 |
| **Quartz** | 用 Spring 內建排程即可（`@Scheduled` / `TaskScheduler`） |

新增任何第三方相依前：**先問「沒有它會怎樣」**，答不出具體損失就不要加。要加必須在 plan §2 明列並說明理由。

JSON-RPC 直接用 Spring 內建的 HTTP client 打即可。

---

## 3. 命名與格式

- 縮排 4 空白，遵循專案 `.editorconfig`。
- 類別 / 介面 / Record：`PascalCase`（`ChainScanner`、`TenantResolver`、`EventEnvelope`）
- 方法 / 變數 / 參數：`camelCase`
- 常數：`UPPER_SNAKE_CASE`
- package：小寫，不帶底線或連字號
- **角色後綴一致**：`XxxScanner` / `XxxAdapter` / `XxxResolver` / `XxxRepository`

---

## 4. Java 21 語法實踐

- **不可變優先**：值物件、DTO、事件封包一律用 **`record`**；實體成員優先 `final`。
- **`sealed` interface + `record`** 表達封閉的變體（例如鏈別 Adapter 的結果型別），搭配 **switch 模式匹配**取代 if-else 鏈。
- `var` 用於型別顯而易見的區域變數。
- **金額一律 `BigDecimal`**，禁止 `double` / `float`。鏈上原始值用 `BigInteger`（`amount_raw`），換算後才是 `BigDecimal`。
- **不用虛擬執行緒**（plan D18 已評估：平均 0.9 RPS、3 條掃描執行緒，規模與虛擬執行緒的適用場景差好幾個量級）。要用先回報。

---

## 5. 語言與 Log

- **註解與 Javadoc：繁體中文**（技術術語保留英文：RPC、Reorg、Outbox、cursor、tenant）。
- **Log 訊息：英文**，便於蒐集與解析。
- Log 等級：
  - `info`：關鍵狀態轉換（掃描高度推進、租戶開通、Failover 切換）
  - `warn`：可自我修復／降級（RPC 逾時後重試、切備援 provider）
  - `error`：阻礙當前處理的錯誤，帶 context（chain、blockNumber、tenantId）
  - `debug`：開發調試，正式環境不輸出冗餘
- **結構化欄位**：涉及租戶的 log **必須帶 `tenantId`**，否則事故時無法分租戶追查。

**Log 脫敏（硬規則）：** `subscribers.api_key`（明碼）、RPC provider 的 API Key、任何憑證**嚴禁**出現在 log 或例外訊息。資料庫只存 `api_key_hash`。

---

## 6. 例外處理

- 領域錯誤以專案自訂例外表達，**禁止**裸 `catch (Exception e)` 後吞掉。
- **可預期的失敗必須留痕且可觀測**：RPC 逾時、429、provider 不可達、Receipt 回傳 `null`、區塊資料格式異常 —— 都要有 metric 與 log，不得靜默略過。
- **事務邊界（I1）**：一個區塊的處理是單一事務。不要在事務內做 RPC 呼叫（會把外部延遲綁進事務、放大鎖持有時間）。**先取資料、再開事務寫入。**

---

## 7. 大檔案讀取策略（Context 硬規則）

| 對象 | 行數 | 策略 |
|------|-----:|------|
| `plan/*-implementation-steps.md` | 1499 | ❌ 禁 full read |
| `plan/*-development-plan.md` | 1081 | ❌ 禁 full read |
| `plan/*-bigpicture.md` | 579 | ❌ 禁 full read（但「取代對照表」必讀） |
| 程式碼檔 > 300 行 | — | ❌ 禁 full read |

**流程：**

```bash
grep -nE "^#{1,3} " plan/2026-08-17-crypto-node-implementation-steps.md   # 標題索引
grep -n "^### S12" -A 40 plan/2026-08-17-crypto-node-implementation-steps.md  # 只讀該步驟
```

程式碼同理：先 `grep -n "class \|void \|public "` 建索引，再 `Read(offset, limit)`。
**例外**：`pom.xml`、`application.yml`、Flyway migration、測試 fixture 不受此限。

---

## 8. 結構性設計 vs 投機性複雜度

> 前面幾節管「**怎麼寫**」，這節管「**為什麼要有這個抽象**」。
>
> ⚠️ **這節不是「少寫抽象」。** 本專案導入六角架構 + Modulith 的立案理由，就是**避免再次陷入框架升級地獄**（D19）。該有的結構**一個都不能少——少了才是缺陷**。

### 判準只有一句話

> **這個抽象隔離的是哪一個「已知的變動源」？**

- **答得出來** → **結構性設計，必須做**。「現在只有一個實作」不構成質疑理由。
- **答不出來，只能說「以後可能會…」** → 投機性複雜度，不做。

### 結構性設計（必做，缺了就是缺陷）

| 抽象 | 隔離的變動源 | 憑什麼說它「已知」 |
|------|------------|------------------|
| **Outbound Port** | Spring Boot 版本、JPA↔JDBC↔JOOQ、HTTP client、DB | 本專案**已經為 Boot 版本吵過一輪**（`locked-decisions.md` §3）。它一定會再發生 |
| **Domain 零框架** | 整個框架世代 | 同上。這是全案價值最高的一道牆 |
| **鏈別 Adapter** | EVM×2 + TRON | **已知三個實作**，不是猜的 |
| **Modulith 模組 + `internal` 封裝** | 變更半徑；D11 已言明日後可能拆微服務 | 拆分需求是明說過的 |
| **事務邊界在 Application** | 持久化技術 | JPA→JDBC 是明確選項 |
| 不變量的落地（單一事務、Advisory Lock、UNIQUE 約束、租戶過濾） | — | **這是規格，不是抽象**，沒有討論空間 |

> 這些的成本**現在付**，價值在**下一次升級**兌現。用「現在只有一個實作」否決它們，等於用今天的視角砍掉明天的保險——而這個專案已經證明那個「明天」會來。

### 投機性複雜度（不做）

| 想做的事 | 變動源存在嗎 |
|---------|------------|
| Port **之上**再造 `PortFactory` / 註冊表 / 設定驅動的實作選擇 | ❌ Port 已經是接縫了，再加一層沒有隔離任何**新的**東西 |
| 為兩個 URL 輪替的 Failover 造 provider 外掛框架 | ❌ 真正的變動源是「換一家 provider」，那改 Port 實作就好 |
| 為單一常數造設定載入器 + schema 驗證 + 環境覆寫 | ❌ 現在沒有人要在不改 code 的情況下切它 |
| 為 WebSocket / Webhook / `reorged` 留接縫或 enum 值 | ❌ **這些已被 D2 / D16 / D17 移除**。留了就會有人來填 |
| 為「以後可能有多種投遞方式」造 `DeliveryChannel` 註冊機制 | ❌ D16 已定 Pull-only |
| 為步驟沒要求的功能先鋪路 | ❌ plan §2 的檔案清單就是範圍上限 |

### 實作量的節制（與「要不要抽象」無關）

抽象該有的都要有，但**單一方法／類別內部的體積仍要節制**：

1. 「這 200 行能不能是 50 行？」——能 → 重寫。
2. 「資深工程師會不會說**這個方法**太複雜？」——會 → 簡化。

> 這兩題問的是**一個類別內部的複雜度**，不是「要不要有這個類別」。**不要拿它們去質疑分層與 Ports。**

### 兩個方向都會出事

| 失敗模式 | 症狀 | 代價 |
|---------|------|------|
| **結構性設計不足** | Domain import 了 Spring、Domain 物件當 JPA Entity 用、Application 直接碰 `JdbcTemplate` | **升級地獄** —— 本專案要避免的就是這個 |
| **投機性複雜度過多** | 穿過三層 Factory 才找得到真正做事的類別 | 沒人看得懂，接手成本暴增 |

**兩者都是缺陷。不要為了躲開其中一個而掉進另一個。**

> **歸屬**：結構性設計的落實與違規由 `arch-guard` 判定（`architecture.md`）；投機性複雜度與實作量由 `code-reviewer` 判定。
> **`code-reviewer` 不得以「只有一個實作」為由否決 Port、分層或模組邊界** —— 那些是 `arch-guard` 的管轄範圍，且是規格。
