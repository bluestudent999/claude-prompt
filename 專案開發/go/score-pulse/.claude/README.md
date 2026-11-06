# score-pulse 開發範本 — 使用指南

> 一句話定位：**讓 Claude 在 score-pulse 上做 On 體育網精簡版的後端 API 與兩套後台，守住四條線**——租戶隔離、單場順序與冪等、賠率歷史只增不刪、對另一部門的契約不片面改。
> 技術棧：Go 1.27.3 + go-framework｜MySQL 8 + Redis + Kafka + Elasticsearch／Kibana（D29）｜後台前端 Vue 3 + Element Plus + Pinia。**H5 與 App 畫面不在本 repo。**

---

## 部署

```bash
cd ~/workspace/score-pulse         # 換成你本機 score-pulse 的 clone 路徑
git switch developing && git pull --ff-only  # 範本已在版控裡，拉下來就有
claude
```

**範本庫與 repo 的關係：** 本目錄（`claude-prompt/專案開發/go/score-pulse/.claude`）是 score-pulse repo 內 `.claude/` 的**鏡像**，以 repo 為準。要把範本庫的改動帶進 repo：在 feature 分支把檔案複製過去（`.claude/CLAUDE.md` 放到 repo 根目錄 `CLAUDE.md`），另開 `chore(deploy): - ...` commit 走 MR；**不要用 `prompt-setup ... --force`**。repo 裡改了範本，也要同步回這裡（2026-11-04 已同步到 P-31）。

**必知：**

1. 自 2026-11-02 起，`.claude/` 與根 `CLAUDE.md` **隨 score-pulse 進版控**：clone 專案、切到 `developing` 即取得本範本，**不需要再跑 `prompt-setup`**。只排除 `.claude/settings.local.json`（複製 `.example` 填本機值）與 `.claude/worktrees/`。`hooks/git-guard.sh` 會擋在 `main`／`developing` 上 commit、push 到 main、從 main 切分支，以及在 `developing` 上做 `--no-ff` 合併 feature 分支以外的 merge 與改寫歷史的動作。
2. **PM 部署企劃範本**（`prompt-setup 專案企劃`）會覆蓋版控中的 `.claude/` 與 `CLAUDE.md`：不得提交這些改動，建議 PM 另開一份 clone 專做企劃。不要再對開發者的工作目錄執行 `prompt-setup ... --force`，它會清掉版控中的範本（可用 `git checkout -- .claude CLAUDE.md` 復原）。
3. 企劃產出全在 `plan/on-sports-lite/`，**是版控的一部分**。本範本只回填 `plan/task-*-plan.md` 與 ticket 的狀態欄，不改 spec。

---

> **分支**：部署範本不影響分支。開工前先 `git fetch origin && git switch -c feature/<ticket-id>-<slug> origin/developing`；`main` 鎖定、`developing` 不直接 commit，只收 MR 或本機 `--no-ff` 合併 feature 分支（`rules/git-workflow.md` §1；2026-11-05 起 AI agent 審查通過後可自行合併）。

## 前置條件

| 項目 | 檢查 |
|------|------|
| Go 1.27.3+ | `go version`（go.mod 的 go 指令會自動下載 1.27.3 工具鏈） |
| Docker（MySQL 8 / Redis 7 / Kafka 3.8 KRaft / Elasticsearch 7.17 + Kibana，P-32 起） | `docker compose version` |
| golangci-lint | `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest` |
| golang-migrate（mysql tag） | `go install -tags 'mysql' github.com/golang-migrate/migrate/v4/cmd/migrate@latest` |
| swag | `go install github.com/swaggo/swag/cmd/swag@latest` |
| Node 20（web/admin） | `node -v` |
| go-framework 接入 | 能讀 `game_hub/go-framework`；`make go-work`（沒有 `../go-framework` 就 clone，寫不進版控的 go.work）；`bash scripts/setup-go-work.sh --check` 通過 |
| 本機設定 | `cp .claude/settings.local.json.example .claude/settings.local.json` 並填值；`THESPORTS_*` 只給 collector |

