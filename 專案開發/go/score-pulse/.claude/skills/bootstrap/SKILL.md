---
name: bootstrap
description: W1 開工骨架 B-01 ～ B-10——repo 初始化、sp-framework 鎖 tag、三份 profile、可啟動的三角色空殼、docker-compose、migrate、gorm/gen、lint 與 CI、swag、thesports-sim 最小版與框架反壓驗證。第一張 ticket 之前使用；進度寫 plan/dev-bootstrap.md。
---

# bootstrap — W1 開工骨架

**用法：** `/bootstrap`（可指定從某項續跑：`/bootstrap B-05`）

骨架不是 ticket，但沒有它第一張 ticket（S1-T1、S4-T1、S4-T2）驗不了。每項做完把狀態寫進 `plan/dev-bootstrap.md`（表格：編號、完成判準、狀態、日期、備註）。**順序固定**，前一項未過不做下一項。

---

## B-01 · module 與目錄骨架

```bash
go mod init score-pulse && go mod edit -go=1.23
mkdir -p cmd/score-pulse cmd/thesports-sim cmd/gen configs migrations deploy/k8s docs/contract test/{integration,scenario,fixtures/thesports} web/admin
mkdir -p internal/platform/{conf,tenant,auth,apierr,envelope,i18n,rediskey,clock,job}
for p in operator match odds member notify admin collector realtime; do mkdir -p internal/$p/{controller,service,dao,model,dto}; done
mkdir -p internal/inject
```

完成判準：目錄與 `rules/architecture.md` §2 一致；`go build ./...` 通過（空殼）。

## B-02 · sp-framework 鎖 tag（D2a）

```bash
git -C ../sp-framework tag | tail -3                     # 確認維護者已打 tag；沒有 → tech-decisions §6 第 1 項，先回報
go mod edit -require=sp-framework@v0.0.0 \
  -replace=sp-framework=gi88995.kxcodes.com/go-backend/sp-framework.git@<tag>   # 或 GOPRIVATE + 私有模組路徑
go env -w GOPRIVATE='gi88995.kxcodes.com/*'
go mod tidy && go list -m sp-framework
test ! -f go.work || ! grep -q sp-framework go.work || echo "FAIL: go.work 指向同層 checkout"
```

完成判準：`go list -m sp-framework` 印出固定 tag；go.mod 的 replace 指向 tag 不是路徑；無 go.work。

## B-03 · 三份 profile YAML

`configs/application.yaml`（共用）＋ `application_api.yaml`、`application_collector.yaml`、`application_realtime.yaml`。key 一律小寫連字號，機密用 `${ENV}`。

```yaml
# application_api.yaml（節錄）
modules:
  enable-list: [web, mysql, redis, kafka, cache, job]
application: { name: score-pulse, role: api }
kafka:
  brokers: { default-kafka: { brokers: ["${KAFKA_BROKERS}"], replica-factors: 1 } }
  binding:
    producers:
      websocket:    { binder: default-kafka, topic: websocket, partitioner: hash }
      notify-trigger: { binder: default-kafka, topic: notify.trigger, partitioner: hash }
    consumers:
      realtime-core: { binder: default-kafka, topic: match.live, group: sp-realtime-core, partitions: 24, retention-ms: 604800000 }
      realtime-core-odds: { binder: default-kafka, topic: odds.change, group: sp-realtime-core, partitions: 24, retention-ms: 604800000 }
      persist:       { binder: default-kafka, topic: match.live, group: sp-persist, partitions: 24, retention-ms: 604800000 }
      persist-odds:  { binder: default-kafka, topic: odds.change, group: sp-persist, partitions: 24, retention-ms: 604800000 }
      notify:        { binder: default-kafka, topic: notify.trigger, group: sp-notify, partitions: 6, retention-ms: 86400000 }
      monitor:       { binder: default-kafka, topic: source.health, group: sp-monitor, partitions: 3, retention-ms: 86400000 }
# application_realtime.yaml（節錄）
modules: { enable-list: [web, websocket-listener, kafka] }
websocket: { endpoint: /api/ws, kafka-topic: websocket, allow-cross-origin: false, max-connections: 2500, pong-timeout: 30s }
kafka:
  binding:
    consumers:
      websocket: { binder: default-kafka, topic: websocket, latest-offset: true, reset-offset: true, partitions: 12, retention-ms: 600000 }   # 不寫 group → 每實例獨立
```

完成判準：三份檔用 `python3 -c "import yaml,sys;[yaml.safe_load(open(f)) for f in sys.argv[1:]]" configs/*.yaml` 可解析；`thesports.*` 鍵**只**出現在 collector profile（I7）；業務 consumer 都明寫 `group`。

## B-04 · 可啟動的三角色空殼

`cmd/score-pulse/main.go`：讀 profile → 依 `application.role` 選 `inject.API / Collector / Realtime` → `ioc.NewIOC(...).Run()`。`internal/inject/{api,collector,realtime}.go` 只有 `fx.Options`。

