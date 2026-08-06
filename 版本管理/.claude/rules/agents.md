# Agent 協作編排（升級期）

> Agent 定義位於 `.claude/agents/`，本檔規範升級期的風險分層、reviewer 路由與子 Agent briefing。

---

## 編排模型

```
升級工單 UPGRADE-xxx
   │
   ▼
/upgrade-inventory ── 盤點升級面（多模組走 upgrade-sweep workflow）
   │
   ▼
[upgrade-planner] ── 分階段計畫 + 版本鎖定確認表 + OQ
   │  （OQ：目標版本 / 不相容庫替代 → 必問 user）
   ▼ OQ 決議
[dependency-analyzer] + [compat-researcher] ── 依賴/BOM 對齊、查 jakarta 相容版本（平行）
   │
   ▼
/rewrite-run ── OpenRewrite 自動遷移（dryRun → 審 → run）
   │
   ▼
[config-migrator] ── 設定屬性遷移（與 recipe 並行）
   │
   ▼
[build-error-resolver] ── 編譯收斂（recipe 未覆蓋）
   │
   ▼
[regression-reviewer]（升級期主審）+ 視內容追加 reviewer
   │
   ▼
回歸對照 baseline → MR
```

---

## 升級風險分層（決定 reviewer 強度）

升級沒有業務 L 層，改用**升級風險層**判定 reviewer 配置：

| 風險層 | 典型範圍 | reviewer 配置 |
|--------|---------|--------------|
| **U3（低）** | 純依賴版本 bump（無 namespace / 無設定改）、註解相容升版、docs | `regression-reviewer` × 1（輕掃） |
| **U2（中）** | jakarta namespace 機械遷移、Boot 3 設定屬性遷移、recipe 自動改 | `regression-reviewer` + `dependency-analyzer`（驗版本對齊） |
| **U1（高）** | Spring Security 5→6、Hibernate 5→6、換庫（springfox→springdoc）、JVM/GC 參數、字元編碼/序列化行為 | `regression-reviewer` + `build-error-resolver`（若編譯涉入）+ `compat-researcher`（換庫相容），平行 |

> **判定原則：** 命中 `breaking-changes.md §C/§D/§E`（Security / Hibernate / 換庫）一律 U1。有疑問升級不降級。

---

## Agent 清單與路由

| Agent | 職責 | 觸發時機 |
|-------|------|---------|
| **upgrade-planner** | 盤點 → 分階段計畫、版本鎖定表、OQ | 盤點完成後 |
| **dependency-analyzer** | `dependency:tree` 衝突、BOM 對齊、Spring Cloud train、jakarta 相容版本決策 | 依賴版本問題、編譯前 |
| **compat-researcher** | 查第三方庫對 jakarta + Boot 3 的最低相容版本 / 替代庫 | plan §1 查證、換庫選型 |
| **build-error-resolver** | 升級後編譯錯誤分類 + 最小修復（namespace / 移除 API / 簽名變更） | `mvn compile` 大量錯誤 |
| **config-migrator** | yml / properties / bootstrap Boot 3 屬性遷移 | 設定檔遷移 |
| **regression-reviewer** | 行為等價 / 回歸風險審查（升級期主審） | 每階段 diff 完成、commit 前 |

---

## reviewer 派遣前必讀（硬規則）

主 agent 派 reviewer 前：

1. **讀 plan §0 Meta 的升級風險層**（U1/U2/U3）——單一事實來源，缺欄視同 U1。
2. **對照上表**選 reviewer 組合，禁止憑感覺。
3. **記錄派遣決策**：`[reviewer 派遣] U1（Security 5→6）→ regression-reviewer + compat-researcher`。

| 違反 | 處置 |
|------|------|
| U1（命中 Security/Hibernate/換庫）只派 regression-reviewer | **必須補派** compat-researcher / build-error-resolver |
| 無風險層欄 | **禁止派 reviewer**，先補 plan §0 |

---

## 平行執行

獨立 agent 呼叫**務必**同一則訊息平行啟動。多模組盤點用 `upgrade-sweep` workflow（每模組獨立 context，只回彙整）。

---

## 主 agent context 保護

升級碰大量檔案，主 agent 親自 grep 大範圍會撐爆 context。下列委派 **Explore agent**（獨立 context，只回結論）：

| 情境 | 主 agent 自做 | 委派 Explore |
|------|-------------|-------------|
| 單檔確認某 import / 某設定 | ✅ | — |
| 全 repo 掃 javax 使用面 / 棄用 API | — | ✅（或走 upgrade-sweep workflow） |
| 「springfox 在哪些設定類/註解使用」探查 | — | ✅ |
| 「某第三方庫 caller 分布」 | — | ✅ |

Explore briefing：`以 pattern {P1, P2} 掃 <模組>，回 javax 使用面分類（EE 需遷 / SE 白名單）+ 受影響檔案數 + 關鍵設定類路徑，不回原始 grep 行。` ≤ 300 字。

---

## 子 Agent 規範傳遞

子 Agent 不繼承父 context、不自動讀 skills（rules 會注入）。派子 Agent 必須**自包含**：

### Briefing 必含
| 項目 | 說明 |
|------|------|
| plan 路徑 + 章節 | `upgrade/task-xxx-plan.md §1 §6`，不貼全文 |
| diff 片段 | 貼 `git diff` 輸出（含行號），不丟檔名讓 agent full read |
| 聚焦範圍 | 各 reviewer 分工（見下表） |
| 規範摘要 | 從 rules 抄必要條文（如 jakarta 白名單、breaking-changes 對應條目） |
| Harness Output Contract | 提醒輸出 Status / Summary / Counts / Next actions / Artifacts |

### 平行 reviewer 分工
| reviewer | 聚焦 | 忽略 |
|---------|------|------|
| `regression-reviewer` | 行為等價、breaking-changes §F 高風險點、recipe 是否夾帶邏輯改動 | 版本號對齊 |
| `dependency-analyzer` | BOM/train 對齊、版本衝突、jakarta 相容版本 | source 邏輯 |
| `compat-researcher` | 第三方庫相容版本/替代庫查證 | code review |
| `build-error-resolver` | 編譯錯誤最小修復 | 風格/重構 |

### 規範摘要對照（按任務挑）
| 任務 | 必抄條文 |
|------|---------|
| jakarta 遷移審查 | `jakarta-migration.md §1` 白名單（EE 遷 / SE 不遷）、§3 非 import 出沒點 |
| Security 升級審查 | `breaking-changes.md §C` 全表、§F 第 3 點（路徑匹配整合測試必驗） |
| 依賴對齊審查 | `version-matrix.md §2` Spring Cloud train、§3 第三方相容下限 |
| 行為等價審查 | `breaking-changes.md §F` 6 點、`verification.md §1` baseline 對照法 |

> Briefing 總長 ≤ 500 字。給「任務目標 + 查資料位置」，不抱整箱資料進門。

---

## Harness Output Contract（reviewer / resolver 必守）

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

**Status 判定：** CRITICAL > 0 → `block`；HIGH > 0 → `warning`；其餘 → `approve`。小寫，不翻譯，不用 emoji。

| Agent | 版本 |
|-------|------|
| regression-reviewer / dependency-analyzer | 完整版（5 欄位） |
| build-error-resolver | Resolver 變體（`fixed:` / `remaining:`） |
| compat-researcher / config-migrator | 輕量版（Status / Summary / Counts） |
| upgrade-planner | 豁免 |
