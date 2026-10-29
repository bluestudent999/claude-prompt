# Flyway Migration 版本號規範

> **位置：** `cp-flyway/` 模組（**同 repo、但不在根 pom 的 reactor `<modules>`**，有自己的 pom 與 parent，獨立建置）
> **目錄：** `cp-flyway/src/main/resources/db/migrations/general/`
> **設定（`cp-flyway/src/main/resources/application.yml`）：** `org.mariadb.jdbc.Driver`（規避亂碼）、schema `gamedbn`、`clean-disabled: true`、`out-of-order: true`、`baseline-on-migrate: true`、`validate-on-migrate: true`
> **另一條 SQL 軌：** `zz_document/script/changelog/` —— 見 §6「兩條 SQL 軌」，**是否同步寫不得自行判定**。

---

## 1. 新增一律用時間戳版本號（硬規則）

```
V<YYYYMMDDHHMMSS>__[<單號>_]<description>.sql
```

**範例：**

```
V20261015103000__PRJ-1299_add_xxx.sql      # 帶單號（lion 既有慣例，建議）
V20261015104512__add_user_money_index.sql  # 無單號
```

**取得版本號：**

```bash
date +%Y%m%d%H%M%S        # 例：20261015103000
```

**格式硬規則：**

- `V` **大寫**（Flyway 區分大小寫；小寫 `v` 不會被辨識為 versioned migration）
- 14 位數字，**不加任何分隔符**（不是 `V2026.10.15.103000`）
- 版本號後是**兩個底線** `__`
- 單號（選填）接在 `__` 後、照原樣大寫（`PRJ-1299`），再接一個底線
- 描述用 `snake_case`，**動詞開頭**說明做了什麼（`add_` / `alter_` / `drop_` / `backfill_` / `create_index_`）
- 一個檔案**只做一件事**——回退與追查的粒度就是檔案

---

## 2. 既有版號保留，不得回頭改寫

本專案既有的 migration 使用語意版號 + 單號（`V1.1.0` … `V1.8.9__PRJ-1299_rech_cfg_split_uw_wallet.sql` 這類）。

- **既有檔一律不動。** 已執行的 migration 修改內容，**不會在已執行過的環境重跑**。
- **lion 特有的靜默失效：** `cp-flyway` 的 `FlywayConfig` 在 `migrate()` 前先呼叫 `flyway.repair()` —— 改過的已執行檔**不會**讓服務起不來，而是 checksum 被默默改寫成新值，**新內容在舊環境永遠不會執行**，各環境 schema 從此不一致且沒有任何錯誤訊息。所以這條紅線在 lion 比一般專案更不能靠「部署會炸」來發現。
- **不要為了統一格式而批次重新命名既有檔**——那等同修改已執行的 migration。
- 新舊格式**共存是正常的**，不是待清理的技術債。

### 為什麼共存不會亂序

Flyway 逐段做**數值**比較。時間戳是單段 14 位數（`20261015103000`），遠大於任何既有語意版號：

```
V1.8.8  →  1.8.8
V1.8.9  →  1.8.9
V20261015103000  →  20261015103000   ← 必定排在所有既有語意版號之後
```

所以切換到時間戳之後，**新檔一定接在既有序列後面**。至於時間戳檔彼此之間：平行分支後合入的檔可能比已執行的檔「舊」，因 `out-of-order: true`，Flyway 仍會補執行它，不會略過。

---

## 3. 為什麼改用時間戳

**核心理由：平行分支不會撞版號。**

語意版號的失敗模式：

```
feature/A  →  取下一號 V1.8.10__add_a.sql
feature/B  →  同時也取 V1.8.10__add_b.sql       ← 兩人都看到最新是 V1.8.9
        ↓ 兩個 MR 都合進 developing
Flyway 遇到重複版本 → 啟動失敗；或先執行者把後者永久卡住
```

**lion 實證：** `V1.8.0` 曾被三支不同功能各取一次（`redenp_rain_add_nation_currency`、`rebate_template_classification`、`negative_user_money`）；且已執行的 `V1.8.0__rebate_template_classification.sql` 事後又被修改過。

