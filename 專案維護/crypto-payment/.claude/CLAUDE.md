# crypto-payment

多租戶加密貨幣支付平台：Spring Boot 3 / Java 21 後端 + Vue 2 後台前端。支援 TRON / BSC / Ethereum，處理錢包產生、入款偵測、代幣歸集(sweep)與 webhook 通知。本文件是 `.claude/` 規範集的入口索引；細節請依連結深入閱讀。

> **語言慣例：** AI 回覆與程式碼註解一律**繁體中文**（技術術語用英文）；日誌訊息用英文。

---

## 0. 快速上手導引

當使用者說出「如何開始」「怎麼開始」「要提供哪些資訊」「如何提需求」等關鍵詞時，
用 `grep -n "## 快速開始" .claude/README.md` 取得行號 N，再 Read offset=N limit=20，將內容直接輸出給使用者。

---

## 1. 專案概覽

- **groupId / 模組**：`crypto-payment`（Maven 多模組，**同一 repo**）
  - `crypto-payment-service` — 主後端，port 8700
  - `crypto-payment-flyway` — Flyway DB migration runner
  - `front/crypto-payment-admin-frontend` — Vue 2 後台
- **Java**：21 / **Spring Boot**：3.1.2
- **資料層**：MySQL 8 + **ShardingSphere 5.4**（讀寫分離，自動路由）+ Flyway（**同 repo 模組**）
- **快取**：Redis / **Jedis 4.4.3**（**非** Lettuce）
- **訊息**：**原生 Apache Kafka**（**不是** Spring Cloud Stream）
- **排程**：Quartz + Spring `@Scheduled`
- **區塊鏈**：Web3j 4.9.4（BSC/ETH）、Trident 0.10.0（TRON）、BitcoinJ 0.15.10
- **加密**：Bouncy Castle 1.78、AES-GCM
- **前端**：Vue 2 + Element UI + Vuex + Webpack 3
- **建置**：`mvn clean package -DskipTests`；測試 `mvn test`

## 2. 模組路由（接到任務時優先查這裡）

完整路由索引（domain / 風險等級 / 對應目錄 / API 分區）→ [`.claude/rules/modules.md`](.claude/rules/modules.md)
> **多租戶硬規則：** 幾乎所有查詢都須以 `platform_id` 過濾；跨平台資料存取 = **critical bug**（見 [`.claude/rules/security.md`](.claude/rules/security.md)）。

## 跨 prompt-setup 職責路由（越界即提示切換）

本範本（`.claude/`）只負責軟體生命週期的**單一階段**。若接到的工作**不屬於本階段職責**——例如「這其實是新需求規劃」或「這其實是版本升級遷移」——**不要硬接、不要在本階段臆測代答**，而是明確**提示使用者切換到對應的 prompt-setup 範本**，並附一句「為什麼這屬於他階段」。

| 撞到的工作性質（非本職） | 應切換到 | 指令 |
|---|---|---|
| 需求收斂 / 商業價值 / 範圍界定 / Persona / 驗收標準 / 規格 / 任務拆解 | 企劃 | `prompt-setup 專案企劃` |
| 新功能開發（Python / AI UX 稽核平台） | 開發 | `prompt-setup 專案開發 ai-ux-agent` |
| 新功能開發（Java 21 / Spring Modulith） | 開發 | `prompt-setup 專案開發 java` |
| 既有主業務維護 / 修 bug（cx-sports-v2，Java 8 / Boot 2） | 維護 | `prompt-setup 專案維護 cx-sports` |
| 既有加密支付維護 / 修 bug（crypto-payment，Java 21 / Boot 3） | 維護 | `prompt-setup 專案維護 crypto-payment` |
| Java 8→21 / Boot 2→3 版本升級遷移 | 版本管理 | `prompt-setup 版本管理` |
| 已完成網站的 UX 體驗稽核（實際開瀏覽器體驗、產 UX 修改建議報告） | 網站體驗稽核 | `prompt-setup 網站體驗稽核` |
| 既有骰寶辨識維護 / 修 bug（sicbo，Python / YOLO 影像辨識） | 維護 | `prompt-setup 專案維護 sicbo` |
| crypto-node 鏈下索引服務開發（Java 21 / Boot 3.5 / 多租戶） | 開發 | `prompt-setup 專案開發 java crypto-node` |
| YUMMY 老虎機開發（Java 21 / Boot 3.5 + H5 遊戲前端，複製既有玩法） | 開發 | `prompt-setup 專案開發 java slots` |
| lion-service 包網平台資安掃描（原始碼與設定靜態稽核，只產報告不改 code） | 資訊安全 | `prompt-setup 資訊安全 lion-service` |
| cx-sports-v2 體育投注主業務資安掃描（原始碼與設定靜態稽核，只產報告不改 code） | 資訊安全 | `prompt-setup 資訊安全 cx-sports-v2` |
| 既有包網彩票平台維護 / 修 bug（lion-service，Java 8 / Boot 2.0） | 維護 | `prompt-setup 專案維護 lion-service` |
| score-pulse 比分平台後端與後台開發（Go / sp-framework / MySQL / Kafka） | 開發 | `prompt-setup 專案開發 go score-pulse` |

