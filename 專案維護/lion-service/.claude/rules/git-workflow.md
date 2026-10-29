# Git 工作流程

> git 操作層規範（提交、分支、MR 建立）。開發流程（規劃、TDD、審查）詳見 [development-workflow.md](./development-workflow.md)。
> 團隊使用 **GitLab**，術語以 **Merge Request (MR)** 為準；CLI 使用 `glab`。

---

## Claude 不自行 commit（最高優先硬規則，lion 團隊規範）

**不論任何情境，Claude 不自行執行 `git commit`。** 此規則優先於 auto mode、快速 bug fix 例外與其他所有規則。

只有**同時**滿足下列三條才 commit：

1. 使用者**當前訊息**含明確 commit 動詞（「commit」「幫我 commit」「提交」）
2. commit 範圍明確（哪些檔案）
3. commit 訊息使用者確認過（沿用對話中已對齊的草稿，或使用者在同一則訊息直接給了訊息）

**不是 commit 指令**（即使聽起來像同意）：「OK」「可以」「確認」「好」「都改好了」「沒問題」「下一步」「看起來對」「合入吧」。這些是「同意往下走」，不是「請 commit」。模糊就停下來問：「要我 commit 嗎？訊息草稿：…」

寫完 / 修完程式碼後的固定流程：

```
1. （需要時）跑 build / 驗證
2. 給使用者看 diff 摘要
3. 等使用者明確說 commit        ← 沒拿到就永遠停在這裡
4. 草擬 commit 訊息，等使用者 OK
5. git commit，回報 commit hash + git status
```

**為什麼這麼硬：** Claude 判斷「流程結束了」很容易錯（使用者其實還想再改）；commit 進了 reflog 就會影響後續操作。寧可多問一句，不要事後 reset。

### 不要把 `.claude/` 與 `CLAUDE.md` 一起提交

lion-service 的 git 裡**追蹤著團隊自己的 `.claude/` 與根 `CLAUDE.md`**；部署本範本後，工作目錄的這兩者是本範本，`git status` 會顯示大量改動——**這是正常的，不要提交**。

- 一律指名檔案 `git add <path>`，**禁止** `git add -A` / `git add .` / `git add .claude` / `git add CLAUDE.md`
- commit 前用 `git diff --cached --name-only` 確認暫存區沒有 `.claude/` 與根 `CLAUDE.md`

---

## 提交訊息格式

```
<type>: <description>

<optional body>
```

類型：feat、fix、refactor、docs、test、chore、perf、ci

> 團隊慣例：描述用繁體中文、帶單號（例：`feat: PRJ-1299 指定錢包拆電子錢包／虛擬幣兩欄`）。以 `git log --oneline -20` 對齊近期寫法。

## 分支策略

| 分支 | 用途 | 誰合併 |
|------|------|--------|
| `master` | 正式版本 | 僅 tech lead |
| `developing` | 開發整合 | 開發者（需 MR review） |
| `feature/*` | 功能開發 | 開發者 |
| `hotfix/*` | 緊急修復 | 開發者（需 MR review） |
| `release/<YYYYMMDD>` | 上版批次（例：`release/20261008`） | 依團隊上版流程；Claude 不自行 merge 進去 |
| `security/*` | 資安稽核專用（資安範本與報告設定） | **不合回 `master` / `developing`**；修資安 finding 從 `developing` 切 `feature/*` / `hotfix/*` |
| `developing_test` / `developing-test` | 測試環境驗證（若專案有；lion 目前沒有） | 開發者 merge 進去；**禁止回流** |

> 遇到不在上表的分支（例：`marge/*`、`v3.27.3.1`），先問使用者它的用途，不要自行推論能不能 merge。

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

## Merge Request 建立步驟

1. 分析完整的提交歷史（不只是最新提交）
2. 使用 `git diff [base-branch]...HEAD` 查看所有變更
3. 撰寫完整的 MR 摘要（可用 `glab mr create` 或 GitLab Web UI）
4. 包含含有 TODO 的測試計畫
5. **附 AIDD metrics 段落**（觀察用，不阻擋合入） — 模板見 [development-workflow.md §AIDD metrics 模板](./development-workflow.md)
6. 若為新分支，使用 `-u` 旗標推送

## MR 審查流程

1. 開發者在 `feature/*` 或 `hotfix/*` 分支完成開發
2. 確認建置通過：本地 `mvn -pl <module> -am compile`；CI 走 **Jenkins**（`Jenkinsfile`）— **注意 Jenkins 用 `-Dmaven.test.skip=true`，連測試編譯都跳過** → 測試需本地手動跑，CI 綠不是測試通過的證據
3. 使用 **code-reviewer** agent 完成自審
4. 涉及金額/金額異動/訂單/狀態機時，額外使用 **business-reviewer** agent
5. 建立 MR 到 `developing`，指定 reviewer / approver
6. 通過 review 與 pipeline 後合併
