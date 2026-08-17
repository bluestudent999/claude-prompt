# Flyway Migration 版本號規範

> **層級歸屬：** Flyway 屬 **Infrastructure**（`architecture.md` §1）。migration 是持久化細節，Domain 與 Application 對它一無所知。
> **相關步驟：** `S02 DB Schema 與 Flyway Migration`；不變量 **I4 / I5 / I9** 的 UNIQUE 約束由 migration 落地。

---

## 1. 一律用時間戳版本號（硬規則）

```
V<YYYYMMDDHHMMSS>__<description>.sql
```

**範例：**

```
V20260813131930__add_config.sql
V20260814090512__create_events_table.sql
V20260814091003__add_watched_addresses_unique_chain_address.sql
```

**取得版本號：**

```bash
date +%Y%m%d%H%M%S        # 例：20260813131930
```

**格式硬規則：**

- `V` **大寫**（Flyway 區分大小寫；小寫 `v` 不會被辨識為 versioned migration）
- 14 位數字，**不加任何分隔符**（不是 `V2026_08_13_131930`）
- 描述前是**兩個底線** `__`
- 描述用 `snake_case`，**動詞開頭**說明做了什麼（`create_` / `add_` / `alter_` / `drop_` / `backfill_`）
- 一個檔案**只做一件事**——回退與追查的粒度就是檔案

---

## 2. 為什麼用時間戳

**核心理由：平行分支不會撞版號。**

流水號 / 語意版號的失敗模式：

```
feature/S14-block-write   →  取下一號 V5__add_a.sql
feature/S16-pull-api      →  同時也取 V5__add_b.sql     ← 兩人都看到最新是 V4
        ↓ 兩個分支都 merge
Flyway 遇到重複版本 → 啟動失敗；或先套用者把後者永久卡住
```

本專案採 **D9 縱向切片**，同一階段內多個步驟可能平行推進（S02 建表、後續步驟補索引），撞版號的機率不低。時間戳精確到秒、天然唯一，直接消除這個問題。

次要好處：**版本號自帶時間資訊**，查 schema 演進史時不用翻 git log。

---

## 3. 既有版號保留，不得回頭改寫

本專案是全新開發，理論上從第一個 migration 就用時間戳。但若已存在其他格式的檔案：

- **既有檔一律不動。** 已套用的 migration 一旦修改，Flyway 的 **checksum 驗證會失敗**，服務起不來。
- **不要為了統一格式而批次重新命名**——那等同修改已套用的 migration。
- 新舊共存不會亂序：Flyway 逐段做**數值**比較，時間戳（14 位數）遠大於任何流水號或語意版號。

> `build-error-resolver` 遇到「Flyway migration 失敗」時的既定處置就是：**不要為了讓它過而改既有 migration，改用新版號**。本規範與之一致。

---

## 4. 時區一致性

`date +%Y%m%d%H%M%S` 取的是**執行機器的本機時間**。

- 團隊成員若在不同時區，產生的版本號順序可能與實際建立順序不符（雖然仍然唯一，不會衝突）。
- **本專案統一以本機時間為準**；若日後有跨時區協作，改用 `date -u +%Y%m%d%H%M%S`（UTC）並更新本節。
- 不要手打版本號——**一律用指令產生**，避免打錯位數。

---

## 5. 本專案特有：migration 是不變量的落地處

以下不變量的強制機制**寫在 migration 裡**，不是寫在程式碼裡。改動它們等於改動正確性規格：

| 不變量 | migration 中的機制 |
|--------|------------------|
| **I4** | `UNIQUE (chain, tx_hash, log_index)` on `chain_transactions` |
| **I5** | `UNIQUE (chain, tx_hash, log_index, event_type)` on `events` |
| **I9** | `UNIQUE (chain, address)` on `watched_addresses`（**整個路由模型的地基**） |

**硬規則：**

