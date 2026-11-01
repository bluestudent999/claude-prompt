# 對外 API 契約（跨部門，不可片面變更）

> H5 與 App 由**另一部門**開發，他們只靠本 repo 交付的契約文件工作。契約破了，他們不會立刻報錯，會在整合測試或上線後才發現；而他們的修正排程不歸我們控制。
> **契約是交付物的一部分**：每顆 A 類 ticket 的 DoD 含「OpenAPI 已更新並可由 `/contract-export` 產出」。

---

## 1. 契約表面

| 表面 | 載體 | 產出方式 | 交付路徑 |
|------|------|---------|---------|
| REST（前台給 H5／App） | OpenAPI 3（swag 註解在 `dto` 與 `controller`） | `swag init` | `docs/contract/openapi-front.yaml` |
| REST（兩套後台給 `web/admin`） | OpenAPI 3 | 同上，另一個 group | `docs/contract/openapi-admin.yaml`（內部，仍要產） |
| WebSocket 與 Kafka 訊息 | `realtime-contract.md` + `docs/contract/realtime.md` | 手寫 + `/contract-export` 檢查欄位對照 `platform/envelope` | `docs/contract/realtime.md` |
| 變更紀錄 | `docs/contract/CHANGELOG.md` | 每次契約變更追加 | 同上 |

路徑前綴固定：前台 `/api/front/**`、業主後台 `/api/operator/**`、總控 `/api/admin/**`、WebSocket `/api/ws`。

---

## 2. 設計規則

| # | 規則 | 為什麼 |
|---|------|--------|
| 1 | 前台 API **對 OQ-63 中立**：不出現「app only」「h5 only」的欄位或端點；來源端由 header `x-client: h5|ios|android` 帶，後端只記錄（Spec-6 R34） | 另一部門還沒決定 App 要不要另做畫面 |
| 2 | 回應一律 `{ "code": 0, "msg": "", "data": ... }`（框架 `response.Object[T]`）；分頁用 `response.Page[T]`（`list`、`total`、`page`、`size`） | 框架既有，client 只寫一種解析 |
| 3 | 錯誤碼是**數字 + 穩定語意**，集中在 `platform/apierr`；`msg` 依 `x-lang` 翻譯；**錯誤碼一旦發布不改語意、不重用號碼** | client 會對錯誤碼寫分支 |
| 4 | 時間一律 **ISO-8601 UTC**（`2026-11-09T08:00:00Z`）；時區換算在 client（Spec-3 R68 時區設定是顯示層） | 一個真相 |
| 5 | id 一律字串化的 int64（JSON 裡是字串），避免 JS 精度問題 | TheSports id 超過 2^53 |
| 6 | 資料名稱（聯賽／球隊／球員）回應**已回退過的單一名稱** + `name_lang` 標明實際語言；不回整包多語 | 回退規則在後端（`i18n.md`），client 不重做 |
| 7 | 列表類端點都有 `page`、`size`（上限 100）；沒有「全部」 | 防打爆 |
| 8 | 即時資料端點（列表、詳情、賠率）讀 **Redis 快照**（I9），回應帶 `seq` 與 `ts`，client 以此接 WebSocket | 首屏與推送要接得上 |
| 9 | 媒體（動畫、GIF、影片）回 `{ "type", "url", "playable" }`，**不回供應商原始結構** | 供應商換格式不波及 client |
| 10 | 匿名可用的端點明確標 `security: []`；需登入的回 401、無權限回 403、租戶外資源回 404（`tenant-isolation.md` §4） | client 對三種狀態各有處理 |

---

## 3. 相容規則與版本

| 變更 | 判定 | 要做什麼 |
|------|------|---------|
| 新增可選欄位、新增端點、新增錯誤碼 | **相容** | CHANGELOG 加一行；不需另一部門配合 |
| 欄位改名、改型別、刪欄位、改語意、錯誤碼改語意、路徑改名 | **破壞性** | **停手**。開 OQ 回報使用者，由使用者與另一部門協調過渡期；過渡期內**雙寫**（新舊欄位並存）或 `/api/front/v2/**` 並行 |
| 限制收緊（上限變小、必填變多） | 破壞性 | 同上 |
| 回應排序改變 | 相容，但要寫進 CHANGELOG | client 可能依賴順序 |

**沒有 `schema_version` 欄位**：REST 以路徑版本（`/api/front/v1/**`）為準，第一期只有 v1。WebSocket 訊息的版本見 `realtime-contract.md`。

---

## 4. 交付流程（C 類工作）

1. ticket 完成 → `/contract-export` 產三份檔到 `docs/contract/`。
2. `contract-reviewer` 比對 diff：相容／破壞性判定、CHANGELOG 是否補。
3. 破壞性 → block，回到 §3。
4. 相容 → commit 一起進版控；回覆裡**明寫「契約有更新：<端點清單>」**，讓使用者轉給另一部門。

另一部門回報「API 不符預期」時：先比對 `docs/contract/` 的版本，**不要**憑口頭描述改 API；確認是契約錯還是對方用錯，前者走本文流程，後者回覆文件位置。

---

## 5. 給另一部門的固定附件（`/contract-export` 一併產）

- `docs/contract/README.md`：環境 URL（測試／正式）、Host 與業主的對應方式、`x-lang` / `x-client` / `x-session-token` 的用法、錯誤碼表、匿名端點清單。
- `docs/contract/realtime.md`：連線、握手、frame 格式、destination 清單、訊息 schema、`seq` 缺口處理、重連退避加 jitter 的建議值。
- `docs/contract/ws-client.example.ts`：約百行的 TypeScript 參考 client（只示範協定，不含 UI）。

這三份不存在或過期 → `contract-reviewer` 判 HIGH。
