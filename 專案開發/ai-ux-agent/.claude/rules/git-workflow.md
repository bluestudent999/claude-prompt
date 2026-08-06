# Git 工作流與提交規範

> 本文規範 AI UX Audit Platform 的分支策略、Commit 格式、MR 流程與 AI 開發指標（AIDD）。

---

## 1. 分支策略

- **主分支**：`main` 為穩定分支；`developing` 為集成 / 測試分支。
- **功能開發分支**：從 `developing` 切出，命名 `feature/task-<工單號>-<描述>`（如 `feature/task-3-login-task`）。
- **修復分支**：`hotfix/<描述>`（如 `hotfix/observation-null-dom`）。

---

## 2. 提交訊息規範（Conventional Commits）

```
<type>(<scope>): <subject>

[optional body]
```

- `scope` 建議對映管線階段或 Task：`browser` / `observation` / `reasoning` / `evaluation` / `report` / `persona` / `task`。
- 常見類型：
  - `feat`（如 `feat(report): render markdown with evidence links`）
  - `fix`（如 `fix(login): leave trace on auth failure`）
  - `refactor` / `test` / `chore` / `docs`
- **紅線**：commit 訊息**嚴禁**含帳密 / Token / 目標站憑證（security-audit §1）。

---

## 3. Merge Request（MR）規範

Task 開發完畢並通過審查後，發起 MR 到 `developing`：

- **標題**：對齊工單，例：`Resolve TASK-3: Login task enters member area`。
- **描述**：
  1. **變更摘要**：一句話說明改動與影響的管線階段。
  2. **測試結果**：檢附 `pytest -q`（含 `-m architecture`）與 `ruff check` 的 PASS 證據。
  3. **審計影響**（若涉及觀察/推理/報告）：附 `/ux-audit-eval` 結果 —— 每個 Issue 皆有證據、四欄位齊全。
  4. **AIDD 指標**：見 §4。

---

## 4. AIDD 開發指標模板（觀察用，非每次必填）

> **填寫時機**：此指標用於累積基線後回答「哪步最耗 token / reviewer 命中率」。
> - **E1 demo 階段與 L3 micro 改動**（文案 / docstring / 設定 / 純重構）→ **可省略**，別為單行改動花 token 填表。
> - L1 / L2 且有實質實作的 MR → 建議填，累積到 10~20 個才有統計意義。
> - 純觀察用，**不作合入條件**。

```markdown
### AIDD 指標
- 環境階段：[E1 / E2 / E3]
- 風險等級：[L1 / L2 / L3]
- Plan OQ 數：[例如：3（自答 2、User 決議 1）；不含 defer-to-dev]
- Reviewer 輪次：[例如：code-reviewer 1 + arch-guard 1]
- 審查發現：[CRITICAL=0 HIGH=1 MEDIUM=3]
- 證據品質：[本次產出報告 Issue 數 / 皆有證據？ / 四欄位齊全？]
- 預估 Token 成本：[例如：~80k]
- Context 壓縮次數：[數字]
```

- **計數原則**：
  - **Plan OQ 數**：計畫中被標記並「決議」的 OQ 數量（`defer-to-dev` 不計入待決）。
  - **Reviewer 輪次**：執行 `code-reviewer` / `arch-guard` / `observation-reviewer` 的總次數。
  - **Context 壓縮次數**：執行 `/compact` 或 `/strategic-compact` 的次數。
