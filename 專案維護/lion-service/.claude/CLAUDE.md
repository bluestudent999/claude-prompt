# lion-service

**包網（白標）彩票／博弈平台**的業務服務集合：一套系統服務多家**互為競爭對手**的包網商。Java 8 / Spring Boot 2.0 多模組後端，**前端不在本 repo**。
本文件是 `.claude/` 規範集的入口索引；細節請依連結深入閱讀。

---

## 0. 快速上手導引

當使用者說出「如何開始」「怎麼開始」「要提供哪些資訊」「如何提需求」等關鍵詞時，
用 `grep -n "## 快速開始" .claude/README.md` 取得行號 N，再 Read offset=N limit=20，將內容直接輸出給使用者。

---

## 1. 專案概覽

- **groupId / artifactId**：`com.lc.lion:lion-service:1.0`，`packaging=pom`
- **Java**：1.8 ／ **Spring Boot**：2.0.2.RELEASE ／ **Spring Cloud**：Finchley.RELEASE
- **資料層**：MySQL + **ShardingSphere 4.0.1** 主從分片；DAO 走 **framework_v3 `MysqlBaseDaoImpl` + `SqlUtil`**，共用 DAO 在 `lion-common`
- **Migration**：`cp-flyway/`（**同 repo、不在 reactor**）＋ `zz_document/script/changelog/`（手動上版 SQL）——兩條軌，見 [`rules/flyway-migration.md`](.claude/rules/flyway-migration.md)
- **搜尋**：Elasticsearch **6.8.22** 與 **7.17.18** 並用
- **快取 / 協調**：Redis（Lettuce；collector 用 Jedis）+ Zookeeper / Curator
- **訊息**：Kafka 經 **Spring Cloud Stream**（`spring-cloud-starter-stream-kafka`）—— **不是** `spring-kafka`，不要用 `@KafkaListener` / `KafkaTemplate`
- **測試**：**JUnit 4** + `@RunWith(SpringRunner.class)`
- **CI**：Jenkins `mvn clean -Dmaven.test.skip=true install` —— **CI 不編譯也不跑測試，CI 綠不是證據**

| 模組 | package | 一句話 |
|---|---|---|
| `cp-service` | `com.lc.cp.*` | 最大最核心：主業務、活動、報表、遊戲、代理、彩票計畫、100+ 排程 |
| `single-wallet-service` | `com.lc.single.wallet.*` | 單一錢包，**金額敏感度最高**；`@SingleWalletType` 自動註冊交易類型 |
| `collector-service` | `com.cx.collector.*`（前綴不同是歷史沿革） | 開獎資料聚合；無金額，但**錯開獎 = 錯結算** |
| `upload-service` | `com.lc.upload.*` | 上傳；與獨立 repo `lion-upload-service` 同前綴、不同部署單位 |

**生態（sibling repo，與 lion-service 同層 clone；本機未必都有）**：`framework_v3`（底層框架）、`lion-common`（共享物件 / DAO / Cache / 列舉，**新共享物件一律放這**）、`lion-core`（結算 / 派彩）、`lion-manage`（總控制中心）、`lion-frontend`（前端總倉）。

### 已知失敗模式（先讀，這些都真的發生過或極易發生）

| 失敗 | 正解 |
|---|---|
| 照團隊舊文件寫 MyBatis mapper / XML / `#{}` | **lion 沒有 MyBatis**（0 mapper、0 XML）。SQL 由 framework_v3 組，對齊同模組既有 DAO |
| 照團隊舊文件寫 JUnit 5（`@ExtendWith`、`@Test` from jupiter） | 既有測試全是 JUnit 4；新測試對齊 |
| 把 cx-sports-v2 的寫法 / 版本抄過來 | cx-sports-v2 是 lion 的越南分支，**已升 Boot 2.7**；lion 仍是 2.0.2，很多 API 不一樣 |
| 把 `lotteryplan` / `activity` / `New*Service` 舊版當死碼刪掉或改掉 | 新舊版並存是線上還在跑；新功能用新版、舊版不動（`rules/modules.md`） |
| 照團隊根 CLAUDE.md 去找 `crypto-collector` / `websocket-service` | 這兩個模組不存在；以根 `pom.xml` `<modules>` 為準 |
| Flyway 取下一個 `V1.8.x` | `V1.8.0` 已被三支功能各取一次。新檔一律時間戳（`rules/flyway-migration.md`） |

