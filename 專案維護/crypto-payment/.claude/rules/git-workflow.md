# Git 工作流程（crypto-payment）

> git 操作層規範（提交、分支、合併）。開發流程（規劃、TDD、審查）見 [development-workflow.md](./development-workflow.md)。
> 使用**通用 git**（非 GitLab / glab 專屬）。

## 分支策略

| 分支 | 用途 | 規則 |
|------|------|------|
| `developing` | 主開發分支，永遠保持最新穩定；所有功能從此分支出發 | **禁直接 commit 開發程式碼** |
| `developing_test` | 測試分支，匯集所有待測功能 | 不直接開發；只接收 feature merge |
| `feature/PROJ_XXX` | 功能分支，XXX = 工單號 | 開發在這裡 |

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

## 標準功能流程（不可跳步）

```bash
# 1. 取得最新 developing
git checkout developing
git fetch origin
git pull origin developing

# 2. 從 developing 建立功能分支（XXX 替換為實際單號）
git checkout -b feature/PROJ_XXX

# 3. 開發完成後 commit 並推送
git add -A
git commit -m "feat(PROJ-XXX): 功能描述"
git push -u origin feature/PROJ_XXX

# 4. 合併到測試分支（--no-ff 保留合併節點）
git checkout developing_test
git pull origin developing_test
git merge feature/PROJ_XXX --no-ff

# 5. 推送測試分支
git push origin developing_test
```

## Commit 訊息格式

```
type(PROJ-XXX): 簡短描述
```

| type | 用途 |
|------|------|
| feat | 新功能 |
| fix | 修復 bug |
| refactor | 重構，不改行為 |
| test | 新增 / 修改測試 |
| chore | 設定、依賴、CI 等雜項 |
| docs | 文件 |

範例：
- `feat(PROJ-123): add TRON deposit webhook handler`
- `fix(PROJ-456): resolve platform_id isolation in collector`

> commit message 由 `.claude/hooks/validate_commit_msg.py`（PreToolUse）強制驗證格式，不符會擋下。

## 硬規則

- **永遠從 `developing` 建立新分支**，不從 `developing_test` 或其他功能分支切出
- **功能分支只 merge 到 `developing_test`**，不直接 merge 回 `developing`
- **`developing_test` 的任何內容都不得回流**到 `developing` 或功能分支（merge / cherry-pick / rebase / 複製檔案皆禁止，見上方「測試分支單向流動」）
- merge 到 `developing_test` 用 `--no-ff`
- **任何程式碼修改都不得在 `developing` / `developing_test` 上進行**；若當前在這兩個分支，必須先 `git checkout feature/PROJ_XXX` 切回功能分支才能改
- 推送前確認 commit message 含工單號 `PROJ-XXX`
- git hook 擋住時**讀 hook 訊息找根因，不要 `--no-verify` 繞過**
