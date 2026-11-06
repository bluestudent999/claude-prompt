---
paths:
  - "internal/**"
  - "cmd/**"
  - "migrations/**"
  - "configs/**"
  - "deploy/**"
  - "scripts/**"
  - "web/admin/**"
  - "go.mod"
---

# 已鎖定決策：細節（按需載入）

> 常駐的 `locked-decisions.md` 只放一行索引與不做清單；本檔是每條 D 的完整規格、開發端前置規則、以及長條的停手徵兆。碰到程式碼時自動載入；planner 與 reviewer 需要時 `grep -n "D2[0-9]\|^## " .claude/rules/locked-decisions-detail.md` 後只 Read 那一段。
> 來源與翻案流程同 `locked-decisions.md`。

---

## 二、架構形態被**鎖定**的

| # | 決策 | 規格 |
|---|------|------|
| **D1** | 語言 | **Go**，版本與 go-framework 一致（`go 1.27.3`，2026-11-05 隨 D2 升），不自行升；Dockerfile 與 CI 映像為 golang:1.27.3 |
| **D2** | 框架 | **go-framework**（模組名 `framework`；2026-11-05 取代 sp-framework，缺的機制以只增不改移植進 go-framework，對照表在 go-framework 的 `docs/sp-port/MAPPING.md`）：gin + fx + gorm + go-redis v9 + sarama + gorilla websocket + cron + go-i18n + viper + prometheus + otp。慣例見 `framework-conventions.md` |
| **D2a** | 框架依賴 | （2026-11-06 改，做法同 lion-quest）**go.mod 不寫 framework**；本機、CI、Linux 建置主機都以不進版控的 `go.work`（`use ( . <go-framework 目錄> )`）接入同層 checkout 的 go-framework；**版本記在 `deploy/go-framework.ref`**（40 字元 commit），`scripts/setup-go-work.sh` 依它 clone／checkout 並產生 go.work，`--check` 檢查一致。映像 `make image` 以上一層目錄為 build context、容器內 go.work 編譯（同 lion-quest）。升級框架是一顆明確的 ticket：改 ref 檔、跑完整驗收、與程式碼同一個 commit |
| **D3** | 單 binary 多角色 | `cmd/score-pulse` 一個 binary，`--active=<profile>` 選角色：`api`、`collector`、`realtime`。`api` 內兩個 consumer group：`realtime-core`、`persist`；流量上來時 `persist` 可成第四個 profile，零程式碼改動 |
| **D3a** | 包結構 | **依業務功能分包**：`internal/{platform,match,odds,member,notify,manage,collector,realtime}`，包內 `controller/ service/ dao/ model/ dto/ inject.go`；共用放 `internal/core`（P-19／D20：業主功能包為 `internal/platform`；P-30／D26：總控功能包為 `internal/manage`）。規則見 `architecture.md` |
| **D4** | 訊息 | **Kafka**。業務 topic 以 **`match_id` 當 partition key**；`match.live` **24 個分區**（建立後不改）；業務 topic 保留 **7 天**；`websocket` topic 保留 **10 分鐘**、consumer **`latest-offset: true`**。topic 表見 `realtime-contract.md` |
| **D5** | 即時推送 | 框架 WebSocket 協定；JSON、短欄位名、delta；每場 `seq` 單調遞增；三個時間戳；合流在 `api` 的 `realtime-core` 做一次（離散事件零延遲、賠率與統計 1 秒 Last-Write-Wins）；首屏與重連快照只讀 Redis；心跳 30 秒；**慢連線滿佇列即斷線 —— 框架本身是阻塞語意，由 P-17 的有界佇列層實現**（`framework-conventions.md` §6）；斷線退回 10 秒輪詢 |
| **D6** | 儲存 | **MySQL 8**（gorm + gorm/gen）業務實體主庫；**Redis** 熱狀態、快照、鎖；**Elasticsearch** 存事件與歷史（D29）。賠率歷史改存 ES：只增、只存變動、第一期不刪 |
| **D6a** | Migration | **golang-migrate**，SQL 檔，時間戳版本。規則見 `db-migration.md` |
| **D7** | 多業主 | 單庫，租戶表帶 `platform_code`（業主代碼，D20；系統層級保留 `'0'` 只在後台表 `admin_*`、`login_log`、`operate_log`，D27）；Host → 業主代碼放 context；gorm callback 強制過濾；測試一律雙租戶。規則見 `tenant-isolation.md` |
| **D8** | 後台前端 | **Vue 3 + Element Plus + Pinia + Vite**，兩套後台在本 repo `web/admin/`，共用登入、權限、API client。規則見 `web-frontend.md` |
| **D10** | 外部服務 | 推播 Firebase Go SDK（一專案多 App）；簡訊 provider 介面先接 mock；後台驗證器 TOTP（框架內 otp）；告警郵件 SMTP |
| **D11** | 媒體 | 動畫與 GIF 回 iframe URL 與可播放狀態；影片先驗證 `GET /v1/video/push/stream/list` 在新套餐內可用 |
| **D12** | 設定與部署 | YAML + 環境變數，三角色各一份 profile；Docker 映像跑在 Linux 主機（docker compose，自動重啟），**不用 k8s**；MySQL 為獨立主機；Nginx 反向代理；業主域名 Nginx + ACME |
| **D13** | 第一週工具 | `cmd/thesports-sim`：內嵌 MQTT broker 重放 fixture + HTTP stub。W1 交付，見 `skills/sim-scenario` |
| **D14** | 新增依賴 | MQTT：`github.com/eclipse/paho.mqtt.golang`；lint：golangci-lint；測試：testify + docker-compose；API 文件：swag。**其他第三方相依要在 plan §2 說明理由** |
| **D15** | TheSports 介接 | MQTT over WebSocket（`mq.thesports.com:443`）+ HTTP 全量／增量；賠率即時每 3 秒、60 秒窗口；歷史 30 天內單場補齊。規則見 `thesports-ingest.md` |
| **D16** | collector 高可用 | 主備兩實例、Redis 鎖選主、備機熱待命；套用一律 compare-and-set；每場維護最後收到時間；供應商心跳當全站中斷依據 |
| **D20** | 業主命名與租戶識別 | 業主 = `platform`（表 `platform`、`platform_*`，功能包 `internal/platform`；共用層 `internal/core`）；租戶鍵是字串**業主代碼** `platform_code`（= `platform.code`，建立時由總控輸入、小寫英數與連字號 3～20 字、保留字 `login`、`logout`、`auth`、`admin`、`api`、`manage` 不可用、全平台唯一、**建立後不可改**）；系統層級保留 `'0'` 只在後台表（`admin_*`、`login_log`、`operate_log`，D27）；範圍值總控 `manage`（D26）、業主後台 `platform`；API `/api/platform/**`。執行見 `tickets/prep/P-19.md` |
| **D17** | 可觀測性 | 每則訊息三個時間戳，Prometheus 直方圖出 p95；gateway 連線數、每秒收訊、每秒推送、丟棄慢連線數都是指標；realtime 更新一次一台（Nginx 摘除、等連線轉走再停） |
| **D18** | 後台密碼 | 後台前端送出前算 **MD5**（32 位小寫十六進位），只送 MD5、走 `Authorization: Basic` 標頭；後端只接受 MD5 格式，資料庫存 **bcrypt(MD5)**；密碼規則由前端在設定密碼畫面檢查；MD5 值視同機密不進日誌（2026-11-02 使用者指定，P-18） |
| **D21** | 後台驗證器的發放 | 驗證器密鑰**由系統在新增帳號（及重置驗證器）時產生，只顯示一次給執行的管理者**，由管理者把帳號、密碼、驗證器資訊交給新管理員；**登入一律要求驗證碼，登入流程不提供任何取得密鑰或綁定的步驟**，帳號沒有密鑰就不能登入（40208）。密文附加資料是「範圍＋業主代碼＋帳號」；首位總控超管由 P-20 工具同時產生密碼雜湊與驗證器密文（2026-11-03 使用者決定）。執行見 `tickets/prep/P-21.md` |
| **D22** | migration 基準 | 第一次部署前把既有 migration **一次性整併**成全新環境的基準：一表一支 create（直接是最終結構，不含 rename、ALTER、回填）＋總控內置角色的 seed；舊鏈與新基準在拋棄式資料庫逐表比對等價。整併後恢復「**已套用的 migration 不可改**」，開發者本機刪庫重建；之後的結構變更一律新開 migration（2026-11-03 使用者決定）。執行見 `tickets/prep/P-22.md` |
| **D23** | 後台選單與權限 | 兩套後台的選單**以原型 v1.0.0 為準**（群組 → 選單 → 頁面 → 動作）；權限單位是**頁面 × 動作**（查看、新增、編輯、刪除、審核、**匯出獨立**），每個一個 **8 位數字選單代碼**（總控群組 10～19、業主後台 20～29），定義只在 `internal/core/auth`，**發布後不改語意、不重用**（`docs/contract/admin-menu-codes.md` 只增不改）；角色存勾選的代碼、下級 ⊆ 上級、有效權限每次請求重讀並沿上級交集；**每支後台 API 經 `auth.RouteTable` 宣告所需代碼**（持有任一個即可），伺服器端判定、**fail-closed**（沒宣告又不在白名單、或權限檢查器不是代碼版 → 服務起不來）。執行見 `tickets/prep/P-23.md` |
| **D24** | 總控權限範圍 | **取消「僅指派的業主」**：有總控權限就能操作**所有**業主，人員之間的差別只在角色的頁面權限（D23 選單代碼）；總控指定業主只經 `auth.ManageTarget`；業主後台的業主代碼只來自 session，請求帶的一律忽略（I1）。`is_manage_all`、指派集合、`manageScope` 與依指派範圍過濾的程式全部移除；「負責員工」保留為業務窗口標示、不影響權限（2026-11-03 使用者決定）。執行見 `tickets/prep/P-28.md` |
| **D25** | 後台 IP 白名單 | 兩套後台的**所有 API**（含登入）先過 IP 白名單：總控一份、每位業主各一份，**沒有設定 = 全部拒絕**（總控也是，第一筆由 `deploy/sql/seed_admin_ip_allow.sql` 寫入）；只有總控能新增、刪除（不提供修改；刪除後執行者自己的 IP 不再允許時拒絕）；用戶端 IP 只信任 `admin.ip-allow.trusted-proxies` 內的反向代理帶的 `X-Real-IP`，否則用 TCP 來源；被擋 403／40401、讀不到白名單 503／40402；業主停用不額外擋（Spec-1 R41）。執行見 `tickets/prep/P-29.md` |
| **D26** | 總控命名 | 代表總控的 `admin` 全部改為 **`manage`**：Go 包 `internal/manage`（`manage.Options()`）、API `/api/manage/**`、後台網址 `/manage/**`（登入 `/manage/login`）、`web/admin/src/views/manage/**`、session 與資料庫的 scope 值 `manage`（`auth.ScopeManage`）、`tenant.ManageRows`、`auth.ManageTarget`、選單代碼總表的後台欄（一次性例外，代碼數字不變；arch-check 第 13 項以基準 sha256 鎖定）；資料表只改 `admin_user` → **`admin_info`**。**不改**（兩套後台共用或「管理員」意義）：其他 `admin_*` 表（`admin_role`、`admin_audit`（其後 D27 拆成 `login_log`、`operate_log`）、`admin_ip_allow`）、`web/admin` 目錄、`openapi-admin.yaml`、`admin-menu-codes.md`、設定鍵 `admin.*`、環境變數 `SP_ADMIN_*`、指標 `sp_admin_*`、Redis 前綴 `sp:adm:`、`make dev-admin`。業主保留代碼新增 `manage`（`admin` 仍保留）；舊前綴 `/api/admin` 不留路由（404），啟動檢查仍把它當後台候選（掛路由即起不來）；舊網址 `/admin/**` 與未知網址一樣導到 `/manage`。第一次部署前比照 D22 直接改基準 migration、本機刪庫重建。執行見 `tickets/prep/P-30.md` |
| **D27** | 後台登入與操作記錄分表 | 舊的後台記錄表拆成 **`login_log`**（登入記錄：帳號快照、姓名快照、結果、失敗原因碼、來源 IP（白名單 middleware 判定的值）；**不存**密碼、MD5、驗證碼、session token、User-Agent）與 **`operate_log`**（操作記錄）；兩表都是租戶表（總控列 `platform_code = '0'`、`scope = manage`）、append-only（I10）、按 `created_at` 月分區；登入（含失敗）只寫 `login_log`，工作台「最近操作」與操作記錄只讀 `operate_log`；寫入權只在 `internal/manage`，登入服務只拿得到登入記錄寫入器。第一次部署前比照 D22 直接改基準 migration、本機刪庫重建。執行見 `tickets/prep/P-31.md` |
| **D28** | 總控可改業主專屬域名 | 取消 Spec-1 R6／AC-12 的「總控只看不改」：總控可替任何業主填寫、更換、撤回專屬域名，與業主後台**共用同一個 service 與同一組規則**（格式、全平台唯一、兩態、再改一次、撤回），**不另寫一套總控版規則**；總控 API `/api/manage/platforms/:code/domain`（查看、填寫、`/withdraw`）只認路徑 `:code` 並經 `auth.ManageTarget`＋存在性檢查；業主後台 `/api/platform/domain` 的業主代碼只來自 session；兩邊都以「產品管理 › 域名」查看／編輯選單代碼上鎖（D23）。Spec-1 v1.1、Spec-4 Flow-D step4／R31 已回寫（2026-11-06 使用者決定，S1-T2 實作） |
| **D29** | 事件與歷史資料改存 Elasticsearch | ES 存導流點擊／曝光／訪問（租戶 index，帶 `platform_code`）、賠率歷史、歷史賽事（完場比分、事件、統計；同場一份、external version 覆寫）；不建對應 MySQL 表。寫入：記錄 API 由 Host 推導業主、產生事件 id、送 Kafka `redirect.event` 後立即回 204 → `redirect-sink` consumer 批次寫；賠率與歷史賽事由 `persist` 寫；bulk 成功才 commit offset；固定 `_id` 去重。client 只在 `internal/core/es`，查詢只在 `internal/<包>/esdao`；導流查詢經 `tenant.ESScope`／`ESAllPlatforms`；去重人數用 composite aggregation；strict mapping 在 `deploy/es/templates`、`make es-init`；不刪資料；ES／Kibana 7.17.x，Kibana 只給內部。完整規則 `es-store.md`，執行見 `tickets/prep/P-32.md`（2026-11-06 使用者決定） |

