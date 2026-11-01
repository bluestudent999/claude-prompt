---
name: arch-check
description: 跑架構守門檢查——包依賴方向、角色邊界、禁用相依、租戶表 dao 經 tenant.Scope、append-only 表無 UPDATE/DELETE、每個 controller handler 有單元測試、投注字眼。提交前、新增包或檔案、動 import 後使用。
---

# arch-check — 架構邊界檢查

**用法：** `/arch-check`，或 `bash .claude/skills/arch-check/arch-check.sh`（`make arch-check` 同義）

檢查項對應 `rules/architecture.md` §6。每項印 `PASS`／`FAIL`，任一 FAIL 離開碼 1。**提交前必跑**；Stop hook 也會跑一次。

---

## 檢查項

| # | 檢查 | 依據 |
|---|------|------|
| 1 | `go list -deps` 比對依賴白名單：包內 controller → service → dao → model；跨功能包只准 import 對方 `service`、`dto`；`platform` 不依賴功能包；`collector` 不被任何功能包 import；`inject` 只被 `cmd/score-pulse` import；`realtime` 不 import `dao` | architecture §3 |
| 2 | 禁用相依：`sp-common`、`ignite`、`olivere/elastic`、`.proto` 檔、`proto.Marshal` 在 `internal/realtime` 或對前端路徑、`go.work` 含 `sp-framework`、`Subscribe(`／`PSubscribe(` 在 realtime 或 api 推送路徑、`cmd/` 下多出非白名單目錄 | locked-decisions D2、D3、D4、D5 |
| 3 | 租戶表 dao 經 `tenant.Scope`：對 `rules/tenant-isolation.md` §2 的租戶表清單，`dao/` 內出現 `model.<Table>` 的檔案必須同時含 `tenant.Scope` 或 `tenant.AdminScope`（近似檢查） | I1 |
| 4 | append-only 表（`odds_history`、`admin_audit`、`redirect_click`、`redirect_impression`、`visit_log`、`match_event`）無 `UPDATE`／`DELETE`／`.Updates(`／`.Delete(`（match_event 允許 `cancelled` 欄位更新，另列白名單） | I5、I6、I10 |
| 5 | 每個 controller handler 有對應 `_test.go`，且租戶相關 handler 的測試檔含 `OtherTenant` 或 `Unauthorized` 字樣（近似檢查） | testing §1 |
| 6 | 投注字眼：`settle`、`settlement`、`bet`、`stake`、`payout` 不出現在 `internal/`（註解除外） | locked-decisions D3 |
| 7 | `os.Getenv(`、`gin.New(`、`gin.Default(`、`gorm.Open(`、`redis.NewClient(`、`cron.New(`、`websocket.Upgrader{` 不出現在 `internal/`（`platform/conf` 除外） | framework-conventions §9 |

---

## Step 1 · 自動檢查

```bash
bash .claude/skills/arch-check/arch-check.sh
```

## Step 2 · 讀結果

- FAIL 1（依賴方向）：看印出的 `A -> B`。修法是把被依賴的東西抽介面到呼叫方那一側，**不是**搬到 `platform`。
- FAIL 3（租戶 Scope）：若該表確實不是租戶表 → 先改 `rules/tenant-isolation.md` §2 與 `rules/architecture.md` §4，再重跑；不要為了過檢查把 Scope 加在共用表上。
- FAIL 5（handler 無測試）：補測試，見 `rules/testing.md` §1；**不可**用 `//nolint` 或改名繞過。
- 誤報：腳本是 grep 近似。確認是誤報時，在回報裡寫明理由，並在 `arch-check.sh` 的白名單區（檔頭常數）加例外，**同一個 commit**。

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
