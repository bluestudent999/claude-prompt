---
paths:
  - "internal/**/esdao/**"
  - "internal/core/es/**"
  - "internal/core/tenant/**"
  - "internal/platform/**"
  - "internal/odds/**"
  - "internal/match/**"
  - "deploy/**"
  - "configs/**"
  - "docs/contract/**"
  - "test/**"
---

# Elasticsearch 事件與歷史庫（D29）

> 來源：`plan/on-sports-lite/tech-decisions.md` D29（2026-11-06 使用者決定，取代 D6 的「不用 ES」）。執行前置：`tickets/prep/P-32.md`。
> **一句話：** MySQL 存業務實體（會被修改的資料），ES 存**只增不改的事件**與**歷史查詢資料**，Redis 存即時快照。三者分工固定，不要「順便」寫到另一邊。

---

## 1. 哪些資料進 ES（這張表以外的資料一律不進 ES）

| Index（月 index，`<名>_<YYYYMM>_v<版本>`） | 擁有者包 | 租戶？ | `_id` | 月份依據欄位 | 寫入者 | 可覆寫？ | 取代的 MySQL 表 |
|---|---|---|---|---|---|---|---|
| `sp_redirect_click` | platform | **是**（`platform_code`） | 事件 id（api 收到時產生 ULID） | `occurred_at` | api `redirect-sink` consumer | 否 | `redirect_click`（不建） |
| `sp_redirect_impression` | platform | **是** | 事件 id | `occurred_at` | api `redirect-sink` | 否 | `redirect_impression`（不建） |
| `sp_visit_log` | platform | **是** | 事件 id | `occurred_at` | api `redirect-sink` | 否 | `visit_log`（不建） |
| `sp_odds_history` | odds | 否（全平台共用） | `<match_id>:<company_id>:<market>:<stage>:<provider_ts 毫秒>` | `provider_ts` | api `persist`（`odds.change`） | 否 | `odds_history`（不建） |
| `sp_match_history` | match | 否 | `match_id` | 開賽時間 `start_time` | api `persist`（`match.live` 終局狀態與覆寫） | **是**（同 `_id` 整份覆寫，external version） | 無（MySQL `match*` 照舊保留全部比賽） |

- **不進 ES**：`login_log`、`operate_log`（仍是 MySQL，D27）、應用程式日誌、會員與業主等實體資料、`match_stat` 以外的即時資料。要加新 index → 停手，走決策流程改 D29。
- `sp_match_history` 是**完場比賽的歷史文件**：基本資料（球種、聯賽、主客隊 id、開賽時間）、終局狀態、各階段比分、事件、統計（原 2a R26「自存每場完賽統計」併入這裡）。只放 id，不放多語名稱（顯示時由 MySQL／Redis 字典回填，`i18n.md`）。
- 何時寫 `sp_match_history`：比賽進入終局狀態（完場、腰斬、取消）時；之後供應商修正或總控覆寫（I4）該場時再寫一次。用 `version_type=external`、`version = 封包 pv`，舊版本寫入會被 ES 拒絕（等同 I3 的 compare-and-set）。

## 2. 讀取來源（誰讀哪裡）

| 查詢 | 讀哪裡 |
|---|---|
| 即時比分、狀態、事件、賠率的首屏與重連快照 | **Redis**（I9，不變） |
| 比賽列表、比賽詳情（含已完場） | MySQL＋Redis（不變） |
| 跨場的歷史查詢：歷史交鋒、近期戰績、趨勢、進球分佈、完賽統計（S2-T7 等） | **ES `sp_match_history`** |
| 賠率走勢圖、變盤列表、初盤（S2-T21～T23） | **ES `sp_odds_history`** |
| 導流數據頁、M1、匯出（S1-T10、S1-T12、S4-T13、S5-T12） | **ES 導流三個 index** |

## 3. 寫入路徑

### 3.1 導流事件（H5／App → api → Kafka → ES）

1. H5／App 在轉導或曝光時以**非同步請求**打記錄 API（`navigator.sendBeacon` 或 `fetch(..., {keepalive: true})`），**不等回應**再轉導。這是給另一部門的契約，寫進 `docs/contract`（`api-contract.md` §3 雙邊變更流程）。
2. 記錄 API（`/api/front/**`）：業主代碼只由 Host 推導（I1，請求帶的一律忽略）；伺服器產生事件 id 與 `occurred_at`；業主已停用 → 不記錄（I10、Spec-1 R40）；`EmitWithKey(platform_code, ...)` 送進 topic `redirect.event`；**立即回 204**。送 Kafka 失敗 → log + metric，仍回 204（Spec-1 E15：跳轉優先、接受漏計）。
3. **api 不直接寫 ES。** 寫 ES 只在 consumer。

### 3.2 consumer 規則（`redirect-sink`、`persist`）

| 規則 | 說明 |
|---|---|
| 批次 | 累積到 500 筆或 1 秒就 bulk 寫入（數值放 YAML） |
| offset | **bulk 成功才 commit**；ES 連不上、429、5xx = 可重試錯誤 → `AcceptMessage` 回 error（不 commit） |
| 單筆失敗 | mapping 錯誤等資料錯誤 → log + metric + 跳過該筆，**不卡分區**（`framework-conventions.md` §5） |
| 去重 | 一律用 §1 的固定 `_id` 寫入（`op_type=create`；`sp_match_history` 例外用 external version），Kafka 重送不會多一筆 → 維持 I10「每次點擊一筆」 |
| 只存變動 | 賠率只在值有變動時寫（`persist` 比對同鍵上一筆，I5） |

## 4. Index、mapping 與部署