```bash
for r in api collector realtime; do (go run ./cmd/score-pulse --active=$r & sleep 5; curl -sf localhost:$(grep -A1 '^web:' configs/application_$r.yaml | grep -o '[0-9]\+')/ping && echo "$r ping ok"; kill %1); done
```

完成判準：三角色各自啟動、`/ping` 回 200、`/metrics` 有輸出；main 無業務邏輯。

## B-05 · docker-compose 與 Dockerfile

`deploy/docker-compose.yml`：mysql 8（utf8mb4_bin、TZ UTC）、redis 7（requirepass）、kafka 3.8 KRaft（單節點、auto-create 關閉由框架建）。`deploy/Dockerfile` 多階段、distroless 或 alpine、`--active` 由環境變數帶。

完成判準：`docker compose -f deploy/docker-compose.yml up -d && docker compose ps` 三者 healthy；`docker build -f deploy/Dockerfile .` 成功。

## B-06 · golang-migrate 與第一支 migration

```bash
go install -tags 'mysql' github.com/golang-migrate/migrate/v4/cmd/migrate@latest
migrate create -ext sql -dir migrations -format 20060102150405 init_operator
migrate -path migrations -database "mysql://$MYSQL_USER:$MYSQL_PASSWORD@tcp($MYSQL_HOST:3306)/$MYSQL_DB" up
```

第一支含 `operator`、`operator_domain`（唯一鍵 `domain` 全平台唯一、不分大小寫）。完成判準：up/down 成對、`migrate version` 正確；兩張表已登記在 `rules/tenant-isolation.md` §2。

## B-07 · gorm/gen

`cmd/gen/main.go` 從 DB schema 產 `internal/<pkg>/model/*.gen.go`（表歸屬照 `rules/architecture.md` §4）。完成判準：`go run ./cmd/gen` 重跑無 diff；model 檔不手改。

## B-08 · lint、Makefile、CI

`.golangci.yml`（errcheck、govet、staticcheck、gocritic、revive、gosec）；`Makefile` 目標：`build test lint integration scenario arch-check contract-export`；`.gitlab-ci.yml` 草案：build → lint → unit → integration（services: mysql/redis/kafka）→ arch-check。

完成判準：`make lint test arch-check` 本機通過；CI 檔可被 `gitlab-ci-lint` 接受（或至少 YAML 合法）。

## B-09 · swag 與契約目錄

```bash
go install github.com/swaggo/swag/cmd/swag@latest
bash .claude/skills/contract-export/contract-export.sh
```

完成判準：`docs/contract/{openapi-front.yaml,openapi-admin.yaml,realtime.md,README.md,ws-client.example.ts,CHANGELOG.md}` 存在（內容可先是骨架）。

## B-10 · thesports-sim 最小版 + 框架反壓驗證

`cmd/thesports-sim`：內嵌 MQTT broker（`github.com/mochi-mqtt/server/v2`）、HTTP stub（gin）、`--scenario <file>` 重放 `test/fixtures/thesports/*.json`。最小版只需重放一個足球比分 fixture。設計要求見 `/sim-scenario`。

**反壓驗證（tech-decisions §6 第 7 項）：** 起 realtime 角色，寫一個只連線不讀取的慢 client，從 api 側灌 10,000 則 push；觀察該連線是否在 `write-timeout` 後被斷、hub 其他連線是否仍正常。

完成判準：模擬器可重放並讓 collector 產出 `match.live`；反壓結果（滿了斷線／阻塞）**回填 `plan/on-sports-lite/tech-decisions.md` §6 第 7 項**；若是阻塞，開一張補充任務在 `internal/realtime` 包一層有界佇列。

---

## 三個基礎包的最小要求（B-04 一併建）

| 包 | 最小內容 |
|----|---------|
| `platform/tenant` | `Operator` 結構、`FromCtx`／`MustFromCtx`、`Scope(ctx)`、Host 解析 middleware（Sort 100，查 `operator_domain` 經 Redis 快取）、gorm callback（租戶表無 `operator_id` 條件 → panic）、租戶表清單常數 |
| `platform/job` | 實作框架 `job.Scheduler` 的 Redis 版（`AcquireLock` 用 `SET NX PX`），並在三角色組裝時注入取代 `EmptyScheduler` |
| `platform/envelope` | `MatchLive`、`OddsChange`、`WsPush` 結構（短欄位名照 `rules/realtime-contract.md` §1.1、§2.4）、`Encode`／`Decode`、`seq` 產生器（Redis `INCR`） |

---

## 回報

`plan/dev-bootstrap.md` 十項全部「完成」後，回覆列出：框架 tag、三角色 ping 結果、反壓驗證結論、尚未到位的外部項目（E1 憑證、第二台 collector IP）。

**下一步執行** `/ticket-run S1-T1`（W1 的根 ticket，總控建立業主）
