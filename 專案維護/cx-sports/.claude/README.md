# cx-sports-v2 Claude 使用指南

> `.claude/` 是 Claude Code CLI 的專案級配置目錄，內含規範（rules）、自訂 Agent 定義、Skill 集合與 Hooks。
> 這些配置讓 Claude 了解 cx-sports-v2 的架構慣例，並依照團隊規範自動執行開發工作流程。
> 你只需要在 **cx-sports-v2 根目錄啟動 `claude`**，其餘由配置驅動。

---

## 前置條件

1. 安裝 Claude Code CLI：
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```
2. 首次登入：在終端機輸入 `claude`，依提示完成 Anthropic 帳號授權
3. 複製本機設定範本（**敏感金鑰不進 git**）：
   ```bash
   cp .claude/settings.local.json.example .claude/settings.local.json
   # 填入 GITLAB_TOKEN 等 env 變數
   ```
4. 確認 JDK 1.8 已安裝（Step -1 Preflight 細節見下方）

---

## 目錄結構

```
.claude/
├── README.md             ← 本文件
├── settings.json         ← 自動允許指令清單 + Hooks 設定（git 追蹤）
├── settings.local.json   ← 本機私有金鑰 / env（不進 git，.gitignore）
├── rules/                ← 11 份規範（Claude 每次 session 自動注入）
├── agents/               ← 9 個 Sub-agent 定義（Claude 自動路由）
├── skills/               ← 16 個 Skill（用 /skill-name 呼叫）
└── hooks/                ← Session 啟動 / 編輯前 / commit 前自動觸發腳本
```

---

## 快速開始

1. 在 **cx-sports-v2 根目錄**啟動 Claude：
   ```bash
   claude
   ```

2. 輸入需求（建議用以下 5 欄位格式，缺欄位不擋工，Claude 會補問）：
   ```
   需求類型：新功能 / bug fix / 重構 / typo
   需求簡述：（一句話說明）
   業務關鍵字：（例：投注、結算、餘額）
   觸發情境：（例：使用者呼叫 /bet API 時）
   預期結果：（例：下注成功後餘額扣減、訂單建立）
   備註：（deadline / ticket 連結，可省略）
   ```

3. Claude 會自動走完整工作流程，遇到需要決策的地方會暫停詢問。

---

## 開發工作流程（6 步）

完整說明見 [`rules/development-workflow.md`](rules/development-workflow.md)。

| 步驟 | 行動 | 輸出 |
|------|------|------|
| **Step -1** Preflight | JDK 1.8 對齊 + `mvn compile` smoke | 環境通過才開工 |
| **Step 0** Research | grep 既有實作、鎖定 domain 目錄（見 `modules.md`） | 受影響檔案清單 |
| **Step 1** Spec | `/spec-review`：產出規格讓 PO 確認，**未確認不動工** | `plan/xxx_spec.md` |
| **Step 2** Plan | `planner` agent 拆步驟、識別風險 | `plan/xxx_plan.md` |
| **Step 3** Test | L1 風險 → `@SpringBootTest` 整合測試（強制）；L2/L3 不強制 | 測試檔 |
| **Step 4** Review | code-reviewer + 領域 reviewer 平行啟動（依 L 層配置） | Harness Output |
| **Step 5** Commit | conventional commit → `feature/*` → MR to `developing` | MR 連結 |

### 哪些任務可以跳過某步驟

| 任務類型 | 可跳過 |
|---------|--------|
| Bug 修復（非業務邏輯） | Step 1 Spec |
| 純重構 | Step 1 Spec + Step 3 Test |
| 單行 typo / config 值 | Step -1 到 Step 3 全跳，直接 Step 4 輕掃 |

---

## Skill 速查表

> 大多數 skill 由 Claude 依任務自動載入；以下標示**需要開發者主動呼叫**的情況。

| Skill | 呼叫方式 | 何時用 |
|-------|---------|--------|
| `spec-review` | Claude 自動 | 新功能開發前規格確認 |
| `springboot-patterns` | Claude 自動 | Spring Boot 架構、雙層快取、Kafka 事件模式 |
| `springboot-security` | Claude 自動 | 驗簽、API Key、Log 脫敏 |
| `springboot-tdd` | Claude 自動 | JUnit 4 + SpringRunner 測試基座設置 |
| `mysql-patterns` | Claude 自動 | DAO、ShardingSphere、Flyway migration |
| `es-patterns` | Claude 自動 | ES 6.8 / 7.17 並用、主從切換 |
| `api-connector-builder` | **`/api-connector-builder`** | 新增第三方對接時主動呼叫 |
| `cross-repo-commit` | **`/cross-repo-commit`** | 跨 repo 提交前主動呼叫 |
| `documentation-lookup` | **`/documentation-lookup`** | 查第三方函式庫最新 API |
| `package-structure` | **`/package-structure`** | 新模組初始化或重構 package 結構 |
| `vue2-patterns` | Claude 自動（前端任務） | Vue 2 API 呼叫、認證、表格分頁 |
| `vue2-coding-standards` | Claude 自動（前端任務） | Vue 2 + Element UI 程式碼規範 |
| `strategic-compact` | **`/strategic-compact`** | 評估是否需要壓縮 context |

---

### rules/ — 規範（不需手動載入）

| 檔案 | 內容 |
|------|------|
| `development-workflow.md` | **核心**：Preflight → Spec → Plan → Test → Review → Commit 流程 |
| `git-workflow.md` | 分支策略、conventional commit、MR 建立 |
| `patterns.md` | 分層架構、DI、雙層快取、資料物件命名 |
| `security.md` | 金額 BigDecimal、RoundingMode、7 步餘額異動、Log 脫敏 |
| `testing.md` | L1-L3 風險分層、JUnit 4 + SpringRunner 整合測試基座 |
| `coding-style.md` | 命名、Log、大檔案讀取策略（> 300 行禁 full read） |
| `modules.md` | 業務 domain 索引（收需求時先對照這裡縮小 grep 範圍） |
| `agents.md` | Agent 路由邏輯、Harness Output Contract、子 Agent 規範 |
| `i18n.md` | 多語系新增：前端走 Python 腳本，禁止直接 Edit i18n 檔 |
| `java-hooks.md` | Pre-commit hook / PostToolUse Maven 設定 |
| `stability.md` | 系統穩定性、登入 Token 相容與 WebSocket 斷線防禦 |

### agents/ — Sub-agent（Claude 自動啟動，無需手動呼叫）

| Agent | 觸發時機 |
|-------|---------|
| `planner` | 功能需求確定後，拆解實作步驟 |
| `code-reviewer` | 每次寫完程式碼後的第一道審查 |
| `java-reviewer` | Controller / Service / DAO 等 Java 變更 |
| `business-reviewer` | 涉及金額、訂單、狀態機的邏輯審查 |
| `security-reviewer` | 驗簽、加密、回調、使用者輸入相關 |
| `database-reviewer` | SQL、Flyway migration、Schema 設計 |
| `tdd-guide` | L1 風險整合測試驅動開發 |
| `build-error-resolver` | `mvn compile` 失敗時自動診斷 |
| `architect` | 技術方案評估、架構決策 |


## Agent 路由（依風險層）

Claude 依變更風險自動決定派哪些 reviewer，**不需要手動指定**。

| 風險層 | 典型場景 | Reviewer 配置 |
|--------|---------|--------------|
| **L1**（高） | 金額 / 餘額 / 結算 / 狀態機 / 併發 / 第三方對接 | code-reviewer + java-reviewer + business/security-reviewer（平行） |
| **L2**（中） | 一般 service / controller / 跨模組整合 | code-reviewer + 擇一領域 reviewer |
| **L3**（低） | config / DTO / i18n / pure wiring / typo | code-reviewer × 1（輕掃） |

> 判定原則：**有疑問升級，不降級**。L2/L3 邊界不確定時取 L2 配置。

## Hooks（自動觸發，了解即可）

| 觸發時機 | 行為 |
|---------|------|
| **Session 啟動** | 讀取 Memory 記錄、檢查是否有未解決的 Open Questions |
| **Edit / Write 前** | 偵測嘗試直接編輯 i18n 檔，擋住並提示用 script |
| **Bash commit 前** | 檢查 plan.md 是否有未決議的 OQ（⏳ 待決），有則阻擋合入 |

---

## 深入閱讀

| 主題 | 文件 |
|------|------|
| 完整開發工作流程 | [`rules/development-workflow.md`](rules/development-workflow.md) |
| Git 分支 / MR / commit | [`rules/git-workflow.md`](rules/git-workflow.md) |
| 架構分層 / DI / 快取 | [`rules/patterns.md`](rules/patterns.md) |
| 金額 / 金鑰 / Log 脫敏 | [`rules/security.md`](rules/security.md) |
| 測試政策（L1-L3） | [`rules/testing.md`](rules/testing.md) |
| 命名 / Log / 大檔讀取策略 | [`rules/coding-style.md`](rules/coding-style.md) |
| 業務 domain 索引 | [`rules/modules.md`](rules/modules.md) |
| Agent 編排 / 路由 / Harness | [`rules/agents.md`](rules/agents.md) |
| i18n 多語系 | [`rules/i18n.md`](rules/i18n.md) |
| Pre-commit Hook 設定 | [`rules/java-hooks.md`](rules/java-hooks.md) |
| 系統穩定性與平滑發佈 | [`rules/stability.md`](rules/stability.md) |
