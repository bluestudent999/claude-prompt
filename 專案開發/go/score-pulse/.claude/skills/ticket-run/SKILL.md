---
name: ticket-run
description: 執行 plan/on-sports-lite/tickets/ 的某一張 ticket——Preflight、讀 ticket 與指定 spec 節、判工作類別、planner、實作、驗收、審查、回填。要開始做某張 ticket（例如 S2-T8）時使用。
---

# ticket-run — 執行一張 ticket

**用法：** `/ticket-run S2-T8`

一次一張。ticket 的粒度就是驗收與回填的粒度。開工前的骨架（B-01 ～ B-10）不是 ticket，走 `/bootstrap`。

---

## Step 0 · Preflight（每個 session 第一次動工前）

```bash
go version | grep -E "go1\.2[3-9]" || echo "[preflight] Go 版本不符"
grep -n "sp-framework" go.mod | grep -E "v[0-9]+\.[0-9]+\.[0-9]+" || echo "[preflight] sp-framework 未鎖 tag（D2a）"
test -f go.work && grep -q "sp-framework" go.work && echo "[preflight] go.work 指向同層 checkout（D2a 禁止）"
go build ./... || echo "[preflight] HEAD 編譯失敗 — 必修"
docker compose -f deploy/docker-compose.yml ps 2>/dev/null | grep -q mysql || echo "[preflight] 整合環境未起（整合測試會跳過）"
```

Go 版本、框架 tag、go.work、編譯失敗 → **必修，不動工**。compose 未起 → 單元層可做。

---

## Step 1 · 讀 ticket（禁 full read spec）

```bash
T=S2-T8   # 換成實際編號
cat plan/on-sports-lite/tickets/$T.md                              # 整張 ticket 都讀（本來就短）
grep -n "^## 只讀這幾節" -A 2 plan/on-sports-lite/tickets/$T.md    # Required Spec Sections
grep -n "^| 規格 |" plan/on-sports-lite/tickets/$T.md              # 要讀哪幾份 spec
grep -nE "^#{2,4} " plan/on-sports-lite/spec/spec-2a-match-live.md  # 先建索引，再 Read(offset, limit) 讀指定節
grep -n "^| 狀態 |" plan/on-sports-lite/tickets/<前置ticket>.md     # 前置 ticket 狀態
```

確認：**Scope 含／不含**、**Depends On 已完成**（否則 `Blocked By: <ticket>`；標「（驗收）」者只卡驗收可開工）、**AC 編號**、**部門分工**。

> spec 每份 300 ～ 560 行。看到自己在讀 Required Spec Sections 以外的節，就是沒照做。

---

## Step 1.5 · 判工作類別（寫進 plan §0）

| 類 | 判定 | 本 repo 做什麼 |
|----|------|---------------|
| **A · 後端 API** | 主責後端；或主責前端但「部門分工」的前端項目是 H5／App 畫面 | 資料、API、Kafka、Redis、推送；畫面標「另一部門」 |
| **B · 後台前端** | 前端項目是總控或業主後台畫面（多在 S4、S5；S1-T6、S1-T10 等） | `web/admin` 畫面 + 對應後端 API |
| **C · 契約交付** | 動到 `/api/front/**`、WebSocket destination、Kafka 封包 | `/contract-export` 產出 + `contract-reviewer` |

判「畫面在另一部門」的方法：ticket「部門分工」的前端描述提到比分卡、列表、詳情分頁、App、推播畫面、下載提示條 → 另一部門。提到總控、業主後台、匯出、設定頁 → B 類。

同時查：碰到哪些 **D**（`rules/locked-decisions.md`）、哪些 **I**（`rules/invariants.md`）、哪些表屬租戶表（`rules/tenant-isolation.md` §2）。

---

## Step 2 · 規劃（planner）

調用 `planner`，產出 `plan/task-<ticket>-plan.md`。

**閘門：** plan §4 必須逐一列出**每個新增或修改的 API 的測試函式名**（`rules/testing.md` §1），涉及租戶表的必須指明雙租戶 fixture。**OQ 未決不得寫業務程式碼。** 業務疑問回企劃（PM），不改 spec。

---

## Step 3 · 實作

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

## Step 4 · 驗收

```bash
go build ./... && go vet ./... && golangci-lint run
go test ./internal/...                                  # 單元（含每個 API 的測試）
go test -tags=integration ./test/...                    # 動到 dao／consumer 時
bash .claude/skills/arch-check/arch-check.sh            # 或 /arch-check
```

動到租戶表 → `/tenant-check`；動到契約 → `/contract-export`。**DoD 七條**（`rules/testing.md` §8）全滿足才算完成。

---

## Step 5 · 審查

| 情境 | reviewer |
|------|---------|
| 一律 | `code-reviewer` |
| 包結構、新增包、跨包 import、引入相依、角色組裝 | + `arch-guard` |
| 租戶表查詢、認證、Host 解析、總控指派範圍、WebSocket 握手 | + `tenant-isolation-reviewer` |
| `/api/front/**`、WebSocket destination 或訊息、Kafka 封包 | + `contract-reviewer` |
| collector、`realtime-core`、`persist`、合流、快照、賠率歷史 | + `data-pipeline-reviewer` |
| `web/admin` | + `web-reviewer` |

領域 reviewer 平行啟動（同一則訊息）。

---

## Step 6 · 回填（DoD 第 7 條，不可略）

1. `plan/task-<ticket>-plan.md` §8 完成紀錄：日期、測試結果、契約變更、Remaining Work。
2. ticket 狀態欄（**只改這一格**）：

```bash
T=S2-T8; D=$(date +%Y-%m-%d)
sed -i '' "s/^| 狀態 | 待開工 |/| 狀態 | 已完成（$D） |/" plan/on-sports-lite/tickets/$T.md
# 阻塞：sed -i '' "s/^| 狀態 | .* |$/| 狀態 | 阻塞：待外部 E2 影片文件 |/" plan/on-sports-lite/tickets/$T.md
grep -n "^| 狀態 |" plan/on-sports-lite/tickets/$T.md
```

> 企劃的 `_generate.py` 重跑會覆蓋開發 ticket 的狀態欄；**plan 檔 §8 是進度真相**，狀態欄是副本。

3. 確認 `plan/` 無「⏳ 待決」OQ；與程式碼**同一個 commit** 提交；不加 `.claude/`、`CLAUDE.md`。

---

## Step 7 · 回報

```
工單：S2-T8 <名稱>（波次 W7 ／ 類別 A）
狀態：完成 / 受阻
涉及不變量：I2、I3 → 測試 <函式名> PASS
API 測試：<逐一列出 Test 名> PASS
架構檢查：arch-check PASS
契約影響：無 / 相容（CHANGELOG 已記）/ 破壞性（已停手，OQ-n）
對映 AC：AC-40、AC-41、AC-46 已驗
Remaining Work：<或 Blocked By: S2-T5>
```

最後一行固定：**下一步執行** <依 `rules/development-workflow.md` 的下一步>（<一句話為什麼>）。
