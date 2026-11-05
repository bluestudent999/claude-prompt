---
paths:
  - "internal/**"
  - "cmd/**"
  - "configs/**"
  - "go.mod"
---

# 架構：單 binary 多角色 + 功能分包（D3、D3a）

> 本文管的是「程式碼放哪、誰能 import 誰、角色怎麼組裝」。決策的推導在 `plan/on-sports-lite/tech-decisions.md` §2；框架慣例在 `framework-conventions.md`。
> **判準只有一個：單顆 ticket 只碰一兩個功能包；角色切換只改 YAML，不改程式碼。**

---

## 1. 執行拓樸（已決）

```
                 TheSports
          MQTT(wss)  │  HTTP(full/incr)
                     ▼
            ┌─────────────────┐  主備兩實例（Redis 鎖選主），持有憑證（I7）
            │   collector     │  modules: mysql, redis, kafka, job  + MQTT client
            └────────┬────────┘
                     │ Kafka：match.live / odds.change / source.health（key = match_id）
        ┌────────────┼──────────────┐
        ▼                           ▼
┌───────────────┐          ┌────────────────┐
│     api  ×N   │          │  realtime  ×N  │
│ web,mysql,    │ ──────►  │ web,           │  Kafka `websocket` topic（框架扇出，
│ redis,kafka,  │ websocket│ websocket-     │  每實例獨立 group，latest-offset）
│ cache,job     │  topic   │ listener,kafka │
└───┬───────┬───┘          └───────┬────────┘
    │       │                      │ ws（框架協定）
    ▼       ▼                      ▼
 MySQL 8   Redis            H5 / App / 兩套後台（web/admin）
                     ▲
              Nginx + ACME（業主域名 → Host → 業主代碼）
```

`api` 內兩個 Kafka consumer group：

| group | 消費 | 做什麼 | 不做什麼 |
|---|---|---|---|
| `realtime-core` | `match.live`、`odds.change` | compare-and-set 套用（I3）、寫 Redis 快照、合流、發 `websocket` topic、發 `notify.trigger` | 不寫 MySQL |
| `persist` | `match.live`、`odds.change` | 批次落庫、賠率歷史 INSERT（I5）；flush 成功才 commit offset（I9） | 不推送 |

> 兩個 group 消費同一批訊息、各自 commit。`persist` 慢不影響推送。要獨立部署時加一份 `application_persist.yaml`，把 `realtime-core` 從 `api` 拿掉即可。
>
> **任何使用 `inject.API()` 組裝的 profile，`modules.enable-list` 都必須保留 `cache` 與 `web`**：快取登記處（`core/cachereg`，P-27）依賴框架 cache 模組的本地快取清單與 `cache-refresh` emitter，後台路由依賴 web；少了任一個，api 起不來（fail-closed，不是靜默少功能）。

---

## 2. 目錄結構