---

## 1.5 lion 最高風險三條（每次改動都要自問）

| # | 風險 | 一句話 | 規範 |
|---|---|---|---|
| 1 | **包網商隔離** | A 家看得到或改得到 B 家的任何東西就是事故；**單一平台測試 100% 測不出**。platformId 只取自登入 token | [`rules/platform-isolation.md`](.claude/rules/platform-isolation.md) |
| 2 | **filter 防線** | 認證 filter **曾被實際繞過入侵**（帶 `.do` 的請求直接放行）。禁止新增副檔名 / 子字串型放行 | [`rules/security.md`](.claude/rules/security.md) §filter 防線 |
| 3 | **彩票賠率、限額、開獎** | 攻擊者不必入侵，讓賠率照他的意思成立或封盤後還能下注就能穩定獲利 | [`rules/security.md`](.claude/rules/security.md) §彩票 |

碰到任一條 → **L1**，必派 `security-reviewer`（必要時 + `business-reviewer`），且都用 `model: "opus"`。

---

## 2. 模組路由（接到任務時優先查這裡）

完整路由索引（domain 細分目錄 / 風險等級 / 常連帶模組 / 業務知識正本）→ [`.claude/rules/modules.md`](.claude/rules/modules.md)

> **業務知識正本**：lion 的業務 domain 知識由團隊維護在 git 版 `.claude/skills/business/<domain>/SKILL.md`，**本範本不複製**（複本會跟正本漂移）。
> 要讀時：`git show origin/developing:.claude/skills/business/<domain>/SKILL.md`（讀不到退 `HEAD:`；都讀不到就告知使用者，**不憑印象補業務規則**）。細節見 `rules/modules.md` §業務知識正本。

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

> **你在這裡：維護 · lion-service**（表格第 13 列為本職，不適用切換）。切換提示範例：「這是一次 Java/Boot 版本升級遷移，本維護範本不處理，請 `prompt-setup 版本管理` 後再進行」「這是要對 lion-service 做資安掃描、產資安報告，請改用 `prompt-setup 資訊安全 lion-service`（稽核者不該同時是修復者）」「這是一段全新需求，請先 `prompt-setup 專案企劃` 收斂範圍」。
>
> **反方向是本職**：拿資安報告來修某條 finding → 留在本範本，當 bug fix 處理。

## 3. 硬性規範（合入前必查）

| 主題 | 規範 |
|------|------|
| **Claude 不自行 commit** | [`.claude/rules/git-workflow.md`](.claude/rules/git-workflow.md)（最高優先：使用者當前訊息明確說 commit 才 commit；**不要 `git add .claude` / `CLAUDE.md` / `-A`**） |
| **包網商隔離** | [`.claude/rules/platform-isolation.md`](.claude/rules/platform-isolation.md)（platformId 只取自 token；SO 帶的要比對或覆寫；快取 / ES / 匯出 / 排程都要帶） |
| **filter 防線 / 彩票 / 金額** | [`.claude/rules/security.md`](.claude/rules/security.md)（禁副檔名 / 子字串放行；賠率只取自伺服器；BigDecimal / RoundingMode.DOWN / 8 步金額異動） |
| 測試（Mode B） | [`.claude/rules/testing.md`](.claude/rules/testing.md)（L1 強制整合測試 / JUnit 4 / 至少兩個 platformId） |
| 資料物件命名 | [`.claude/rules/patterns.md`](.claude/rules/patterns.md) §8（VO/SO/BO/Query/Record/Event，禁 DTO/Request/Entity；共享物件放 lion-common） |
| 雙層快取 | [`.claude/rules/patterns.md`](.claude/rules/patterns.md) §6.5（Redis + CacheService，禁 @Cacheable） |
| Grounding / Token | [`.claude/rules/coding-style.md`](.claude/rules/coding-style.md) §6（> 300 行禁 full read） |
| **Migration 版本號與兩條 SQL 軌** | [`.claude/rules/flyway-migration.md`](.claude/rules/flyway-migration.md)（**新檔用時間戳**、禁改既有、changelog 是否同步不得自判） |
| 分級與審查 | [`.claude/rules/severity-rubric.md`](.claude/rules/severity-rubric.md)、[`.claude/rules/reviewer-checklists.md`](.claude/rules/reviewer-checklists.md)、`.claude/checks/` |

