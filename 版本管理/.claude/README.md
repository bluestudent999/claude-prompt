# 版本升級 Claude 使用指南

> `.claude/` 是 Claude Code CLI 的專案級配置目錄，**專門用於「將 Maven 多模組專案從 Java 8 / Spring Boot 2.x 升級到 Java 17/21 / Spring Boot 3.x」**。
> 內含升級生命週期規範（rules）、升級專用 Sub-agent、自動遷移 Skill 與 Hooks。
> 把整個 `.claude/` 連同 `CLAUDE.md` 複製到**待升級專案根目錄**，在該根目錄啟動 `claude` 即可。

---

## 升級策略：直接跳躍

本配置採**直接跳躍升級**——一次把版本拉到目標（Java 21 + Boot 3.x），靠下列三道安全網收斂，不逐版遞進：

1. **自動遷移**（OpenRewrite recipe）先吃掉 80% 機械改動
2. **編譯錯誤收斂**（`build-error-resolver`）處理 recipe 未覆蓋的尾巴
3. **回歸測試**（`verification.md`）證明行為等價

> 直接跳躍快，但 breaking change 一次全湧出。**核心防呆 = 行為等價紅線 + 版本單一事實來源 + 自動遷移優先**（見 `CLAUDE.md §2`）。

---

## 前置條件

1. 安裝 Claude Code CLI：`npm install -g @anthropic-ai/claude-code`，首次 `claude` 完成授權。
2. 本機同時安裝**來源 JDK（8）與目標 JDK（17 或 21）**，記錄路徑到 `settings.local.json`。
3. 複製本機設定範本（敏感資訊不進 git）：
   ```bash
   cp .claude/settings.local.json.example .claude/settings.local.json
   # 填入 JAVA_HOME_SOURCE / JAVA_HOME_TARGET 等
   ```
4. 確認可連到 Maven 私服（若有內部依賴）。

---

## 目錄結構

```
.claude/
├── README.md                    ← 本文件
├── CLAUDE.md                    ← 部署到專案根目錄的主規範（升級紅線 + 6 步生命週期）
├── settings.json                ← 權限 + Hooks（git 追蹤）
├── settings.local.json.example  ← 本機私有 env 範本（不進 git）
├── rules/                       ← 9 份規範（每次 session 自動注入）
├── agents/                      ← 6 個升級專用 Sub-agent（自動路由）
├── skills/                      ← 5 個 Skill（用 /skill-name 呼叫）
├── workflows/                   ← 2 個多 Agent 編排（升級掃描 / 等價驗證）
└── hooks/                       ← Session 啟動 / commit 前 / jakarta 單向性守門
```

---

## 升級生命週期（6 步）

完整說明見 [`rules/upgrade-workflow.md`](rules/upgrade-workflow.md)。

| 步驟 | 行動 | 輸出 |
|------|------|------|
| **Step -1** Preflight | 雙 JDK 對齊、來源版本 baseline 綠燈（升級前最後一次全綠） | 升級基準點 |
| **Step 0** 盤點 | `/upgrade-inventory` 掃 javax import / 棄用 API / 依賴版本 / 設定屬性 | `upgrade/inventory.md` |
| **Step 1** 計畫 | `upgrade-planner` 分階段（依賴 BOM → jakarta → 設定 → 編譯收斂 → 回歸） | `upgrade/task-xxx-plan.md` |
| **Step 2** 自動遷移 | `/rewrite-run` 跑 OpenRewrite（先 dryRun 審 diff 再 run） | recipe diff |
| **Step 3** 編譯收斂 | `build-error-resolver` 分類修復 recipe 未覆蓋的編譯錯誤 | 真編譯綠燈 |
| **Step 4** 回歸驗證 | 跑回歸測試套件，`regression-reviewer` 審行為等價 | 回歸證據 + Review |
| **Step 5** 提交 | 升級分支 → conventional commit → MR（附版本對照 + 行為差異） | MR 連結 |

---

## Skill 速查表

| Skill | 呼叫方式 | 何時用 |
|-------|---------|--------|
| `upgrade-inventory` | **`/upgrade-inventory`** | 升級開工第一步，盤點整個升級面 |
| `rewrite-run` | **`/rewrite-run`** | 跑 OpenRewrite recipe 做自動遷移（jakarta / Boot 3 屬性 / 棄用 API） |
| `boot3-config-migrate` | **`/boot3-config-migrate`** | 遷移 application.yml / properties 的 Boot 3 屬性改名與棄用 |
| `dependency-bump` | **`/dependency-bump`** | 升級單一第三方依賴並查 jakarta + Spring 6 相容版本 |
| `strategic-compact` | **`/strategic-compact`** | 評估是否需要壓縮 context |

## Sub-agent 速查表（Claude 自動啟動）

| Agent | 觸發時機 |
|-------|---------|
| `upgrade-planner` | 盤點完成後，拆解升級階段與 OQ |
| `dependency-analyzer` | 依賴版本衝突、BOM 對齊、jakarta 相容版本決策 |
| `compat-researcher` | 查第三方庫對 jakarta + Boot 3 的最低相容版本 |
| `build-error-resolver` | 升級後 `mvn compile` 大量錯誤時 |
| `config-migrator` | application.yml / properties 設定遷移 |
| `regression-reviewer` | 升級 diff 的行為等價 / 回歸風險審查（升級期主審） |

---

## rules/ — 規範（自動注入，不需手動載入）

| 檔案 | 內容 |
|------|------|
| `upgrade-workflow.md` | **核心**：Preflight → 盤點 → 計畫 → 自動遷移 → 編譯收斂 → 回歸 → 提交 |
| `version-matrix.md` | **單一事實來源**：Java / Boot / Framework / 第三方依賴相容版本矩陣 |
| `jakarta-migration.md` | javax → jakarta namespace 遷移規範 + Java SE 保留 javax 白名單 |
| `breaking-changes.md` | Java 17/21 + Spring Boot 3 已知 breaking change 清單與修法 |
| `openrewrite.md` | OpenRewrite recipe 使用規範（自動遷移主力、dryRun 先行） |
| `verification.md` | 行為等價回歸測試政策（升級期測試的意義與分層） |
| `coding-style.md` | 升級期程式碼風格（可採用哪些新特性、大檔讀取策略） |
| `git-workflow.md` | 升級分支、commit 粒度（一階段一 commit）、MR 模板 |
| `agents.md` | 升級風險分層、reviewer 路由、子 Agent briefing |

---

## Hooks（自動觸發，了解即可）

| 觸發時機 | 行為 |
|---------|------|
| **Session 啟動** | 讀 Memory、檢查 `upgrade/*-plan.md` 是否有未決 OQ |
| **Bash commit 前** | plan 有「⏳ 待決」OQ 則阻擋 commit |
| **Edit / Write 前** | （Boot 3 階段啟用後）攔截新增非 Java SE 的 `javax.*` import |

> 啟用 jakarta 單向性守門：進入 Boot 3 階段後，把 `hooks/block-new-javax-import.sh` 內 `GUARD_ENABLED` 改為 `1`。

---

## 快速開始

```bash
# 1. 在待升級專案根目錄
claude

# 2. 下達升級工單
執行 UPGRADE-001：將 cx-xxx-service 從 Spring Boot 2.7 / Java 8 升級到 Spring Boot 3.x / Java 21

# Claude 會自動：盤點 → 計畫（遇 OQ 暫停問你）→ OpenRewrite 自動遷移 → 編譯收斂 → 回歸 → MR
```
