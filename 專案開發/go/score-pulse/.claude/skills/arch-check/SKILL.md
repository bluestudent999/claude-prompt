---
name: arch-check
description: 跑架構守門檢查——包依賴方向、角色邊界、禁用相依、租戶表 dao 經 tenant.Scope、append-only 表無 UPDATE/DELETE、每個 controller handler 有單元測試、投注字眼。提交前、新增包或檔案、動 import 後使用。
---

# arch-check — 架構邊界檢查

**用法：** `/arch-check`，或 `bash scripts/arch-check.sh`（`make arch-check` 同義；CI 的 arch-check job 也跑它）

> 腳本在 repo 的 `scripts/`（進版控，CI 與 Makefile 同一份）；本目錄只放說明。改檢查規則請改 `scripts/` 並隨 ticket 提交。

檢查項對應 `rules/architecture.md` §6。每項印 `PASS`／`FAIL`，任一 FAIL 離開碼 1。**提交前必跑**（`/ticket-run` Step 3 驗收）；不掛 Stop hook，規劃與問答的回合不會觸發。

---

## 檢查項

| # | 檢查 | 依據 |
|---|------|------|
| 1 | `go list -deps` 比對依賴白名單：包內 controller → service → dao → model；跨功能包只准 import 對方 `service`、`dto`；`core` 不依賴功能包；`collector` 不被任何功能包 import；`inject` 只被 `cmd/score-pulse` import；`realtime` 不 import `dao` | architecture §3 |
| 1a | `internal/` 的頂層目錄只准 `FEATURES`（八個功能包）、`core`、`inject`（含隱藏目錄與連結；fail-closed）：第 1 項只走 `FEATURES` 列出的包，清單外的目錄整包不受檢查（例：P-30 後重建總控的舊包目錄 `internal/admin`）；新增功能包要先加進 `FEATURES` | architecture §2、§3、D26 |
| 2 | 禁用相依：`sp-common`、`ignite`、`olivere/elastic`（**P-32 起**改為只准在 `internal/core/es` 與 `internal/*/esdao`，D29；P-32 前腳本仍整個禁用）、`.proto` 檔、`proto.Marshal` 在 `internal/realtime` 或對前端路徑、`go.work`／`go.work.sum` 進版控、go.mod 寫 framework、`deploy/go-framework.ref` 不是 40 字元 commit、`Subscribe(`／`PSubscribe(` 在 realtime 或 api 推送路徑、`cmd/` 下多出非白名單目錄 | locked-decisions D2、D3、D4、D5 |
| 3 | 租戶表 dao 經 `tenant.Scope`：對 `rules/tenant-isolation.md` §2 的租戶表清單，`dao/` 內出現 `model.<Table>` 的檔案必須同時含 `tenant.Scope`、`tenant.AllPlatforms`、`tenant.ManageRows` 或 `tenant.SelfScope`（近似檢查）；清單含 `AdminInfo`、`AdminRole`、`AdminIPAllow`、`LoginLog`、`OperateLog` | I1 |
| 4 | append-only 表（`login_log`、`operate_log`、`match_event`；`odds_history`、`redirect_click`、`redirect_impression`、`visit_log` 依 D29 改存 ES、不得建表，**P-32 起**另掃 esdao 無 Update／Delete（By Query），`sp_match_history` 除外）無更新／刪除：Go 以跨行比對 `model.<M>` 或 `Table("<t>")` 之後 120 字內的 `.Update(s)(`、`.UpdateColumn(s)(`、`.Delete(`、`.Save(`；Go 另比對方法在前的 `.Delete(&model.<M>`／`.Save([]model.<M>`（經變數傳遞的抓不到，靠 review）；SQL 先去 `/* */` 與 `--` 註解、再以 `;` 切成語句，`UPDATE`／`DELETE`／`TRUNCATE`／`REPLACE`、`WITH … UPDATE|DELETE`、`INSERT … ON DUPLICATE KEY UPDATE`、`ALTER … DROP／TRUNCATE／EXCHANGE PARTITION` 提到這些表即 FAIL（沒有放行清單；每月新增分區的 `REORGANIZE PARTITION` 不刪資料，不算）。match_event 允許 `cancelled` 欄位更新 | I5、I6、I10 |
| 5 | 每個 controller handler 有對應 `_test.go`，且租戶相關 handler 的測試檔含 `OtherTenant` 或 `Unauthorized` 字樣（近似檢查） | testing §1 |
| 6 | 投注字眼：`settle`、`settlement`、`bet`、`stake`、`payout` 不出現在 `internal/`（註解除外） | locked-decisions D3 |
| 7 | `os.Getenv(`、`gin.New(`、`gin.Default(`、`gorm.Open(`、`redis.NewClient(`、`cron.New(`、`websocket.Upgrader{` 不出現在 `internal/`（`core/conf` 除外） | framework-conventions §9 |
| 8 | `tenant.AllPlatforms(` 只准出現在 `internal/manage/*`、`internal/platform/dao/platform.go` 的 `ExistsByName`／`ExistsByCode`／`ListForManage`／`SummaryForManage`、`internal/core/tenant/resolver.go`（`core/tenant` 的定義處除外） | tenant-isolation §3、S1-T1、P-19、P-24 |
| 9 | `tenant.ManageRows(` 只准出現在 `internal/manage/dao/`（`internal/core/tenant/` 自身除外） | tenant-isolation §3、S4-T1 |
| 10 | `tenant.SelfScope(` 只准出現在 `internal/platform/dao/`（`internal/core/tenant/` 自身除外） | tenant-isolation §3、P-19 |
| 11 | `internal/` 非測試程式的 `.Raw(`／`.Exec(`：第一個引數必須是字串字面值（否則 FAIL，fail-closed）；去掉 `'…'` 字串值後不得提到任何租戶表（清單讀 `internal/core/tenant/tables.go`）；`database/sql`（import、`.DB()`、`Query`／`QueryRow`／`ExecContext`／`Prepare`…）只准在 `internal/core`。非 SQL 的 `.Exec(`（go-redis pipeline）逐檔列在 `RAW_EXEC_ALLOW` 並寫原因 | tenant-isolation §3、I1、P-19 |
| 12 | `tenant.SystemWrite(`（ctx 沒有業主的 INSERT 標記）只准出現在 `internal/manage/dao/`、`internal/platform/dao/`（`internal/core/tenant/` 自身除外） | tenant-isolation §3、P-19 |
| 13 | 後台選單代碼只增不改：`docs/contract/admin-menu-codes.md` 每列前四欄（代碼｜後台｜選單鍵.頁面鍵｜動作）與基準（`MENU_CODES_BASE`，預設 `origin/developing` 最新一筆）比，基準有的每一組都必須原樣存在（名稱、狀態欄可改，下架標「停用」）；基準不存在 → FAIL（CI 先 fetch developing）；基準還沒有這個檔 → PASS。分支沒 rebase 時會把 developing 新加的列報成被刪 → 先 rebase。另有永久檢查：後台欄只能是 `manage`（代碼 1 開頭）或 `platform`（代碼 2 開頭）。**P-30 一次性例外**（D26）：基準代碼列的 sha256 恰等於 P-30 開工時 `origin/developing` 的 78 列時，只把基準列後台欄的 `admin` 換成 `manage` 再比（訊息帶「P-30 一次性改名對照」）；P-30 合併後雜湊不再相符、自動失效 | D23、P-23、D26 |
| 14 | 後台路由只經 `auth.RouteTable` 登記：提到後台前綴（`/api/manage`、`/api/platform`，以及 P-30 退役的 `/api/admin`）的非測試檔不得直接 `web.GET／POST／ANY` 或 gin 的 `.GET`…`.Match` 掛路由（`internal/core/auth/routes.go` 除外）；`NoRoute`／`NoMethod`、`.Use`、`.Group` 方法值或帶 middleware、改寫或讀取 `.Handlers` 一律不准。靜態縱深防禦；真正的防線是啟動檢查 `auth.VerifyBackOfficeRoutes` | D23、P-23 |
| 15 | 業主與身分只在**檔案層級**白名單放進 ctx（掃 `internal` 與 `cmd` 的非測試檔；比對字詞含方法值與轉手函式；純註解行除外，`//go:linkname` 不算註解）：`tenant.WithPlatform` 只准 `internal/core/tenant/context.go`（定義）、`internal/core/tenant/middleware.go`（前台 Host）、`internal/core/auth/session_middleware.go`、`internal/core/auth/bridge.go`、`internal/core/auth/manage_target.go`、`internal/manage/service/login.go`（登入網址的代碼）、`internal/manage/dao/role.go`（建業主同一事務的第一批角色列）；`auth.WithPrincipal` 只准 `internal/core/auth/principal.go`、`internal/core/auth/session_middleware.go`；`auth.WithSession` 只准 `internal/core/auth/session.go`、`internal/core/auth/session_middleware.go`；白名單檔案內三者只准直接呼叫 `Name(`（方法值、賦值轉手 FAIL）；兩包不匯出的 `ctxKey` 只准各自定義檔，且只准 `type ctxKey struct{}` 與 WithValue／Value 的引數（`= ctxKey` 別名、以它建的匯出型別或變數 FAIL）；session 的 `ctxSession` 只准 `internal/core/auth/session.go`；舊匯出名 `CtxKey`／`CtxPrincipal` 一律 FAIL；15e：任何 `Value` 方法宣告 FAIL（`VALUE_METHOD_ALLOW` 為空）。業主 ctx 只來自 Host、session 身分或 `auth.ManageTarget`；身分與 session 只來自 session middleware | tenant-isolation §3、I1、P-28（D24） |

