---
name: ticket-run
description: 執行 plan/on-sports-lite/tickets/ 的某一張 ticket——Preflight、planner（讀 ticket 與指定 spec 節、判工作類別、寫計畫）、實作、驗收、審查、回填。要開始做某張 ticket（例如 S2-T8）時使用。
---

# ticket-run — 執行一張 ticket

**用法：** `/ticket-run S2-T8`

一次一張。ticket 的粒度就是驗收與回填的粒度。開工前的骨架（B-01 ～ B-10）不是 ticket，走 `/bootstrap`。

> **讀 ticket 與 spec 只做一次，由 planner 做**（2026-11-04 決策 A）。主流程 Preflight 過了就呼叫 planner，**不先自己讀 ticket**；主流程對這張 ticket 的認識來自 planner 回傳的摘要與 plan §0。

---

## Step 0 · Preflight（每個 session 第一次動工前）

```bash
# 分支（使用者 2026-11-02 指定：main 鎖定、每張 ticket 從 developing 切分支）
B=$(git rev-parse --abbrev-ref HEAD)
echo "$B" | grep -Eq '^(main|master|developing)$' && echo "[preflight] 在 $B 上 — 先切分支：git fetch origin && git switch -c feature/<ticket-id>-<slug> origin/developing"
echo "$B" | grep -Eq '^feature/' || echo "[preflight] 分支名不是 feature/<ticket-id>-<slug>"
# 環境
go version | grep -E "go1\.2[3-9]" || echo "[preflight] Go 版本不符"
grep -n "sp-framework" go.mod | grep -E "v[0-9]+\.[0-9]+\.[0-9]+" || echo "[preflight] sp-framework 未鎖 tag（D2a）"
test -f go.work && grep -q "sp-framework" go.work && echo "[preflight] go.work 指向同層 checkout（D2a 禁止）"
go build ./... || echo "[preflight] HEAD 編譯失敗 — 必修"
docker compose -f deploy/docker-compose.yml ps 2>/dev/null | grep -q mysql || echo "[preflight] 整合環境未起（整合測試會跳過）"
```

分支不對 → **先切分支，不動工**（只有要切新分支時才連遠端查 `origin/developing`）：

```bash
T=S2-T8; SLUG=live-score
git ls-remote --heads origin developing | grep -q developing || echo "[preflight] origin/developing 不存在 — 停手回報，不要用 main 代替"
git fetch origin && git switch -c feature/$T-$SLUG origin/developing && git push -u origin feature/$T-$SLUG
```

Go 版本、框架 tag、go.work、編譯失敗 → **必修，不動工**。compose 未起 → 單元層可做。`internal/realtime` 的 ticket → 先確認 `plan/on-sports-lite/tickets/prep/P-17.md` 狀態為「已到位」。

---

## Step 1 · 規劃（planner）

Preflight 全過 → **直接調用 `planner`**，只給它 ticket 編號（例 `S2-T8`）。planner 自己讀整張 ticket、只讀 Required Spec Sections、查前置 ticket 狀態、判工作類別與尺寸、做一次性查證，產出 `plan/task-<ticket>-plan.md`，並回傳摘要（格式見 `agents/planner.md`「回傳摘要」）。

主流程拿到摘要後確認三件事，不重讀 ticket：

| 看摘要的哪一欄 | 確認什麼 |
|---|---|
| 前置 ticket | 有 `Blocked By` → 停手回報，不往下 |
| 工作類別、畫面在哪 | A／B／C 與「畫面：另一部門」的判定合理；H5／App 畫面沒被排進 §2 |
| OQ 數 | **OQ 未決不得寫業務程式碼**；業務疑問回企劃（PM），不改 spec |

**閘門：** plan §4 必須逐一列出**每個新增或修改的 API 的測試函式名**（`rules/testing.md` §1），涉及租戶表的必須指明雙租戶 fixture。

---

## Step 2 · 實作

**Golden Rule：依計畫實作。** 範圍上限是 plan §2 的檔案清單。

