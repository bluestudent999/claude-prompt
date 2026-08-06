# Git 工作流程（crypto-payment）

> git 操作層規範（提交、分支、合併）。開發流程（規劃、TDD、審查）見 [development-workflow.md](./development-workflow.md)。
> 使用**通用 git**（非 GitLab / glab 專屬）。

## 分支策略

| 分支 | 用途 | 規則 |
|------|------|------|
| `developing` | 主開發分支，永遠保持最新穩定；所有功能從此分支出發 | **禁直接 commit 開發程式碼** |
| `developing_test` | 測試分支，匯集所有待測功能 | 不直接開發；只接收 feature merge |
| `feature/PROJ_XXX` | 功能分支，XXX = 工單號 | 開發在這裡 |

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
- merge 到 `developing_test` 用 `--no-ff`
- **任何程式碼修改都不得在 `developing` / `developing_test` 上進行**；若當前在這兩個分支，必須先 `git checkout feature/PROJ_XXX` 切回功能分支才能改
- 推送前確認 commit message 含工單號 `PROJ-XXX`
- git hook 擋住時**讀 hook 訊息找根因，不要 `--no-verify` 繞過**
