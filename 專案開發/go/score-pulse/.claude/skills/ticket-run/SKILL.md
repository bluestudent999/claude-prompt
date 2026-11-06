---
name: ticket-run
description: 執行 plan/on-sports-lite/tickets/ 的某一張 ticket——Preflight、planner（讀 ticket 與指定 spec 節、判工作類別、寫計畫）、實作、驗收、審查、回填。要開始做某張 ticket（例如 S2-T8）時使用。
---

# ticket-run — 執行一張 ticket

**用法：** `/ticket-run S2-T8`

一次一張。ticket 的粒度就是驗收與回填的粒度。開工前的骨架（B-01 ～ B-10）不是 ticket，走 `/bootstrap`。

> **一張 ticket 一個 session，主流程只調度**（2026-11-05 實測後加入）：主流程不親手寫功能碼、不把長輸出讀進上下文；MR 開好就收尾，下一張先 `/clear`。細則見 `rules/development-workflow.md`「Session 與 token 紀律」。

> **讀 ticket 與 spec 只做一次，由 planner 做**（2026-11-04 決策 A）。主流程 Preflight 過了就呼叫 planner，**不先自己讀 ticket**；主流程對這張 ticket 的認識來自 planner 回傳的摘要與 plan §0。

---

## Step 0 · Preflight（每個 session 第一次動工前）

```bash
# 分支（使用者 2026-11-02 指定：main 鎖定、每張 ticket 從 developing 切分支）
B=$(git rev-parse --abbrev-ref HEAD)
echo "$B" | grep -Eq '^(main|master|developing)$' && echo "[preflight] 在 $B 上 — 先切分支：git fetch origin && git switch -c feature/<ticket-id>-<slug> origin/developing"
echo "$B" | grep -Eq '^feature/' || echo "[preflight] 分支名不是 feature/<ticket-id>-<slug>"
# 環境
go version | grep -Eq "go1\.(2[7-9]|[3-9][0-9])" || echo "[preflight] Go 版本不符（需 1.27.3+）"
bash scripts/setup-go-work.sh --check || echo "[preflight] go.work 或 go-framework 版本不符（D2a）：make go-work，或 setup-go-work.sh --checkout"
grep -q "framework" go.mod && echo "[preflight] go.mod 寫了 framework（D2a：只經 go.work 接入）"
go build ./... || echo "[preflight] HEAD 編譯失敗 — 必修"
docker compose -f deploy/docker-compose.yml ps 2>/dev/null | grep -q mysql || echo "[preflight] 整合環境未起（整合測試會跳過）"
```

分支不對 → **先切分支，不動工**（只有要切新分支時才連遠端查 `origin/developing`）：

```bash
T=S2-T8; SLUG=live-score
git ls-remote --heads origin developing | grep -q developing || echo "[preflight] origin/developing 不存在 — 停手回報，不要用 main 代替"
git fetch origin && git switch -c feature/$T-$SLUG origin/developing && git push -u origin feature/$T-$SLUG
```

Go 版本、go.work 與框架版本、編譯失敗 → **必修，不動工**（本機若是有意同時改 go-framework，版本不符可以繼續，但要在 plan §8 註明）。compose 未起 → 單元層可做。`internal/realtime` 的 ticket → 先確認 `plan/on-sports-lite/tickets/prep/P-17.md` 狀態為「已到位」。

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

## Step 2 · 實作（派給實作代理）

主流程**不自己寫功能碼**。依 planner 摘要的工作類別派工，派工訊息照代理的 Input Schema，**不轉述 plan 內容**：

| 工作類別 | 派給 | 順序 |
|------|------|------|
| A、C | `implementer` | — |
| B | `web-implementer` | 依賴的後端 API 已存在 → 可與 `implementer` 同一則訊息平行；否則等 `implementer` 回傳後再派，並附它的 API 清單 |

```
ticket：S2-T8
plan：plan/task-S2-T8-plan.md
範圍：plan §3 第 1～7 步
分支：feature/S2-T8-live-score（已切好）
```