## 4. 開發工作流程（5 步 + preflight）

```
Step -1 Preflight（JAVA_HOME=1.8 + mvn compile smoke）
Step 0  Research（先搜庫內同類實作、分清新舊版、讀業務知識正本、再搜 GitLab）
Step 1  Spec   （spec-review skill → specs/YYYY-MM-DD_<feat>_spec.md；規格未確認不動工）
Step 2  Plan   （planner agent → specs/YYYY-MM-DD_<feat>_plan.md）
Step 3  Test   （L1 → 整合測試；L2/L3 → 不強制）
Step 4  Review （增量 + 最終多 reviewer 平行）
Step 5  Commit （整理 diff 與訊息草稿，等使用者明確說 commit；MR → developing）
```

完整規範見 [`.claude/rules/development-workflow.md`](.claude/rules/development-workflow.md) 與 [`.claude/rules/git-workflow.md`](.claude/rules/git-workflow.md)。
拿資安報告（`security-report/<日期>/`）來修 finding → 當 bug fix 工單、L1 起跳，見 `rules/development-workflow.md`。

## 5. Agent 路由

L3 → `code-reviewer` × 1；L2 → + 擇一領域；L1 → + `java-reviewer` + 必要領域，**平行啟動**；L1 的 business / security reviewer 帶 `model: "opus"`。
所有 reviewer 依 `rules/reviewer-checklists.md` 檢查、標 🔬 的項目先讀 `checks/*.md`、依 `rules/severity-rubric.md` 分級，並輸出 Harness Output Contract。
詳見 [`.claude/rules/agents.md`](.claude/rules/agents.md)（含依 lion 模組追加 reviewer 的對照表）。

## 6. Skills（按任務載入）

| Skill | 用途 |
|-------|------|
| `spec-review` | 開發前產出結構化規格讓 PO 確認 |
| `api-connector-builder` | 新第三方對接（對齊 cp-service / single-wallet / collector 既有寫法） |
| `springboot-patterns` | Spring Boot 架構、快取、事件、排程 |
| `springboot-security` | 驗證、驗簽、API Key、Log 脫敏 |
| `springboot-tdd` | JUnit 4 + SpringRunner 測試基座備忘 |
| `mysql-patterns` | framework_v3 DAO / ShardingSphere / migration |
| `es-patterns` | ES 6/7 並用、主從切換、索引命名 |
| `cross-module-changes` | 跨模組 / 共享層 / enum / schema 連動修改 checklist |
| `cross-repo-commit` | 多 repo 同步提交 checklist（lion-service / lion-common / framework_v3 / lion-core / 前端） |
| `documentation-lookup` | Context7 MCP 查第三方函式庫文件 |
| `package-structure` | 標準 package 分層模板 |
| `strategic-compact` / `skill-stocktake` / `rules-distill` | context 壓縮 / skill 品質盤點 / 規則萃取 |

## 7. 團隊既有資產（本範本會用到，但不擁有）