---

## 三、開發端前置（無 D 號）帶進來的鎖定規則

| 前置 | 規則 |
|------|------|
| **P-20** 首位超管用 SQL 建 | **不在 api 啟動時用環境變數建帳號**（`SP_ADMIN_BOOTSTRAP_*`、`admin.bootstrap.*` 已移除）。部署環境用 `make admin-credentials` 產出 `deploy/sql/seed_first_admin.sql`，密碼與驗證器密鑰**只顯示一次**；本機用 `make dev-admin` |
| **P-24** 工作台 | 計數類查詢判不出租戶範圍時**回錯，不是回 0**；`SummaryForManage` 列入 `tenant.AllPlatforms` 函式白名單（arch-check 第 8 項） |
| **P-26** session 上限 | 後台 session 從登入起算最長 **30 分鐘**（`admin.session.max-minutes`，5～720，超出範圍啟動失敗），與閒置時限（`admin.session.idle-minutes`）**任一先到就登出**；Redis session TTL 不得長於剩餘存活時間；監控頁不例外 |
| **P-27** 快取管理 | 快取一律登記到 `internal/core/cachereg`；**沒登記的本地快取讓服務起不來**。用 `inject.API()` 組裝的 profile 必須保留 `cache` 與 `web` 模組；刷新經 `cache-refresh` 廣播到每台 api，並寫操作記錄 |

