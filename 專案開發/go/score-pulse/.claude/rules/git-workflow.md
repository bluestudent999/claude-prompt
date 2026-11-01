# Git 工作流與提交規範

> 本文規範 score-pulse 的分支策略、Commit 訊息格式、Merge Request（MR）規範與本機範本不進版控的紀律。
> 範本本身不進 git：`.claude/*` 與根 `CLAUDE.md` 已在 `.gitignore`，且 `hooks/block-claude-dir-staging.sh` 會攔 `git add -A` / `.` / `-f`。

---

## 1. 分支策略

| 分支 | 用途 | 規則 |
|------|------|------|
| `main` | 穩定生產 | 只收 `developing` 的 release merge |
| `developing` | 集成主線 | 功能分支的 MR 目標 |
| `developing_test` | 測試環境 | **只收 merge、不回流**（下方紅線） |
| `feature/<ticket-id>-<desc>` | 一張 ticket 一條 | 從 `developing` 切出；例 `feature/S2-T8-live-score`、`feature/B-03-profiles`（bootstrap 步驟） |
| `hotfix/<desc>` | 緊急修復 | 從 `main` 切出，回 `main` 與 `developing` |

一條功能分支只做一張 ticket；ticket 完成（DoD 七條）才開 MR。

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
| scope | **= 功能包名或層名**：`operator`、`match`、`odds`、`member`、`notify`、`admin`、`collector`、`realtime`、`platform`、`web`（`web/admin`）、`contract`（`docs/contract`）、`migration`、`sim`（`cmd/thesports-sim`）、`deploy` |
| ticket id | **必含**，subject 開頭：`feat(match): S2-T8 apply score rollback with compare-and-set`；bootstrap 用 `B-03`；無 ticket 的雜務用 `chore(deploy): - bump sp-framework tag`（`-` 佔位） |
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

| hook | 擋什麼 |
|------|--------|
| `check-oq-on-commit.sh` | `plan/` 下仍有「⏳ 待決」OQ → 攔 commit；先決議並回寫 plan |
| `block-claude-dir-staging.sh` | `git add -A`、`git add .`、`git add .claude`、`git add CLAUDE.md`、`git commit -a`、`git add -f` 命中範本路徑 → 攔；改為指名檔案 `git add internal/...` |

`.claude/` 與 `CLAUDE.md` 是本機範本，**永遠不提交**。`git status` 看不到它們是正常的（已 ignore）。

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

## 5. 回填與提交順序（對齊 `development-workflow.md` Step 5）

1. plan §8 完成紀錄 → ticket 狀態欄。
2. `git add <指名檔案>`（含測試、migration、gen、docs/contract）。
3. `git diff --cached --name-only` 確認沒有 `.claude/`、`CLAUDE.md`、`node_modules/`、`dist/`。
4. commit → push → MR。

---

## 6. 不要做的事

| 動作 | 為什麼 |
|------|--------|
| `git push --force` 到 `developing` / `main` | 改寫共用歷史 |
| 在 `developing` 直接 commit | 一律走功能分支 + MR |
| `git commit --no-verify` | 繞過 OQ 與範本攔截 |
| 把兩張 ticket 放同一條分支 | 回填與驗收粒度對不上 |
| commit 裡修改已套用的 migration | `db-migration.md` §1 |
| 契約改了但 `docs/contract/` 沒跟 | `api-contract.md` §4 |
