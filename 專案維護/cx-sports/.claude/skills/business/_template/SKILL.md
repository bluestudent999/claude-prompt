---
name: business-template
description: 業務領域 skill 模板。**這是模板本身，不要直接呼叫**。新增業務領域知識請複製此目錄為 `.claude/skills/business/<domain>/`，改 frontmatter `name` 與 `description`，再依骨架填內容。
origin: template
---

# 業務領域 Skill 模板（複製改名後使用）

> **這份 SKILL.md 是「模板」，不是可載入的業務知識。** 此檔位於 `.claude/skills/business/_template/`，不會被 Claude Code skill loader 自動發現（loader 不遞迴掃子目錄），這是有意設計。

## 套用方式

```bash
# 1. 複製整個目錄到 business/<domain>/
cp -r .claude/skills/business/_template .claude/skills/business/<domain>
# 例：.claude/skills/business/wallet/

# 2. 改 frontmatter（name 改為 business-<domain> / description / origin: project）
# 3. 依下方骨架填內容（替換 {{...}} placeholder）
# 4. 到 .claude/rules/modules.md 把對應 domain 列「完整 skill」欄
#    從 ❌ 改為 🚧 `.claude/skills/business/<domain>/`
#    填完後再從 🚧 改 ✅
```

## 為何放在子目錄而非 top-level

Claude Code 的 skill loader 只掃描 `.claude/skills/<name>/SKILL.md` 單層，不遞迴。把業務知識放 `business/<domain>/` 子目錄是**有意設計**：

- **避免 prompt token 浪費**：60+ domain 若全 top-level，每次對話 system prompt 都會載入 60+ description（~2k tokens × 50 輪 ≈ 100k tokens）
- **業務知識不靠自動發現**：本專案規定走 `rules/modules.md` 索引，主 agent 收到需求時對照索引找路徑，再用 Read 讀取
- **子 agent 一律由 briefing 指路**：本來就不依賴 auto-discovery

---

# {{Module Display Name}}

{{此業務模組的一段話總覽 — 在系統中扮演的角色、與其他模組的關係。}}

## 適用時機

- {{何時應載入此 skill，例如：開發新的轉帳 API 時}}
- {{除錯此領域問題時}}
- {{審查涉及此模組的 PR 時}}

## 領域概念

### 核心實體

| 實體 | 說明 | 對應資料表 |
|------|------|-----------|
| `{{Entity1}}` | {{說明}} | `{{table_name}}` |
| `{{Entity2}}` | {{說明}} | `{{table_name}}` |

### 關鍵欄位語義

- **`{{field_name}}`**：{{欄位含義、可能值、業務意義}}
- **`{{status_field}}`**：狀態欄位，可能值 `{{0}}`/`{{1}}`/`{{2}}`，狀態轉換見下方狀態機

## 狀態機

```
{{StateA}} → {{StateB}} → {{StateC}}
                  ↓
              {{StateError}}
```

| 從 | 到 | 觸發條件 | 注意事項 |
|----|-----|---------|---------|
| `{{StateA}}` | `{{StateB}}` | {{條件}} | {{例如：需取得 Redis 鎖}} |
| `{{StateB}}` | `{{StateC}}` | {{條件}} | {{例如：金額需用 BigDecimal}} |

## 核心業務規則

### 規則 1：{{規則名稱}}
- **What**：{{做什麼}}
- **Why**：{{為何如此}}
- **違反風險**：{{若違反會發生什麼}}

### 規則 2：{{規則名稱}}
- **What**：...
- **Why**：...
- **違反風險**：...

## 金額處理

> 若此模組涉及金額，必須遵循以下規範

- 使用 `BigDecimal` + `RoundingMode.DOWN`
- 精度為 {{N}} 位小數
- 幣別轉換時：{{說明}}

## 併發控制

> 若此模組涉及併發

- **Redis 鎖 key 格式**：`{{module}}:{{operation}}:{{userId}}`
- **鎖超時**：{{N}} 秒
- **重入策略**：{{說明}}

## 常見錯誤模式

### 錯誤 1：{{錯誤描述}}
- **症狀**：{{現象}}
- **原因**：{{根因}}
- **修正**：{{正確做法}}

## 相關檔案

- Service：`com.cx.{{module}}.service.{{Module}}Service`
- DAO：`com.cx.{{module}}.dao.{{Module}}Repository`
- Entity：`com.cx.{{module}}.bean.{{Module}}Entity`
- 設定：`{{module}}-config.yml`

## 相關 SQL / 資料表

```sql
-- 主要查詢模式
SELECT ... FROM {{table_name}} WHERE ...

-- 索引設計
CREATE INDEX idx_{{module}}_{{column}} ON {{table_name}}({{column}});
```

## 對接其他模組

| 對接模組 | 方式 | 資料流 |
|---------|------|--------|
| `{{other-module}}` | {{API/事件/直接呼叫}} | {{說明}} |

## 相關 Agent 與 Skill

- 審查涉及金額/狀態機 → `business-reviewer` agent
- 規格預審 → `spec-review` skill
- SQL 審查 → `database-reviewer` agent

---

## 客製檢查清單

複製此模板為新業務 skill 後，請完成：

- [ ] 目錄放在 `.claude/skills/business/<domain>/`（小寫，與 service domain 名一致）
- [ ] 更新 frontmatter：`name: business-<domain>` / 改 `description` / `origin: project`
- [ ] 移除所有 `{{placeholder}}`
- [ ] 移除不適用的章節（例如非金額模組移除「金額處理」）
- [ ] 補上實際的狀態機圖
- [ ] 列出實際的核心業務規則（至少 3 條）
- [ ] 到 `.claude/rules/modules.md` 對應列把 `❌` 改為 `🚧 \`.claude/skills/business/<domain>/\``
- [ ] 補完且 PO 確認後，把 🚧 改為 ✅
