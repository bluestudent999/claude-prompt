掃描目前 git diff 中所有資料庫查詢，確認多租戶 platform_id 隔離完整。

cross-platform 資料存取是 CLAUDE.md 定義的 **critical bug**，此指令在每次修改 repository/service 後執行。

## 執行步驟

1. **取得變更範圍**
   ```bash
   git diff HEAD -- '*.java'
   ```
   提取所有 `.java` 檔案中以 `+` 開頭的新增行（排除 `+++ b/` 檔頭行）

2. **掃描 Repository 層**
   在新增行中找出以下模式：
   - `findBy*`、`findAll*`、`deleteBy*`、`countBy*`、`existsBy*` 方法名稱
   - `@Query` 注釋中的 `SELECT`、`UPDATE`、`DELETE`
   - `JpaRepository` / `CrudRepository` 的繼承方法使用

   對每個查詢確認是否包含 `platform_id` / `platformId` / `PlatformId` 條件。

3. **掃描 Service 層**
   找出新增的 Service 方法，確認：
   - 呼叫 Repository 方法時有傳入 `platformId` 參數
   - 方法入參中有 `platformId`，或從 context/resolver 取得（`@CurrentPlatform`、`PlatformContext` 等）

4. **分類輸出**

   ```
   ===== Platform 隔離審查 =====

   ✓ 已隔離（共 N 個查詢）
   ─────────────────────────────
   [列出確認有 platform_id 的查詢]

   ✗ 疑似缺少隔離（共 N 個查詢）⚠ 需立即修正
   ─────────────────────────────
   [檔案路徑:行號] 方法名稱 → 缺少 platform_id 條件

   ⚠ 無法確認（共 N 個查詢）→ 需人工確認
   ─────────────────────────────
   [列出無法靜態分析的查詢]

   ============================
   ```

5. **結論**
   - 無 ✗ 項目 → 「✅ platform_id 隔離審查通過」
   - 有 ✗ 項目 → 「❌ 發現 {N} 個潛在跨平台存取風險，請修正後再次執行」