| 情境 | 必問 |
|------|------|
| 寫任何查詢 | 「它經過 `tenant.Scope` 了嗎？」（I1） |
| 套用供應商更新 | 「它用 `pv` 做 compare-and-set 了嗎？比分變小有被接受嗎？」（I3） |
| 寫 handler／訂閱 action／consumer | 「它的 `_test.go` 在哪？」（testing §1） |
| `Emit` 到 Kafka | 「key 是 `match_id` 嗎？」（I2） |
| REST 讀即時比分、狀態、事件 | 「讀的是 Redis 快照嗎？」（I9） |
| 寫框架相關程式碼 | 「這是 sp-framework 的寫法，還是網路教學的寫法？」（`rules/framework-conventions.md` §9） |

**Stop Rule：** ticket vs spec、tech-decisions vs 外部方案圖互相矛盾 → 立即停止回報，不要挑一個猜。

---

## Step 3 · 驗收

```bash
go build ./... && go vet ./... && golangci-lint run
go test ./internal/...                                  # 單元（含每個 API 的測試）
go test -tags=integration ./test/...                    # 動到 dao／consumer 時
bash scripts/arch-check.sh                               # 或 /arch-check、make arch-check（只在這裡跑，不掛 Stop hook）
```

動到租戶表 → `/tenant-check`；動到契約 → `/contract-export`。**DoD 七條**（`rules/testing.md` §8）全滿足才算完成。

---

## Step 4 · 審查

| 情境 | reviewer |
|------|---------|
| 一律 | `code-reviewer` |
| 包結構、新增包、跨包 import、引入相依、角色組裝 | + `arch-guard` |
| 租戶表查詢、認證、Host 解析、總控指定業主（`ManageTarget`）、業主後台業主注入（`MustPlatform`）、WebSocket 握手 | + `tenant-isolation-reviewer` |
| `/api/front/**`、WebSocket destination 或訊息、Kafka 封包 | + `contract-reviewer` |
| collector、`realtime-core`、`persist`、合流、快照、賠率歷史 | + `data-pipeline-reviewer` |
| `web/admin` | + `web-reviewer` |

領域 reviewer 平行啟動（同一則訊息）。

---

## Step 5 · 回填（DoD 第 7 條，不可略）

1. `plan/task-<ticket>-plan.md` §8 完成紀錄：日期、測試結果、契約變更、Remaining Work。
2. ticket 狀態欄（**只改這一格**；`sed -i` 會改檔案，故意不放進免確認名單）：

```bash
T=S2-T8; D=$(date +%Y-%m-%d)
sed -i '' "s/^| 狀態 | 待開工 |/| 狀態 | 已完成（$D） |/" plan/on-sports-lite/tickets/$T.md
# 阻塞：sed -i '' "s/^| 狀態 | .* |$/| 狀態 | 阻塞：待外部 E2 影片文件 |/" plan/on-sports-lite/tickets/$T.md
grep -n "^| 狀態 |" plan/on-sports-lite/tickets/$T.md
```

> 企劃的 `_generate.py` 重跑會覆蓋開發 ticket 的狀態欄；**plan 檔 §8 是進度真相**，狀態欄是副本。

3. 確認 `plan/` 無「⏳ 待決」OQ；與程式碼**同一個 commit** 提交；範本（`.claude/`、`CLAUDE.md`）改動不夾帶進 ticket commit。
4. 推分支、開 MR 到 `developing`（**不在本機 merge**）：

```bash
git rebase origin/developing && go test ./internal/... && git push --force-with-lease
# 之後在 GitLab 開 MR：來源 feature/<ticket-id>-<slug> → 目標 developing，描述照 rules/git-workflow.md §4
```

---

## Step 6 · 回報

```
工單：S2-T8 <名稱>（波次 W7 ／ 類別 A ／ 尺寸 小）
狀態：完成 / 受阻
涉及不變量：I2、I3 → 測試 <函式名> PASS
API 測試：<逐一列出 Test 名> PASS
架構檢查：arch-check PASS
契約影響：無 / 相容（CHANGELOG 已記）/ 破壞性（已停手，OQ-n）
對映 AC：AC-40、AC-41、AC-46 已驗
Remaining Work：<或 Blocked By: S2-T5>
```

最後一行固定：**下一步執行** <依 `rules/development-workflow.md` 的下一步>（<一句話為什麼>）。
