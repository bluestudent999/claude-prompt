將目前的 feature 分支合併至 `developing_test`，嚴格執行 CLAUDE.md 定義的流程。

## 執行步驟

1. **前置確認**
   - 執行 `git branch --show-current` 確認目前在 `feature/*` 分支
   - 若在 `developing`、`developing_test` 或其他非 feature 分支，**立即中止**並說明原因
   - 記錄目前分支名稱（後續切回用）

2. **安全審查（必做，不可跳過）**
   - 執行 `/security-check`
   - 若有任何 ✗ 違規項目，**停下等待使用者確認是否繼續**
   - 使用者明確確認後才繼續下一步

3. **確認無未提交變更**
   ```bash
   git status --short
   ```
   若有未提交變更，提示使用者先 commit 或 stash

4. **合併至 developing_test**
   ```bash
   git checkout developing_test
   git pull origin developing_test
   git merge {feature_branch} --no-ff
   ```

5. **處理 merge conflict**
   - 若有衝突，執行 `git diff --name-only --diff-filter=U` 列出衝突檔案
   - **停下並等待使用者解決衝突**，不得自動處理衝突
   - 使用者解決後繼續執行步驟 6

6. **推送並切回**
   ```bash
   git push origin developing_test
   git checkout {feature_branch}
   ```

7. **輸出摘要**
   - 顯示：合併的 commit 數量、影響的檔案數
   - 提醒：feature 分支保留，待 developing merge 後再刪除

> **規則**：merge 到 developing_test 時**必須使用 `--no-ff`**，保留合併節點。
