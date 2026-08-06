審查新增的 REST endpoint，確保符合 CLAUDE.md 的所有程式規範與安全要求。

目標：`$ARGUMENTS`（Controller 檔名或 class 名稱；留空則自動從 git diff 找出所有新增 endpoint）

## 執行步驟

1. **定位 endpoint**
   - 若有 `$ARGUMENTS`：讀取指定 Controller 檔案
   - 若無：從 `git diff HEAD` 找出所有含 `@GetMapping`、`@PostMapping`、`@PutMapping`、`@DeleteMapping`、`@RequestMapping` 的新增方法

2. **逐一審查（每個 endpoint 獨立輸出）**

   針對每個新 endpoint，檢查以下六項：

   ### A. BaseResponse 包裝
   - 回傳型別是否為 `BaseResponse<T>` 或 `BaseResponse<Void>`？
   - **違規**：直接回傳 raw object、`Map`、`String`、`void`

   ### B. SignFilter 覆蓋（僅 `/api/pay/*`）
   - 路徑含 `/api/pay/` 時，確認 `application.yml` 的 `uri.sign.list` 已涵蓋
   - **違規**：`/api/pay/*` endpoint 未在簽名保護範圍

   ### C. Platform 取得
   - 確認方法中有透過 resolver / context 取得 `platformId`（如 `@CurrentPlatform`、`PlatformContext.get()` 或方法參數注入）
   - **違規**：方法體內無任何 platform 相關操作（對純 manage 類型 endpoint 可豁免，需說明理由）

   ### D. 例外處理
   - 確認 throws 的例外為自定義例外類別（非 `RuntimeException`、`Exception`）
   - **違規**：直接 `throw new RuntimeException(...)`

   ### E. 日誌規範
   - 確認使用 `@Slf4j` + `log.info/debug/warn/error`
   - **違規**：`System.out.println`、`e.printStackTrace()`

   ### F. 輸入驗證
   - `@RequestBody` 參數是否有 `@Valid`
   - `@RequestParam` / `@PathVariable` 是否有必要的 null / 格式驗證
   - **違規**：使用者可控輸入未驗證直接進入 Service 層

3. **輸出格式**
   ```
   ===== Endpoint 審查：POST /api/pay/withdraw =====
   A. BaseResponse  ✓
   B. SignFilter    ✓
   C. Platform 取得 ✗ → 未找到 platformId 取得邏輯（第 42 行）
   D. 例外處理      ✓
   E. 日誌規範      ✓
   F. 輸入驗證      ✗ → @RequestBody WithdrawRequest 缺少 @Valid（第 38 行）
   結論：❌ 2 項需修正
   ================================================
   ```

4. **彙總**
   所有 endpoint 審查完畢後，輸出：通過數 / 總數，以及所有違規的修正建議。
