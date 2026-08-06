---
name: review-req
description: 審查現有企劃產出(Brief / Spec / Backlog)的完整性與邏輯漏洞,調用獨立 spec-reviewer 產出 Harness Output Contract。定案前把關時使用。
---

# review-req — 企劃產出審查

調用 `spec-reviewer` agent(獨立角色),審查 Brief / Spec / Backlog 是否完整、無歧義、可切片、依賴健全。

## 啟用時機
- 任一企劃產出準備定案 / 打 Baseline 前。
- 懷疑規格有邏輯漏洞或 Edge Case 缺失。

## 流程
1. **指定對象**:告訴 skill 要審哪份文件 + 類型(Brief / Spec / Backlog)。
2. **附上游**:提供上游文件路徑供一致性比對(審 Spec 附 Brief;審 Backlog 附 Spec)。
3. **委派 spec-reviewer**:只讀目標 + 上游,逐項對照 Quality Gate。
4. **收 Harness Output Contract**:依 Status 決定後續。

## Status 處置
| Status | 處置 |
|--------|------|
| `block`(CRITICAL>0) | **必修** — 回產出 Agent 修正後重審 |
| `warning`(HIGH>0) | 通常要修,至少要有決議紀錄 |
| `approve` | 可進 Baseline 閘門(仍需無 `⏳` OQ + 利害關係人確認) |

## 硬規則
- **審查獨立**:spec-reviewer 只回報不改文件;修正由原產出 Agent 負責。
- **不放行未決 OQ**:文件仍有 `⏳` → CRITICAL,不得 approve。
- **Baseline 需三條件**:approve + 無 `⏳` + 利害關係人確認(見 `planning-workflow.md` Step 4)。

## 完成輸出
轉述 spec-reviewer 的 Status / Counts / Next actions / Artifacts,並給下一步建議。
