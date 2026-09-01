# Git 工作流與提交規範

> 本文規範 AI UX Audit Platform 的分支策略、Commit 格式、MR 流程與 AI 開發指標（AIDD）。

---

## 1. 分支策略

- **主分支**：`main` 為穩定分支；`developing` 為集成分支（開發主線）。
- **測試分支**：若專案另有 `developing_test` / `developing-test`，它**只收 merge、不回流**（見下方紅線）。
- **功能開發分支**：從 `developing` 切出，命名 `feature/task-<工單號>-<描述>`（如 `feature/task-3-login-task`）。
- **修復分支**：`hotfix/<描述>`（如 `hotfix/observation-null-dom`）。

<!-- shared:test-branch-one-way -->
### 測試分支單向流動（紅線）

**程式碼只能從開發分支流向測試分支，永遠不能回流。**

| 方向 | 允許？ |
|------|--------|
| 開發分支 / 功能分支 → 測試分支 | ✅ 正常流程 |
| 測試分支 → 開發分支 / 功能分支 | ❌ 一律禁止 |

**測試分支** ＝ 名稱為 `developing_test`、`developing-test`（或其他 `*_test` / `*-test` 變體）的分支。無法判斷某分支是不是測試分支時**問使用者**，不要自行認定。

**禁止的具體動作**（在開發分支、或從開發分支切出的功能分支上）：

| ❌ 動作 | 說明 |
|---|---|
| `git merge developing_test` | 含在開發分支上 `git pull` 誤拉測試分支來源 |
| `git cherry-pick <測試分支的 commit>` | 「只挑一個 commit」一樣是污染 |
| `git rebase` / `git reset --hard` 到測試分支 | 同上，且會改寫開發分支歷史 |
| `git checkout developing_test -- <path>`、手工複製測試分支的檔案內容 | 繞過 git 一樣算回流 |
| 從測試分支切出新的功能分支 | 新分支一開始就帶著整包待測程式碼 |

**為什麼是紅線：** 測試分支匯集的是**所有待測功能**，其中包含這次不打算上線的東西。一旦回流，這些未核准的變更就混進開發分支，上線時**夾帶沒有要上線的代碼**；而且混入之後已無法從 diff 分辨哪些屬於本次上線範圍，只能靠人記憶，必然出錯。

**遇到「我要的修改只存在於測試分支」時：**

1. 停手，先告知使用者「這個修改只在測試分支上」。
2. 正解是**從開發分支切出功能分支重新實作**（可以讀測試分支的 diff 當參考，但不 merge、不 cherry-pick），再照正常流程合併回測試分支。
3. 只有使用者明確授權才例外——那是使用者的決策，agent **不得自行判斷「這次應該沒關係」**。
<!-- /shared -->

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