```
score-pulse/
├── cmd/
│   ├── score-pulse/main.go          唯一的服務 binary；--active=<profile> 選角色
│   ├── thesports-sim/               D13 模擬器（內嵌 MQTT broker + HTTP stub + 情境腳本）
│   └── gen/                         gorm/gen：由 DB schema 產 internal/*/model
├── configs/
│   ├── application.yaml             共用：log、i18n、kafka brokers、redis、mysql（主機與密碼走環境變數）
│   ├── application_api.yaml         modules: web, mysql, redis, kafka, cache, job；consumers: realtime-core, persist, notify
│   ├── application_collector.yaml   modules: mysql, redis, kafka, job；thesports.*（憑證鍵只在這裡）
│   └── application_realtime.yaml    modules: web, websocket-listener, kafka；websocket.*
├── internal/
│   ├── core/                        跨功能共用，不含業務規則（P-19 前名為 platform）
│   │   ├── conf/                    專案自己的設定結構（包框架 BaseConf）
│   │   ├── tenant/                  Host → 業主代碼解析、context 存取、gorm Scope / callback（I1）
│   │   ├── auth/                    後台登入、session、TOTP、權限檢查；會員 token
│   │   ├── apierr/                  錯誤碼表與 response 包裝（api-contract.md §3）
│   │   ├── envelope/                Kafka 訊息封包、WebSocket 訊息結構、seq 與時間戳（realtime-contract.md）
│   │   ├── i18n/                    go-i18n 內嵌檔與資料名稱回退（i18n.md）
│   │   ├── rediskey/                所有 Redis key 的唯一定義處
│   │   ├── cachereg/                快取登記處（本地與 Redis 快取的名稱、說明、刷新；總控「快取管理」頁用，只組裝在 api，P-27）
│   │   ├── clientip/                用戶端 IP 判定：TCP 來源，或可信反向代理覆寫的 `X-Real-IP`（P-29；不用框架與 gin 依標頭算的值）
│   │   └── clock/                   可注入的時鐘（測試用）
│   ├── platform/                    Backlog-1：業主（platform）、域名、品牌、導流、曝光點擊、導流數據
│   ├── match/                       Backlog-2a：賽程、比分、狀態、事件、統計、陣容、媒體 URL、校正覆寫、快照
│   ├── odds/                        Backlog-2b：賠率即時、賠率歷史、走勢、聯賽／球隊／球員／數據頁、榮譽
│   ├── member/                      Backlog-3：會員、登入、簡訊、收藏、設定、搜尋
│   ├── notify/                      Backlog-3：通知設定、觸發比對、站內通知、推播發送、通知中心
│   ├── manage/                      Backlog-4／5：角色權限、帳號、驗證器、操作記錄、熱門內容、重點賽事、監控、App 版本
│   ├── collector/                   D15／D16：MQTT client、HTTP 同步、補齊、停更偵測、主備選主、health 上報
│   ├── realtime/                    D5：訂閱 action、握手檢查、合流、快照讀取（給 realtime 角色與 api 的 realtime-core 共用）
│   └── inject/                      角色組裝：api.go / collector.go / realtime.go（只有 fx.Options，沒有邏輯）
├── migrations/                      golang-migrate SQL（db-migration.md）
├── web/admin/                       Vue 3 兩套後台（web-frontend.md）
├── test/
│   ├── integration/                 docker-compose 起 MySQL／Redis／Kafka 的整合測試
│   └── fixtures/                    雙租戶 fixture、TheSports 錄製回傳
├── deploy/                          Dockerfile、docker-compose.yml（本機中介軟體）、Linux 主機部署設定（D12）
├── docs/contract/                   交付 H5／App 的 OpenAPI 與 realtime 契約（/contract-export 產出）
└── plan/                            企劃三件套、tickets、task plan（企劃的產出，開發只回填）
```

### 功能包內部

```
internal/match/
├── controller/      gin handler（只做：綁參數、呼叫 service、包回應）；每個 handler 一個 *_test.go（testing.md §1）
├── service/         業務規則、不變量、事務邊界；對外只暴露介面
├── dao/             gorm 查詢；租戶表一律經 tenant.Scope；不含業務判斷
├── model/           gorm/gen 產出，不手改
├── dto/             請求／回應結構；swag 註解在這裡
├── consumer/        （有的話）Kafka MessageHandler
├── job/             （有的話）排程 BaseJob
└── inject.go        本包的 fx.Options：Provide 全部 + RegisterRouter / RegisterKafkaConsumer / RegisterJob
```

---

## 3. 依賴方向（硬規則）

```
controller ──► service ──► dao ──► model
     │             │
     └──► dto ◄────┘
```

| 規則 | 說明 |
|------|------|
| **包內**：只能往右依賴 | controller 不碰 dao；dao 不回呼 service |
| **跨功能包**：只能 import 對方的 `service` 介面與 `dto` | 不 import 對方的 `dao`、`model`、`controller`；需要對方資料就呼叫對方 service |
| **`core` 不依賴任何功能包** | 反向依賴 = 設計錯了，把業務規則搬回功能包 |
| **`collector` 不被任何功能包 import** | 它是入口，產出只走 Kafka |
| **`realtime` 不 import `dao`** | 它只讀 Redis 快照與 Kafka |
| **`inject` 只能被 `cmd/score-pulse` import** | 組裝層不是共用庫 |
| **`core` 子包可以提供組裝函式 `XxxOptions() fx.Option`**（裡面可以有 `fx.Provide`、`fx.Invoke`、`web.RegisterRouter` 等 `Register*`） | 只准被 `internal/inject` 引用（例：`auth.RouteGuardOptions()`，P-23）；它只組裝 core 自己的元件、不含業務規則，功能包不得呼叫 |
| **角色邊界** | `collector` 包只在 `inject/collector.go` 組裝；`realtime` 包的訂閱 action 只在 `inject/realtime.go` 組裝；`api` 不載入 MQTT client |

跨包循環依賴時：**抽介面到呼叫方那一側**（consumer 定義它需要的介面），不要抽到 `core`。

---

## 4. 資料歸屬（哪個包擁有哪些表）

