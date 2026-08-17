# Flyway Migration 版本號規範

> **位置：** `Flyway` 模組（**獨立 repo**，非 reactor 建置）
> **目錄：** `Flyway/src/main/resources/db/migrations/general/`
> **注意：** 本專案 Flyway 使用 `org.mariadb.jdbc.Driver` 規避亂碼；schema 限定 `gamedbn`，`clean-disabled: true`。

---

## 1. 新增一律用時間戳版本號（硬規則）

```
V<YYYYMMDDHHMMSS>__<description>.sql
```

**範例：**

```
V20260813131930__add_config.sql
V20260814090512__add_user_money_index.sql
```

**取得版本號：**

```bash
date +%Y%m%d%H%M%S        # 例：20260813131930
```

**格式硬規則：**

- `V` **大寫**（Flyway 區分大小寫；小寫 `v` 不會被辨識為 versioned migration）
- 14 位數字，**不加任何分隔符**（不是 `V2026.08.13.131930`）
- 描述前是**兩個底線** `__`
- 描述用 `snake_case`，**動詞開頭**說明做了什麼（`add_` / `alter_` / `drop_` / `backfill_` / `create_index_`）
- 一個檔案**只做一件事**——回退與追查的粒度就是檔案

---

## 2. 既有版號保留，不得回頭改寫

本專案既有的 migration 使用語意版號（`V1.5.0__user_money_init.sql` 這類）。

- **既有檔一律不動。** 已執行的 migration 一旦修改，Flyway 的 **checksum 驗證會失敗**。
- **不要為了統一格式而批次重新命名既有檔**——那等同修改已執行的 migration。
- 新舊格式**共存是正常的**，不是待清理的技術債。

### 為什麼共存不會亂序

Flyway 逐段做**數值**比較。時間戳是單段 14 位數（`20260813131930`），遠大於任何既有語意版號：

```
V1.4.2  →  1.4.2
V1.5.0  →  1.5.0
V20260813131930  →  20260813131930   ← 必定排在所有既有檔之後
```

所以切換到時間戳之後，**新檔一定接在既有序列後面**，順序有保證。

---

## 3. 為什麼改用時間戳

**核心理由：平行分支不會撞版號。**

語意版號的失敗模式：

```
feature/A  →  取下一號 V1.5.1__add_a.sql
feature/B  →  同時也取 V1.5.1__add_b.sql        ← 兩人都看到最新是 V1.5.0
        ↓ 兩個 MR 都合進 developing
Flyway 遇到重複版本 → 啟動失敗；或先執行者把後者永久卡住
```

**本專案的 Flyway 是獨立 repo**，跨 repo 協調版號更容易漏掉（改 sport 的人不一定記得去看 Flyway repo 的最新版號）。時間戳精確到秒、天然唯一，直接消除這個問題。

次要好處：**版本號自帶時間資訊**，查 schema 演進史時不用去翻另一個 repo 的 git log。

---

## 4. 時區一致性

`date +%Y%m%d%H%M%S` 取的是**執行機器的本機時間**。

- 團隊成員若在不同時區，產生的版本號順序可能與實際建立順序不符（雖然仍然唯一，不會衝突）。
- **本專案統一以本機時間為準**；若日後有跨時區協作，改用 `date -u +%Y%m%d%H%M%S`（UTC）並更新本節。
- 不要手打版本號——**一律用指令產生**，避免打錯位數或抄到別人的。

---

## 5. 與既有規範的關係

| 既有規範 | 是否仍有效 |
|---------|-----------|
| **絕不修改已執行的遷移檔**（Flyway checksum 驗證） | ✅ 完全有效，且時間戳強化了它 |
| 大表修改遷移檔 → 寫**新 `V` 檔案**修正，不改舊檔 | ✅ 不變，新檔用時間戳 |
| 禁止 `DROP TABLE` / `TRUNCATE` / 無 WHERE 的 `DELETE`（除非明確確認） | ✅ 不變 |
| ShardingSphere 主從分片相容性 | ✅ 不變 |
| `clean-disabled: true`、schema 限定 `gamedbn` | ✅ 不變 |

---

## 6. 新增 migration 的流程

```bash
# 1. 產生版本號
VER=$(date +%Y%m%d%H%M%S)

# 2. 在 Flyway repo 建立檔案（描述用 snake_case、動詞開頭）
touch "Flyway/src/main/resources/db/migrations/general/V${VER}__add_config.sql"

# 3. 確認沒有撞到既有檔
ls Flyway/src/main/resources/db/migrations/general/ | grep "^V${VER}"
```

**提交前檢查：**

- [ ] 檔名為 `V` + 14 位數字 + `__` + snake_case 描述 + `.sql`
- [ ] 沒有改動任何既有 migration 檔
- [ ] 一個檔案只做一件事
- [ ] ShardingSphere 主從分片相容性已確認
- [ ] 金額欄位使用 `DECIMAL`
- [ ] 交由 `database-reviewer` 審查

> **Flyway 是獨立 repo。** 涉及 schema 的需求會同時動到 sport 與 Flyway 兩個 repo —— 走 `cross-repo-commit` skill 的 checklist，確認兩邊的 MR 有交叉引用。

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

### 7.7 本專案的落點（注意：Flyway 是獨立 repo）

- 驗證器**放在 `Flyway` repo 內**，掃描 `src/main/resources/db/migrations/general/`。
- `Flyway` 是**非 reactor 的獨立建置**，不會跟著 sport 的 `mvn` 跑 —— 所以：
  - 驗證器必須在 **`Flyway` repo 自己的 CI** 中執行，不能指望 sport 那邊的 pipeline 會擋。
  - sport 側的 MR 若涉及 schema，`cross-repo-commit` 的 checklist 要加一項：**確認 Flyway repo 的驗證器已通過**。
- **這是本專案最容易漏的地方**：改 sport 的人在自己 repo 看到全綠，卻不知道另一個 repo 的 migration 有問題。
- 額外檢查（本專案特有）：
  - ShardingSphere 主從分片相容性
  - 金額欄位為 `DECIMAL`
  - `clean-disabled: true` 未被關閉、schema 限定 `gamedbn`
  - Flyway 使用 `org.mariadb.jdbc.Driver`（規避亂碼），DDL 中的字元集設定需與之相容
