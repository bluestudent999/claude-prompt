# sp-framework 慣例（AI 最容易寫錯的地方）

> sp-framework 是公司內部 Go 框架：gin + uber fx + gorm + go-redis v9 + sarama + gorilla websocket + robfig/cron + go-i18n + viper + prometheus + zap。
> 它**不是**網路上任何一套教學的寫法。以下每一條都是讀過框架原始碼確認的；**憑印象寫會跑不起來**。
> 不確定時：`grep -rn "<符號>" $(go env GOMODCACHE)/sp-framework@*/pkg/` 看定義，不要猜。

---

## 1. 啟動與模組

| 慣例 | 寫法 |
|------|------|
| 容器 | `ioc.NewIOC(baseInjects, rootInjects).Run()`；`module.GetInjectionsByModule(baseConf, projectInjects)` 依 YAML `modules.enable-list` 組基礎模組 |
| 可用模組名 | `web`、`mysql`、`redis`、`kafka`、`cache`、`job`、`websocket-listener`（依賴 `web`）、`es`、`ignite`、`qqwry`。**本專案只用前七個** |
| 設定 | viper，**key 一律小寫、用連字號**（`kafka.binding.consumers.realtime-core.group`）。大寫 key 讀不到且不報錯 |
| profile | `--active=api` 讀 `application_api.yaml` 疊在 `application.yaml` 上；`--instance=N` 同機多實例 |
| 環境變數 | `BaseConf.GetString(key, default)`；機密以 `${ENV_NAME}` 寫在 YAML、由 BaseConf 展開，**不要在程式碼 `os.Getenv`** |
| 自訂啟動參數 | `conf.NewBaseConfWithCommand(yaml, activeYaml, profile, conf.CommandParam{Name:"role", Type:"string", ...})` |

---

## 2. 依賴注入（fx）

```go
// 參數物件必須是具名 struct 並內嵌 fx.In；欄位必須是「被 Provide 過的具體型別或介面」
type MatchServiceArgs struct {
    fx.In
    MatchDao   *dao.MatchDao
    Snapshot   *cache.SnapshotCache
    Emitter    *WsEmitter          // 具體型別
}
type MatchService struct{ args *MatchServiceArgs }   // 存指標，避免「bad result … embeds a dig.In」
func NewMatchService(args MatchServiceArgs) *MatchService { return &MatchService{args: &args} }
```

| 坑 | 正確做法 |
|----|---------|
| 回傳含 `fx.In` 的 struct 當結果 | 回傳自己的 struct，`fx.In` 只能在參數 |
| 一個 constructor Provide 兩次 | 用 `fx.Annotate(ctor, fx.As(new(Iface)), fx.ResultTags(`group:"x"`))` 另註冊介面版本；框架大量用「`NewXxx` + `NewXxxAsInterface`」成對 |
| 要被收集成清單的元件（Router、Middleware、MessageHandler、ProducerEmitter、BaseJob、WebSocketSubscriptionAction） | **必須用框架的 Register 函式**：`web.RegisterRouter`、`web.RegisterMiddleware`、`message.RegisterKafkaConsumer`、`message.RegisterKafkaProducer`、`job.RegisterJob`、`wss.RegisterWebsocketSubscribe`。自己 `fx.Provide` 不會進清單 |
| 想在啟動時跑一段 | `fx.Invoke(func(x *X){})` 放進 rootInjects；不要在 `init()` 做 I/O |
| 循環依賴 | fx 啟動時 panic。拆介面到呼叫方（`architecture.md` §3） |

---

## 3. Web（gin）

