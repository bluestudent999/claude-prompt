# score-pulse 開發範本 — 使用指南

> 一句話定位：**讓 Claude 在 score-pulse 上做 On 體育網精簡版的後端 API 與兩套後台，守住四條線**——租戶隔離、單場順序與冪等、賠率歷史只增不刪、對另一部門的契約不片面改。
> 技術棧：Go 1.23 + sp-framework｜MySQL 8 + Redis + Kafka｜後台前端 Vue 3 + Element Plus + Pinia。**H5 與 App 畫面不在本 repo。**

---

## 部署

```bash
cd ~/workspace/score-pulse         # 換成你本機 score-pulse 的 clone 路徑
prompt-setup 專案開發 go score-pulse --force
claude
```

**部署前必知：**

1. `.claude/` 與根 `CLAUDE.md` **不進版控**（score-pulse 的 `.gitignore` 已排除）。hook `block-claude-dir-staging.sh` 會擋 `git add -A` / `git add .` / `git add .claude`。
2. 同一個 repo 裡 **PM 在自己機器上保留企劃範本**（`prompt-setup 專案企劃`），開發者部署本範本，互不干擾。`--force` 只清你本機的 `.claude/`。
3. 企劃產出全在 `plan/on-sports-lite/`，**是版控的一部分**。本範本只回填 `plan/task-*-plan.md` 與 ticket 的狀態欄，不改 spec。

---

## 前置條件

| 項目 | 檢查 |
|------|------|
| Go 1.23+ | `go version` |
| Docker（MySQL 8 / Redis 7 / Kafka 3.8 KRaft） | `docker compose version` |
| golangci-lint | `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest` |
| golang-migrate（mysql tag） | `go install -tags 'mysql' github.com/golang-migrate/migrate/v4/cmd/migrate@latest` |
| swag | `go install github.com/swaggo/swag/cmd/swag@latest` |
| Node 20（web/admin） | `node -v` |
| sp-framework tag 可解析 | `go env -w GOPRIVATE='gi88995.kxcodes.com/*'`；`go list -m sp-framework` 印出固定 tag |
| 本機設定 | `cp .claude/settings.local.json.example .claude/settings.local.json` 並填值；`THESPORTS_*` 只給 collector |

---

## 快速開始

```
/bootstrap                 ← W1 骨架 B-01 ~ B-10（module、框架 tag、三份 profile、三角色空殼、compose、migrate、gen、lint/CI、swag、thesports-sim + 反壓驗證）
/ticket-run S1-T1          ← 執行一張 ticket：讀 ticket → planner → 實作 → 驗收 → 審查 → 回填
/arch-check                ← 依賴方向、禁用相依、租戶 Scope、append-only、每個 handler 有測試
/tenant-check              ← 動到租戶表時的過濾盤點
/contract-export           ← 產 OpenAPI 與 realtime 契約、判斷契約是否變更
/sim-scenario              ← thesports-sim 情境腳本（順序、回退、停更、中斷、賠率、p95）
/db-migrate <name>         ← 建 migration、判租戶表、重產 model、驗證器
/vue3-console              ← 後台前端開工程序（防 Vue 2 混入、三態、權限）
/strategic-compact         ← 一張 ticket 做完後壓縮 context
```

直接說「做 S2-T8」也可以，Claude 會走同一套流程。

### 三類工作

| 類 | 認法 | 驗收 |
|----|------|------|
| **A · 後端 API** | ticket 主責後端；或主責前端但畫面在 H5／App（只做後端部分） | AC + **每個 API 的單元測試** + 不變量測試 |
| **B · 後台前端** | 畫面在總控或業主後台（`web/admin`） | AC + 畫面三態 + 後端 API 測試 |
| **C · 契約交付** | 動到 `/api/front/**`、WebSocket、Kafka 封包 | `/contract-export` + `contract-reviewer` |

---

## 架構一頁圖

```
                 TheSports
          MQTT(wss)  |  HTTP(full/incr)
                     v
            +-----------------+  主備兩實例（Redis 鎖選主），持有憑證（I7）
            |   collector     |  modules: mysql, redis, kafka, job + MQTT client
            +--------+--------+
                     | Kafka：match.live / odds.change / source.health（key = match_id）
        +------------+--------------+
        v                           v
+---------------+          +----------------+
|     api  xN   |          |  realtime  xN  |
| web,mysql,    | -------> | web,           |  Kafka websocket topic（框架扇出，
| redis,kafka,  | websocket| websocket-     |  每實例獨立 group，latest-offset）
| cache,job     |  topic   | listener,kafka |
+---+-------+---+          +-------+--------+
    |       |                      | ws（框架協定）
    v       v                      v
 MySQL 8   Redis            H5 / App / 兩套後台（web/admin）
                     ^
              Nginx + ACME（業主域名 -> Host -> operator）
```

**同一個 binary**（`cmd/score-pulse --active=<api|collector|realtime>`），角色只差 YAML 的 `modules.enable-list`。`api` 內兩個 consumer group：`realtime-core`（套用、快照、合流、推送）與 `persist`（批次落庫、賠率歷史）。推導見 `plan/on-sports-lite/tech-decisions.md`。

---

## 目錄結構