| 包 | 擁有的表（寫入權） | 租戶表？ |
|---|---|---|
| platform | `platform`、`platform_domain`、`platform_brand`、`redirect_setting`、`ad_slot`、`ad_material`、`redirect_click`、`redirect_impression`、`visit_log` | 全部是（`platform_code`；`platform` 表本身以 `code` 為租戶鍵） |
| match | `sport`、`league`、`team`、`player`、`season`、`match`、`match_event`、`match_stat`、`match_lineup`、`match_override`、`match_media` | 否（全平台共用） |
| odds | `odds_company`、`odds_live`、`odds_history`（分區）、`honor_map`、`ranking_*` | 否 |
| member | `member`、`member_device`、`member_login`、`sms_record`、`favorite`、`member_setting`、`search_log` | 是 |
| notify | `notice_setting`、`notice`、`push_token`、`push_record` | 是 |
| manage | `admin_info`、`admin_role`、`admin_menu`、`login_log`（後台登入記錄）、`operate_log`（後台操作記錄）、`admin_ip_allow`、`hot_content`、`featured_match`、`source_monitor`、`app_version`（總控與業主後台各自的角色／帳號表以 `scope` 欄區分） | 業主後台帳號是；總控不是 |
| collector | 無（只寫 Redis 與 Kafka） | — |

**一張表只有一個擁有者包能寫。** 其他包要改它 → 呼叫擁有者的 service。

---

## 5. 角色組裝（fx）

```go
// internal/inject/api.go（與現行程式一致；功能包依 ticket 逐一掛進來）
func API() []fx.Option {
    return []fx.Option{
        // core：排程鎖、Host → 業主解析、時鐘、後台安全設定、session store、三個 middleware、後台路由登記表、I1 保險絲、seq 產生器、快取登記處
        job.ProvideScheduler(corejob.NewRedisScheduler),
        fx.Provide(tenant.NewResolver),
        fx.Provide(clock.NewSystem),
        fx.Provide(conf.NewAdminSecurity), // 首位總控超管不在啟動時開通：deploy/sql/seed_first_admin.sql（P-20）
        fx.Provide(fx.Annotate(auth.NewRedisSessionStore, fx.As(new(auth.SessionStore)))),
        web.RegisterMiddleware(tenant.NewMiddleware),      // Sort 100：Host → 業主代碼
        web.RegisterMiddleware(auth.NewSessionMiddleware), // Sort 200
        web.RegisterMiddleware(auth.NewPrincipalBridge),   // Sort 250
        fx.Provide(conf.NewAdminIPAllow),                  // admin.ip-allow.*：可信反向代理（P-29，D25）
        fx.Provide(clientip.NewResolver),
        web.RegisterMiddleware(auth.NewIPAllowMiddleware), // Sort 150：後台 IP 白名單（排在 session 之前，被擋的請求不碰 session）
        auth.RouteGuardOptions(),                          // 後台路由登記表 + 啟動檢查：沒宣告選單代碼的後台路由使服務起不來（P-23，D23）
        fx.Invoke(tenant.RegisterGormCallbacks),           // I1 保險絲
        fx.Provide(envelope.NewSeqGenerator),
        cachereg.Options(),                            // 快取登記處 + 啟動檢查：框架本地快取沒登記使服務起不來（P-27；需要 cache 模組）
        cachereg.Register(tenant.NewDomainCacheEntry), // core 的快取才登記在這裡；功能包的快取在自己的 inject.go 登記（緊鄰 cache.RegisterCache）
        // 功能包
        platform.Options(),
        manage.Options(),
        // match.Options(), odds.Options(), member.Options(), notify.Options(), realtime.Options(),
    }
}
// internal/inject/realtime.go：auth.RouteGuardOptions() + core 的必要 provider + realtime 的訂閱 action、握手
// internal/inject/collector.go：auth.RouteGuardOptions() + core 的必要 provider（Redis 版排程鎖）+ collector
// 三個角色都掛 auth.RouteGuardOptions()：開了 web 模組的角色，任何後台路由誤掛上來都要過同一個啟動檢查；
// 沒開 web 模組的角色（例如日後獨立的 persist profile）沒有 *http.Server、沒有路由，檢查自動略過（D3：換角色只改 YAML）。
```

`cmd/score-pulse/main.go` 只做三件事：讀 profile、依 `application.role` 選 `inject.API / Collector / Realtime`、`ioc.NewIOC(...).Run()`。**main 裡不得有業務邏輯**。

---

## 6. 架構測試（`/arch-check` 跑的）