| 慣例 | 寫法 |
|------|------|
| Router | 實作 `web.Router` 介面：`Handle(engine *gin.Engine)`；用 `web.RegisterRouter(NewXxxRouter)` |
| Handler 簽名 | 框架 `web.ContextWrapper` + 綁定好的 DTO，回傳 `*response.Object[T]`／`*response.Page[T]`；由 `web.Wrap(handler, web.HandlerMeta{Permissions: []string{...}})` 轉成 gin HandlerFunc |
| 綁參數 | `wrapper.Bind(&so)`（query/form）、`wrapper.BindBody(&so)`（JSON）；驗證用 `validator` tag |
| Middleware | 實作 `web.Middleware`：`HandlerFunc(c *gin.Context)` + `Sort() int`；**數字小先跑**。本專案固定：100 tenant、200 auth、300 lang-override、900 audit |
| 錯誤流程 | **`panic(runtime.BusinessError(errCode, args...))`**，由框架 `RecoverMiddleware` 轉成 HTTP 回應。**不要 `return err` 到 handler 外**；不要自己 `c.JSON(400, ...)` |
| 錯誤碼 | `*dto.ErrorCode{Code, Msg}`，集中在 `internal/platform/apierr`；Msg 是 i18n key 的 default |
| 其他錯誤建構子 | `runtime.ParameterError()`、`InvalidParameterError(msg)`、`UnauthorizedError()`、`PermissionError(msg)`、`TooManyRequestError()` |
| context 值 | 框架已放：`constants.TraceId`、`constants.HeaderLang`（`x-lang`）、`constants.RealClientIp`。本專案再放：`tenant.CtxOperator`、`auth.CtxPrincipal` |
| 標頭常數 | `x-lang`、`x-trace-id`、`x-session-token`、`x-session-platform-code`（本專案**不用** platform-code，業主由 Host 決定） |
| Ping／metrics | 框架自帶 `web.ping-path` 與 `/metrics`（`web.metrics.enabled`）；不要自己再寫 |
| CORS | `web.allow-cors` 是全開，**prod 關掉**，由 Nginx 處理 |

---

## 4. 資料（gorm / redis）

| 慣例 | 寫法 |
|------|------|
| 取 DB | 注入 `*mysql.DataSources`，`ds.SelectDefault()` 回 `*gorm.DB`；多資料源用 `SelectByName` |
| 讀寫分離 | 框架 `dbresolver`：YAML 寫 `master` + `replicas`，gorm 自動分流；**寫後立即讀用 `db.Clauses(dbresolver.Write)`** |
| 事務 | `mysql.Transactional(ctx, ds, func(tx *gorm.DB) error {...})`（框架 `transactional.go`）；service 層開，dao 層不開 |
| model | `cmd/gen` 用 gorm/gen 產 `*.gen.go`，**不手改**；要加方法寫在同包另一個檔 |
| 租戶表 | dao 查詢一律 `db.Scopes(tenant.Scope(ctx))`（`tenant-isolation.md`） |
| Redis | 注入 `*v9.RedisDataSources`，`SelectDefault()` 回 `*redis.Client`；key 只能用 `platform/rediskey` 的函式產生 |
| 本地快取 | 實作 `cache.AbstractCache` 並用 `fx.ResultTags(`group:"cache"`)` 註冊；失效靠 `cache` 模組的 Kafka 廣播（`cache.kafka-topic`） |
| 時間 | DB 與 Redis 一律 UTC；YAML `mysql.locale` 不要改 |
| 金額／賠率 | `shopspring/decimal`，不用 float64 |

---

## 5. Kafka

```go
// 生產者：實作 kafka.ProducerEmitter（內嵌 kafka.AbstractProducerEmitter），Name() 必須等於 YAML 的 producers 鍵
type MatchLiveEmitter struct{ kafka.AbstractProducerEmitter }
func (e *MatchLiveEmitter) Name() string { return "match-live" }
func (e *MatchLiveEmitter) Send(matchID int64, env *envelope.MatchLive) { e.EmitWithKey(strconv.FormatInt(matchID, 10), env) }
// 註冊：message.RegisterKafkaProducer(NewMatchLiveEmitter, NewMatchLiveEmitterAsInterface)

// 消費者：實作 kafka.MessageHandler，Name() 必須等於 YAML 的 consumers 鍵
func (h *RealtimeCoreHandler) Name() string { return "realtime-core" }
func (h *RealtimeCoreHandler) AcceptMessage(ctx context.Context, msg *sarama.ConsumerMessage) error { ... }
// 註冊：message.RegisterKafkaConsumer(NewRealtimeCoreHandler)
```

| 坑 | 說明 |
|----|------|
| `Name()` 與 YAML 鍵對不上 | 啟動 `log.Fatal`：「kafka producer not exists」。鍵一律小寫連字號 |
| 分區 key | **`EmitWithKey(matchID, ...)`**，不要 `Emit`（隨機分區會破壞 I2） |
| 序列化 | 框架 `SerializationHandler` 用 sonic JSON；訊息結構放 `platform/envelope`，欄位用短名（`realtime-contract.md`） |
| 回傳 error | `AcceptMessage` 回 error = **不 commit、重試**。只有「可重試的基礎設施錯誤」才回 error；資料錯誤要 log + metric + 回 nil，否則卡死分區 |
| offset | `persist` group：批次 flush 成功後才回 nil（I9）。`websocket` consumer：YAML `latest-offset: true` + `reset-offset: true` |
| 預設 group | 不設 `group` 時框架用 `GetUniqName()`（主機名 + 實例號）= **每實例獨立**，這正是 realtime 扇出要的；業務 consumer **一定要明寫 group** |
| topic 自動建立 | 框架啟動時依 consumer 設定建 topic，**分區數與保留期由 YAML 指定**（`match.live` 24 分區、7 天；`websocket` 10 分鐘） |

