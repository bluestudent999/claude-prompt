根據存款處理流程，追蹤指定交易的完整路徑，協助 debug webhook 與入帳問題。

查詢條件：`$ARGUMENTS`（tx_hash、錢包地址、訂單 ID，或留空顯示流程架構）

## 執行步驟

1. **前置說明**
   - ⚠ 依 CLAUDE.md 規則，`logs/` 目錄**禁止讀取**
   - 若需查 log，請使用者自行提供相關 log 片段貼入對話

2. **靜態流程追蹤（不讀 log，只讀程式碼）**

   依序找出並列出以下各層的**實際類別名稱與方法**：

   | 層級 | 要找的東西 |
   |------|-----------|
   | ① Webhook 入口 | `/api/thirdparty/*` 對應的 Controller method |
   | ② 簽名驗證 | `SignFilter` 或 Webhook HMAC 驗證的具體邏輯位置 |
   | ③ 鏈上解析 | ChainLog 相關 Service 的 parse/match 方法 |
   | ④ 錢包比對 | 用戶錢包查詢邏輯（Repository 方法名稱）|
   | ⑤ Kafka 發布 | `KafkaTemplate.send(...)` 的 topic 名稱與 payload 類型 |
   | ⑥ 事件消費 | `@KafkaListener` 的 topic 對應 handler 類別與方法 |
   | ⑦ 帳戶更新 | 用戶餘額更新的 Service 方法（含 `@Transactional`）|
   | ⑧ 下游通知 | 外部平台 Webhook 發送邏輯 |

3. **輸出流程圖**（文字版）
   ```
   [① Webhook 入口] QuickNodeController.receiveWebhook()
        ↓
   [② 簽名驗證] SignFilter.doFilter() → HmacVerifier.verify()
        ↓
   [③ 鏈上解析] ChainLogService.parseLog()
        ↓
   [④ 錢包比對] UserWalletRepository.findByAddressAndPlatformId()
        ↓
   [⑤ Kafka 發布] KafkaTemplate.send("deposit-topic", DepositEvent)
        ↓
   [⑥ 事件消費] DepositEventListener.onDepositEvent()
        ↓
   [⑦ 帳戶更新] UserAccountService.creditBalance()  [@Transactional]
        ↓
   [⑧ 下游通知] WebhookNotifyService.notifyPlatform()
   ```

4. **若有 `$ARGUMENTS`**（tx_hash / 錢包 / 訂單 ID）
   - 在各層程式碼中搜尋對應的查詢條件（字段名、參數名）
   - 標示「此層應用 `$ARGUMENTS` 做為查詢條件」的位置
   - 若某層缺少對應欄位的查詢，標注 `⚠ 此層無法用此條件追蹤`

5. **常見問題 checklist**
   根據追蹤結果，列出最可能的 debug 方向：
   - [ ] Webhook 簽名是否通過？（確認 HMAC key 設定）
   - [ ] 鏈別（TRON/BSC/ETH）的解析器是否正確路由？
   - [ ] 錢包地址大小寫是否一致？
   - [ ] Kafka consumer group offset 是否正常？
   - [ ] `@Transactional` 是否因 exception 導致 rollback？
