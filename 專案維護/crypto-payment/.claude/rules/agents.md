# Agent 協作編排（crypto-payment）

> Agent 定義位於 `.claude/agents/`，此 rule 規範使用原則與路由。

---

## 編排模型

```
使用者需求
   │
   ▼ 越界先攔（見 CLAUDE.md 跨 prompt-setup 路由）
[domain 定位] — 查 rules/modules.md，鎖定最窄 domain + 預判 L 層
   │
   ▼
[spec-review] — 業務 gate（規格未確認不動工）
   │
   ▼ CONFIRM
[planner] — 拆步驟 + 每步標 L1/L2/L3
   │
   ▼ 有 L1 時
[tdd-guide] — L1 關鍵路徑整合測試
   │
   ▼
[code-reviewer] + [java-reviewer]
   │
   ▼ 視內容並行
[security-reviewer] [business-reviewer] [database-reviewer]
   │
   ▼
提交 / merge to developing_test
```

### 何時繞過

- **Bug 修復（非業務邏輯）**：省 `spec-review`，直接 `planner` → `tdd-guide`
- **純重構**：省 `spec-review`/`tdd-guide`，用 `refactor-cleaner` → `code-reviewer`
- **單行改動（typo / config）**：省整個流程，改完請 `code-reviewer` 輕掃

---

## 需求入口：先定位 domain（硬規則）

1. **越界先攔**：若需求本質是「新需求規劃 / 規格 / 任務拆解」或「Java/Boot 版本升級遷移」或「cx-sports-v2 體育主業務」→ **不屬本範本職責**，提示切換對應 prompt-setup（見 CLAUDE.md 路由表），不臆測代答。
2. **查 `rules/modules.md`**：比對「業務關鍵字」鎖定最窄 domain 列；「對應目錄」= grep 範圍上限，禁止擴大。
3. **立即預判 L 層**：從該列讀出 L1/L2/L3 輸出給使用者確認，寫入 spec §風險評估。planner 只確認不得降級，有升級理由在 plan §5 說明。
4. **索引找不到** → 委派 Explore agent（quick）搜 `com/lion/crypto/service/*`，回最可能 domain + ≤5 檔路徑，再補 modules.md。

---

## Agent 清單與路由

| Agent | 職責 | 觸發 |
|-------|------|------|
| **code-reviewer** | 程式碼品質、結構、可維護性 | 寫完程式碼後第一輪 |
| **java-reviewer** | Spring Boot 3 分層 / 事務 / DI 深度審查 | Java 變更（Controller/Service/Repository） |
| **business-reviewer** | 業務正確性（入款/歸集/狀態機/冪等/金額） | 涉及金額 / 入帳 / 歸集 / 狀態機 |
| **security-reviewer** | 私鑰/AES-GCM/HMAC/platform_id/驗簽/輸入 | 涉及私鑰、驗簽、回調、使用者輸入、對外 API |
| **database-reviewer** | SQL / ShardingSphere 5.4 / Flyway | 寫 SQL、Flyway migration、Schema |
| **build-error-resolver** | Java/Maven 建置錯誤 | `mvn compile` 失敗 |
| **refactor-cleaner** | 死碼清理、重複消除 | 移除未使用碼、合併重複邏輯 |
| **tdd-guide** | 測試驅動（JUnit 5） | 新功能、Bug 修正（測試先行） |
| **planner** | 實作計畫拆解 | 已定方案，要拆步驟 |
| **architect** | 架構設計、技術權衡 | 評估技術方案、選型 |

---

## 依 L 層決定 reviewer 數

| L 層 | 範圍 | reviewer 配置 |
|------|------|---------------|
| **L3** | config / VO / 純 wiring / typo | **code-reviewer × 1**（輕掃） |
| **L2** | 一般 service / controller / 跨模組 | **code-reviewer** + 擇一領域 reviewer |
| **L1** | 金額/入帳/歸集/狀態機/併發/冪等/**私鑰**/**AES-GCM**/**HMAC**/**platform_id**/webhook/鏈對接 | **code-reviewer** + **java-reviewer** + 必要領域（business/security/database），**平行啟動** |

### 依情境追加（與 L 層疊加）

| 情境 | 追加 reviewer |
|------|---------------|
| 金額 / 入帳 / 歸集 / 訂單 / 狀態機 | **business-reviewer** |
| 私鑰 / AES-GCM / 驗簽 / 回調 / 使用者輸入 / platform_id | **security-reviewer** |
| SQL / ShardingSphere / Flyway / Schema | **database-reviewer** |
| `mvn compile` 失敗 | **build-error-resolver** |

### 判定原則

