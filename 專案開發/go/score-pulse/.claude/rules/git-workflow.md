# Git 工作流與提交規範

> 本文規範 score-pulse 的分支策略、Commit 訊息格式與 Merge Request（MR）規範。
> 開發範本（`.claude/` 與根 `CLAUDE.md`）自 2026-11-02 起隨專案進版控；只排除 `.claude/settings.local.json` 與 `.claude/worktrees/`。範本改動另開 `chore` commit，不與 ticket 混在一起。

---

## 1. 分支策略（2026-11-02 使用者指定：master 鎖定、每張 ticket 從 developing 切分支；2026-11-05 使用者指定：完成的 feature 可在本機合併回 developing）

| 分支 | 用途 | 誰能動 | 規則 |
|------|------|--------|------|
| `main`（= master） | **鎖定**：正式版 | 只有 release 負責人經 MR | **不得 commit、不得 push、不得從它切 feature**。只收 `developing` 的 release MR |
| `developing` | 集成主線 | MR，或開發者（含 AI agent）本機合併 | **不得直接 commit**；只收 feature／hotfix／planning 分支：開 MR，或照 §1.2 在本機 `--no-ff` 合併後 push |
| `planning/<專案>` | 企劃文件（PM） | PM | `plan/` 的變更在這裡；要讓開發讀到新版 ticket → 開 MR 進 `developing` |
| `feature/<ticket-id>-<slug>` | **一張 ticket 一條** | 開發者 | **只能從 `developing` 切出**；例 `feature/S2-T8-live-score`、`feature/B-03-profiles`（bootstrap）、`feature/P-17-ws-bounded-queue`（開發端前置） |
| `developing_test` | 測試環境 | CI | **只收 merge、不回流**（下方紅線） |
| `hotfix/<slug>` | 正式版緊急修復 | 開發者 | 從 `main` 切出，MR 進 `main` **與** `developing` 各一 |

### 1.1 開始一張 ticket 的固定動作

```bash
git fetch origin
git switch -c feature/S2-T8-live-score origin/developing     # 一定從 origin/developing，不從 main、不從別的 feature
git push -u origin feature/S2-T8-live-score                   # 早 push、早開 Draft MR
```

- `developing` 不存在 → **停手回報**（第一次由 release 負責人從 `main` 建立並設保護）；不要自己用 `main` 代替。
- 一條分支只做一張 ticket。ticket 沒做完想做下一張 → 另開分支，不疊在同一條上。
- 分支落後 `developing` 時用 `git rebase origin/developing`（在 feature 分支上），不要把 `developing` merge 進 feature。

### 1.2 完成一張 ticket 的固定動作

1. DoD 七條全過（`testing.md` §8）、Step 4 的 reviewer 沒有 block、plan §8 與 ticket 狀態已回填並 commit。
2. `git rebase origin/developing` → 跑一次 `go test ./internal/...`（動到 `web/admin` 再跑 `npx vitest run`）→ `git push --force-with-lease`。
3. 合併回 `developing`，二選一：
   - **本機合併（2026-11-05 使用者指定；AI agent 完成 ticket 後可自行執行，不必再問）**：
     ```bash
     git switch developing && git pull --ff-only origin developing
     git merge --no-ff feature/<ticket-id>-<slug> -m "Merge branch 'feature/<ticket-id>-<slug>' into 'developing'"
     git push origin developing
     ```
     merge 有衝突 → `git merge --abort`，回 feature 分支 rebase 解衝突、重跑測試後再合；**不在 `developing` 上解衝突**。push 被遠端拒絕（分支保護、非 fast-forward）→ 停手回報，不換方式硬推。
   - **開 MR**：目標 `developing`，描述照 §4 格式；指派 reviewer。**建 MR 時確認目標分支是 `developing`**（GitLab 預設目標常是 `main`；2026-11-05 曾因此把 S4-T3a／T3b 合進 `main`）。
4. 合併後可刪除 feature 分支。
5. **絕不** 在本機把任何分支合併進 `main` 再 push；`main` 只收 `developing` 的 release MR。

**本機合併的邊界（hook 照此攔）**：`developing` 上只准 `git merge --no-ff` 合併 `(origin/)feature/…` 或 `hotfix/…`；不准直接 commit、cherry-pick、revert、squash 或 fast-forward 合併、合併 `main` 或測試分支、rebase、reset、不帶 `--ff-only` 的 pull、改寫歷史的推送。