---

## 6. WebSocket（realtime 角色）

| 慣例 | 寫法 |
|------|------|
| 協定 | 二進位 frame：第 1 byte opcode（client `0` ping、`S` subscribe、`U` unsubscribe、`M` message；server `1` pong、`p` push、`e` error），第 2 byte destination 長度，接 destination，接 payload |
| 訂閱 action | 實作 `wss.WebSocketSubscriptionAction`：`SubscribePath() string`（支援 `$param` 樣式）+ `Subscribe(params map[string]string, body []byte) ([]byte, error)`；回傳的 `[]byte` 是**訂閱當下的快照**（從 Redis 讀，I9）。用 `wss.RegisterWebsocketSubscribe` |
| 握手 | 實作 `wss.HandshakeHandler`，用 `wss.RegisterHandshakeHandler`；在這裡做 Host → operator、Origin 白名單、每 IP 連線數（D7） |
| 推送 | `api` 側注入 `*wss.WebSocketEmitter`，`SendWsMessage(&wss.WebsocketMessage{Destinations: []string{...}, Data: json})`；realtime 側由框架 `WebsocketListener` 收 Kafka 後 `NotifyByDestination` |
| 連線上限 | `websocket.max-connections`（預設 2500／實例）；`websocket.pong-timeout` 30 秒；`websocket.write-timeout` 2 秒 |
| 跨域 | `websocket.allow-cross-origin` 預設 **true**，prod 改 false 並在握手檢 Origin |
| 反壓 | 待驗證（tech-decisions §6 第 7 項）：框架每連線寫入是否有界、滿了是否斷線。bootstrap 時驗，不是就在 `internal/realtime` 包一層 |

---

## 7. 排程（job）

| 慣例 | 寫法 |
|------|------|
| Job | 內嵌 `*job.AbstractJob`，實作 `Name()`、`Cron()`（6 欄，含秒）、`Execute(ctx, *job.Task) error`；`Partition()` 預設 1 |
| 分散式鎖 | 框架 `Scheduler` 介面；預設 `EmptyScheduler`（**不鎖**）。本專案 `collector` 與 `api` 都多實例，**必須注入 Redis 版 Scheduler**（`platform/job`），否則排程每台都跑 |
| 註冊 | `job.RegisterJob(NewXxxJob)`；`job.namespace` 用角色名 |

---

## 8. i18n、log、監控

| 慣例 | 寫法 |
|------|------|
| i18n | `i18n.InitBundle(embedFS)` 載 `<lang>.json`；取字串 `i18n.LoadByLang(lang, &i18n.Index{Prefix, Key, Default, Args})`；語言從 context 的 `x-lang` 取。語言碼用框架常數：`zh`、`en`、`vi`、`tl`（繁中本專案自訂 `zht`，見 `i18n.md`） |
| log | `log.Info(ctx, "msg {}", log.String("k", v))`；**一定帶 ctx**（trace id 才會出現）；敏感值不進 log（I7） |
| metrics | `web.metrics.enabled: true` 自動暴露；自訂指標用 `prometheus/client_golang` 註冊到預設 registry |
| 錯誤型別 | `runtime.CustomError{ErrType, Status, Code, DefaultMsg}`；判斷用 `errors.As` |

---

## 9. 一眼就知道寫錯的樣子

| 看到 | 代表 |
|------|------|
| `gin.Default()`、`r := gin.New()` 在業務包 | 沒走框架 Router 介面 |
| `c.JSON(http.StatusBadRequest, ...)` | 沒走 panic 錯誤流程 |
| `os.Getenv(` 在 `internal/` | 設定沒走 BaseConf |
| `sarama.NewSyncProducer(` | 沒走框架 emitter |
| `gorm.Open(` 在 `internal/` | 沒走 DataSources |
| `redis.NewClient(` 在 `internal/` | 同上 |
| `websocket.Upgrader{` 在業務包 | 沒走框架 wss |
| `cron.New(` | 沒走框架 job |
| `float64` 存賠率 | 用 decimal |
| handler 沒有 `_test.go` | 違反 testing.md §1 |
