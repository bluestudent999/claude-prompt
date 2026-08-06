掃描目前 git diff 中所有新增/修改的程式碼，逐項執行 CLAUDE.md 定義的安全審查清單。

## 執行步驟

1. **取得變更範圍**
   執行 `git diff HEAD`（含 staged 與 unstaged）取得所有變更內容。
   若無任何變更，回報「目前無未提交變更，審查結束」。

2. **逐項審查（每項都必須明確標示 ✓ 或 ✗）**

   ### ① platform_id 隔離
   - 找出所有新增的 Repository 方法（`findBy`、`findAll`、`@Query`、`SELECT`、`UPDATE`、`DELETE`）
   - 確認每個查詢都帶有 `platform_id` / `platformId` 過濾條件
   - **違規**：任何缺少 `platform_id` 的資料庫查詢

   ### ② SignFilter 覆蓋
   - 找出所有新增的 `@RequestMapping`、`@GetMapping`、`@PostMapping`、`@PutMapping`、`@DeleteMapping`
   - 若路徑含 `/api/pay/`，確認 `application.yml` 的 `uri.sign.list` 有涵蓋此路徑
   - **違規**：新的 `/api/pay/*` endpoint 未在簽名保護範圍內

   ### ③ 私鑰明文
   - 掃描新增行中是否出現 `privateKey`、`seedPhrase`、`mnemonic`、`secretKey` 等敏感字串**賦值**（非參數名稱）
   - 確認私鑰相關變數在儲存前有經過 AES-GCM 加密（呼叫含 `Encrypt`/`Aes`/`Gcm` 的方法）
   - **違規**：明文私鑰出現在程式碼、log 輸出或任何儲存路徑

   ### ④ @Transactional
   - 找出所有新增的 Service 方法中，會執行 INSERT / UPDATE / DELETE（呼叫 `save`、`delete`、`update`、repository 寫入方法）的方法
   - 確認這些方法都有 `@Transactional` 注釋
   - **違規**：狀態修改方法缺少 `@Transactional`

   ### ⑤ 輸入驗證
   - 找出所有新增的 Controller 方法的 `@RequestBody` 與 `@RequestParam` 參數
   - 確認有 `@Valid` 注釋，或方法內有明確的手動驗證邏輯
   - **違規**：使用者可控輸入未經驗證直接進入業務邏輯

3. **輸出格式**
   ```
   ===== 安全審查報告 =====
   ① platform_id 隔離  ✓ / ✗ [違規位置]
   ② SignFilter 覆蓋    ✓ / ✗ [違規位置]
   ③ 私鑰明文          ✓ / ✗ [違規位置]
   ④ @Transactional    ✓ / ✗ [違規位置]
   ⑤ 輸入驗證          ✓ / ✗ [違規位置]
   ========================
   結論：通過 / 未通過（X 項需修正）
   ```

4. **結論**
   - 全部通過 → 「✅ 安全審查通過，可執行 commit」
   - 任何違規 → 「❌ 安全審查未通過，請修正後再 commit」，並列出所有問題的具體修正建議
