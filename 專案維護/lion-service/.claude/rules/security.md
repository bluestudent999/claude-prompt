---
paths:
  - "**/*.java"
---
# Java 安全性

> 安全規範：通用原則 + lion-service 特有的四條（filter 防線、彩票、金額、Log）。
> **包網商隔離**另立一份：[`platform-isolation.md`](./platform-isolation.md)（lion 風險最高的一條）。

## 通用安全原則

- 機密（密碼、API Key、Token、簽名金鑰）不硬編碼，統一從設定檔、環境變數或 config 表讀取
- **SQL 不拼接使用者輸入。** lion 沒有 MyBatis，SQL 由 framework_v3 `MysqlBaseDaoImpl` / `SqlUtil` 組出 —— 注入面就在「字串拼接」本身：值一律走參數綁定；欄名、排序、表名這類無法綁定的，必須先對照白名單
- 邊界輸入驗證：Controller 層用 `@Valid` + Bean Validation
- API 錯誤回應不暴露 stack trace、SQL 語句或內部路徑

## 第三方 API 金鑰管理

- 第三方 API 金鑰、Secret 存放於對應的 config 資料表，非硬編碼於程式
- 執行期透過 `*ConfigCache`（例：`PayConfigCache`、`TelegramConfigCache`）預載入與快取；新增對接沿用同一做法
- `.claude/settings.local.json` 的 `env` 區段存放本地開發憑證（不進版控）
- 第三方回調（cp-service `controller/third/`、single-wallet 全部入口）必須驗簽或 IP 白名單（見 `SingleWalletSignFilter`、各 `ThirdController`）

---

## 【lion 特有】filter 防線（已發生過實際入侵）

**事故：** 認證 filter 被繞過、系統被實際打進來。成因是**帶特定副檔名（`.do`）的請求被直接放行，完全不檢查**。
2026-09 的資安掃描另點名多處同類寫法（`MyFilter` 的放行分支、`SingleWalletSignFilter` 以 `contains("sync")` 跳過驗簽、多條子字串比對放行）。

這一類最難抓，因為**它看起來就是「有防線」**——filter 存在、也真的在檢查登入，只是某些請求根本走不到那段檢查。

**紅線（改任何 `*Filter.java`、放行清單、白名單、`isUriContains` 類判斷時）：**

| ❌ 禁止 | ✅ 改成 |
|---|---|
| 新增以**副檔名**判斷放行（`.do`、`.html`、`.json`…） | 明確列舉的完整路徑 |
| 新增以**子字串 / `contains` / `startsWith` 片段**判斷放行 | 精確比對；比對前先正規化路徑（去 `;` 參數、`//`、`..`、大小寫），並與容器分派用的字串一致 |
| 檢查失敗只記 log 不 `return` | 失敗一律中止請求 |
| 「順手」擴充既有的副檔名 / 子字串放行分支 | 停手，告知使用者這是已知的事故型寫法，由使用者決定是否另開修復單 |

- 這類改動一律 **L1**，必派 `security-reviewer`（`checks/filter-bypass.md`）
- **不要在一般需求裡順手重寫既有放行邏輯**——它影響全站入口，屬於另開修復單（可由資安報告驅動）的範圍

---

## 【lion 特有】彩票：賠率、限額、封盤、開獎

錢的流向由**開獎結果**與**賠率、限額設定**決定。攻擊者不需要入侵系統——只要讓賠率照自己的意思成立、在封盤後仍能下注、突破限額、或影響開獎結果的寫入，就能穩定獲利。

| 紅線 | 說明 |
|---|---|
| **賠率只取自伺服器端設定** | 請求帶來的賠率 / 賠付倍數只能拿來比對，不能拿來計算 |
| **限額檢查與扣額要在同一把鎖 / 同一個事務內** | 先查後寫無鎖 → 併發可突破限額（`checks/idempotency-orderno.md` §2） |
| **封盤 / 期號時間窗以伺服器時間判定** | 不信任請求帶的期號狀態或時間 |
| **開獎結果的寫入 / 改寫 / 重新派彩** | 屬最高風險操作：必須有權限檢查與操作留痕；改動必派 business + security reviewer |

- 相關位置：cp-service `playcom` / `lottery` / `randomodds`、開獎寫入 `LotteryResultService` / `HighOfficialLotteryResult*`；開獎資料來源 collector-service（資料品質 = 金錢）
- **派彩計算在 `lion-core`（跨 repo）**——本 repo 的改動若會影響派彩輸入，在 spec / plan 列跨 repo 影響，不要假設 lion-core 會自己處理

---

## 【lion 特有】金額安全

- **所有金額運算使用 `BigDecimal`**，**禁止** `double` / `float`
  - 例外：純統計（筆數、頁數、耗時）、隨機數、限流速率可用 `double`
- 餘額異動走既有入口（lion-common `UserMoneyService.changeMoney*`、single-wallet `service/balance/BalanceService`），**不得跳過直接改 DB**
- **金額異動 8 步（不可省略、不可合併、不可跳步）：** 取分散式鎖（玩家維度）→ `@Transactional` → `SELECT … FOR UPDATE` → 驗餘額 / 狀態 → 扣減或加款 → 寫流水 → commit → 釋放鎖
- **冪等判定在寫流水之前**：同 `orderNo` 重送必須回傳與首次相同的結果，不得重複扣款 / 派彩
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

## 【lion 特有】Log 脫敏

- 禁止記錄使用者密碼、Token、完整 API Key、簽名金鑰、銀行卡號
- 第三方回調的原始請求 body 可記錄，但需遮蔽敏感欄位