| 資產 | 位置 | 本範本怎麼用 |
|---|---|---|
| 業務知識正本 | git 版 `.claude/skills/business/<domain>/` | `git show` 讀，不複製、不在這裡改（見 `rules/modules.md`） |
| 規格與計畫 | `specs/*_spec.md`、`specs/*_plan.md` | spec / plan 一律寫在這；`specs/INDEX.md` 是 `scripts/index-specs.py` 產生的衍生檔 |
| reviewer 誤報 / 漏報紀錄 | `evals/findings/*.md` | 主 agent 判定 finding 是誤報或漏報時記一筆（價值在跨人累積） |
| i18n CLI | `scripts/i18n.py` | 多語系一律走它（`rules/i18n.md`） |
| reviewer briefing 產生器 | `scripts/generate_reviewer_briefing.py` | 讀 `rules/reviewer-checklists.md` 產派遣 briefing，可直接用 |
| code-review-graph（MCP，`.mcp.json`） | `scripts/crg.sh` | **選用**：已安裝就先用它縮範圍再讀原始碼；圖與原始碼不一致以原始碼為準；沒裝不阻擋 |

---

## 索引

| 主題 | 位置 |
|------|------|
| 開發流程（preflight / spec / plan / test / review） | [`.claude/rules/development-workflow.md`](.claude/rules/development-workflow.md) |
| Git 分支 / MR / commit（**Claude 不自行 commit**、測試分支禁止回流） | [`.claude/rules/git-workflow.md`](.claude/rules/git-workflow.md) |
| 包網商隔離 | [`.claude/rules/platform-isolation.md`](.claude/rules/platform-isolation.md) |
| filter 防線 / 彩票 / 金額 / 金鑰 / Log 脫敏 | [`.claude/rules/security.md`](.claude/rules/security.md) |
| 分層 / DI / 快取 / 資料物件 / 系統參數 | [`.claude/rules/patterns.md`](.claude/rules/patterns.md) |
| 測試政策（Mode B / L1-L3 / 基座） | [`.claude/rules/testing.md`](.claude/rules/testing.md) |
| 格式 / 命名 / 註解語言 / Log / 重構安全 | [`.claude/rules/coding-style.md`](.claude/rules/coding-style.md) |
| Migration 版本號（時間戳）與兩條 SQL 軌 | [`.claude/rules/flyway-migration.md`](.claude/rules/flyway-migration.md) |
| i18n 多語系一律走 `scripts/i18n.py`，禁止 Edit i18n 檔 | [`.claude/rules/i18n.md`](.claude/rules/i18n.md) |
| 業務 domain 索引與業務知識正本（收需求先比對） | [`.claude/rules/modules.md`](.claude/rules/modules.md) |
| Token / Session 相容與平滑發佈 | [`.claude/rules/stability.md`](.claude/rules/stability.md) |
| Java PostToolUse / pre-commit hook | [`.claude/rules/java-hooks.md`](.claude/rules/java-hooks.md) |
| Agent 編排 / 路由 / Harness Output Contract | [`.claude/rules/agents.md`](.claude/rules/agents.md) |
| 分級標準 / reviewer 檢查項 / 原子檢查 | [`.claude/rules/severity-rubric.md`](.claude/rules/severity-rubric.md)、[`.claude/rules/reviewer-checklists.md`](.claude/rules/reviewer-checklists.md)、[`.claude/checks/README.md`](.claude/checks/README.md) |
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

> **lion-service 特有：** 這個 repo 的 git **追蹤著團隊自己的 `.claude/` 與根 `CLAUDE.md`**，所以加 `.gitignore` 擋不住已追蹤的檔案——部署本範本後 `git status` 會一直顯示這兩者有改動，**屬正常，永遠不要 `git add` 它們**（`rules/git-workflow.md`）。
> 要 `git pull` 又保留本機範本，可用 repo 根目錄的 `pull-keep-claude.sh`；注意它目前把正本目錄寫死為 `security-claude/`（資安範本用），維護範本要比照時需另設正本目錄。

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