cp-flyway 雖然**和程式碼同 repo**，但 `feature/*`、`hotfix/*`、`release/<YYYYMMDD>` 各自從不同時間點切出，大家看到的「最新版號」不同，跨分支照樣撞號。時間戳精確到秒、天然唯一，直接消除這個問題。

次要好處：**版本號自帶時間資訊**，查 schema 演進史時不用翻 git log。

---

## 4. 時區一致性

`date +%Y%m%d%H%M%S` 取的是**執行機器的本機時間**。

- 團隊成員若在不同時區，產生的版本號順序可能與實際建立順序不符（雖然仍然唯一，不會衝突；`out-of-order: true` 也會補執行）。
- **本專案統一以本機時間為準**；若日後有跨時區協作，改用 `date -u +%Y%m%d%H%M%S`（UTC）並更新本節。
- 不要手打版本號——**一律用指令產生**，避免打錯位數或抄到別人的。

---

## 5. 與既有規範的關係

| 既有規範 | 是否仍有效 |
|---------|-----------|
| **絕不修改已執行的遷移檔** | ✅ 完全有效；lion 因 `repair()` 會靜默吞掉，更要嚴守 |
| 已執行的 migration 有誤 → 寫**新 `V` 檔案**修正，不改舊檔 | ✅ 不變，新檔用時間戳 |
| 禁止 `DROP TABLE` / `TRUNCATE` / 無 WHERE 的 `DELETE`（除非明確確認） | ✅ 不變 |
| ShardingSphere 4.0.1 主從分片相容性 | ✅ 不變 |
| `clean-disabled: true`、schema 限定 `gamedbn` | ✅ 不變，不得關閉或改動 |

---

## 6. 兩條 SQL 軌（lion 獨有，易錯）

| 軌 | 位置 | 角色 |
|---|---|---|
| **Flyway** | `cp-flyway/src/main/resources/db/migrations/general/V*.sql` | 由 cp-flyway 啟動時自動執行 |
| **changelog** | `zz_document/script/changelog/<YYYY>/<YYYYMMDD>_<單號>_<desc>.sql` | **手動執行 / DBA 上版對照用** |

**既有做法（觀察到的，不是成文規則）：**

- 同一張單常**兩邊都有檔**（例：PRJ-1299 有 `V1.8.9__PRJ-1299_rech_cfg_split_uw_wallet.sql` 與 `changelog/2026/20261006_PRJ-1299_rech_cfg_split_uw_wallet.sql`）
- 也有**只進 changelog** 的（曾有 commit 把 flyway 檔搬到 changelog）
- 兩邊都有時，changelog **檔首註記**對照關係，慣例三件事：
  1. 「對應 cp-flyway migration：`V<版號>`（本檔為手動執行 / DBA 上版對照用，內容須與 flyway 一致）」
  2. 前提（需先執行哪支 SQL）
  3. 能否重跑（例：只能執行一次、重跑會失敗的原因）

**硬規則：何時兩邊都寫、何時只寫一邊，範本不得自行判定。**

1. 先查**同模組近期同類單**的做法（`git log --oneline -- cp-flyway/src/main/resources/db/migrations/general/ zz_document/script/changelog/`，看同 domain / 同類 DDL 怎麼放）
2. 仍判不出 → **問使用者**（列 OQ：只寫 flyway / 只寫 changelog / 兩邊都寫，各自的代價）
3. 兩邊都寫時，**內容必須一致**，changelog 檔首依上面三件事註記；任何一邊改了，另一邊同步改

---

## 7. 新增 migration 的流程

```bash
# 1. 產生版本號
VER=$(date +%Y%m%d%H%M%S)

# 2. 建立檔案（描述用 snake_case、動詞開頭；單號選填）
touch "cp-flyway/src/main/resources/db/migrations/general/V${VER}__PRJ-1299_add_xxx.sql"

# 3. 確認沒有撞到既有檔
ls cp-flyway/src/main/resources/db/migrations/general/ | grep "^V${VER}"

# 4. 依 §6 判定 changelog 是否同步
```