---

## Step 1 · 自動檢查

```bash
bash scripts/arch-check.sh
```

## Step 2 · 讀結果

- FAIL 1（依賴方向）：看印出的 `A -> B`。修法是把被依賴的東西抽介面到呼叫方那一側，**不是**搬到 `core`。
- FAIL 3（租戶 Scope）：若該表確實不是租戶表 → 先改 `rules/tenant-isolation.md` §2 與 `rules/architecture.md` §4，再重跑；不要為了過檢查把 Scope 加在共用表上。
- FAIL 5（handler 無測試）：補測試，見 `rules/testing.md` §1；**不可**用 `//nolint` 或改名繞過。
- 誤報：腳本是 grep 近似。確認是誤報時，在回報裡寫明理由，並在 `scripts/arch-check.sh` 的白名單區（檔頭常數）加例外，**同一個 commit**。

## Step 3 · 人工補掃（腳本抓不到的）

```bash
grep -rn "EmitWithKey\|\.Emit(" --include=*.go internal/ | grep -v _test.go      # 業務 topic 都該是 EmitWithKey(match_id)
grep -rn "newScore\s*<\|score\s*<\s*old" --include=*.go internal/                  # 以分數大小過濾更新（I3 違規）
grep -rn "SelectDefault().*Model(&model\.Match\b" --include=*.go internal/*/controller/   # controller 直接讀 DB 取即時資料（I9）
grep -rn "allow-cross-origin: true" configs/application_realtime.yaml           # prod 必須 false
```

## 回報格式

```
arch-check：PASS / FAIL（n 項）
FAIL 項目：<編號 + 檔案:行號 + 一句修法>
誤報與白名單異動：<無 / 檔案與理由>
```