### 1.3 hook 會擋的動作（`hooks/git-guard.sh` 的分支檢查）

| ❌ 動作 | 為什麼 |
|---|---|
| 在 `main`／`master` 上 `git commit`、`git merge`、`git push` | 鎖定分支 |
| `git push origin main`（任何形式把 main 推上去） | 同上 |
| 在 `developing` 上 `git commit`／`cherry-pick`／`revert`／`rebase`／`reset` | 集成分支不直接改、不改寫歷史 |
| 在 `developing` 上 `git merge`，但不是 `--no-ff` 合併 `feature/…`／`hotfix/…`（含 squash、合 `main`、合測試分支） | 只准 §1.2 的本機合併 |
| 在 `developing` 上 `git pull` 不帶 `--ff-only`；強制推送 `developing`（`--force`、`-f`、`--force-with-lease`、`+developing`） | 不在本機產生同步用的合併 commit；不改寫共用歷史 |
| `git switch -c X main`、`git checkout -b X main`、`git branch X main` | feature 必須從 `developing` 切 |

被攔到時不要找繞法（`--no-verify`、先改名分支再推）。那是在規避規則，回報使用者。

<!-- shared:test-branch-one-way -->
### 測試分支單向流動（紅線）

**程式碼只能從開發分支流向測試分支，永遠不能回流。**

| 方向 | 允許？ |
|------|--------|
| 開發分支 / 功能分支 → 測試分支 | ✅ 正常流程 |
| 測試分支 → 開發分支 / 功能分支 | ❌ 一律禁止 |

**測試分支** ＝ 名稱為 `developing_test`、`developing-test`（或其他 `*_test` / `*-test` 變體）的分支。無法判斷某分支是不是測試分支時**問使用者**，不要自行認定。

**禁止的具體動作**（在開發分支、或從開發分支切出的功能分支上）：

| ❌ 動作 | 說明 |
|---|---|
| `git merge developing_test` | 含在開發分支上 `git pull` 誤拉測試分支來源 |
| `git cherry-pick <測試分支的 commit>` | 「只挑一個 commit」一樣是污染 |
| `git rebase` / `git reset --hard` 到測試分支 | 同上，且會改寫開發分支歷史 |
| `git checkout developing_test -- <path>`、手工複製測試分支的檔案內容 | 繞過 git 一樣算回流 |
| 從測試分支切出新的功能分支 | 新分支一開始就帶著整包待測程式碼 |

**為什麼是紅線：** 測試分支匯集的是**所有待測功能**，其中包含這次不打算上線的東西。一旦回流，這些未核准的變更就混進開發分支，上線時**夾帶沒有要上線的代碼**；而且混入之後已無法從 diff 分辨哪些屬於本次上線範圍，只能靠人記憶，必然出錯。

**遇到「我要的修改只存在於測試分支」時：**

1. 停手，先告知使用者「這個修改只在測試分支上」。
2. 正解是**從開發分支切出功能分支重新實作**（可以讀測試分支的 diff 當參考，但不 merge、不 cherry-pick），再照正常流程合併回測試分支。
3. 只有使用者明確授權才例外——那是使用者的決策，agent **不得自行判斷「這次應該沒關係」**。
<!-- /shared -->

---

## 2. 提交訊息（Conventional Commits）

```
<type>(<scope>): <ticket-id> <subject>

[body：為什麼、涉及不變量、契約變更]
```

| 項目 | 規則 |
|------|------|
| type | `feat`、`fix`、`refactor`、`test`、`chore`、`docs`、`perf` |
| scope | **= 功能包名或層名**：`platform`（業主）、`match`、`odds`、`member`、`notify`、`manage`（總控）、`collector`、`realtime`、`core`（共用層）、`web`（`web/admin`）、`contract`（`docs/contract`）、`migration`、`sim`（`cmd/thesports-sim`）、`deploy` |
| ticket id | **必含**，subject 開頭：`feat(match): S2-T8 apply score rollback with compare-and-set`；bootstrap 用 `B-03`；無 ticket 的雜務用 `chore(deps): - bump go-framework ref`（`-` 佔位） |
| subject | 英文、祈使句、小寫、不加句點、≤ 72 字 |
| body | 涉及不變量寫 `Invariants: I3, I9`；契約變更寫 `Contract: compatible` 或 `Contract: BREAKING (see docs/contract/CHANGELOG.md)` |
| 一個 commit 一件事 | 不把兩張 ticket 混在一個 commit |

