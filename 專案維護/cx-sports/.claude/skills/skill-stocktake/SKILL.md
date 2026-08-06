---
name: skill-stocktake
description: 審計 Claude skill 與指令的品質。支援快速掃描（僅變更的 skill）與完整盤點兩種模式，使用循序子 Agent 批次評估。
origin: ECC
---

# Skill 盤點

指令（`/skill-stocktake`）用於審計所有 Claude skill，使用品質檢查清單 + AI 整體判斷。支援兩種模式：快速掃描（僅最近變更的 skill）與完整盤點。

## 掃描範圍

指令以**呼叫時的目錄**為基準，掃描以下路徑：

| 路徑 | 說明 |
|------|------|
| `~/.claude/skills/` | 全域 skill（所有專案） |
| `{cwd}/.claude/skills/` | 專案層級 skill（若目錄存在） |

**Phase 1 開始時，指令會明確列出找到並掃描了哪些路徑。**

### 指定特定專案

若要包含專案層級的 skill，請從該專案的根目錄執行：

```bash
cd ~/path/to/my-project
/skill-stocktake
```

若專案沒有 `.claude/skills/` 目錄，則僅評估全域 skill 與指令。

## 模式

| 模式 | 觸發條件 | 預估時間 |
|------|----------|----------|
| 快速掃描 | `results.json` 存在（預設） | 5–10 分鐘 |
| 完整盤點 | `results.json` 不存在，或 `/skill-stocktake full` | 20–30 分鐘 |

**結果快取：** `$CLAUDE_PROJECT_DIR/.claude/skills/skill-stocktake/results.json`

## 快速掃描流程

僅重新評估自上次執行以來有變更的 skill（5–10 分鐘）。

1. 讀取 `$CLAUDE_PROJECT_DIR/.claude/skills/skill-stocktake/results.json`
2. 執行：`bash $CLAUDE_PROJECT_DIR/.claude/skills/skill-stocktake/scripts/quick-diff.sh \
         $CLAUDE_PROJECT_DIR/.claude/skills/skill-stocktake/results.json`
3. 若輸出為 `[]`：回報「自上次執行以來無變更」並結束
4. 僅對變更的檔案使用相同的 Phase 2 標準重新評估
5. 未變更的 skill 沿用先前結果
6. 僅輸出差異部分
7. 執行：`bash $CLAUDE_PROJECT_DIR/.claude/skills/skill-stocktake/scripts/save-results.sh \
         $CLAUDE_PROJECT_DIR/.claude/skills/skill-stocktake/results.json <<< "$EVAL_RESULTS"`

## 完整盤點流程

### Phase 1 — 盤點清冊

執行：`bash $CLAUDE_PROJECT_DIR/.claude/skills/skill-stocktake/scripts/scan.sh`

腳本列舉 skill 檔案、提取 frontmatter、收集 UTC 修改時間。
呈現掃描摘要與清冊表格：

```
掃描中：
  ✓ ~/.claude/skills/         (17 個檔案)
  ✗ {cwd}/.claude/skills/    (未找到 — 僅全域 skill)
```

| Skill | 7 日使用 | 30 日使用 | 說明 |
|-------|---------|----------|------|

### Phase 2 — 品質評估

啟動 Agent 子代理（**general-purpose agent**），帶入完整清冊與檢查清單。

子代理讀取每個 skill，套用檢查清單，回傳各 skill 的 JSON：

`{ "verdict": "Keep"|"Improve"|"Update"|"Retire"|"Merge into [X]", "reason": "..." }`

**分批指引：** 每次子代理呼叫處理約 20 個 skill，保持上下文可管理。每批完成後將中間結果存入 `results.json`（`status: "in_progress"`）。

所有 skill 評估完成後：設定 `status: "completed"`，進入 Phase 3。

**續傳偵測：** 若啟動時發現 `status: "in_progress"`，從第一個未評估的 skill 繼續。

每個 skill 依以下檢查清單評估：

```
- [ ] 已檢查與其他 skill 的內容重疊
- [ ] 已檢查與 MEMORY.md / CLAUDE.md 的重疊
- [ ] 已驗證技術引用的時效性（若包含工具名稱/CLI 旗標/API，使用 WebSearch）
- [ ] 已考量使用頻率
```

判定標準：

| 判定 | 含義 |
|------|------|
| Keep | 有用且最新 |
| Improve | 值得保留，但需要具體改進 |
| Update | 引用的技術已過時（以 WebSearch 驗證） |
| Retire | 品質低、過時、或成本不對稱 |
| Merge into [X] | 與其他 skill 大量重疊；指定合併目標 |

評估為**整體 AI 判斷** — 非數值評分。指導維度：
- **可操作性**：程式碼範例、指令或步驟，讓你能立即行動
- **範圍適切**：名稱、觸發條件與內容一致；不會太廣或太窄
- **獨特性**：價值無法被 MEMORY.md / CLAUDE.md / 其他 skill 取代
- **時效性**：技術引用在當前環境中仍有效

**Reason 品質要求** — `reason` 欄位必須自足且能支持決策：
- 不要只寫「未變更」— 永遠重述核心證據
- **Retire**：說明 (1) 發現什麼具體缺陷，(2) 什麼替代方案覆蓋相同需求
- **Merge**：指定目標並描述要整合的內容
- **Improve**：描述需要的具體變更（哪個段落、什麼動作、目標大小）
- **Keep**（快速掃描中僅 mtime 變更）：重述原始判定理由

### Phase 3 — 摘要表格

| Skill | 7 日使用 | 判定 | 理由 |
|-------|---------|------|------|

### Phase 4 — 整合

1. **Retire / Merge**：在與使用者確認前，呈現每個檔案的詳細理由：
   - 發現什麼具體問題（重疊、過時、參考失效等）
   - 什麼替代方案覆蓋相同功能
   - 移除的影響（是否有相依的 skill、MEMORY.md 引用或工作流程受影響）
2. **Improve**：呈現具體改進建議與理由，由使用者決定是否執行
3. **Update**：呈現已驗證來源的更新內容
4. 檢查 MEMORY.md 行數；若超過 100 行，建議壓縮

## 結果檔案格式

`$CLAUDE_PROJECT_DIR/.claude/skills/skill-stocktake/results.json`：

**`evaluated_at`**：必須設定為評估完成的實際 UTC 時間。
透過 Bash 取得：`date -u +%Y-%m-%dT%H:%M:%SZ`。不要使用僅日期的近似值如 `T00:00:00Z`。

```json
{
  "evaluated_at": "2026-02-21T10:00:00Z",
  "mode": "full",
  "batch_progress": {
    "total": 80,
    "evaluated": 80,
    "status": "completed"
  },
  "skills": {
    "skill-name": {
      "path": "~/.claude/skills/skill-name/SKILL.md",
      "verdict": "Keep",
      "reason": "具體、可操作、對 X 工作流程有獨特價值",
      "mtime": "2026-01-15T08:30:00Z"
    }
  }
}
```

## 注意事項

- 評估一視同仁：相同檢查清單適用於所有 skill，不分來源（ECC、自建、自動提取）
- 封存 / 刪除操作必須經使用者明確確認
- 不依 skill 來源做判定分支
