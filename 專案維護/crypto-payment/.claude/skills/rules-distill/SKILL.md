---
name: rules-distill
description: 掃描 skill 提取跨領域原則，並萃取為 rules — 附加、修訂或建立新的 rule 檔案。
origin: ECC
---

# Rules 萃取

掃描已安裝的 skill，提取出現在多個 skill 中的跨領域原則，並萃取為 rules — 附加到現有 rule 檔案、修訂過時內容、或建立新的 rule 檔案。

採用「確定性收集 + 交叉閱讀判斷」原則：腳本窮舉收集事實，交叉閱讀完整上下文後產出判定。

## 適用時機

- 定期維護 rules（每月或安裝新 skill 後）
- skill-stocktake 揭示應成為 rules 的模式後
- 感覺 rules 相對於使用中的 skill 不夠完整時

## 運作方式

Rules 萃取流程分為三個階段：

### Phase 1：盤點（確定性收集）

#### 1a. 收集 skill 清冊

```bash
bash $CLAUDE_PROJECT_DIR/.claude/skills/rules-distill/scripts/scan-skills.sh
```

#### 1b. 收集 rules 索引

```bash
bash $CLAUDE_PROJECT_DIR/.claude/skills/rules-distill/scripts/scan-rules.sh
```

#### 1c. 呈現給使用者

```
Rules 萃取 — Phase 1：盤點
────────────────────────────
Skills：{N} 個檔案已掃描
Rules：{M} 個檔案（{K} 個標題已索引）

進入交叉閱讀分析...
```

### Phase 2：交叉閱讀、比對與判定

提取與比對在單一 pass 中統一完成。Rules 檔案足夠小（約 800 行），可完整讀取 — 無需 grep 預過濾。

#### 分批

依描述將 skill 分為**主題群組**。在子代理中分析每個群組，附帶完整的 rules 文字。

#### 跨批合併

所有批次完成後，跨批合併候選項：
- 去除相同或重疊原則的候選項
- 使用**所有**批次的證據重新檢查「2+ skill」要求 — 每批只在 1 個 skill 中出現但總計 2+ 個 skill 的原則仍然有效

#### 子代理 Prompt

啟動 general-purpose Agent，使用以下 prompt：

````
你是一位分析師，交叉閱讀 skill 以提取應提升為 rules 的原則。

## 輸入
- Skills：{本批 skill 的完整文字}
- 現有 rules：{所有 rule 檔案的完整文字}

## 提取標準

僅在以下**所有**條件為真時才納入候選項：

1. **出現在 2+ 個 skill**：僅出現在 1 個 skill 的原則應留在該 skill
2. **可操作的行為變更**：可寫成「做 X」或「不要做 Y」— 而非「X 很重要」
3. **明確的違反風險**：忽略此原則會出什麼問題（1 句話）
4. **尚未在 rules 中**：檢查完整的 rules 文字 — 包含以不同用語表達的概念

## 比對與判定

對每個候選項，比對完整的 rules 文字並指定判定：

- **Append**：加到現有 rule 檔案的現有段落
- **Revise**：現有 rule 內容不準確或不足 — 提出修正
- **New Section**：在現有 rule 檔案加入新段落
- **New File**：建立新的 rule 檔案
- **Already Covered**：已在現有 rules 中充分涵蓋（即使用語不同）
- **Too Specific**：應留在 skill 層級

## 輸出格式（每個候選項）

```json
{
  "principle": "1-2 句，以「做 X」/「不要做 Y」形式",
  "evidence": ["skill-name: §Section", "skill-name: §Section"],
  "violation_risk": "1 句話",
  "verdict": "Append / Revise / New Section / New File / Already Covered / Too Specific",
  "target_rule": "filename §Section，或 'new'",
  "confidence": "high / medium / low",
  "draft": "Append/New Section/New File 判定的草稿文字",
  "revision": {
    "reason": "為什麼現有內容不準確或不足（僅 Revise）",
    "before": "要替換的現有文字（僅 Revise）",
    "after": "提議的替換文字（僅 Revise）"
  }
}
```

## 排除

- 已在 rules 中的明顯原則
- 語言/框架特定知識（屬於語言特定的 rules 或 skill）
- 程式碼範例與指令（屬於 skill）
````

#### 判定參考

| 判定 | 含義 | 呈現給使用者 |
|------|------|-------------|
| **Append** | 加到現有段落 | 目標 + 草稿 |
| **Revise** | 修正不準確/不足的內容 | 目標 + 原因 + 前/後 |
| **New Section** | 在現有檔案加新段落 | 目標 + 草稿 |
| **New File** | 建立新 rule 檔案 | 檔名 + 完整草稿 |
| **Already Covered** | 已在 rules 中涵蓋 | 原因（1 行） |
| **Too Specific** | 應留在 skill | 連結到相關 skill |

### Phase 3：使用者審查與執行

#### 摘要表格

```
# Rules 萃取報告

## 摘要
掃描 Skill：{N} | Rules：{M} 個檔案 | 候選項：{K}

| # | 原則 | 判定 | 目標 | 信心度 |
|---|------|------|------|--------|
| 1 | ... | Append | security.md §Input Validation | high |
| 2 | ... | Revise | patterns.md §Exception | medium |
| 3 | ... | New Section | coding-style.md | high |
| 4 | ... | Too Specific | — | — |

## 詳細
（每個候選項的詳細資訊：證據、違反風險、草稿文字）
```

#### 使用者操作

使用者以編號回應：
- **核准**：直接套用草稿到 rules
- **修改**：套用前編輯草稿
- **略過**：不套用此候選項

**絕不自動修改 rules。必須經使用者核准。**

#### 儲存結果

將結果存入 skill 目錄（`results.json`）：

- **時間戳格式**：`date -u +%Y-%m-%dT%H:%M:%SZ`（UTC，精確到秒）
- **候選項 ID 格式**：從原則衍生的 kebab-case（例如 `llm-output-trust-boundary`）

```json
{
  "distilled_at": "2026-03-18T10:30:42Z",
  "skills_scanned": 56,
  "rules_scanned": 22,
  "candidates": {
    "llm-output-trust-boundary": {
      "principle": "儲存或重新注入時，將 AI 輸出視為不可信",
      "verdict": "Append",
      "target": "rules/security.md",
      "evidence": ["llm-memory-trust-boundary", "llm-social-agent-anti-pattern"],
      "status": "applied"
    }
  }
}
```

## 設計原則

- **What, not How**：僅提取原則（rules 領域）。程式碼範例與指令留在 skill。
- **回連**：草稿文字應包含 `See skill: [name]` 引用，讓讀者能找到詳細的 How。
- **確定性收集，交叉閱讀判斷**：腳本保證窮舉性；交叉閱讀保證上下文理解。
- **反抽象化防護**：三層過濾（2+ skill 證據、可操作行為測試、違反風險）防止過度抽象的原則進入 rules。
