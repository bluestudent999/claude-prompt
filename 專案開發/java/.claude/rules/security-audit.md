# 安全與審計規範

> 本文規範 SDRP 專案的安全性、審計追蹤、金額計算精度以及事務並發控制。

---

## 1. 審計追蹤 (Audit Trail)

SDRP 作為數據可靠性平台，對所有寫入型操作必須留下不可篡改的審計日誌。

- **硬性規則**：所有變更（Insert / Update / Delete / State Change）必須留存 **Append-Only 審計記錄**。
- **審計欄位要求**：每筆記錄必須包含：
  - `correlationId`：用於追蹤跨模組甚至跨系統的請求鏈。
  - `actorType`：變更發起者類型（如 `AI_AGENT`、`USER`、`SYSTEM`）。
  - `decisionVersion`：當前決策或數據的版本，防範併發覆寫。

---

## 2. 自動化安全與 AI 煞車

- **Fail-Safe**：對結算與對齊引擎，必須設計 Fail-Safe 機制。當對齊引擎不可用或信心分數過低時，必須安全退回人工審查流程，**禁止 Fail-Open**（放行未驗證或錯誤的數據結果）。
- **AI 煞車**：低信心度（Confidence Score 低於閥值）的數據一律轉為 **HITL (Human-in-the-Loop)** 人工審核，降低 false-auto (錯誤自動化) 概率。

---

## 3. 金額安全與精度規範

- **數據類型**：所有金額計算與餘額記錄，**一律使用 `BigDecimal`**，禁止使用 `double` 或 `float`。
- **取整模式 (RoundingMode)**：
  - 值會變成**實際入帳/出帳**的金額，必須使用 **`RoundingMode.DOWN`**（無條件捨去），防止多付或溢出。
  - 純顯示或非結算中間值可使用 `RoundingMode.HALF_UP`（四捨五入）。
- **悲觀鎖與併發安全**：
  - 餘額與扣款等異動操作，必須在資料庫事務中使用 `SELECT ... FOR UPDATE` 悲觀鎖進行鎖定。
  - 分散式環境下，必須搭配 Redis 分散式鎖，嚴禁在單機使用 `synchronized` 或 `ReentrantLock`。

---

## 4. 敏感資訊與 Log 脫敏

- **金鑰管理**：API 密鑰、Token、資料庫憑證等敏感資訊，必須配置於 `application.yml` 的環境變數插值中，或存放於 `.claude/settings.local.json`，**嚴禁硬編碼於代碼中**。
- **日誌脫敏**：
  - Log 紀錄中禁止直接印出明文密碼、API Key 或完整 API 請求體中的敏感個人數據。
  - 使用日誌框架（如 Logback 遮蔽過濾器）或工具類自動將 Token/Secret 字段轉為 `******`。

---

## 5. SQL 注入防護

- **參數化查詢**：MyBatis / MyBatis-Plus 中一律使用 `#{param}` 進行參數綁定。
- **動態 SQL 限制**：嚴禁使用 `${param}` 來拼接 SQL 語句。若因動態表名或動態排序必須使用 `${}`，必須使用白名單過濾器（Whitelist Validation）確保傳入參數的安全性。