---

## 四、看到這些就停手（長條，短條在 `locked-decisions.md`）

| 徵兆 | 它違反了 |
|------|---------|
| P-19 前的業主命名重新出現：數字業主 id 欄、舊業主後台 API 前綴、舊業主功能包名（`/api/platform/**`、`platform_code`、`internal/platform` 才對；P-19 §4.7 殘留檢查應無輸出） | D20 |
| 租戶鍵不是 `<鍵> = ?`／`<鍵> IN (?, …)` 綁字串（數字、布林、運算式、函式、NOT、OR 分組…）、租戶表查詢用 `.Or()`／頂層 OR、租戶表 upsert（ON CONFLICT／Save(切片)）、主表是共用表卻 JOIN／Table／Select／手寫子查詢帶進租戶表、ctx 沒有業主卻寫租戶表（未明寫 `tenant.SystemWrite`）、`Raw`／`Exec` 用非字面值或碰租戶表、`database/sql` 出現在 `internal/core` 以外 | D7、D20、I1 |
| 後台路由（`/api/manage/**`、`/api/platform/**`）不經 `auth.RouteTable` 宣告選單代碼就掛上：直接 `web.GET／POST` 或 gin 方法（`.GET`、`.POST`、`.Handle`、`.Any`…）、前兩段是萬用字元的路由（`/:x/manage/…`、`/api/:v/…`、`/*any`）、掛在退役總控段 `/api/admin` 底下的路由（P-30）、`fx.New` 之後才掛的路由、後台路由所在 group 的 handler 鏈被另掛／換掉／縮短，或 `srv.Handler` 被換掉 —— **服務啟動檢查**會擋（未登記／萬用字元路由與 group 鏈在 `fx.New`，group 鏈必須與 engine 全域鏈逐一相同（函式指標）；fx.New 期間的 Invoke 與排在檢查之前的 OnStart 掛的路由、換的 Handler 在聽埠前的 OnStart）；**排在檢查之後（聽埠之後）的 OnStart 掛的路由或換的 Handler 不在涵蓋範圍**；`NoRoute`／`NoMethod`（含方法值）、`internal/` 任何 `.Use`（含方法值）、帶 middleware 引數的 `.Group(` 或 `.Group` 方法值、改寫或讀取 `.Handlers`、`.Handler = …` —— **arch-check 第 14 項**會擋 | D23（P-23）：後台路由一律經 `auth.RouteTable` 宣告選單代碼；middleware 一律經 `web.RegisterMiddleware`；被擋不要繞 |
| 後台 API 加「免 IP 白名單」的例外路徑；以 `X-Forwarded-For`／`X-Real-IP`（未經可信代理判定）、`c.ClientIP()`、`constants.RealClientIp` 判斷授權或白名單 | D25、P-29 |
| P-30 前的總控命名重新出現：重建 `internal/admin`（arch-check 第 1a 項 FAIL）、在 `/api/admin` 掛路由（啟動檢查起不來）、後台網址 `/admin/**`、scope 值 `'admin'`、表 `admin_user`、`ScopeAdmin`／`AdminRows`／`AdminTarget`（`internal/manage`、`/api/manage/**`、`/manage/**`、`manage`、`admin_info`、`ScopeManage`／`ManageRows`／`ManageTarget` 才對；P-30 §4.7 殘留檢查應無輸出） | D26 |