**同一 commit 必須一起進的東西：**

| 變更 | 必須同 commit |
|------|-------------|
| 新增或修改 migration | 對應的 `*.gen.go` 重產結果與使用它的程式碼 |
| 契約變更（`/api/front/**`、WebSocket、Kafka 封包） | `docs/contract/` 的 OpenAPI、`realtime.md`、`CHANGELOG.md` |
| 新增或修改 handler／訂閱 action／consumer | 它的 `_test.go`（`testing.md` §1） |
| 後台畫面（B 類） | 對應後端 API 若同張 ticket，一起進 |

---

## 3. 提交前 hook 會擋的事

兩項檢查都在同一支 `hooks/git-guard.sh`（PreToolUse Bash；指令沒有 `git` 字樣就直接放行，JSON 只解析一次）：

| 檢查 | 擋什麼 |
|------|--------|
| check-oq | `plan/` 下仍有「⏳ 待決」OQ → 攔 commit；先決議並回寫 plan |
| protected-branch | 在 `main`／`master` 上 commit／merge、push 到 main、從 main 切分支；在 `developing` 上 commit 或做 §1.2 以外的 merge、rebase、reset、強制推送 → 攔；照 §1.1 從 `origin/developing` 切 feature 分支，照 §1.2 合併 |

`.claude/` 與 `CLAUDE.md` 是版控中的開發範本：改動它們等於改專案規範，另開 `chore(deploy)` commit 走 MR。PM 在本機部署企劃範本造成的覆蓋**不得提交**。

---

## 4. Merge Request 規範

目標分支 `developing`；標題 `<ticket-id>: <一句話>`，例 `S2-T8: 比分與狀態 5 秒內推送、回退更正`。

描述固定格式：

```markdown
## Ticket
S2-T8 — plan/task-S2-T8-plan.md

## AC 對映
| AC | 測試 |
|----|------|
| 2a AC-40 | test/scenario/latency_test.go::TestScoreLatencyP95 |
| 2a AC-41 | internal/match/service/apply_test.go::TestApply_ScoreRollback |

## API 測試清單（每個新增或修改的 API）
- GET /api/front/v1/match/{id} → internal/match/controller/detail_test.go（OK / BadParam / NotFound / OtherTenant）
- WS /match/{matchId} → internal/realtime/subscribe_match_test.go（Snapshot / BadDestination）

## 契約變更
無 ／ 相容（CHANGELOG 已補）／ 破壞性（已與使用者協調，過渡期：…）

## 不變量
I2、I3、I9 — 測試：…

## 驗證
- go build / vet / lint：PASS
- go test ./internal/...：PASS（N 個測試）
- go test -tags=integration ./test/...：PASS ／ 未跑（原因）
- /arch-check：PASS
- /tenant-check：PASS ／ 不適用

## Remaining Work
無 ／ Blocked By: … ／ 待外部: …
```

reviewer（人）以此對照 `testing.md` §8 的 DoD 七條；缺任一段退回。

---

## 5. 回填與提交順序（對齊 `/ticket-run` Step 5）

1. plan §8 完成紀錄 → ticket 狀態欄。
2. `git add <指名檔案>`（含測試、migration、gen、docs/contract）。
3. `git diff --cached --name-only` 確認沒有 `node_modules/`、`dist/`、`.claude/settings.local.json`；ticket commit 不夾帶範本（`.claude/`、`CLAUDE.md`）改動。
4. commit → push → MR。

---

## 6. 不要做的事

| 動作 | 為什麼 |
|------|--------|
| `git push --force` 到 `developing` / `main` | 改寫共用歷史 |
| 在 `developing` 直接 commit | 一律走功能分支，再以 MR 或 §1.2 本機 `--no-ff` 合併 |
| `git commit --no-verify` | 繞過 OQ 與分支攔截 |
| 把兩張 ticket 放同一條分支 | 回填與驗收粒度對不上 |
| commit 裡修改已套用的 migration | `db-migration.md` §1 |
| 契約改了但 `docs/contract/` 沒跟 | `api-contract.md` §4 |
