---
paths:
  - "**/*.java"
---
# Java 安全性

> 安全規範：通用原則 + 本專案特有要求。

## 通用安全原則

- 機密（密碼、API Key、Token）不硬編碼，統一從設定檔或環境變數讀取
- SQL 一律使用參數化查詢，禁止字串拼接；MyBatis 用 `#{param}`，**禁 `${param}`**（動態表名需白名單校驗）
- 邊界輸入驗證：Controller 層用 `@Valid` + Bean Validation
- API 錯誤回應不暴露 stack trace、SQL 語句或內部路徑

## 第三方 API 金鑰管理

- 第三方 API 金鑰、Secret 存放於對應的 config 資料表（如 `third_api`、`on_chain_pay`、`provider_*`），非硬編碼於程式
- 執行期透過 `*ConfigCache`（例：`TelegramConfigCache`、`PayConfigCache`、`CryptoActiveChainConfigCache`）預載入與快取
- `.claude/settings.local.json` 的 `env` 區段存放本地開發憑證（不進版控）
- 第三方回調 URL（`/third/*`）需驗證簽名或 IP 白名單（見各 `ThirdController` / `SingleWalletSignFilter`）

## 【專案特有】金額安全

- **所有金額運算使用 `BigDecimal`**，**禁止** `double` / `float`
  - 例外：純統計（筆數、頁數、耗時）、隨機數、限流速率可用 `double`
- **金額異動操作必須在 DB 事務中使用悲觀鎖**（`SELECT ... FOR UPDATE`，見 `cx-sport-single-wallet-service` `AbstractSingleWalletService` / `cx-sports-v2` 錢包相關 Service）
- **餘額異動 7 步（不可跳步）：** Redis 分散式鎖 → `@Transactional` 開事務 → `SELECT … FOR UPDATE` 悲觀鎖 → 驗餘額充足 → 扣減 → 寫流水 → commit
- **禁用 `synchronized` 做跨節點業務鎖**（叢集環境無效，見 [`patterns.md §6`](./patterns.md)）

### RoundingMode 使用規範（依場景區分）

| 場景 | RoundingMode | 原因 |
|------|--------------|------|
| **金額異動 / 餘額 / 退款** | **`DOWN`**（無條件捨去） | 避免多給錢 |
| **多幣別 rate 換算**（系統 ↔ 第三方） | **`DOWN`** | 避免多給錢 |
| **一般業務計算中間值** | `HALF_UP` 可接受 | 常規四捨五入 |
| **報表 / 顯示用聚合** | `HALF_UP` 可接受 | 僅顯示，不影響實際帳務 |
| **validAmount / 結算金額** | **`DOWN`** | 屬於帳務範疇 |

> **判定原則：** 值會變成**實際入帳/出帳**的金額用 `DOWN`；僅用於**計算中間值或顯示**的用 `HALF_UP`。不確定時預設 `DOWN`。

## 【專案特有】Log 脫敏

- 禁止記錄使用者密碼、Token、完整 API Key
- 第三方回調的原始請求 body 可記錄，但需遮蔽敏感欄位