- **禁止在 migration 中放寬或移除這些約束。** 要改 → 停手，回報使用者（`locked-decisions.md` 的翻案流程）。
- 新增涉及租戶的表或欄位時，`tenant_id` 的 NOT NULL 與外鍵約束必須一併加上（I8/I9）。
- `events.id` 是下游游標依據（`event-contract.md`）——**序號的產生方式不得變更**，那會破壞所有下游的游標。

---

## 6. 新增 migration 的流程

```bash
# 1. 產生版本號
VER=$(date +%Y%m%d%H%M%S)

# 2. 建立檔案（描述用 snake_case、動詞開頭）
touch "src/main/resources/db/migration/V${VER}__add_config.sql"

# 3. 確認沒有撞到既有檔
ls src/main/resources/db/migration/ | grep "^V${VER}"
```

**提交前檢查：**

- [ ] 檔名為 `V` + 14 位數字 + `__` + snake_case 描述 + `.sql`
- [ ] 沒有改動任何既有 migration 檔
- [ ] 一個檔案只做一件事
- [ ] 涉及 I4 / I5 / I9 的 UNIQUE 約束未被放寬或移除
- [ ] 涉及租戶的表已有 `tenant_id` 約束
- [ ] 金額欄位型別正確（`NUMERIC`，對應程式端 `BigDecimal`）
- [ ] 在乾淨資料庫（Testcontainers）驗證過可一次套用
- [ ] 動到 schema → 跑 `/invariant-check` 確認相關不變量的測試仍通過

---

## 7. 版本號驗證器（必須實作，不是可選）

> **為什麼一定要有：** 版本號寫錯的失敗模式**全部都是靜默的** —— 小寫 `v` 的檔案 Flyway 直接當作不存在、13 位數的打錯時間戳會被當成別的東西、既有檔被改到要等下次部署才炸。這些**靠 code review 抓不到**（沒人會去數位數），只能靠機器。

### 7.1 分工：格式自己驗，執行狀態用 Flyway 原生

| 面向 | 用什麼 | 理由 |
|------|--------|------|
| **檔名格式、版本號、內容紅線** | **自己寫的驗證器** | Flyway 不管檔名以外的慣例，也不管 snake_case 或危險 SQL |
| **漏執行 / checksum 不符 / 有記錄無檔案** | **Flyway 原生指令**（`flyway:validate`、`flyway:info`） | 這是 Flyway 的本職，**不要自己去比對 `flyway_schema_history`** —— 重造輪子且容易寫錯 |

> `flyway:info` 會列出 `Pending` 狀態的 migration（＝漏執行）；`flyway:validate` 會抓 checksum 不符與缺檔。把它們接進 CI 即可，**不需要自己實作這一段**。

### 7.2 靜態檢查清單（驗證器必須全部涵蓋）

每一條都要能獨立回報，訊息要指出**檔名 + 為什麼 + 怎麼修**。

| # | 檢查 | 漏掉會怎樣 |
|---|------|-----------|
| 1 | `V` **大寫** | 小寫 `v` 不被 Flyway 辨識為 versioned migration，**這個檔案永遠不會執行**，而且沒有任何錯誤訊息 |
| 2 | 版本號恰為 **14 位純數字** | 位數錯的檔案會被當成別的版本語意，排序位置無法預期 |
| 3 | 14 位數是**合法的 `YYYYMMDDHHMMSS`** | `V20261399999999` 這種能過位數檢查但不是日期 |
| 4 | 時間戳**不在未來** | 手打錯年份（`2062`）或時區設錯 → 這個檔會永遠排在所有後續檔之後 |
| 5 | 分隔為**兩個底線** `__` | 單底線不符 Flyway 慣例，描述會被吃進版本號 |
| 6 | 描述為 **snake_case**（小寫英數與底線，不可開頭/結尾/連續底線） | 命名不一致，日後難以掃描與統計 |
| 7 | **版本號不重複** | Flyway 遇到重複版本**直接啟動失敗** |
| 8 | 新時間戳檔的版本號**大於既有最大版本** | 排序異常 —— 新檔會排在既有檔之前 |
| 9 | **既有 migration 未被修改／刪除／改名**（用 `git diff --name-status HEAD` 比對） | 已套用的檔改了，Flyway **checksum 驗證失敗，服務起不來** |
| 10 | 內容非空（去掉註解後仍有 SQL） | 空的 migration 會被記錄為已套用，之後補內容也不會再執行 |
| 11 | 危險操作標記：`DROP TABLE` / `DROP DATABASE` / `TRUNCATE` / 無 `WHERE` 的 `DELETE` | 需人工明確確認，**不得由 Agent 自動放行** |