**交付前檢查：**

- [ ] 檔名為 `V` + 14 位數字 + `__` + （選填 `<單號>_`）+ snake_case 描述 + `.sql`
- [ ] 沒有改動任何既有 migration 檔
- [ ] 一個檔案只做一件事
- [ ] §6 兩條 SQL 軌已依規則判定（不是自己猜的）；兩邊都寫時內容一致、changelog 檔首有對照註記
- [ ] ShardingSphere 主從分片相容性已確認
- [ ] 金額欄位使用 `DECIMAL`
- [ ] 帶 platformId 的表，新索引 / 查詢條件有考慮 platformId 維度（`rules/platform-isolation.md`）
- [ ] 交由 `database-reviewer` 審查

> **cp-flyway 不在 reactor**：根目錄 `mvn -pl <module>` 與 Jenkins（`mvn clean -Dmaven.test.skip=true install`）都不會建置它，**CI 綠完全不代表 migration 沒問題**。

---

## 8. 版本號驗證器（必須實作，不是可選）

> **為什麼一定要有：** 版本號寫錯的失敗模式**全部都是靜默的** —— 小寫 `v` 的檔案 Flyway 直接當作不存在、13 位數的打錯時間戳會被當成別的東西、既有檔被改到會被 `repair()` 默默吞掉。這些**靠 code review 抓不到**（沒人會去數位數），只能靠機器。

### 8.1 分工：格式自己驗，執行狀態用 Flyway 原生

| 面向 | 用什麼 | 理由 |
|------|--------|------|
| **檔名格式、版本號、內容紅線** | **自己寫的驗證器** | Flyway 不管檔名以外的慣例，也不管 snake_case 或危險 SQL |
| **漏執行 / checksum 不符 / 有記錄無檔案** | **Flyway 原生指令**（`flyway:validate`、`flyway:info`） | 這是 Flyway 的本職，**不要自己去比對 `flyway_schema_history`** —— 重造輪子且容易寫錯 |

> `flyway:info` 會列出 `Pending` 狀態的 migration（＝漏執行）；`flyway:validate` 會抓 checksum 不符與缺檔。注意 lion 啟動時會先 `repair()`，**啟動成功不等於 validate 通過** —— 要另外跑 `flyway:validate`。

### 8.2 靜態檢查清單（驗證器必須全部涵蓋）

每一條都要能獨立回報，訊息要指出**檔名 + 為什麼 + 怎麼修**。

| # | 檢查 | 漏掉會怎樣 |
|---|------|-----------|
| 1 | `V` **大寫** | 小寫 `v` 不被 Flyway 辨識為 versioned migration，**這個檔案永遠不會執行**，而且沒有任何錯誤訊息 |
| 2 | 版本號恰為 **14 位純數字** | 位數錯的檔案會被當成別的版本語意，排序位置無法預期 |
| 3 | 14 位數是**合法的 `YYYYMMDDHHMMSS`** | `V20261399999999` 這種能過位數檢查但不是日期 |
| 4 | 時間戳**不在未來** | 手打錯年份（`2062`）或時區設錯 → 這個檔會永遠排在所有後續檔之後 |
| 5 | 分隔為**兩個底線** `__` | 單底線不符 Flyway 慣例，描述會被吃進版本號 |
| 6 | 描述為「選填單號 + snake_case」：`^([A-Z][A-Z0-9]*-[0-9]+_)?[a-z0-9]+(_[a-z0-9]+)*$` | 命名不一致，日後難以掃描與統計；單號以外出現大寫或 `-` 即報錯 |
| 7 | **版本號不重複** | Flyway 遇到重複版本**直接啟動失敗** |
| 8 | 新時間戳檔的版本號**大於所有既有語意版號**（`V1.x.y`） | 排序異常 —— 新檔會排在既有檔之前。時間戳檔彼此不要求遞增（`out-of-order: true` 會補執行） |
| 9 | **既有 migration 未被修改／刪除／改名**（用 `git diff --name-status <base>` 比對） | 已套用的檔改了，lion 的 `repair()` 會**默默改寫 checksum**，新內容在舊環境永遠不執行 |
| 10 | 內容非空（去掉註解後仍有 SQL） | 空的 migration 會被記錄為已套用，之後補內容也不會再執行 |
| 11 | 危險操作標記：`DROP TABLE` / `DROP DATABASE` / `TRUNCATE` / 無 `WHERE` 的 `DELETE` | 需人工明確確認，**不得由 Agent 自動放行** |

