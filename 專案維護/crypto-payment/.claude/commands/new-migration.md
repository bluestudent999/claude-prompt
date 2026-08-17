建立新的 Flyway 資料庫遷移檔案，版本號一律以**時間戳**產生。

參數：`$ARGUMENTS`（格式：`DESCRIPTION`，例如 `add_withdrawal_table`。**不需要也不接受版本號** —— 版本號由指令自動產生）

> 完整規範見 [`rules/flyway-migration.md`](../rules/flyway-migration.md)。

## 執行步驟

1. **解析參數**
   - 若 `$ARGUMENTS` 為空 → 詢問使用者此次變更的描述。
   - 否則整個 `$ARGUMENTS` 即為 `DESCRIPTION`。
   - **若使用者傳入了版本號（如 `1.1.8 add_xxx`）**：提醒本專案已改用時間戳版本號，忽略該版本號，只取描述部分。

2. **格式化描述**
   - 空格與連字號一律替換為底線（`_`），全部轉小寫 → `snake_case`。
   - 確認為**動詞開頭**（`add_` / `alter_` / `drop_` / `backfill_` / `create_index_`）；若不是，建議使用者改寫。

3. **產生版本號**

   ```bash
   VERSION=$(date +%Y%m%d%H%M%S)     # 例：20260813131930
   ```

   - **一律用指令產生，不得手打**（避免位數錯誤或抄到別人的）。
   - 格式為 14 位數字，不加任何分隔符。

4. **衝突檢查**

   ```bash
   ls crypto-payment-flyway/src/main/resources/db/migration/ | grep "^V${VERSION}"
   ```

   - 時間戳精確到秒，理論上不會衝突；若真的撞到（同秒內建兩個檔），等 1 秒重新產生。

5. **建立檔案**

   路徑：`crypto-payment-flyway/src/main/resources/db/migration/V{VERSION}__{DESCRIPTION}.sql`

   > **`V` 必須大寫** —— 小寫 `v` 不會被 Flyway 辨識為 versioned migration。

   內容範本：

   ```sql
   -- ============================================================
   -- Migration : V{VERSION}__{DESCRIPTION}
   -- Date      : {YYYY-MM-DD HH:mm:ss}
   -- Author    :
   -- Ticket    : PROJ-XXX
   -- Description:
   --   TODO: 描述此次 schema 變更的目的
   -- ============================================================

   -- TODO: 在此撰寫 DDL / DML


   ```

6. **輸出確認**
   - 顯示完整檔案路徑與產生的版本號。
   - 提醒規則：
     - ✅ 可在此新檔案中自由新增 SQL
     - ✅ 版本號自帶建立時間，平行分支不會撞號
     - ❌ **禁止修改任何已存在的舊 migration 檔**（含既有語意版號檔 `V1_0_x__*.sql`，Flyway checksum 驗證會失敗）
     - ❌ **禁止為了統一格式而重新命名既有檔**
     - ❌ 禁止在 `testdata/` 以外的目錄放測試資料
     - ❌ **禁止自動執行 `flyway:migrate`** —— 產出檔案後停下來，由人確認並執行
   - 提醒：一個檔案只做一件事；涉及 `platform_id` 的表需確認多租戶隔離；交由 `database-reviewer` 審查。

7. **跑版本號驗證器**（見 [`rules/flyway-migration.md`](../rules/flyway-migration.md) §7）
   - 若專案尚未實作驗證器 → **先實作它**，那是 §7 明訂的必要交付項，不是可選。
