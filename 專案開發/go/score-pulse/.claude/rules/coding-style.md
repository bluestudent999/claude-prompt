# Go 風格與例外規範（Go 1.23 + sp-framework）

> 框架怎麼用在 `framework-conventions.md`；本文管「寫得像不像這個專案」：格式、錯誤、context、命名、log、設定鍵、大檔讀取、什麼時候抽介面。

---

## 1. 格式與靜態檢查

| 項目 | 規則 |
|------|------|
| 格式 | `gofmt` + `goimports`（import 分三組：標準庫、第三方、`score-pulse/`）；提交前必跑 |
| lint | `golangci-lint run`，設定在 `.golangci.yml`；**無新問題**才算通過（既有問題不順手修） |
| 啟用的 linter | `errcheck`、`govet`、`staticcheck`、`revive`、`gocyclo`（閾值 15）、`unparam`、`ineffassign`、`unused`、`gosec`（排除測試） |
| 排除 | `*.gen.go`、`docs/`、`web/`、`cmd/thesports-sim/fixtures/` |
| 版本 | `go.mod` 的 `go 1.23`；不用 1.24+ 才有的語法（泛型別名、`testing.B.Loop` 等） |

---

## 2. 錯誤處理

| 規則 | 寫法 |
|------|------|
| 包裝 | `return fmt.Errorf("load match %d: %w", id, err)`；訊息小寫、無句點、含關鍵 id |
| 業務錯誤（handler 可達） | `panic(runtime.BusinessError(apierr.MatchNotFound))`；由框架 recover 轉 HTTP。**只在 service 與 controller 層 panic**，dao 回 error |
| 判斷 | `errors.Is` / `errors.As`；不比較字串 |
| 不吞錯 | 禁止 `_ = f()`、空 `catch`；真的要忽略寫 `//nolint:errcheck // reason` |
| consumer | `AcceptMessage` 回 error = 重試；資料錯誤 log + metric + 回 nil（`framework-conventions.md` §5） |
| gorm | `errors.Is(err, gorm.ErrRecordNotFound)` → 業務 404；其他 → 包裝回傳 |
| 哨兵 | 包級 `var ErrXxx = errors.New(...)` 只給同包與測試用；跨包用 `apierr` 碼 |

---

## 3. context

| 規則 | 說明 |
|------|------|
| 第一參數 | 所有 service、dao、外部呼叫、log 的第一參數是 `ctx context.Context` |
| 必傳 | `log.Info(ctx, ...)`、`db.WithContext(ctx)`、`rdb.Get(ctx, ...)`、`resty ... SetContext(ctx)`；不傳 = trace id 與租戶會丟 |
| 不存進 struct | struct 欄位不放 ctx；長生命週期物件（consumer、job）每次處理從框架拿新的 ctx |
| 取值 | 只透過 `tenant.FromCtx`、`auth.FromCtx`、框架 `constants.*` 鍵；不自己 `ctx.Value("operator")` |
| 逾時 | 外部 HTTP 呼叫 `context.WithTimeout(ctx, 10*time.Second)`；DB 查詢靠連線池逾時，不另包 |

---

## 4. 狀態、數值、時間

| 規則 | 說明 |
|------|------|
| 禁全域可變狀態 | 不用包級 `var cache = map...`；狀態放 struct、由 fx 注入單例。`sync.Once` 初始化的唯讀表可以 |
| 賠率、金額 | `github.com/shopspring/decimal`；JSON 輸出字串；比較用 `.Equal`、`.Cmp` |
| 時間 | 一律 UTC：`time.Now().UTC()` **只透過 `platform/clock.Clock` 注入**（測試可控）；對外毫秒 Unix；DB `DATETIME(3)` |
| id | `int64`；對外 JSON 字串化（`json:",string"` 或 dto 用 `string`） |
| 並發 | 共享 map 用 `sync.RWMutex` 或框架 `cmap`；goroutine 必有退出條件與 `ctx.Done()` 監聽；不裸 `go func()` 在 handler 裡 |

---

## 5. 命名

| 項目 | 規則 | 例 |
|------|------|----|
| 包名 | 小寫單字、不含底線、不重複上層 | `internal/match/service`，不是 `matchservice` |
| 介面 | 以行為命名，不加 `I` 前綴 | `SmsSender`、`PushSender`、`Clock`、`MqttClient` |
| 實作 | 具體名稱 | `TwilioSmsSender`、`FcmPushSender` |
| dto | 請求 `XxxSO`（search object）、回應 `XxxVO`（view object），對齊 sp-config 慣例；Kafka 封包 `envelope.Xxx` | `MatchListSO`、`MatchDetailVO` |
| handler | 動詞 + 名詞 | `GetMatchDetail`、`ListFavorites`、`SubscribeMatch` |
| 測試 | `Test<Subject>_<Case>` | `TestGetMatchDetail_OtherTenant_NotFound` |
| 常數 | 駝峰，不全大寫 | `maxSubscriptionsPerConn` |
| Redis key | 只在 `platform/rediskey` 以函式產生 | `rediskey.MatchSnapshot(id)` |
| 設定鍵 | 小寫連字號、點分層 | `thesports.stall-threshold`、`websocket.max-connections` |

---

## 6. Log

