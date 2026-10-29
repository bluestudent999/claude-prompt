# lion-service 維護範本 — 使用指南

> 一句話定位：**讓 Claude 在 lion-service 上修 bug、做維護需求時，守住這個包網彩票平台最容易出事的三條線**——包網商隔離、filter 防線、賠率與開獎。
> 你只需要在 **lion-service 根目錄啟動 `claude`**，其餘由配置驅動。

---

## 部署

```bash
cd ~/java/lion-service           # 換成你本機 lion-service 的 clone 路徑
prompt-setup 專案維護 lion-service --force
```

**部署前必知三件事：**

1. **lion-service 的 git 追蹤著團隊自己的 `.claude/` 與根 `CLAUDE.md`。** 部署後 `git status` 會一直顯示這兩者有改動——**正常現象，永遠不要提交它們**。
   本範本內建 hook（`hooks/block-claude-dir-staging.sh`）會擋 `git add -A` / `git add .` / `git add .claude` / `git add CLAUDE.md` / `git commit -a`。
2. **`--force` 是乾淨取代**：工作目錄現有的 `.claude/`（可能是團隊版或資安範本）會被清掉換成本範本。團隊版隨時可用 `git restore .claude CLAUDE.md` 拿回來；
   資安範本請先確認 `security-claude/` 正本存在（`pull-keep-claude.sh save`）。**維護與資安不要共用同一個工作目錄**——建議資安掃描另開 worktree。
3. **`pull-keep-claude.sh` 目前寫死資安範本的正本目錄（`security-claude/`）。** 若要在維護範本下 pull 又保留本機範本，需另設正本目錄，否則 pull 完會被換回資安範本。

---

## 前置條件

1. 安裝 Claude Code CLI 並登入（終端機輸入 `claude`，依提示授權）
2. 本機設定（**敏感金鑰不進 git**）：
   ```bash
   cp .claude/settings.local.json.example .claude/settings.local.json
   # 填 GITLAB_TOKEN / GITLAB_URL / JIRA_* —— 變數名以根目錄 .mcp.json 的 ${...} 為準
   ```
   `enableAllProjectMcpServers: true` 才會載入 `.mcp.json` 的 MCP（code-review-graph / context7 / gitlab / jira），改完重啟 session。
3. JDK 1.8（Step -1 Preflight 會檢查 `javac -version`）
4. 共享層 jar：`~/.m2/repository/com/lc/lion/` 若沒有 `lion-common` / `framework_v3`，先到 sibling repo `mvn install` 一次

---

## 目錄結構

```
.claude/
├── README.md                    ← 本文件
├── settings.json                ← Hooks + autoMode 設定
├── settings.local.json          ← 本機私有金鑰 / env（不進 git）
├── rules/                       ← 15 份規範（每次 session 自動注入）
├── checks/                      ← 7 個原子檢查（reviewer 執行 🔬 項目時讀）
├── agents/                      ← 10 個 Sub-agent 定義
├── skills/                      ← 14 個 Skill
└── hooks/                       ← Session 啟動 / 編輯前 / git 指令前自動觸發
```

---

## 快速開始

1. 在 **lion-service 根目錄**啟動 Claude：
   ```bash
   claude
   ```

2. 輸入需求（建議用以下格式，缺欄位不擋工，Claude 會補問）：
   ```
   需求類型：新功能 / bug fix / 重構 / typo / 修資安 finding
   需求簡述：（一句話說明）
   業務關鍵字：（例：彩票計畫、反水、充值、代理、單一錢包、開獎）
   觸發情境：（例：代理後台查下級會員充提紀錄時）
   預期結果：（例：只看得到自己線下的會員，金額欄位正確）
   備註：（單號 PRJ-xxxx / deadline / 資安報告路徑，可省略）
   ```

3. Claude 會走完整流程，遇到需要你決定的地方會暫停詢問。**做完不會自己 commit**——你說「commit」它才會提交。

---

## 這個範本最特別的三條線

| 線 | 為什麼 | Claude 會怎麼做 |
|---|---|---|
| **包網商隔離** | A 家看得到 B 家的任何東西就是事故，而且**單一平台測試 100% 測不出**、CI 又不跑測試 | platformId 只取自登入 token；查詢 / 快取 / ES / 匯出 / 排程都檢查；L1 測試要兩個 platformId |
| **filter 防線** | 認證 filter **曾被實際繞過入侵**（`.do` 放行） | 禁止新增副檔名 / 子字串型放行；動到 filter 一律 L1 + security-reviewer |
| **賠率、限額、開獎** | 不必入侵，讓賠率照自己的意思成立就能穩定獲利 | 賠率只取自伺服器設定；限額同鎖同事務；封盤以伺服器時間；開獎寫入要留痕 |

---

## 開發工作流程

完整說明見 [`rules/development-workflow.md`](rules/development-workflow.md)。

| 步驟 | 行動 | 輸出 |
|------|------|------|
| **Step -1** Preflight | JDK 1.8 對齊 + `mvn compile` smoke | 環境通過才開工 |
| **Step 0** Research | 鎖定 domain（`modules.md`）、分清新舊版、讀業務知識正本 | 受影響檔案清單 |
| **Step 1** Spec | `/spec-review`：產出規格讓 PO 確認，**未確認不動工** | `specs/YYYY-MM-DD_xxx_spec.md` |
| **Step 2** Plan | `planner` agent 拆步驟、識別風險 | `specs/YYYY-MM-DD_xxx_plan.md` |
| **Step 3** Test | L1 → `@SpringBootTest` 整合測試（JUnit 4，強制）；L2/L3 不強制 | 測試檔 |
| **Step 4** Review | code-reviewer + 領域 reviewer 平行啟動 | Harness Output |
| **Step 5** Commit | 給你看 diff 與訊息草稿 → **你說 commit 才提交** → MR to `developing` | MR 連結 |

