---
name: arch-check
description: 跑架構守門檢查——Modulith 模組邊界驗證、六角架構分層依賴、Domain 純度掃描、I1 與事件的衝突偵測。提交前、新增模組或類別後、引入相依後使用。
---

# arch-check — 架構邊界檢查

**用法：** `/arch-check`（提交前必跑，若本次新增類別、動 package 結構、跨模組呼叫或引入相依）

這套架構的承諾是「Boot 升級時 Domain 零變更」。**每次放行一個違規，就是把承諾兌現的機率往下砍一刀。**

---

## Step 1 · 自動驗證（主要防線）

```bash
./mvnw -q test -Dtest='ArchitectureTests' 2>&1 | tail -40
```

應涵蓋：

| 測試 | 管什麼 |
|------|--------|
| `modules.verify()` | Modulith：模組循環依賴、非法存取他人 `internal` |
| `domain_should_not_depend_on_framework` | ArchUnit：Domain 零框架 |
| `application_should_not_depend_on_infrastructure` | ArchUnit：依賴方向 |

> **`modules.verify()` 管模組邊界，管不到分層。** 兩者都要有，缺一不可。

---

## Step 2 · 人工補掃（自動測試抓不到的）

```bash
cd <專案根>

echo "=== Domain 純度（應為空）==="
grep -rn "^import \(org\.springframework\|jakarta\.persistence\|jakarta\.validation\|com\.fasterxml\|lombok\)" \
  --include="*.java" src/main/java/**/domain/ || echo "  ✓ 乾淨"

echo "=== Domain 的非確定性來源（應為空）==="
grep -rn "Instant\.now()\|System\.currentTimeMillis\|new Random\|Math\.random" \
  --include="*.java" src/main/java/**/domain/ || echo "  ✓ 乾淨"

echo "=== Application → Infrastructure（應為空）==="
grep -rn "^import .*\.infrastructure\." --include="*.java" src/main/java/**/application/ || echo "  ✓ 乾淨"

echo "=== 跨模組 internal 存取 ==="
grep -rn "^import .*\.internal\." --include="*.java" src/main/java/

echo "=== 事件與事務（檢查是否落在 I1 範圍）==="
grep -rn "@ApplicationModuleListener\|@TransactionalEventListener\|@Async" --include="*.java" src/main/java/

echo "=== @Transactional 的位置（應只在 application）==="
grep -rn "@Transactional" --include="*.java" src/main/java/ | grep -vE "/application/"

echo "=== 相依（不應出現 web3j / MQ / Quartz）==="
grep -nE "web3j|quartz|kafka|rabbitmq|activemq" pom.xml || echo "  ✓ 乾淨"

echo "=== Modulith 版本是否由 BOM 管理 ==="
grep -n -A3 "spring-modulith" pom.xml | head -20
```

---

## Step 3 · ⚠ I1 與事件的衝突偵測（本專案特有）

`@ApplicationModuleListener` = `@Async` + `@TransactionalEventListener(AFTER_COMMIT)` + `@Transactional(REQUIRES_NEW)` —— **在原事務 commit 之後、以新事務執行**。

而 **I1** 要求區塊處理的四項寫入在**單一事務**內。

```bash
echo "=== 區塊寫入路徑是否被事件拆開 ==="
grep -rn "chain_blocks\|chain_transactions\|chain_sync_status" --include="*.java" src/main/java/ | \
  awk -F: '{print $1}' | sort -u | while read f; do
    grep -l "@ApplicationModuleListener\|AFTER_COMMIT\|@Async" "$f" 2>/dev/null && echo "  ⚠️ $f 同時觸及區塊寫入與非同步事件"
  done
```

**判定：**

| 發現 | 處置 |
|------|------|
| I1 的四項寫入落在同一模組、同一事務、同步呼叫 | ✅ 正確 |
| 四項寫入被 `@ApplicationModuleListener` 拆開 | ❌ **CRITICAL** — 違反 I1 |
| 四項寫入落在不同模組 | ❌ **模組切分錯了**。收攏到同一模組（提議中的 `event`），不是改用事件把事務拆開 |
| 事件用在可最終一致的動作（metrics、稽核、觸發對帳、告警） | ✅ 正確用法 |

---

## Step 4 · 產出報告

```markdown
## arch-check 結果（<日期>）

### 自動驗證
- `modules.verify()`：PASS / FAIL（<訊息>）
- Domain 純度測試：PASS / FAIL / ⚠️ 未建立
- 依賴方向測試：PASS / FAIL / ⚠️ 未建立

### 人工掃描
| 項目 | 結果 |
|------|------|
| Domain 框架 import | 0 / <n> 處 |
| Domain 非確定性來源 | 0 / <n> 處 |
| Application → Infrastructure | 0 / <n> 處 |
| 跨模組 internal 存取 | 0 / <n> 處 |
| `@Transactional` 位置正確 | 是 / 否 |
| 禁用相依 | 無 / <清單> |

### I1 × 事件
- 區塊寫入路徑是否同事務同步：是 / **否（CRITICAL）**
- 非同步事件使用位置：<清單，逐一判定是否落在 I1 範圍>

### 結論
- 本次引入的違規：<n> 項  ← **必須修掉才能提交**
- 既有違規：<n> 項        ← Domain 純度類建議立即另開步驟；其餘記錄即可
```

---

## 判定紀律

| ❌ | ✅ |
|---|---|
| 「只有這一個地方讓 Domain import Spring」 | 例外一開就回不去。後續程式碼會照抄 |
| 為了讓 `modules.verify()` 過而把類別搬到 API 面 | 那是繞過檢查。正確做法是修依賴方向 |
| 把「只有一個實作的 Port」判為多餘 | 判準是**隔離的變動源是否已知**，不是實作數量（`coding-style.md` §8） |
| 只抓「多餘的抽象」，不抓「該有卻沒有」 | 結構性設計**不足**才是升級地獄的成因，兩個方向都要查 |
| 既有違規一律當本次的錯 | 區分「本次引入」與「既有」；只有前者擋提交 |
| Domain 純度的既有違規也套「一次修一項」緩衝 | 它會被照抄擴散，建議立即修 |
| 架構測試還沒建就先跳過檢查 | 改用人工 grep 全掃，並要求優先補測試 |

---

## 架構測試尚未建立時（S01 之前）

人工 grep 是**唯一防線**，必須全掃而非抽樣。同時在報告的 Next actions 明確要求：

> `ArchitectureTests`（`modules.verify()` + 兩條 ArchUnit 分層規則）應在 **S01 專案骨架**就進 CI。
> **架構測試不是後補項** —— 沒有它，邊界只靠人自律，撐不過三個月。