實作代理自跑驗收並回傳固定格式摘要；「超出 plan §2」不是「無」→ 先判斷要不要擴 §2（擴了要回寫 plan），再讓它繼續。**Golden Rule 與每次必問**見 `rules/development-workflow.md`「六個步驟」。

**Stop Rule：** ticket vs spec、tech-decisions vs 外部方案圖互相矛盾 → 立即停止回報，不要挑一個猜。

---

## Step 3 · 驗收

> **2026-11-06 起 GitLab CI 暫停 Go job**（runner 連不到 GitLab，tech-decisions §6 #10），這一步的本機驗收是合併前**唯一**的 Go 檢查，不可略過、不可只看實作代理的自我回報。

實作代理已跑完整套驗收（build／vet／lint／單元／整合／arch-check／tenant-check）並在摘要列出結果。主流程只做一次快速複核，輸出只看尾巴：

```bash
go build ./... && go test ./internal/... 2>&1 | tail -5
bash scripts/arch-check.sh 2>&1 | tail -5     # 或 /arch-check、make arch-check（只在這裡跑，不掛 Stop hook）
```

動到契約 → 確認 `docs/contract/` 有更新（`/contract-export`）。**DoD 七條**（`rules/testing.md` §8）全滿足才算完成。

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

「動到什麼」看實作代理摘要的「碰到的面向」欄，不自己讀 diff 判斷。`arch-guard` 只在「包結構或跨包 import 新增：是」或 arch-check 有 FAIL 時派；只在既有包內加檔、arch-check PASS → 不派。

領域 reviewer 平行啟動（同一則訊息）。派工時給：ticket 編號、plan 路徑、本輪範圍（第一輪：整個工作樹相對 `origin/developing`）。

### 修正輪（第二輪起）

1. **派修正前先記快照**（含未追蹤的新檔，不動工作樹與索引）：
   ```bash
   snap() { local i; i=$(mktemp); cp "$(git rev-parse --git-dir)/index" "$i"; GIT_INDEX_FILE=$i git add -A; GIT_INDEX_FILE=$i git write-tree; rm -f "$i"; }
   R1=$(snap); echo "$R1"
   ```
2. **修正交給原實作代理**：用 SendMessage 接續同一個 `implementer`／`web-implementer`，訊息只貼發現清單（`<reviewer> <級別> <檔案:行> <一句話>`），不貼 plan。它回報「建議改開新實例」或已無法接續時，才新開一個並附 plan 路徑與發現清單。
3. **只重派有 CRITICAL／HIGH 的 reviewer**，只給增量：
   ```bash
   R2=$(snap); git diff --stat "$R1" "$R2"; git diff "$R1" "$R2" > "$TMPDIR/<ticket>-r2.diff"
   ```
   派工訊息附 diff 檔路徑與「上一輪你提的發現」，請它只驗這些發現是否修好、增量有沒有新問題。只有 MEDIUM／LOW 的 reviewer 不重派，由主流程對照實作代理的「修正輪」欄確認。
4. **最多三輪。** 第三輪後仍有 CRITICAL → 停手回報使用者，附未解發現。

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
4. 推分支，合併回 `developing`（`rules/git-workflow.md` §1.2；2026-11-05 使用者指定：審查通過即可自行在本機合併，不必再問）：

```bash
git rebase origin/developing && go test ./internal/... && git push --force-with-lease
git switch developing && git pull --ff-only origin developing
git merge --no-ff feature/<ticket-id>-<slug> -m "Merge branch 'feature/<ticket-id>-<slug>' into 'developing'"
git push origin developing
# 或改在 GitLab 開 MR：來源 feature/<ticket-id>-<slug> → 目標 developing（確認不是 main），描述照 §4
```

衝突 → `git merge --abort`，回 feature 分支 rebase 解完再合；push 被拒 → 停手回報。不在本機合併進 `main`。

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

最後一行固定：**下一步執行** <依 `rules/development-workflow.md` 的下一步>（<一句話為什麼>）。已合併回 `developing` 或 MR 已開 → 固定寫「**下一步執行** 清空上下文（`/clear`）後 `/ticket-run <下一張>`（一張 ticket 一個 session）」。