### 哪些任務可以跳過某步驟

| 任務類型 | 可跳過 |
|---------|--------|
| Bug 修復（非業務邏輯） | Step 1 Spec |
| 純重構 | Step 1 Spec + Step 3 Test |
| 單行 typo / config 值 | Step -1 到 Step 3 全跳，直接 Step 4 輕掃 |
| 修資安 finding | **不可跳 Review**；L1 起跳，修完用 finding 附的驗證方式回驗 |

---

## Agent 路由（依風險層）

| 風險層 | 典型場景 | Reviewer 配置 |
|--------|---------|--------------|
| **L1**（高） | 金額 / 結算 / 狀態機 / 併發 / 第三方對接 / **platformId** / **filter** / **賠率與開獎** | code-reviewer + java-reviewer + business/security-reviewer（平行，後兩者用 opus） |
| **L2**（中） | 一般 service / controller / 跨模組整合 | code-reviewer + 擇一領域 reviewer |
| **L3**（低） | config / VO 欄位 / i18n / pure wiring / typo | code-reviewer × 1（輕掃） |

> 判定原則：**有疑問升級，不降級**。

reviewer 的分級標準統一在 [`rules/severity-rubric.md`](rules/severity-rubric.md)：CRITICAL 必須同時滿足「直接後果 + 已驗證的事故模式 + 能指出 file:line」，只有 confidence ≥ 85 的 finding 會擋合入。

---

## Skill 速查表

| Skill | 呼叫方式 | 何時用 |
|-------|---------|--------|
| `spec-review` | Claude 自動 | 新功能 / 業務修改開發前規格確認 |
| `springboot-patterns` | Claude 自動 | Spring Boot 架構、雙層快取、Spring Cloud Stream 事件 |
| `springboot-security` | Claude 自動 | 驗簽、API Key、Log 脫敏 |
| `springboot-tdd` | Claude 自動 | JUnit 4 + SpringRunner 測試基座 |
| `mysql-patterns` | Claude 自動 | framework_v3 DAO、ShardingSphere、migration |
| `es-patterns` | Claude 自動 | ES 6.8 / 7.17 並用、主從切換 |
| `cross-module-changes` | Claude 自動 | 跨模組 / 共享層 / enum / schema 連動 |
| `api-connector-builder` | **`/api-connector-builder`** | 新增第三方對接時 |
| `cross-repo-commit` | **`/cross-repo-commit`** | 同一需求動到 lion-common / framework_v3 / 前端等多個 repo 時 |
| `documentation-lookup` | **`/documentation-lookup`** | 查第三方函式庫 API |
| `package-structure` | **`/package-structure`** | 新模組初始化或重構 package 結構 |
| `strategic-compact` | **`/strategic-compact`** | 評估是否需要壓縮 context |

> 業務 domain 知識（彩票、反水、代理線、充提、免費旋轉…）**不在本範本**，由團隊維護在 git 版 `.claude/skills/business/`，Claude 會用 `git show` 去讀（見 [`rules/modules.md`](rules/modules.md)）。

---

## Hooks（自動觸發，了解即可）

| 觸發時機 | 行為 |
|---------|------|
| **Session 啟動** | 讀 Memory、列出 `specs/*_plan.md` 裡還沒決議的 OQ |
| **Edit / Write 前** | 擋直接編輯 i18n 檔（改走 `scripts/i18n.py`）；提示是否該壓縮 context |
| **Bash 前** | 擋 plan 仍有 `⏳ 待決` OQ 的 `git commit`；擋 `git add -A` / `.` / `.claude` / `CLAUDE.md` 與 `git commit -a` |
| **Write / Edit 後** | 改到 `specs/*.md` 時重建 `specs/INDEX.md` |

---

## 深入閱讀

| 主題 | 文件 |
|------|------|
| 完整開發工作流程 | [`rules/development-workflow.md`](rules/development-workflow.md) |
| Git 分支 / MR / commit（Claude 不自行 commit） | [`rules/git-workflow.md`](rules/git-workflow.md) |
| 包網商隔離 | [`rules/platform-isolation.md`](rules/platform-isolation.md) |
| filter 防線 / 彩票 / 金額 / 金鑰 / Log 脫敏 | [`rules/security.md`](rules/security.md) |
| 架構分層 / DI / 快取 / 資料物件 | [`rules/patterns.md`](rules/patterns.md) |
| 測試政策（L1-L3） | [`rules/testing.md`](rules/testing.md) |
| 命名 / 註解語言 / Log / 大檔讀取策略 | [`rules/coding-style.md`](rules/coding-style.md) |
| Migration 版本號與兩條 SQL 軌 | [`rules/flyway-migration.md`](rules/flyway-migration.md) |
| 業務 domain 索引與業務知識正本 | [`rules/modules.md`](rules/modules.md) |
| Agent 編排 / 路由 / Harness | [`rules/agents.md`](rules/agents.md) |
| 分級標準 / reviewer 檢查項 / 原子檢查 | [`rules/severity-rubric.md`](rules/severity-rubric.md)、[`rules/reviewer-checklists.md`](rules/reviewer-checklists.md)、[`checks/README.md`](checks/README.md) |
| i18n 多語系 | [`rules/i18n.md`](rules/i18n.md) |
| Pre-commit Hook 設定 | [`rules/java-hooks.md`](rules/java-hooks.md) |
| Token / Session 相容與平滑發佈 | [`rules/stability.md`](rules/stability.md) |