```
.claude/
├── CLAUDE.md                  ticket 驅動運作模式、三類工作、路由表、指路、紅線、提交前固定動作
├── README.md                  本檔
├── settings.json              權限、SessionStart 提醒、OQ 與 .claude 攔截 hook、Stop 跑 arch-check、autoMode
├── settings.local.json.example 本機環境變數範本
├── rules/
│   ├── development-workflow.md  Preflight → 讀 ticket → planner → 實作 → 驗收 → 審查 → 回填
│   ├── locked-decisions.md      D1~D17 執行版 + 不做清單 + 「看到這些就停手」
│   ├── invariants.md            10 條不變量與驗證方式
│   ├── architecture.md          單 binary 多角色、功能分包、依賴方向、表歸屬、fx 組裝
│   ├── framework-conventions.md sp-framework 慣例（panic 錯誤流程、fx.In、YAML 小寫、Name() 對 YAML、EmitWithKey）
│   ├── tenant-isolation.md      Host → operator、gorm Scope/callback、租戶表清單、雙租戶測試
│   ├── api-contract.md          OpenAPI、錯誤格式、相容規則、交付另一部門的流程
│   ├── realtime-contract.md     Kafka topics、封包短名、WebSocket frame/destination、合流、SLO
│   ├── thesports-ingest.md      MQTT/HTTP 接入、補齊、停更與中斷偵測、主備
│   ├── i18n.md                  資料名稱回退、分類名稱自譯、通知與簡訊 5 語系、後台只中文
│   ├── db-migration.md          golang-migrate、時間戳、分區、gen 重產
│   ├── coding-style.md          Go 風格、error wrapping、context、decimal、UTC、log
│   ├── testing.md               每個 API 必有單元測試、雙租戶 fixture、模擬器、AC 對映、DoD 七條
│   ├── web-frontend.md          Vue 3 + Element Plus + Pinia、防 Vue 2、三態、權限
│   └── git-workflow.md          分支、Conventional Commits、測試分支單向流動
├── agents/                    planner、code-reviewer、arch-guard、tenant-isolation-reviewer、
│                              contract-reviewer、data-pipeline-reviewer、web-reviewer、build-error-resolver
├── skills/                    ticket-run、bootstrap、arch-check、tenant-check、contract-export、
│                              sim-scenario、db-migrate、vue3-console、strategic-compact
└── hooks/                     check-oq-on-commit、check-oq-pending-session、block-claude-dir-staging
```

---

## 第一週該做什麼（2026-11-09 開工）

1. **`/bootstrap` B-01 ～ B-10**（約 3 人日，含 thesports-sim 最小版與框架反壓驗證）。十項全綠前不開 ticket。
2. **W1 的 ticket**（總計畫 §3）：
   | ticket | 本 repo 做什麼 |
   |---|---|
   | S1-T1 總控建立業主 | A + B（總控畫面） |
   | S4-T1 角色與權限 | A + B（兩套後台） |
   | S4-T2 帳號與驗證器 | A + B |
   | S3-T5 設定項（語言、賠率格式、時區、日夜） | **只做後端**（偏好儲存 API）；畫面在另一部門 |
   | S6-T1 App 殼、S6-T7 H5 下載提示條 | **不在本 repo** |
3. **外部等待**：E1 TheSports 憑證（用模擬器先做）、第二台 collector IP 進白名單、sp-framework tag（B-02 前要有）。

---

## 跨部門契約怎麼交付

1. A 類 ticket 動到 `/api/front/**` 或 WebSocket → `/contract-export` 產 `docs/contract/{openapi-front.yaml,realtime.md,README.md,ws-client.example.ts,CHANGELOG.md}`。
2. `contract-reviewer` 判相容／破壞性；破壞性停手、開 OQ 讓使用者協調過渡期。
3. 與程式碼同一個 commit；回覆裡寫「契約有更新：<端點清單>」，使用者轉給 H5／App 部門。
4. 另一部門回報不符 → 先比對 `docs/contract/` 版本，不憑口頭改 API。

另一部門的 OQ（OQ-63 App 沿用 H5 或另做、OQ-62 媒體能否在 App 播、OQ-32a 哪些瀏覽器支援推播）**不由本 repo 回答**，API 對它們保持中立。

---

## 常見問題

| 問題 | 答 |
|------|----|
| ticket 的「前端」分工要不要做？ | 看畫面在哪：總控／業主後台 → 做（B 類）；H5／App → 不做，plan §0 標「畫面：另一部門」 |
| spec 有錯或 AC 不合理 | 列 OQ 標明屬企劃職責，提示使用者切 `prompt-setup 專案企劃`；本 repo 不改 spec |
| `_generate.py` 重跑把我回填的 ticket 狀態洗掉了 | 已知，PM 要改腳本；**plan 檔 §8 是進度真相** |
| 框架有 bug | 先繞過（在 `platform` 包一層），開一張補充任務記錄；不自行升級框架版本（D2a） |
| 想用 Redis Pub/Sub、protobuf、動態訂閱 | 第一期不做，各有量測觸發點（`rules/locked-decisions.md` D4、D5） |
| 想拆 persist 成獨立部署 | 加一份 `application_persist.yaml` 即可，零程式碼改動（`rules/architecture.md` §1） |
| TheSports 憑證還沒來 | `cmd/thesports-sim` 重放 fixture；plan §8 標 `待外部：E1` |
| 後台前端要多語系嗎 | 不要，後台只做中文（dept-assignment 預設 1） |