- **先看 L 層再看情境**；有疑問升級不降級（L2/L3 邊界模糊取 L2）
- 同一 PR 派超過 3 個 reviewer 時，重評估是否拆 MR
- **派遣前讀 spec/plan §0 `l_tier` 欄位**（單一事實來源；缺欄視同 L1）；L1 只派 code-reviewer → 必補 business+security+database

---

## 平行執行

獨立 agent 呼叫**務必**在同一則訊息中平行啟動，不要循序等待。

## 主 agent context 保護（委派 Explore agent）

跨多檔搜尋 / 預期 > 10 行結果 / 「是否已有類似實作」/「資料流追蹤」→ 委派 **Explore agent**（獨立 context，只回結論）。明確檔案 + 明確字串的精準 grep 才主 agent 自做。

- **thoroughness**：quick（1-2 次）/ medium（3-5 次）/ thorough（全面）
- **回傳**：只回結論（不回原始 grep 行）；字數上限 quick ≤300 / medium ≤800 / thorough ≤1500

---

## 子 Agent 規範傳遞

子 Agent **不繼承父 context**、**不自動讀 skills**（rules 會自動注入）。**派子 Agent 必須自包含**：spec/plan 路徑 + diff 片段 + 規範摘要 + Harness Output Contract 提醒。**Briefing ≤ 500 字**。

### 平行 reviewer 分工聚焦

| reviewer | 聚焦 | 忽略 |
|---------|------|------|
| `code-reviewer` | 結構 / 命名 / 死碼 / 重複 | 業務細節 |
| `java-reviewer` | 分層 / Spring 模式 / 事務 / DI | 業務規則正確性 |
| `business-reviewer` | 入款/歸集/狀態機/金額/冪等 | 語法風格 |
| `security-reviewer` | 私鑰/AES-GCM/HMAC/platform_id/輸入/脫敏 | 結構分層 |
| `database-reviewer` | SQL 參數化 / ShardingSphere / Flyway | Controller / VO |

### 規範摘要對照（按任務挑抄進 briefing）

| 任務類型 | 必抄條文 |
|---------|----------|
| 金額 / 入帳 | `BigDecimal` + `RoundingMode.DOWN`、`SELECT FOR UPDATE` + 事務、txHash/orderNo/nonce 冪等 |
| 私鑰 / 加密 | AES-GCM 加密落庫、禁明文 / 禁 log、加密類改動須確認 |
| 驗簽 / webhook | SignFilter HMAC、timestamp+nonce、5 分鐘 replay window、不繞過 filter chain |
| 多租戶 | 所有查詢過濾 `platform_id`，跨平台存取 = critical |
| SQL / DB | ShardingSphere 5.4 自動路由、`#{param}` 參數化、Flyway 只增不改 |

### reviewer briefing 模板

```
# 任務
Review <feature>，聚焦 <分工項目>，產出 Harness Output Contract。

# 變更範圍（精準行號 + diff）
<file>:<L_start>-<L_end>
```diff
<git diff 片段>
```

# 相關規範（從 rules 抄必要條文）
- <條文>

# 輸出格式
最後一段必須是 Harness Output Contract：Status / Summary / Counts / Next actions / Artifacts
```

---

## Harness Output Contract（reviewer / resolver / 執行類 agent 必須遵守）

最後一段固定輸出：

```
---
**Status:** approve | warning | block
**Summary:** {一句話 ≤ 80 字}
**Counts:** CRITICAL=N HIGH=N MEDIUM=N LOW=N
**Next actions:**
- [ ] {動作 — 誰改哪個檔做什麼}
**Artifacts:**
- {file}:{line} — {issue} | fix: {fix}
```

**Status 判定：** CRITICAL > 0 → `block`；HIGH > 0 → `warning`；其餘 → `approve`。小寫英文，不翻譯，不用 emoji。

| Agent 類型 | 版本 |
|-----------|------|
| Reviewer（code/java/security/database/business） | 完整版（5 欄位） |
| build-error-resolver | Resolver 變體（`fixed:` / `remaining:`） |
| tdd-guide / refactor-cleaner | 輕量版（Status / Summary / Counts） |
| planner / architect / spec-review | 豁免 |

---

## 相關資源

| 主題 | 位置 |
|------|------|
| Agent 實作定義 | `.claude/agents/*.md` |
| 開發流程 | `rules/development-workflow.md` |
| Git 操作 | `rules/git-workflow.md` |
| 私鑰 / 金額 / 驗簽 / platform_id | `rules/security.md` |
| 分層 / DI / 回應信封 / 快取 | `rules/patterns.md` |
| 業務 domain 索引 | `rules/modules.md` |
