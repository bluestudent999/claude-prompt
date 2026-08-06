# crypto-payment Claude 使用指南

> `.claude/` 是 Claude Code CLI 的專案級配置目錄，內含規範（rules）、自訂 Agent、Skill 與 Hooks。
> 這些配置讓 Claude 了解 crypto-payment 的架構慣例，並依團隊規範自動執行維護開發工作流程。
> 你只需要在 **crypto-payment 根目錄啟動 `claude`**，其餘由配置驅動。

> **語言：** AI 回覆與程式碼註解一律繁體中文；日誌訊息英文。

---

## 前置條件

1. 安裝 Claude Code CLI：`npm install -g @anthropic-ai/claude-code`
2. 首次登入：終端輸入 `claude` 完成授權
3. 確認 **JDK 21** 已安裝（Step -1 Preflight）
4. 若有 `.claude/settings.local.json.example`，複製一份填本地憑證（勿進版控）

---

## 目錄結構

```
.claude/
├── README.md             ← 本文件
├── settings.json         ← 自動允許清單 + Hooks（git 追蹤）
├── rules/                ← 規範（Claude 每次 session 自動注入）
├── agents/               ← Sub-agent 定義（Claude 自動路由）
├── skills/               ← Skill（用 /skill-name 或自動載入）
├── commands/             ← 專用指令（/new-feature、/trace-deposit…）
└── hooks/                ← Session / commit / 編輯後觸發腳本
```

---

## 快速開始

1. 在 **crypto-payment 根目錄**啟動：`claude`

2. 輸入需求（建議 6 欄位格式，缺欄位不擋工，Claude 會補問）：
   ```
   需求類型：新功能 / bug fix / 重構 / typo
   需求簡述：（一句話）
   業務關鍵字：（例：入款、歸集、webhook、錢包、platform_id）
   觸發情境：（例：QuickNode webhook 進來時）
   預期結果：（例：ETH 入款成功後 credit 用戶帳戶並發 Kafka event）
   備註：（工單 PROJ-XXX / deadline，可省略）
   ```

3. Claude 自動走工作流程，遇需決策處暫停詢問。

---

## 開發工作流程（5 步 + preflight）

完整說明見 [`rules/development-workflow.md`](rules/development-workflow.md)。

| 步驟 | 行動 | 輸出 |
|------|------|------|
| **Step -1** Preflight | JDK 21 對齊 + `mvn compile` smoke | 環境通過才開工 |
| **Step 0** Research | grep `utils/`（25 類）+ 既有 `service/`，鎖定 domain（`modules.md`） | 受影響檔案清單 |
| **Step 1** Spec | `/spec-review`：產出規格讓 PO 確認，**未確認不動工** | `plan/xxx_spec.md` |
| **Step 2** Plan | `planner` 拆步驟、識別風險、OQ | `plan/xxx_plan.md` |
| **Step 3** Test | L1 → JUnit 5 整合測試（強制）；L2/L3 不強制 | 測試檔 |
| **Step 4** Review | code-reviewer + 領域 reviewer 平行（依 L 層） | Harness Output |
| **Step 5** Commit | `type(PROJ-XXX)` → `feature/PROJ_XXX` → merge `--no-ff` `developing_test` | 分支 |

### 可跳步的任務

| 任務 | 可跳過 |
|------|--------|
| Bug 修復（非業務邏輯） | Step 1 Spec |
| 純重構 | Step 1 Spec + Step 3 Test |
| 單行 typo / config | Step -1~3 全跳，直接 Step 4 輕掃 |

---

## 硬性規範速查（合入前必查）

| 主題 | 位置 |
|------|------|
| 私鑰 AES-GCM / 禁明文 / 禁 log | [`rules/security.md`](rules/security.md) §1 |
| 多租戶 platform_id 隔離 | [`rules/security.md`](rules/security.md) §2 |
| HMAC 驗簽 / SignFilter / 防重放 | [`rules/security.md`](rules/security.md) §3 |
| 金額 BigDecimal / RoundingMode.DOWN | [`rules/security.md`](rules/security.md) §5 |
| Flyway 只增不改 / ShardingSphere 自動路由 | [`rules/patterns.md`](rules/patterns.md) §8 |
| BaseResponse / 建構子注入 / 自訂例外 | [`rules/patterns.md`](rules/patterns.md) §2-4 |
| webhook / Kafka 冪等 / 鏈重組 | [`rules/stability.md`](rules/stability.md) |