### 8.3 一個實作陷阱（實測踩過，務必處理）

**13 位或 15 位的打錯時間戳，很容易被誤判為「既有的流水號 / 語意版號」而靜默放行。**

因為驗證器通常會這樣分類：「14 位數字 → 新格式」「其他純數字 → 既有格式，合法保留」。而 `V2026101510300`（13 位）剛好落在第二類。

**正確判別：**

- 單段純數字、長度 **8 位以上但不等於 14** → **幾乎確定是打錯的時間戳**，必須報錯
- 單段純數字、長度 ≤ 7（`V1`、`V12`）→ 既有流水號，放行
- 多段（`V1.8.9`、`V1_0_3`）→ 既有語意版號，放行

漏了這條，驗證器就抓不到最常見的打字錯誤 —— 而那正是它存在的理由。

### 8.4 掛在哪裡（越早擋越好）

| 時機 | 手段 |
|------|------|
| 開發者本機 | pre-commit hook 或一行指令，**秒級完成** |
| **CI（必要）** | 與既有靜態檢查同一個 stage；**失敗即擋合入** |
| 部署前 | `flyway:validate` + `flyway:info` 確認無 Pending、無 checksum 不符 |

**不需要資料庫連線的檢查（#1~#11）一律進 CI**，這樣不必為了跑檢查而配置 DB 憑證。

### 8.5 驗證器自己也要被驗證

**永遠通過的檢查器沒有價值。** 實作完成後必須做**故障注入**，逐條確認真的會報錯：

```
小寫 v · 13 位數 · 未來時間 · 非法日期 · 非 snake_case · 單號格式錯
版本號重複 · 小於既有語意版號 · 改既有檔 · 空檔 · DROP TABLE
```

把這批故障樣本留成測試 fixture，之後改動驗證器時可回歸。

### 8.6 不要做的事

| ❌ | 為什麼 |
|---|--------|
| 驗證器自動「修正」檔名 | 重新命名既有檔 = 修改已套用的 migration |
| 自己讀 `flyway_schema_history` 比對漏執行 | Flyway 的 `info` / `validate` 已經做了，重造容易寫錯 |
| 把危險 SQL 檢查做成自動放行的白名單 | 那類操作就是要人看過 |
| 為了讓 CI 過而放寬檢查 | 放寬的那條，就是下次出事的那條 |
| 把 `FlywayConfig` 的 `repair()` 當成「改舊檔也沒關係」的保護 | 它只是讓錯誤變成靜默的 schema 漂移 |

### 8.7 本專案的落點（注意：cp-flyway 不在 reactor）

- 驗證器掃描 `cp-flyway/src/main/resources/db/migrations/general/`；目前 repo **尚未有**驗證器。
- cp-flyway 不在根 pom `<modules>`，Jenkins 也不建置它 —— 所以：
  - 驗證器**不能指望現有 Jenkins pipeline 會擋**；要掛 pre-commit 還是新增 Jenkins stage 是**團隊決定**，Claude 不自行改 `Jenkinsfile` 或 `.git/hooks/`，要做先列 OQ 問使用者。
  - 在驗證器上線前，新增 migration 時**逐條手動對照 §8.2**，結果寫進 MR 測試計畫。
- 額外檢查（本專案特有）：
  - ShardingSphere 主從分片相容性
  - 金額欄位為 `DECIMAL`
  - `clean-disabled: true` 未被關閉、schema 限定 `gamedbn`
  - Flyway 使用 `org.mariadb.jdbc.Driver`（規避亂碼），DDL 中的字元集設定需與之相容
  - §6 兩條 SQL 軌：changelog 有對應檔時，內容與 flyway 一致