| 檢查 | 工具 |
|------|------|
| import 方向（§3 全部規則） | `go list -deps` + 腳本比對白名單（`scripts/arch-check.sh`） |
| `internal/` 的頂層目錄只有功能包（§2 的八個）、`core`、`inject`（不在清單的目錄不受 import 方向檢查；P-30 後重建舊總控包目錄即 FAIL） | `find internal -maxdepth 1`（第 1a 項，fail-closed） |
| 禁用依賴：`sp-common`、Ignite、ES、protobuf 對前端、`go.work` 指向同層 | grep |
| 租戶表 dao 都經 `tenant.Scope` | grep `db.Model(&model.<租戶表>` 對照 §4 清單 |
| append-only 表（`odds_history`、`login_log`、`operate_log`、`redirect_click`、`redirect_impression`、`visit_log`）無 UPDATE／DELETE | Go 跨行比對 `model.<M>`／`Table("<t>")` 之後的 `Update(s)`／`UpdateColumn(s)`／`Delete`／`Save`；SQL 去 `--` 註解後以 `;` 切語句比對（含 `ALTER … DROP／TRUNCATE／EXCHANGE PARTITION`）；沒有放行清單 |
| `internal/` 的 `.Raw(`／`.Exec(` 不碰租戶表（保險絲不涵蓋手寫 SQL） | perl 比對字串引數 × `internal/core/tenant/tables.go` 的租戶表清單 |
| `tenant.AllPlatforms`／`ManageRows`／`SelfScope`／`WithPlatform`、`auth.WithPrincipal`／`WithSession` 只在白名單位置（第 15 項為檔案層級、只准直接呼叫，含 `cmd`；`ctxKey`／`ctxSession` 不得別名或轉手；15e：不得宣告任何 `Value` 方法） | grep（第 8～10、15 項） |
| `collector` 包未被 import | `go list -deps ./internal/... \| grep collector` |
| 每個 controller handler 有對應 `_test.go` | 腳本（testing.md §1） |
| 後台選單代碼只增不改：`docs/contract/admin-menu-codes.md` 每列前四欄（代碼｜後台｜選單鍵.頁面鍵｜動作）與 `origin/developing` 最新一筆比，不得刪改、不得重用（第 13 項；push 前先 rebase） | `git show` + 腳本 |
| 後台路由只經 `auth.RouteTable`：提到後台前綴的檔不直接 `web.GET／POST` 或 gin 方法；`internal/` 任何非測試檔（先去掉註解、字串與 rune 字面值）不 `.Use`（含方法值 `u := e.Use`）、不 `.Group(前綴, middleware…)`、不取 `.Group` 方法值、不改寫或索引 `.Handlers`（`= …`、`[i]`；讀取也只准 `internal/core/auth/routes.go`）、不 `.Handler = …`（換掉 http.Server 的 Handler）（白名單 `USE_GROUP_ALLOW` 逐檔寫原因）、不准 `NoRoute`／`NoMethod`（含方法值）（第 14 項） | grep + perl |

每個 ticket 提交前跑一次。新增包或動 import 時必跑。

**啟動時的路由檢查（P-23，D23；不在 `/arch-check`，在服務啟動時）**：`auth.RouteGuardOptions()` 的 `auth.VerifyBackOfficeRoutes` 拿 gin engine 的實際路由逐條比對——每一條可能服務到後台路徑的路由（不分大小寫的 `/api/manage`、`/api/platform` 前綴；P-30（D26）退役的總控段 `/api/admin` 仍視為候選、掛路由即起不來；以及前兩段是萬用字元的 `/:x/manage/…`、`/api/:v/…`、`/*any`）都必須經 `auth.RouteTable` 登記且宣告該後台的選單代碼（或在固定白名單）、所在 group 的 handler 鏈必須**等於** engine 的全域鏈（長度與每個 handler 的函式指標逐一相同：group 另掛、換掉或縮短 middleware，或之後再 `engine.Use` 都會不符）、框架的權限檢查器必須是代碼版；不符 → `fx.New` 失敗、服務起不來。聽埠前的 OnStart 再檢查一次（`app.Start` 失敗、不聽埠）：`*http.Server` 的 Handler 必須仍是框架建的那個 engine，且路由與鏈照上述再比一次——涵蓋 `fx.New` 期間的 Invoke 與排在這個檢查之前的 OnStart 掛上的路由或換掉的 Handler。**不涵蓋**排在檢查之後的 OnStart（web server 建好之後才 Append 的都在聽埠之後才跑）掛上的路由或換掉的 Handler：gin 沒有凍結 engine 的機制，這部分靠 arch-check 第 14 項與 code review。沒開 web 模組的角色沒有路由，檢查略過。`internal/inject/routes_test.go` 以正式的 api 角色組裝驗這件事，arch-check 第 14 項是它的靜態縱深防禦。