### 7.3 一個實作陷阱（實測踩過，務必處理）

**13 位或 15 位的打錯時間戳，很容易被誤判為「既有的流水號 / 語意版號」而靜默放行。**

因為驗證器通常會這樣分類：「14 位數字 → 新格式」「其他純數字 → 既有格式，合法保留」。而 `V2026081409000`（13 位）剛好落在第二類。

**正確判別：**

- 單段純數字、長度 **8 位以上但不等於 14** → **幾乎確定是打錯的時間戳**，必須報錯
- 單段純數字、長度 ≤ 7（`V1`、`V12`）→ 既有流水號，放行
- 多段（`V1.5.0`、`V1_0_3`）→ 既有語意版號，放行

漏了這條，驗證器就抓不到最常見的打字錯誤 —— 而那正是它存在的理由。

### 7.4 掛在哪裡（越早擋越好）

| 時機 | 手段 |
|------|------|
| 開發者本機 | pre-commit hook 或一行指令，**秒級完成** |
| **CI（必要）** | 與既有靜態檢查同一個 stage；**失敗即擋合入** |
| 部署前 | `flyway:validate` + `flyway:info` 確認無 Pending |

**不需要資料庫連線的檢查（#1~#11）一律進 CI**，這樣不必為了跑檢查而配置 DB 憑證。

### 7.5 驗證器自己也要被驗證

**永遠通過的檢查器沒有價值。** 實作完成後必須做**故障注入**，逐條確認真的會報錯：

```
小寫 v · 13 位數 · 未來時間 · 非法日期 · 非 snake_case
版本號重複 · 順序異常 · 改既有檔 · 空檔 · DROP TABLE
```

把這批故障樣本留成測試 fixture，之後改動驗證器時可回歸。

### 7.6 不要做的事

| ❌ | 為什麼 |
|---|--------|
| 驗證器自動「修正」檔名 | 重新命名既有檔 = 修改已套用的 migration = checksum 失敗 |
| 自己讀 `flyway_schema_history` 比對漏執行 | Flyway 的 `info` / `validate` 已經做了，重造容易寫錯 |
| 把危險 SQL 檢查做成自動放行的白名單 | 那類操作就是要人看過 |
| 為了讓 CI 過而放寬檢查 | 放寬的那條，就是下次出事的那條 |

### 7.7 本專案的落點

- **列為 `S02 DB Schema 與 Flyway Migration` 的交付項之一** —— 與 schema 同一個步驟完成，不是後補。
- 實作方式建議與 `ArchitectureTests` 同層級：一個進 CI 的測試，失敗即紅燈。理由一致 —— **邊界靠測試守，不靠自律**。
- **額外檢查（本專案特有，對應不變量）**：
  - migration 中**不得** `DROP` 或放寬 `chain_transactions` 的 `UNIQUE (chain, tx_hash, log_index)`（**I4**）
  - 不得 `DROP` 或放寬 `events` 的 `UNIQUE (chain, tx_hash, log_index, event_type)`（**I5**）
  - 不得 `DROP` 或放寬 `watched_addresses` 的 `UNIQUE (chain, address)`（**I9**，整個路由模型的地基）
  - 新增涉及租戶的表／欄位時，`tenant_id` 的 `NOT NULL` 與外鍵約束必須一併存在（**I8 / I9**）
  - 不得變更 `events.id` 的序號產生方式（那是下游游標依據，見 `event-contract.md`）
- 這些約束一旦被放寬，`invariant-guard` 在程式碼層面**看不出來** —— 它們只存在於 migration 裡，所以必須由這個驗證器守。