| 規則 | 說明 |
|------|------|
| 英文 | 訊息英文、小寫開頭；中文只出現在業務字串資料裡 |
| 結構化 | `log.Info(ctx, "match applied", log.Int64("match", id), log.String("kind", k))`；不用 `fmt.Sprintf` 拼進訊息 |
| 帶 ctx | 一定帶，trace id 才會出現 |
| 必帶欄位 | 比賽相關 `match`；租戶相關 `operator`；consumer `topic`、`partition`、`offset` |
| 不進 log | TheSports 憑證、session token、簡訊驗證碼、手機號全碼（遮罩後四碼）、推播 token |
| 等級 | `Error` 只給需要人處理的；可預期失敗（429、供應商暫時錯）用 `Warn` + metric |
| 不印整包 | 不 `log.Info(ctx, "msg", log.Any("payload", big))`；印 id 與長度 |

---

## 7. 大檔案讀取策略（Context 硬規則）

| 情境 | 做法 |
|------|------|
| 檔案 > 300 行 | **禁止一次 full read**；先 `grep -n "^func \|^type " <檔>` 建索引，再 `Read(offset, limit)` 讀需要的函式 |
| spec 與 plan | 只讀 ticket 的 Required Spec Sections（`development-workflow.md` Step 0） |
| `*.gen.go` | 不讀；要欄位名 `grep -n "column:" <檔>` |
| 框架原始碼 | `grep -rn "<符號>" $(go env GOMODCACHE)/sp-framework@*/pkg/` 定位後只讀該檔的該段 |
| 測試輸出 | `go test ./... 2>&1 | tail -40`，不要整包餵進 context |

---

## 8. 結構性設計 vs 投機性複雜度

**判準：這個抽象隔離的是哪一個「已知的變動源」？** 答得出來 → 結構性設計，必須有；答不出來 → 投機性複雜度，不要有。

| 必須抽介面（已知會換） | 不抽介面（沒有第二個實作的理由） |
|---|---|
| `SmsSender`（簡訊供應商 P-06 未定，先 mock） | dao：直接具體型別，測試用 docker-compose 的真 MySQL |
| `PushSender`（FCM；中國大陸 Android 可能加廠商通道） | service 之間：具體型別注入；跨包才用介面（`architecture.md` §3） |
| `Clock`（測試控時） | Redis、Kafka 的框架型別 |
| `MqttClient`（paho；模擬器與測試替身） | envelope、dto |
| `MediaResolver`（動畫／GIF／影片三種來源） | 錯誤碼表 |
| 跨功能包的 consumer-side 介面 | 設定讀取 |

| 禁止 | 為什麼 |
|------|--------|
| 為單一實作抽 `XxxRepository` 介面 | 沒有變動源；只增加一層跳轉 |
| Factory／Registry 在介面之上再疊一層 | 介面已是接縫 |
| 為 Out of Scope 鋪路（結算、聊天、第二家資料源、Sportradar、帳號互通） | 留了就會有人來填 |
| 「通用」工具包（`utils`）收納業務函式 | 業務函式回功能包；`platform` 只放跨包且無業務語意的東西 |
| 單一函式超過 gocyclo 15 | 拆函式，不是關 linter |

---

<!-- shared:no-emoji-in-code -->
## 程式碼與設定檔禁止 emoji

| 位置 | 可以用 emoji？ |
|---|---|
| 說明文件（`.md`、`.html`）、企劃書、規格、報告 | ✅ 可以 |
| 前端程式碼 | ✅ 可以 |
| **後端程式碼、腳本** | ❌ **禁止** |
| **程式註解**（任何語言） | ❌ **禁止** |
| **設定檔**（`.yml` / `.yaml` / `.json` / `.properties` / `.xml` / `.sql` / `.env` / `.toml` / `.ini`） | ❌ **禁止** |
| **Log 訊息、例外訊息、CLI 輸出**（寫在程式碼裡的字串） | ❌ **禁止** |

**為什麼：**

| 理由 | 具體會發生什麼 |
|---|---|
| **grep 找不到** | 用 emoji 當標記，別人不知道要搜什麼，鍵盤也打不出來 |
| **編碼會炸** | emoji 是 4 bytes 的 UTF-8。資料庫欄位定序、舊終端機、部分 log 收集器與建置工具會吐錯或顯示成亂碼 |
| **diff 噪音** | 不同編輯器與字型對 emoji 的寬度處理不一致，會產生看不出原因的行變更 |
| **機器要讀** | log 與設定檔是給程式解析的，不是給人看的裝飾 |

**替代寫法**：用文字前綴。`// TODO:`、`// WARNING:`、`// NOTE:`、`[ERROR]`、`[WARN]`、`log.warn("...")` —— 搜得到、打得出來、不會壞。

### 一個例外：emoji 是「資料」的時候

emoji 若是**要比對或要產生的文件內容**，那不是裝飾，是資料，**照留**：

```bash
grep -rl '⏳ 待決' "$PLAN_DIR"          # 對，這在比對 .md 裡的標記
echo "  ✗ $file"                        # 錯，這只是裝飾 → 改成 "  - $file"
```

判準：**把這個 emoji 換成文字，功能會不會壞？** 會壞 → 是資料，留著；不會壞 → 是裝飾，拿掉。
<!-- /shared -->