> **你在這裡：維護 · crypto-payment**（表格第 5 列為本職，不適用切換）。切換提示範例：「這是一段全新需求，請先 `prompt-setup 專案企劃` 收斂範圍」「這是 cx-sports-v2（體育主業務）的維護，本範本是 crypto-payment，請 `prompt-setup 專案維護 cx-sports`」。

## 3. 硬性規範（合入前必查）

| 主題 | 規範 |
|------|------|
| 私鑰 / 加密 | [`.claude/rules/security.md`](.claude/rules/security.md)（AES-GCM 私鑰、禁明文、禁 log） |
| 多租戶隔離 | [`.claude/rules/security.md`](.claude/rules/security.md)（所有查詢過濾 `platform_id`） |
| HMAC 驗簽 | [`.claude/rules/security.md`](.claude/rules/security.md)（SignFilter /api/pay/*，timestamp+nonce，5 分鐘 replay window） |
| 金額 | [`.claude/rules/security.md`](.claude/rules/security.md)（BigDecimal / RoundingMode.DOWN） |
| DB Migration | [`.claude/rules/flyway-migration.md`](.claude/rules/flyway-migration.md)（**新檔用時間戳版本號**、禁改既有）＋ [`.claude/rules/patterns.md`](.claude/rules/patterns.md)（ShardingSphere 自動路由） |
| 回應信封 / 例外 | [`.claude/rules/patterns.md`](.claude/rules/patterns.md)（BaseResponse&lt;T&gt;、自訂 exception、建構子注入） |
| 冪等 / 防重放 | [`.claude/rules/stability.md`](.claude/rules/stability.md)（webhook / Kafka 重送、nonce、鏈重組） |
| 測試（Boot 3） | [`.claude/rules/testing.md`](.claude/rules/testing.md)（JUnit 5 Jupiter，L1 強制整合測試） |
| Grounding / Token | [`.claude/rules/coding-style.md`](.claude/rules/coding-style.md)（&gt; 300 行禁 full read） |

## 4. 開發工作流程（5 步 + preflight）

```
Step -1 Preflight（JAVA_HOME=21 + mvn compile smoke）
Step 0  Research（先查 utils/ 25 類 + 既有 service/，避免重複造輪子）
Step 1  Spec   （spec-review skill；規格未確認不動工）
Step 2  Plan   （planner agent → plan/YYYY-MM-DD_<feat>_plan.md，8 章節）
Step 3  Test   （L1 → JUnit 5 整合測試；L2/L3 → 不強制）
Step 4  Review （增量 + 最終多 reviewer 平行）
Step 5  Commit （type(PROJ-XXX): 描述；feature/PROJ_XXX → merge --no-ff developing_test）
```

完整規範見 [`.claude/rules/development-workflow.md`](.claude/rules/development-workflow.md) 與 [`.claude/rules/git-workflow.md`](.claude/rules/git-workflow.md)。

## 5. Agent 路由

L3 → `code-reviewer` × 1；L2 → + 擇一領域；L1 → + `java-reviewer` + 必要領域（**私鑰/HMAC/webhook → security；金額/入帳/歸集/狀態機 → business；SQL/Flyway → database**），**平行啟動**；所有 reviewer 須輸出 Harness Output Contract。
詳見 [`.claude/rules/agents.md`](.claude/rules/agents.md)。

## 6. Skills（按任務載入）

| Skill | 用途 |
|-------|------|
| `spec-review` | 開發前產出結構化規格讓 PO 確認 |
| `springboot3-patterns` | Spring Boot 3 / Java 21 架構、分層、Kafka、快取失效、排程 |
| `springboot-security` | AES-GCM、HMAC 驗簽、IP 白名單、2FA、金額安全、Log 脫敏 |
| `springboot-tdd` | JUnit 5 + Mockito + `@SpringBootTest` 測試基座 |
| `mysql-shardingsphere5` | DAO / ShardingSphere 5.4 讀寫分離 / Flyway migration |
| `blockchain-wallet` | 錢包產生、私鑰加密、鏈 client（Web3j/Trident）、入款/歸集/webhook |
| `api-connector-builder` | 新第三方鏈 / webhook provider 對接（QuickNode/Tatum，對齊既有模式） |
| `cross-module-changes` | 跨模組（service / flyway / frontend）連動修改 checklist |
| `documentation-lookup` | Context7 MCP 查第三方函式庫文件 |
| `package-structure` | 標準 package 分層模板 |
| `vue2-patterns` / `vue2-coding-standards` | Vue 2 + Element UI 前端開發模式與規範 |

## 7. 專用指令（`/command`）

| 指令 | 用途 |
|------|------|
| `/new-feature` | 依標準流程起一個新功能工單 |
| `/new-migration` | 新增 Flyway 版號 migration（只增不改） |
| `/trace-deposit` | 追蹤一筆入款流程（webhook → 驗簽 → 匹配 → 入帳） |
| `/check-platform-isolation` | 稽核查詢是否都有 `platform_id` 過濾 |
| `/review-endpoint` | 審查新 endpoint（filter chain / 驗簽 / 權限） |
| `/security-check` | 安全規範自查（私鑰 / HMAC / platform_id / @Transactional） |
| `/gen-test` | 產生 JUnit 5 測試骨架 |
| `/merge-to-test` | 合併 feature 分支到 developing_test（--no-ff） |
| `/export-pdf` | 匯出文件為 PDF |

---

## 索引

| 主題 | 位置 |
|------|------|
| 開發流程（preflight / spec / plan / test / review） | [`.claude/rules/development-workflow.md`](.claude/rules/development-workflow.md) |
| Git 分支 / commit / merge | [`.claude/rules/git-workflow.md`](.claude/rules/git-workflow.md)（**`developing_test` 禁止回流 `developing`**） |
| 分層 / DI / 回應信封 / 快取 | [`.claude/rules/patterns.md`](.claude/rules/patterns.md) |
| **Flyway migration 版本號（時間戳）** | [`.claude/rules/flyway-migration.md`](.claude/rules/flyway-migration.md) |
| 私鑰 / AES-GCM / HMAC / platform_id / 金額 / Log 脫敏 | [`.claude/rules/security.md`](.claude/rules/security.md) |
| 測試政策（JUnit 5 / L1-L3 / 基座） | [`.claude/rules/testing.md`](.claude/rules/testing.md) |
| 格式 / 命名 / Log / 重構安全 | [`.claude/rules/coding-style.md`](.claude/rules/coding-style.md) |
| 冪等 / 防重放 / 鏈重組 / 平滑發佈 | [`.claude/rules/stability.md`](.claude/rules/stability.md) |
| 業務 domain 索引（收需求先比對） | [`.claude/rules/modules.md`](.claude/rules/modules.md) |
| Java PostToolUse / pre-commit hook | [`.claude/rules/java-hooks.md`](.claude/rules/java-hooks.md) |
| Agent 編排 / 路由 / Harness Output Contract | [`.claude/rules/agents.md`](.claude/rules/agents.md) |
| Agent 實作 | `.claude/agents/*.md` |
| Skills | `.claude/skills/*/SKILL.md` |
| 專用指令 | `.claude/commands/*.md` |

---

<!-- shared:claude-local-only -->
## Claude Code 專案規範 / 範本 — 僅本機使用，不進版控（`settings.json` 除外）

`CLAUDE.md` 與 `.claude/` 是**本機開發輔助設定**，不隨專案進版控；唯一例外是 `.claude/settings.json`（團隊共用的 hook／權限設定）。部署本範本後，專案 `.gitignore` 須含：

```gitignore
# Claude Code 專案規範 / 範本 — 僅本機使用,不進版控(settings.json 除外)
CLAUDE.md
.claude/*
!.claude/settings.json
```
<!-- /shared -->

---

<!-- shared:next-step-closing -->
## 收尾固定格式：每次任務結束必須寫「下一步執行」

任務（一顆 TASK、一次修復、一份產出、一次審查）做完後，回覆的**最後一行**固定為：

> **下一步執行** <下一個流程步驟>（<一句話為什麼是它>）

**硬規則：**

- **一定要寫**，即使使用者沒問。做完就收尾，不留「然後呢」讓使用者自己猜。
- **只寫一個**——流程上真正緊接的那一步，不列待辦清單、不寫「可以考慮…」。
- 步驟名稱**取自本範本自己的工作流程文件**（`rules/` 下的 `*-workflow.md`），照原文用詞，不自創階段名。
- **不知道下一步 → 不要編**。寫「**下一步執行** 待確認（缺 <什麼> 才能決定）」。
- **流程已走完 → 明說**。寫「**下一步執行** 無（<流程名> 已完成）」。
- **有阻塞就指向解除阻塞那一步**（`⏳ 待決` OQ、驗證未過、等外部），不得跳過它往下推。
<!-- /shared -->
