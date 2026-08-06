從 `developing` 建立新功能分支，嚴格執行 CLAUDE.md 定義的五步 git 流程。

工單號：$ARGUMENTS

## 執行步驟

1. **驗證參數**
   - 若 `$ARGUMENTS` 為空，停下並詢問工單號
   - 確認格式符合 `PROJ-` 開頭（例如 `PROJ-123`），否則中止並說明正確格式

2. **同步 developing**
   ```bash
   git checkout developing
   git fetch origin
   git pull origin developing
   ```

3. **建立功能分支**
   ```bash
   git checkout -b feature/$ARGUMENTS
   ```

4. **確認並輸出**
   - 顯示目前分支名稱：`feature/$ARGUMENTS`
   - 顯示最新 commit hash 與訊息（即 developing 的 HEAD）
   - 提醒：開發完成後執行 `/merge-to-test` 合併至測試分支

> **注意**：絕對不能在 `developing` 或 `developing_test` 上直接進行開發。
