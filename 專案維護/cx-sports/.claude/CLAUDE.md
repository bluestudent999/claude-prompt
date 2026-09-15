# cx-sports-v2

體育投注主業務 monorepo：Java/Spring Boot 後端服務 + 多個 Vue 2 前端子專案。本文件是 `.claude/` 規範集的入口索引；細節請依連結深入閱讀。

---

## 0. 快速上手導引

當使用者說出「如何開始」「怎麼開始」「要提供哪些資訊」「如何提需求」等關鍵詞時，
用 `grep -n "## 快速開始" .claude/README.md` 取得行號 N，再 Read offset=N limit=20，將內容直接輸出給使用者。

---

## 1. 專案概覽

- **groupId / artifactId**：`com.lc.lion:lion-service:vn.1.0`，`packaging=pom`
- **Java**：1.8
- **Spring Boot**：2.7.11 / **Spring Cloud**：2021.0.5
- **資料層**：MySQL 5.7 + MyBatis（`mapper-starter 2.0.3-beta1`）+ **ShardingSphere 4.0.0-RC2** 主從分片 + Flyway（獨立 repo）
- **搜尋**：Elasticsearch **6.8.22** 與 **7.17.18** 並用（`ES 主從切換 aspect`）
- **快取 / 協調**：Redis（Lettuce）+ Zookeeper + Curator
- **訊息**：Kafka 經 **Spring Cloud Stream**（`spring-cloud-starter-stream-kafka`，Finchley） — **不是** `spring-kafka`，不要用 `@KafkaListener` / `KafkaTemplate`
- **監控**：Micrometer + Prometheus + Spring Boot Admin Client
- **CI**：Jenkins（`Jenkinsfile`） — 跑 `mvn clean install -Dmaven.test.skip=true`，**CI 不跑測試**

## 2. 模組路由（接到任務時優先查這裡）

完整路由索引（domain 細分目錄 / 風險等級 / 常連帶模組 / 前端子專案）→ [`.claude/rules/modules.md`](.claude/rules/modules.md)
> **控制中心 vs 總控制中心（常混淆）**：控制中心（單一平台）→ `lion-frontend/ctrl-center-frontend`；總控制中心（跨平台）→ `manage-center/manage-frontend`。

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

> **你在這裡：維護 · cx-sports-v2**（表格第 4 列為本職，不適用切換）。切換提示範例：「這是一次 Java/Boot 版本升級遷移，本維護範本不處理，請 `prompt-setup 版本管理` 後再進行」「這是一段全新需求，請先 `prompt-setup 專案企劃` 收斂範圍」。

## 3. 硬性規範（合入前必查）

| 主題 | 規範 |
|------|------|
| 金額與錢包 | [`.claude/rules/security.md`](.claude/rules/security.md)（BigDecimal / RoundingMode.DOWN / 7 步餘額異動） |
| 測試（Mode B） | [`.claude/rules/testing.md`](.claude/rules/testing.md)（L1 強制整合測試 / JUnit 4 / 禁 JUnit 5） |
| 資料物件命名 | [`.claude/rules/patterns.md`](.claude/rules/patterns.md) §8（VO/SO/BO/Query/Record/Event，禁 DTO/Request/Entity） |
| 雙層快取 | [`.claude/rules/patterns.md`](.claude/rules/patterns.md) §6.5（Redis + CacheService，禁 @Cacheable） |
| 系統參數 | [`.claude/rules/patterns.md`](.claude/rules/patterns.md) §8.5（config 表 + FrontConfigVO 反射） |
| Grounding / Token | [`.claude/rules/coding-style.md`](.claude/rules/coding-style.md) §6（> 300 行禁 full read） |
| **Flyway migration 版本號** | [`.claude/rules/flyway-migration.md`](.claude/rules/flyway-migration.md)（**新檔用時間戳**、禁改既有、獨立 repo） |

## 4. 開發工作流程（5 步 + preflight）