| 項目 | 規則 |
|---|---|
| 客戶端 | `github.com/olivere/elastic/v7`（公司慣例），經 go-framework `pkg/data/elasticsearch/v7_1` 建 client；**只在 `internal/core/es` 建立並以 fx 提供**（`es.Options()`），各包不自建 client |
| 程式位置 | ES 查詢與寫入只在 `internal/<擁有者包>/esdao/`；service 依 interface 呼叫 esdao |
| repository | go-framework `NewMonthIndexRepository`；查詢依時間區間算出 index 清單（`GetIndicesByTimeBetween`），帶 `IgnoreUnavailable`，**一定要帶時間範圍** |
| mapping | `deploy/es/templates/<index>.json` 的 index template（`index_patterns: sp_redirect_click_*` 等），`"dynamic": "strict"`；月 index 由第一筆寫入依 template 自動建立，不需要排程 |
| 套用 | `make es-init`：冪等套用全部 template（部署流程的一步，與 migration 並列） |
| 改 mapping | 已存在的欄位**不改型別**；要改 → 版本號 +1（`_v2`）、新 template、reindex 舊月份，舊版本 index 保留到確認 |
| 保留 | **不刪**：導流（Spec-1 R43）、賠率歷史（2b R12、I5）、歷史賽事都永久保留；不設 ILM 刪除階段；總控監控頁顯示各 index 筆數與大小（`_cat/indices`），取代原本的 MySQL 分區容量 |
| 版本 | Elasticsearch 與 Kibana **7.17.x**（olivere v7 相容） |
| 部署 | `deploy/docker-compose.yml` 加 `elasticsearch`（單節點）與 `kibana`；正式環境 ES 比照 MySQL 獨立主機；開 xpack security（帳密，存環境變數 `SP_ES_*`） |
| Kibana | **只給平台內部**（運維、PM 臨時分析）：只綁內網、要帳密；兩套後台**不嵌入、不連結** Kibana；業主永遠看不到 Kibana |

## 5. 查詢規則

| 規則 | 說明 |
|---|---|
| 租戶過濾（I1） | 導流三個 index 的**每一個查詢**都要經 `tenant.ESScope(ctx)`（從 ctx 取業主代碼產生 `term platform_code` filter；ctx 沒有業主 → panic）；總控查全部業主必須明寫 `tenant.ESAllPlatforms(ctx)`，只准在白名單位置（與 MySQL 的 `tenant.Scope`／`AllPlatforms` 同一套，`tenant-isolation.md`）；總控單一業主經 `auth.ManageTarget` 後照常 `ESScope` |
| 共用 index | `sp_odds_history`、`sp_match_history` 不加業主過濾，也**不得**出現 `platform_code` 欄位 |
| 去重人數要精確 | 到站人數（R26）與 M1（R45）用 **composite aggregation 分頁**算精確去重會員數；**產品查詢禁用 `cardinality`**（近似值，只能在 Kibana 臨時分析用） |
| 分頁 | 列表用 `search_after`，不用深度 `from/size`（> 10000 會失敗） |
| 停用業主 | 歷史數據保留並計入總控匯總（Spec-1 R30），查詢不因業主狀態過濾 |

## 6. 測試（補充 `testing.md`）

| 層 | 怎麼測 |
|---|---|
| service | mock esdao interface（單元） |
| esdao | 整合測試對 compose 的真 ES（`docker compose -f deploy/docker-compose.yml up -d elasticsearch`），測前 `make es-init` 套 template、測後刪測試 index；index 名加測試前綴避免互相污染 |
| consumer | 單元測試用假的 bulk writer：成功 → commit；可重試錯誤 → 回 error 不 commit；壞資料 → 跳過不卡分區；同一事件送兩次 → 只一筆（同 `_id`） |
| 雙租戶（I1） | 導流 esdao 必測：op-a 的查詢取不到 op-b 的事件；總控（`ESAllPlatforms`）看得到兩家；總控 `ManageTarget(op-b)` 只看到 op-b |
| 記錄 API | 回 204 不等 Kafka 以外的任何東西；請求帶 `platformCode` 被忽略；停用業主 → 不送 Kafka |

## 7. P-32 之前（過渡期）

- `scripts/arch-check.sh` 第 2 項仍禁 `olivere/elastic`、`elasticsearch`：**P-32 改腳本之前不要在 `internal/` import ES**，arch-check 會 FAIL。
- 依賴 ES 的 ticket（S1-T8、S1-T10、S1-T12、S2-T7、S2-T20～T23、S4-T13、S5-T12）開工前確認 `tickets/prep/P-32.md` 狀態為「已到位」。

## 8. 看到這些就停手

| 徵兆 | 違反 |
|---|---|
| 建 MySQL 表 `redirect_click`、`redirect_impression`、`visit_log`、`odds_history` | D29 |
| api 的 request handler 直接寫 ES（不經 Kafka consumer） | D29 §3 |
| `internal/core/es`、`internal/*/esdao` 以外 import `olivere/elastic` | D29 §4 |
| 導流 index 的查詢沒經 `tenant.ESScope`／`ESAllPlatforms`；查詢參數接受呼叫端給的業主代碼 | I1 |
| 產品查詢用 `cardinality` 聚合算人數 | D29 §5 |
| 對導流或賠率 index 呼叫 `Update`、`UpdateByQuery`、`Delete`、`DeleteByQuery`、刪 index | I5、I10 |
| template 沒有 `"dynamic": "strict"`；改既有欄位型別 | D29 §4 |
| 兩套後台嵌入或連到 Kibana | D29 §4、I1 |
| 把 §1 以外的資料（登入／操作記錄、應用日誌、會員資料）寫進 ES | D29 §1 |