---

## 快速開始

```
/bootstrap                 ← W1 骨架 B-01 ~ B-10（module、框架 tag、三份 profile、三角色空殼、compose、migrate、gen、lint/CI、swag、thesports-sim + 反壓驗證）
/ticket-run S1-T1          ← 執行一張 ticket：Preflight → planner（讀 ticket 與指定 spec 節）→ 實作 → 驗收 → 審查 → 回填
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

看 ticket 的「部門分工」段：**後端條目全是我們的（含總控與業主後台畫面，部門分工 v4）**，**前端條目全是另一部門的（H5、App）**。

| 類 | 認法 | 驗收 |
|----|------|------|
| **A · 後端 API** | 後端條目的資料、API、推送、排程 | AC + 每個 API 的單元測試 + 不變量 |
| **B · 後台前端** | 後端條目含後台畫面（`web/admin`） | AC + 畫面三態 + 後端 API 測試 |
| **C · 契約交付** | 動到 `/api/front/**`、WebSocket、Kafka 封包 | `/contract-export` + `contract-reviewer` |

混合 ticket（S1-T3、S1-T5、S1-T6、S5-T15、S5-T16、S5-T19）：前台欄歸前端部門，後台欄歸我們。

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
 Elasticsearch（D29：導流事件、賠率歷史、歷史賽事；Kibana 只給內部）
                     ^
              Nginx + ACME（業主域名 -> Host -> 業主代碼）
```

**同一個 binary**（`cmd/score-pulse --active=<api|collector|realtime>`），角色只差 YAML 的 `modules.enable-list`。`api` 內兩個 consumer group：`realtime-core`（套用、快照、合流、推送）與 `persist`（批次落庫、賠率歷史）。推導見 `plan/on-sports-lite/tech-decisions.md`。

---

## 目錄結構

```
.claude/
├── CLAUDE.md                  ticket 驅動運作模式、三類工作、路由表、指路、紅線、提交前固定動作
├── README.md                  本檔
├── settings.json              權限、SessionStart 提醒、git-guard hook、autoMode（arch-check 只在 /ticket-run Step 3 驗收跑，不掛 Stop）
├── settings.local.json.example 本機環境變數範本
├── rules/
│   ├── development-workflow.md  文件優先序、三類工作、六步判準（可執行版在 /ticket-run）、Session 與 token 紀律
│   ├── locked-decisions.md      常駐索引：不做清單 + D1~D29 一行版 + 短條停手徵兆
│   ├── locked-decisions-detail.md D 完整規格 + P-20/24/26/27 規則 + 長條停手徵兆（paths: internal、cmd、migrations、configs、deploy、scripts、web/admin）
│   ├── invariants.md            10 條不變量與驗證方式
│   ├── architecture.md          單 binary 多角色、功能分包、依賴方向、表歸屬、fx 組裝（paths: internal、cmd、configs、go.mod）
│   ├── framework-conventions.md go-framework 慣例（含自 sp-framework 移植的部分）（panic 錯誤流程、fx.In、YAML 小寫、Name() 對 YAML、EmitWithKey）（paths: **/*.go、configs）
│   ├── tenant-isolation.md      Host → 業主代碼、gorm Scope/callback、租戶表清單、雙租戶測試（paths: dao、controller、service、core/tenant、core/auth、realtime、migrations、test）
│   ├── api-contract.md          OpenAPI、錯誤格式、相容規則、交付另一部門的流程（paths: controller、dto、core/apierr、docs/contract）
│   ├── realtime-contract.md     Kafka topics、封包短名、WebSocket frame/destination、合流、SLO（paths: realtime、collector、core/envelope、match、odds、notify、docs/contract）
│   ├── thesports-ingest.md      MQTT/HTTP 接入、補齊、停更與中斷偵測、主備（paths: internal/collector、cmd/thesports-sim）
│   ├── i18n.md                  資料名稱回退、分類名稱自譯、通知與簡訊 5 語系、後台只中文（paths: platform/i18n、notify、member、match/service）
│   ├── db-migration.md          golang-migrate、時間戳、分區、gen 重產（paths: migrations、cmd/gen）
│   ├── es-store.md              D29：哪些資料進 ES、Kafka consumer 寫入、strict mapping、ESScope 租戶過濾、Kibana 只給內部（paths: esdao、core/es、platform、odds、match、deploy、configs、docs/contract、test）
│   ├── coding-style.md          Go 風格、error wrapping、context、decimal、UTC、log（paths: **/*.go）
│   ├── testing.md               每個 API 必有單元測試、雙租戶 fixture、模擬器、AC 對映、DoD 七條（paths: *_test.go、test、web/admin 測試）
│   ├── web-frontend.md          Vue 3 + Element Plus + Pinia、防 Vue 2、三態、權限（paths: web/admin）
│   └── git-workflow.md          分支、Conventional Commits、測試分支單向流動
├── agents/                    planner、implementer、web-implementer、code-reviewer、arch-guard（sonnet）、
│                              tenant-isolation-reviewer、contract-reviewer（sonnet）、data-pipeline-reviewer、
│                              web-reviewer、build-error-resolver（sonnet）
├── skills/                    ticket-run、bootstrap、arch-check、tenant-check、contract-export、
│                              sim-scenario、db-migrate、vue3-console、strategic-compact
└── hooks/                     git-guard（OQ 未決、分支規則二合一，指令沒有 git 字樣直接放行）、check-oq-pending-session
```

---

## 第一週該做什麼（2026-11-09 開工；總計畫 v4.3）

> **2026-11-02 兩個變動**：① 部門分工 v4：總控與業主後台的全部畫面歸後端部門 = 本 repo（前端部門只做 H5 與 App），後端成為唯一瓶頸；② 分支規則：`main` 鎖定、`developing` 只收 MR、每張 ticket 從 `origin/developing` 切 `feature/<ticket-id>-<slug>`。
> **2026-11-04 提速修改（planner 慢的 9 項）**：讀 ticket 與 spec 只由 planner 做一次（決策 A）；拿掉 Stop hook 的 arch-check（只在驗收跑）；五份只跟特定目錄有關的規則改成 `paths:` 按需載入；planner 查證合併成一段 bash、計畫範本分小／大尺寸；兩支 git hook 合成 `hooks/git-guard.sh`（`.claude` 已進版控，原本擋 `git add .claude` 的 hook 不再需要）；`head`、`sed -n`、`git ls-remote` 進免確認名單。**改完先拿一張實際 ticket 跑一次 `/ticket-run`，記 planner 耗時與改前比。**
> **2026-11-05 token 瘦身（依 8 個 session 的實測）**：實測 planner 仍 10～11 分鐘，瓶頸是 plan 檔 43～98KB、每個子代理開工就背約 75K token、主 session 上下文中位數 35～60 萬。改了六項：① planner 加字數上限（小 12,000／大 30,000 字元），§1 不貼原始輸出，附錄拆檔；② 再六份規則改 `paths:`，locked-decisions 拆成常駐索引與按需細節，development-workflow 與 CLAUDE.md 去掉和 `/ticket-run` 重複的段落；③ 一張 ticket 一個 session、主流程只調度、長輸出只取尾巴；④ 新增 `implementer`、`web-implementer` 取代臨時的 general-purpose，修正輪用 SendMessage 接續；⑤ 修正輪只重派有 CRITICAL／HIGH 的 reviewer、只給增量 diff，最多三輪；⑥ arch-guard、contract-reviewer、build-error-resolver 改用 sonnet。**改完要再拿一張實際 ticket 量一次，與本次實測比較。**
> **2026-11-05 框架改用 go-framework（tech-decisions v1.13，D1／D2／D2a）**：使用者決定以 `gi88995.kxcodes.com/game_hub/go-framework`（模組名 `framework`）取代 sp-framework。score-pulse 需要的模組系統、WebSocket、權限與路由登記、業務錯誤流程、快取登記、Redis 鎖排程、Prometheus 以「只增不改」移植進 go-framework 分支 `feature/score-pulse-port`，對照表在它的 `docs/sp-port/MAPPING.md`；Go 升為 1.27.3。`rules/framework-conventions.md` §0 列出改名的符號（`web.InjectGET`、`web.WebMiddleware`、`log.*Args`、`log.FieldErrorStack`…），go-framework 原有的 `web.Run`（CORS 全開）與不帶 `Args` 的 log API 不要用。**go-framework 的移植 MR !8 尚未合併；score-pulse 先以該分支 commit 的 pseudo-version 鎖定（以 commit 代 tag，同 sp-framework 時代 B-02）。go-framework 模組路徑沒有 `/v2`，之後的 tag 必須是 v1.x。本機路徑 replace 會被 arch-check 第 2 項擋下。**
> **2026-11-06 改用 go.work（做法同 lion-quest，tech-decisions v1.14）**：go.mod 不再寫 framework；本機、CI、Linux 建置主機都以不進版控的 go.work 接入同層 checkout 的 go-framework，版本記在 `deploy/go-framework.ref`，`make go-work` 準備、`setup-go-work.sh --check` 檢查；映像 `make image` 以上一層目錄為 build context、容器內 go.work 編譯（同 lion-quest）。

1. **分支**：確認 `origin/developing` 存在（沒有 → 請 release 負責人建立並設保護）；每張 ticket、每個 bootstrap 步驟都開 feature 分支，完成後合併回 `developing`（本機 `--no-ff` 或 MR，`rules/git-workflow.md` §1.2）。hook 會擋在 `main`／`developing` 上 commit。
2. **`/bootstrap` B-00 ～ B-10**。B-10 的反壓驗證已做完（結論：框架阻塞），後續是 **P-17**（`internal/realtime` 有界佇列），realtime 第一張 ticket 前要到位。
3. **排序**：M1 的 9 張（S1-T1～T3、S4-T1～T4、S2-T1）**插隊優先**，其餘 W1～W3 後端 ticket 與 App 平台端排後面（總計畫 §9.4）。
4. **W1 的 ticket**：
   | ticket | 本 repo 做什麼 |
   |---|---|
   | S1-T1 總控建立業主 | A + B（總控畫面） |
   | S4-T1 角色與權限 | A + B（兩套後台） |
   | S4-T2 帳號與驗證器 | A + B |
   | S3-T5 設定項（語言、賠率格式、時區、日夜） | **只做後端**（偏好儲存 API）；畫面在另一部門 |
   | S6-T1 App 殼、S6-T7 H5 下載提示條 | **不在本 repo** |
5. **外部等待**：E1 TheSports 憑證（用模擬器先做）、第二台 collector IP 進白名單、go-framework 移植分支合進 developing（MR 待開）；合併後把 `deploy/go-framework.ref` 改指向 developing 上的 commit。

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
| 框架有 bug | 先繞過（在 `core` 包一層），開一張補充任務記錄；不自行改 `deploy/go-framework.ref`（D2a） |
| 編譯說 `framework/pkg/... is not in std` | 沒有 go.work：`make go-work` |
| 想用 Redis Pub/Sub、protobuf、動態訂閱 | 第一期不做，各有量測觸發點（`rules/locked-decisions.md` D4、D5） |
| 想拆 persist 成獨立部署 | 加一份 `application_persist.yaml` 即可，零程式碼改動（`rules/architecture.md` §1） |
| TheSports 憑證還沒來 | `cmd/thesports-sim` 重放 fixture；plan §8 標 `待外部：E1` |
| 後台前端要多語系嗎 | 不要，後台只做中文（dept-assignment 預設 1） |