```
Step -1 Preflight（JAVA_HOME=1.8 + mvn compile smoke）
Step 0  Research（先搜庫內 connector/impl/、再搜 GitLab）
Step 1  Spec   （spec-review skill；規格未確認不動工）
Step 2  Plan   （planner agent → plan/YYYY-MM-DD_<feat>_plan.md，8 章節）
Step 3  Test   （L1 → 整合測試；L2/L3 → 不強制）
Step 4  Review （增量 + 最終多 reviewer 平行）
Step 5  Commit （conventional commit；MR → developing）
```

完整規範見 [`.claude/rules/development-workflow.md`](.claude/rules/development-workflow.md) 與 [`.claude/rules/git-workflow.md`](.claude/rules/git-workflow.md)。

## 5. Agent 路由

L3 → `code-reviewer` × 1；L2 → + 擇一領域；L1 → + `java-reviewer` + 必要領域，**平行啟動**；所有 reviewer 須輸出 Harness Output Contract。
詳見 [`.claude/rules/agents.md`](.claude/rules/agents.md)。

## 6. Skills（按任務載入）

| Skill | 用途 |
|-------|------|
| `spec-review` | 開發前產出結構化規格讓 PO 確認 |
| `api-connector-builder` | 新第三方對接（對齊 cx-sports-v2 / single-wallet 既有模式） |
| `springboot-patterns` | Spring Boot 架構、快取、事件、排程 |
| `springboot-security` | 驗證、驗簽、API Key、Log 脫敏 |
| `springboot-tdd` | JUnit 4 + SpringRunner 測試基座備忘 |
| `mysql-patterns` | DAO / ShardingSphere / Flyway / MyBatis |
| `es-patterns` | ES 6/7 並用、主從切換、索引命名 |
| `cross-repo-commit` | 多 repo 同步提交 checklist（sport / common / frontend / manage） |
| `documentation-lookup` | Context7 MCP 查第三方函式庫文件 |
| `package-structure` | 標準 package 分層模板 |
| `vue2-coding-standards` | Vue 2 + Element UI + Webpack 程式碼規範（lion-frontend / manage-center 子專案） |
| `vue2-patterns` | Vue 2 共用開發模式：API 呼叫、認證、表格、篩選器、金額格式化 |

---

## 索引

| 主題 | 位置 |
|------|------|
| 開發流程（preflight / spec / plan / test / review） | [`.claude/rules/development-workflow.md`](.claude/rules/development-workflow.md) |
| Git 分支 / MR / commit | [`.claude/rules/git-workflow.md`](.claude/rules/git-workflow.md)（**測試分支禁止回流開發分支**） |
| 分層 / DI / 快取 / 資料物件 / 系統參數 | [`.claude/rules/patterns.md`](.claude/rules/patterns.md) |
| 金額 / RoundingMode / 金鑰管理 / Log 脫敏 | [`.claude/rules/security.md`](.claude/rules/security.md) |
| 測試政策（Mode B / L1-L3 / 基座） | [`.claude/rules/testing.md`](.claude/rules/testing.md) |
| 格式 / 命名 / Log / 重構安全 | [`.claude/rules/coding-style.md`](.claude/rules/coding-style.md) |
| Flyway migration 版本號（時間戳） | [`.claude/rules/flyway-migration.md`](.claude/rules/flyway-migration.md) |
| i18n 多語系新增 / 對齊統一走 `scripts/i18n-add-key.py`，禁止 Edit i18n 檔 | [`.claude/rules/i18n.md`](.claude/rules/i18n.md) |
| 業務 domain 索引（收需求先比對） | [`.claude/rules/modules.md`](.claude/rules/modules.md) |
| Java PostToolUse / pre-commit hook | [`.claude/rules/java-hooks.md`](.claude/rules/java-hooks.md) |
| Agent 編排 / 路由 / Harness Output Contract | [`.claude/rules/agents.md`](.claude/rules/agents.md) |
| Agent 實作 | `.claude/agents/*.md` |
| Skills | `.claude/skills/*/SKILL.md` |

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