---

## Skill 速查

> 多數 skill 由 Claude 依任務自動載入。

| Skill | 何時用 |
|-------|--------|
| `spec-review` | 新功能開發前規格確認 |
| `springboot3-patterns` | Spring Boot 3 / Java 21 架構、Kafka、快取、排程 |
| `springboot-security` | AES-GCM、HMAC、IP 白名單、2FA、金額安全 |
| `springboot-tdd` | JUnit 5 + Mockito 測試基座 |
| `mysql-shardingsphere5` | DAO、ShardingSphere 5.4、Flyway |
| `blockchain-wallet` | 錢包、私鑰、鏈 client、入款、歸集、webhook |
| `api-connector-builder` | 新鏈 / webhook provider 對接（QuickNode/Tatum） |
| `cross-module-changes` | 跨 service / flyway / frontend 連動 |
| `documentation-lookup` | 查 Web3j / Trident / ShardingSphere 等文件 |
| `package-structure` | 新模組 / 重構 package 結構 |
| `vue2-patterns` / `vue2-coding-standards` | Vue 2 前端開發 |
| `strategic-compact` | 評估是否需壓縮 context |

## 專用指令

| 指令 | 用途 |
|------|------|
| `/new-feature` | 起新功能工單（走標準流程） |
| `/new-migration` | 新增 Flyway 版號 migration |
| `/trace-deposit` | 追蹤入款流程（webhook→驗簽→匹配→入帳） |
| `/check-platform-isolation` | 稽核查詢 platform_id 過濾 |
| `/review-endpoint` | 審查新 endpoint（filter/驗簽/權限） |
| `/security-check` | 安全規範自查 |
| `/gen-test` | 產生 JUnit 5 測試骨架 |
| `/merge-to-test` | 合併 feature 到 developing_test |
| `/export-pdf` | 匯出文件為 PDF |

---

## Agent 路由（依風險層）

| 風險層 | 典型場景 | Reviewer 配置 |
|--------|---------|--------------|
| **L1**（高） | 金額 / 入帳 / 歸集 / 狀態機 / 併發 / 私鑰 / AES-GCM / HMAC / platform_id / webhook / 鏈對接 | code-reviewer + java-reviewer + business/security/database（平行） |
| **L2**（中） | 一般 service / controller / 跨模組 | code-reviewer + 擇一領域 reviewer |
| **L3**（低） | config / VO / 純 wiring / typo | code-reviewer × 1 |

> 判定原則：**有疑問升級，不降級**。詳見 [`rules/agents.md`](rules/agents.md)。

## Hooks（自動觸發）

| 時機 | 行為 |
|------|------|
| **Session 啟動** | 讀取 Memory；檢查 plan/ 未決 Open Questions |
| **Bash git commit 前** | 驗 commit message `type(PROJ-XXX)` 格式；擋 plan 未決 OQ |
| **Edit / Write 後** | 改業務層檔案提示 `/security-check` |
| **Stop** | 有未提交變更時提示 mvn test / security-check / 確認分支 |

---

## 深入閱讀

| 主題 | 文件 |
|------|------|
| 完整開發工作流程 | [`rules/development-workflow.md`](rules/development-workflow.md) |
| Git 分支 / commit / merge | [`rules/git-workflow.md`](rules/git-workflow.md) |
| 分層 / DI / 回應信封 / 快取 / Flyway | [`rules/patterns.md`](rules/patterns.md) |
| 私鑰 / HMAC / platform_id / 金額 / 脫敏 | [`rules/security.md`](rules/security.md) |
| 測試政策（JUnit 5 / L1-L3） | [`rules/testing.md`](rules/testing.md) |
| 命名 / Log / 大檔讀取策略 | [`rules/coding-style.md`](rules/coding-style.md) |
| 業務 domain 索引 | [`rules/modules.md`](rules/modules.md) |
| 冪等 / 防重放 / 鏈重組 / 平滑發佈 | [`rules/stability.md`](rules/stability.md) |
| Agent 編排 / 路由 / Harness | [`rules/agents.md`](rules/agents.md) |
| Pre-commit / PostToolUse Hook | [`rules/java-hooks.md`](rules/java-hooks.md) |
