# Git 工作流與提交規範

> 本文規範 SDRP 專案的分支策略、Commit 訊息格式、Merge Request (MR) 流程與 AI 開發指標（AIDD）要求。

---

## 1. 分支策略 (Branching Strategy)

- **主分支**：`main` 為穩定生產分支；`developing` 為主要集成分支（開發主線）。
- **測試分支**：若專案另有 `developing_test` / `developing-test`，它**只收 merge、不回流**（見下方紅線）。
- **功能開發分支**：從 `developing` 切出，命名格式為 `feature/task-<工單號>-<描述>`（如 `feature/task-102-add-alignment-engine`）。
- **修復分支**：命名格式為 `hotfix/<描述>`（如 `hotfix/resolve-ingestion-npe`）。

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

## 2. 提交訊息規範 (Conventional Commits)

所有的 commit 必須遵循 Conventional Commits 格式：
```
<type>(<scope>): <subject>

[optional body]
```

### 常見類型 (Types)
- `feat`：新增功能（例如：`feat(alignment): introduce golden set evaluator`）。
- `fix`：修復 Bug（例如：`fix(ingestion): filter empty stream headers`）。
- `refactor`：代碼重構，不影響業務邏輯與 API 簽名。
- `test`：新增或修改測試代碼。
- `chore`：構建配置更新、依賴升級或輔助工具變更。
- `docs`：文檔修改。

---

## 3. Merge Request (MR) 規範

當 Task 開發完畢並通過 Step 4 的代碼與架構審查後，發起 Merge Request 到 `developing`：
- **標題格式**：對齊工單，例：`Resolve TASK-102: Add Alignment Engine`
- **描述內容**：
  1. **變更摘要**：一句話說明改動內容與影響模組。
  2. **測試結果**：檢附本地 `./mvnw test` 與 Modulith 測試運行的 PASS 證據。
  3. **AIDD 指標紀錄**：填寫 AI 開發效率指標。

---

## 4. AIDD 開發指標模板 (MR 必填)

為了量化 AI Agent 的開發效率與準確度，請在 MR 描述中包含以下資訊（AI 估算即可，不需極度精確）：

```markdown
### AIDD 指標
- 風險等級：[L1 / L2 / L3]
- Spec 輪次：[數字，包含回流次數]
- Plan OQ 數：[數字，例如：3（自答 2、User 決議 1）]
- Reviewer 輪次：[例如：增量 1 + 最終 1]
- 審查發現：[例如：CRITICAL=0 HIGH=1 MEDIUM=3]
- 預估 Token 成本：[例如：~80k]
- Context 壓縮次數：[數字]
```

- **計數原則**：
  - **Spec 輪次**：`spec-review` 通過確認的次數。
  - **Plan OQ 數**：在計畫中被標記並解決的 `OQ-xxx` 數量。
  - **Reviewer 輪次**：執行 `code-reviewer` 或 `arch-guard` 的總次數。
  - **Context 壓縮次數**：在開發過程中，執行 `/compact` 或壓縮 context 的次數。
