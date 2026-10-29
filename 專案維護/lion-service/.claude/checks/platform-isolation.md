# Check：包網商隔離（platformId）

> **適用 reviewer**：`security-reviewer`（主）、`business-reviewer`（金額 / 報表 / 排程混算）、`database-reviewer`（SQL 條件）
> **severity**：CRITICAL（跨 platformId 讀或寫，即使唯讀）/ HIGH（隔離正確但缺防呆，例：查出後才比對、無筆數上限）
> **confidence 上限**：需跨檔追 platformId 來源（resolver → service → DAO）→ ≤ 70；單檔可見「SO 的 platformId 直接進查詢」→ 無上限
> **規範**：`rules/platform-isolation.md`

單一包網商的測試環境 100% 測不出這類問題，CI 又不跑測試 —— reviewer 是最後一道防線。

## 1. platformId 取自請求端 → CRITICAL

```bash
# 變更範圍內，SO / Query / 請求參數的 platformId 往下傳
grep -niE '(so|query|param|req|vo)\.getPlatform(Id|Code)\(\)' <file>
# 已登入端點卻用 header 換算的 PlatformId 當資料範圍
grep -nE '\bPlatformId [a-zA-Z]+[,)]' <file>
```

**判定**：

| 寫法 | 判定 |
|---|---|
| SO 的 `platformId` 直接進 DAO / 快取 key / 外部呼叫 | CRITICAL |
| SO 的 `platformId` 先與 token 的 platformId 比對（不同就拒絕）或被覆寫 | ✅ 正確（例：`admin/UserController` 比對 `opUser.getPlatformId()`） |
| 已登入端點以 `PlatformId`（header `x-session-platform-code` 換算）決定資料範圍 | CRITICAL —— header 由請求端帶入，本 repo 內不可信 |
| 未登入端點（登入前站台設定、公開資源）用 `PlatformId` | ✅ 正確用途 |

## 2. 以 id 查單筆但不帶 platformId → CRITICAL

```bash
grep -nE '(getById|selectById|findBy(Id|OrderNo|UserId)|queryBy(Id|OrderNo))' <file>
```

只憑 `id` / `orderNo` / `userId` 查出資料就回傳或修改 → 猜 id 就能撈別家。
**必須**：查詢條件帶 platformId，或查出後比對歸屬（不同就拒絕）。

## 3. 隔離維度漏在 SQL 以外 → CRITICAL / HIGH

| 位置 | 查什麼 | severity |
|---|---|---|
| Redis key、`CacheService` key | key 組成含 platformId（或 key 本身已是 platform 專屬的 id） | 漏 → CRITICAL |
| ES 查詢（6.8 與 7.17 兩套 DAO） | 查詢條件含 platformId | 漏 → CRITICAL |
| 匯出 / 報表 / 分頁列表 | 查詢條件含 platformId；有筆數上限 | 漏 platformId → CRITICAL；無上限 → HIGH |
| 排程（`job/`）批次 | 依 platformId 分批處理；金額 / 統計不跨家混算 | 混算 → CRITICAL |
| Spring Cloud Stream 事件 | payload 帶 platformId，listener 依它處理 | 漏 → HIGH |
| 第三方回調 | 由訂單 / 商戶設定反查歸屬，不信回調自報平台 | 信自報 → CRITICAL |

## 4. 測試沒有第二個 platformId → HIGH

L1 變更的測試 fixture 只有一個 platformId → 隔離根本沒被測到。
**必須**有「A 的身分查 / 改 B 的資料 → 查不到或被拒」的案例（`rules/testing.md`）。

## 反例（不要報）

- `/api/manage/**`、`/api/boss/**`、cp-service `controller/boss/` `controller/manage/` `controller/thirdmanage/`：**依設計跨包網商**。只審「進得來的角色對不對」，不報隔離
- 查詢對象本身是全域資料（系統字典、彩種定義、`GameCodeDictionary`）→ 不需 platformId
- key / id 本身已是某家專屬（例：以 platform 專屬設定表的主鍵當 key）且上游已驗歸屬 → 降為 LOW 附註，不報 CRITICAL

## Fix 方向

- 改用 token 解出的 `UserIdWithPlatformId` / `TokenInfo` 取 platformId
- SO 帶的 platformId：比對後拒絕，或在 service 入口覆寫
- 單筆查詢：WHERE 加 platformId；或查出後 `if (!record.getPlatformId().equals(uid.getPlatformId())) throw ...`
- 快取 / ES / 匯出 / 排程：把 platformId 加進 key、條件或批次維度
