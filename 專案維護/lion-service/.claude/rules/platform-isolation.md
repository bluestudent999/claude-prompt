---
paths:
  - "**/*.java"
  - "**/*.sql"
---
# 包網商隔離（platformId）

> lion-service 是**包網（白標）平台**：一套系統服務多家**互為競爭對手**的包網商，`platformId` 是租戶鍵（Java + XML 約 6,000 處引用）。
> **A 包網商能看到或改到 B 包網商的任何東西，就是事故**——即使只是唯讀。

---

## 1. 為什麼這條要單獨立一份

這類 bug 有一個很糟的性質：**在單一包網商的測試環境裡 100% 測不出來。** 功能全過、測試全綠，上線才爆。
而 lion 的 CI 根本不跑測試（`-Dmaven.test.skip=true`），所以防線只剩：**寫的人 + reviewer + 至少兩個 platformId 的測試資料**。

---

## 2. platformId 從哪來（紅線）

cp-service 的 `config/CustomWebMvcConfig` 註冊了幾個參數解析器（實作在 lion-common `com.lc.common.resolver`），controller 用參數型別取得身分：

| 參數型別 | 來源 | 可信度 |
|---|---|---|
| `UserIdWithPlatformId`、`TokenInfo` | **登入 token** 解出 | ✅ 已登入情境的唯一可信來源 |
| `PlatformId` | header `x-session-platform-code` 經 `PlatformCodeCache` 換算 | ⚠️ 只代表「請求**自稱**是哪個站」。header 由請求端帶入（是否被前置 nginx 依網域覆寫，本 repo 看不到）→ **在本 repo 內不得當授權依據** |
| 請求 body / query 的 SO 欄位 `platformId` | 請求端任意填 | ❌ 永遠不可信 |

**硬規則：**

1. **已登入的資料存取，platformId 一律取自 token**（`UserIdWithPlatformId` / `TokenInfo`）。
2. `PlatformId`（header 換算）只用於**未登入情境**（登入前的站台設定、公開圖片等）。已登入端點同時拿到兩者時，**以 token 為準，不一致就拒絕**。
3. SO 帶了 `platformId` → 必須與登入者的 platformId **比對（不同就拒絕）或直接覆寫**，不得直接往下傳。
   既有正確寫法：`admin/UserController` 以 `opUser.getPlatformId()` 比對 `updateUserSO.getPlatformId()`。
4. 以 `id` / `orderNo` / `userId` 查單筆資料時，**查詢條件要同時帶 platformId**，或查出後比對歸屬——只憑 id 查等於讓人猜 id 撈別家資料。

---

## 3. 容易漏掉的地方（不只 SQL WHERE）

| 位置 | 要帶 platformId 的是什麼 |
|---|---|
| SQL / DAO 查詢、更新、刪除 | WHERE 條件（含批次更新、軟刪除） |
| Redis key、本地 `CacheService` key | key 組成（否則 A 家寫入的快取被 B 家讀到） |
| ES 查詢 | 查詢條件（ES 6.8 與 7.17 兩套 client 都要） |
| 匯出（`export/`）、報表、分頁列表 | 查詢條件 + 筆數上限 |
| 排程（`job/`）批次 | 迴圈維度：每家各自處理，不可一次撈全部再混算 |
| Kafka（Spring Cloud Stream）事件 | payload 帶 platformId，listener 依它處理 |
| 第三方回調 | 由訂單 / 商戶設定反查歸屬，不信回調參數自報的平台 |

grep 時**不分大小寫**：程式碼裡有 `platformId` / `platform_id` / `PLATFORM_ID`，請求端另有 `platformCode`。

---

## 4. 依設計跨包網商的位置（不算違規，但權限要求更高）

- `/api/manage/**`（總控制中心）、`/api/boss/**`
- cp-service `controller/boss/`、`controller/manage/`、`controller/thirdmanage/`

這些端點本來就看全部包網商，**問題歸「權限夠不夠」而不是「有沒有隔離」**——改它們時重點是確認只有對應角色進得來。
新端點不確定該不該跨平台 → **問使用者**，不要自行決定。

---

## 5. 落到流程上

| 階段 | 動作 |
|---|---|
| spec / plan | 新查詢、新匯出、新快取、新排程 → 在「影響範圍」寫明 platformId 怎麼取、怎麼帶 |
| 測試（L1） | fixture **至少兩個 platformId**，並有「A 的身分查 B 的資料 → 查不到 / 被拒」的案例（`rules/testing.md`） |
| review | 動到上表任何位置 → 必派 `security-reviewer`，執行 `checks/platform-isolation.md` |
| 分級 | 跨 platformId 失守 → **CRITICAL**（即使唯讀）；單平台測不出的隔離問題不得降級 |
