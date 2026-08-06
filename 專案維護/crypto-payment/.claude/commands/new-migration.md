建立新的 Flyway 資料庫遷移檔案，確保命名規則與版本號正確。

參數：`$ARGUMENTS`（格式：`VERSION DESCRIPTION`，例如 `1.1.8 add_withdrawal_table`）

## 執行步驟

1. **解析參數**
   - 若 `$ARGUMENTS` 為空：
     - 列出 `crypto-payment-flyway/src/main/resources/db/migrations/general/` 中最新的 3 個 migration 版本
     - 詢問使用者：新版本號與描述
   - 否則：第一個空格前為 `VERSION`，其餘為 `DESCRIPTION`

2. **格式化**
   - 將 DESCRIPTION 中的空格替換為底線（`_`）
   - 確認版本號格式為 `X.X.X`（例如 `1.1.8`）

3. **衝突檢查**
   - 掃描 `general/` 目錄，確認不存在相同版本號的檔案
   - 若存在衝突版本，中止並提示使用者選擇更高版本號

4. **建立檔案**

   路徑：`crypto-payment-flyway/src/main/resources/db/migrations/general/v{VERSION}__{DESCRIPTION}.sql`

   內容範本：
   ```sql
   -- ============================================================
   -- Migration : v{VERSION}__{DESCRIPTION}
   -- Date      : {YYYY-MM-DD}
   -- Author    :
   -- Description:
   --   TODO: 描述此次 schema 變更的目的
   -- ============================================================

   -- TODO: 在此撰寫 DDL / DML


   ```

5. **輸出確認**
   - 顯示完整檔案路徑
   - 提醒規則：
     - ✅ 可在此新檔案中自由新增 SQL
     - ❌ 禁止修改 `general/` 中任何已存在的舊 migration 檔案
     - ❌ 禁止在 `testdata/` 以外的目錄放測試資料
