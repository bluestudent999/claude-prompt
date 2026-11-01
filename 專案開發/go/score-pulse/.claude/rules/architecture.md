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
              Nginx + ACME（業主域名 → Host → operator）
```

`api` 內兩個 Kafka consumer group：

| group | 消費 | 做什麼 | 不做什麼 |
|---|---|---|---|
| `realtime-core` | `match.live`、`odds.change` | compare-and-set 套用（I3）、寫 Redis 快照、合流、發 `websocket` topic、發 `notify.trigger` | 不寫 MySQL |
| `persist` | `match.live`、`odds.change` | 批次落庫、賠率歷史 INSERT（I5）；flush 成功才 commit offset（I9） | 不推送 |

> 兩個 group 消費同一批訊息、各自 commit。`persist` 慢不影響推送。要獨立部署時加一份 `application_persist.yaml`，把 `realtime-core` 從 `api` 拿掉即可。

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
│   ├── platform/                    跨功能共用，不含業務規則
│   │   ├── conf/                    專案自己的設定結構（包框架 BaseConf）
│   │   ├── tenant/                  Host → operator 解析、context 存取、gorm Scope / callback（I1）
│   │   ├── auth/                    後台登入、session、TOTP、權限檢查；會員 token
│   │   ├── apierr/                  錯誤碼表與 response 包裝（api-contract.md §3）
│   │   ├── envelope/                Kafka 訊息封包、WebSocket 訊息結構、seq 與時間戳（realtime-contract.md）
│   │   ├── i18n/                    go-i18n 內嵌檔與資料名稱回退（i18n.md）
│   │   ├── rediskey/                所有 Redis key 的唯一定義處
│   │   └── clock/                   可注入的時鐘（測試用）
│   ├── operator/                    Backlog-1：業主、域名、品牌、導流、曝光點擊、導流數據
│   ├── match/                       Backlog-2a：賽程、比分、狀態、事件、統計、陣容、媒體 URL、校正覆寫、快照
│   ├── odds/                        Backlog-2b：賠率即時、賠率歷史、走勢、聯賽／球隊／球員／數據頁、榮譽
│   ├── member/                      Backlog-3：會員、登入、簡訊、收藏、設定、搜尋
│   ├── notify/                      Backlog-3：通知設定、觸發比對、站內通知、推播發送、通知中心
│   ├── admin/                       Backlog-4／5：角色權限、帳號、驗證器、操作記錄、熱門內容、重點賽事、監控、App 版本
│   ├── collector/                   D15／D16：MQTT client、HTTP 同步、補齊、停更偵測、主備選主、health 上報
│   ├── realtime/                    D5：訂閱 action、握手檢查、合流、快照讀取（給 realtime 角色與 api 的 realtime-core 共用）
│   └── inject/                      角色組裝：api.go / collector.go / realtime.go（只有 fx.Options，沒有邏輯）
├── migrations/                      golang-migrate SQL（db-migration.md）
├── web/admin/                       Vue 3 兩套後台（web-frontend.md）
├── test/
│   ├── integration/                 docker-compose 起 MySQL／Redis／Kafka 的整合測試
│   └── fixtures/                    雙租戶 fixture、TheSports 錄製回傳
├── deploy/                          Dockerfile、docker-compose.yml、k8s/
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
| **`platform` 不依賴任何功能包** | 反向依賴 = 設計錯了，把業務規則搬回功能包 |
| **`collector` 不被任何功能包 import** | 它是入口，產出只走 Kafka |
| **`realtime` 不 import `dao`** | 它只讀 Redis 快照與 Kafka |
| **`inject` 只能被 `cmd/score-pulse` import** | 組裝層不是共用庫 |
| **角色邊界** | `collector` 包只在 `inject/collector.go` 組裝；`realtime` 包的訂閱 action 只在 `inject/realtime.go` 組裝；`api` 不載入 MQTT client |

跨包循環依賴時：**抽介面到呼叫方那一側**（consumer 定義它需要的介面），不要抽到 `platform`。

---

## 4. 資料歸屬（哪個包擁有哪些表）

| 包 | 擁有的表（寫入權） | 租戶表？ |
|---|---|---|
| operator | `operator`、`operator_domain`、`operator_brand`、`redirect_setting`、`ad_slot`、`ad_material`、`redirect_click`、`redirect_impression`、`visit_log` | 全部是（`operator_id`） |
| match | `sport`、`league`、`team`、`player`、`season`、`match`、`match_event`、`match_stat`、`match_lineup`、`match_override`、`match_media` | 否（全平台共用） |
| odds | `odds_company`、`odds_live`、`odds_history`（分區）、`honor_map`、`ranking_*` | 否 |
| member | `member`、`member_device`、`member_login`、`sms_record`、`favorite`、`member_setting`、`search_log` | 是 |
| notify | `notice_setting`、`notice`、`push_token`、`push_record` | 是 |
| admin | `admin_user`、`admin_role`、`admin_menu`、`admin_audit`、`hot_content`、`featured_match`、`source_monitor`、`app_version`（總控與業主後台各自的角色／帳號表以 `scope` 欄區分） | 業主後台帳號是；總控不是 |
| collector | 無（只寫 Redis 與 Kafka） | — |

**一張表只有一個擁有者包能寫。** 其他包要改它 → 呼叫擁有者的 service。

---

## 5. 角色組裝（fx）

```go
// internal/inject/api.go
func API(base *conf.BaseConf) []fx.Option {
    return []fx.Option{
        platform.Inject(base),
        operator.Inject(), match.Inject(), odds.Inject(), member.Inject(), notify.Inject(), admin.Inject(),
        realtime.CoreInject(),   // realtime-core consumer + 合流 + 發 websocket topic
    }
}
// internal/inject/realtime.go：platform + realtime.GatewayInject()（訂閱 action、握手）
// internal/inject/collector.go：platform + collector.Inject()
```

`cmd/score-pulse/main.go` 只做三件事：讀 profile、依 `application.role` 選 `inject.API / Collector / Realtime`、`ioc.NewIOC(...).Run()`。**main 裡不得有業務邏輯**。

---

## 6. 架構測試（`/arch-check` 跑的）

| 檢查 | 工具 |
|------|------|
| import 方向（§3 全部規則） | `go list -deps` + 腳本比對白名單（`skills/arch-check`） |
| 禁用依賴：`sp-common`、Ignite、ES、protobuf 對前端、`go.work` 指向同層 | grep |
| 租戶表 dao 都經 `tenant.Scope` | grep `db.Model(&model.<租戶表>` 對照 §4 清單 |
| `odds_history`、`admin_audit`、`redirect_click` 無 UPDATE／DELETE | grep |
| `collector` 包未被 import | `go list -deps ./internal/... \| grep collector` |
| 每個 controller handler 有對應 `_test.go` | 腳本（testing.md §1） |

每個 ticket 提交前跑一次。新增包或動 import 時必跑。
