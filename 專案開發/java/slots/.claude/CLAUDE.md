# CLAUDE.md — YUMMY 老虎機開發專案（實作期 AI Agent 規範）

> **專案定位：** 5×3 網頁版（H5）老虎機「YUMMY」。複製一款已在市場運行的遊戲，成敗看「複製得準不準」。
> **執行環境：** Java 21 + Spring Boot 3.5 ｜ MySQL + Redis ｜ 前端 Vue 3 + Uni-app 外殼 + Cocos Creator 3.x / PixiJS
> **部署位置：** 隨整個 `.claude/` 部署到 slots repo 根目錄。

---

## 0. 運作模式：backlog 驅動，且你有權改企劃（最高優先）

**企劃階段已經跑完。** `plan/yummy/` 現有：

| 文件 | 內容 |
|---|---|
| `backlog.md` | **工單來源** —— 32 顆 T 任務、DAG、9 批實作順序、AC 全覆蓋（87/87） |
| `spec.md` | 業務規則 `R-*`、邊界 `E-*`、驗收條件 `AC-*`（87 條） |
| `business-logic.md` | 角色、資料流、Flow-A~G、規則的來龍去脈 |
| `brief.md` | 範圍與成功指標 |
| `reference-sampling.md` | 參考站取樣事實（`§S*`） |

接到「做 T-07」這類指令時：

1. **讀任務**：到 `backlog.md` 找該顆的 `Required Spec Sections`、`Scope 邊界`、`Depends On`、`對應 AC`。
2. **只讀指定章節**：spec 有 35KB，**不要通讀**。企劃已經幫你切好了，照著讀就不會爆。
3. **planner 拆解**：產出 `plan/task-<編號>-plan.md`。
4. **實作 → 測試 → Review → 回填 backlog**。

### ⭐ 你有權直接改所有企劃文件

規格有洞、任務切得不對、AC 寫錯、規則要跟參考站不一樣 —— **自己改**（`rules/plan-authority.md`）。

- **不需要切回企劃範本。** 進開發後，企劃就是你。
- 唯一的硬規則是**改了要回寫**：規則進 `spec.md`、範圍進 `brief.md`、任務進 `backlog.md`，並標記連帶影響。
- 判準：**一個新來的人只讀 `plan/`，能不能完整知道現在的規則是什麼？**

---

## 跨 prompt-setup 職責路由（越界即提示切換）

本範本（`.claude/`）只負責軟體生命週期的**單一階段**。若接到的工作**不屬於本階段職責**——包含 planner 分流出的 OQ 被判定為「其實是他階段的事」——**不要硬接、不要在本階段臆測代答**，而是明確**提示使用者切換到對應的 prompt-setup 範本**，並附一句「為什麼這屬於他階段」。

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

> **你在這裡：開發 · slots（YUMMY 老虎機）**（表格第 10 列為本職，不適用切換）。
> **這個範本不會把你踢回企劃。** 上表第 1 列（企劃）對本專案**不適用** —— 規格、任務、範圍變更一律在這裡直接改（`rules/plan-authority.md`）。
> **真正的跨系統邊界：**
> - **平台錢包、帳號、大廳是外部系統**，只透過介面互動，不得自建餘額。
> - **儲值／提現／實名／VIP／活動／多語系／法遵報表**屬平台層，不在本專案（`brief.md` §4 Out of Scope）。
> - 需求若是「改平台大廳」或「接真實金流」→ 不屬本 repo，回報使用者。

---

## 1. 指路（每次開工先看）

### 文件優先序（衝突時的裁決順序）

```
plan/yummy/spec.md            ← 實作的唯一依據（R / E / AC）
        ↑ 承接
plan/yummy/business-logic.md  ← 規則的來龍去脈、Flow、資料流
        ↑ 承接
plan/reference-sampling.md    ← 參考站取樣事實（§S）
        ↑ 取代
plan/Yummy_Slot_Development_Plan.md  ← 最早的企劃書，多處已被取代
```

> **規則一律去讀 `plan/`，不要讀這裡。** 本範本刻意不寫任何賠率、線型、符號、公式 ——
> 抄一份就是多一個會過期的來源，而這正是保真度（M-1）最怕的事。

### 規範

- **企劃書修改權限與回寫紀律：** [`.claude/rules/plan-authority.md`](.claude/rules/plan-authority.md)
- **工程不變量 I1~I8：** [`.claude/rules/game-invariants.md`](.claude/rules/game-invariants.md)
- **依據追溯與保真度：** [`.claude/rules/fidelity.md`](.claude/rules/fidelity.md)
- **架構與系統邊界：** [`.claude/rules/architecture.md`](.claude/rules/architecture.md)
- **三個接縫（錢包／啟動／獎勵事件）：** [`.claude/rules/wallet-seam.md`](.claude/rules/wallet-seam.md)
- **開獎、RTP 與營運參數：** [`.claude/rules/rng-rtp.md`](.claude/rules/rng-rtp.md)
- **前端規範：** [`.claude/rules/game-client.md`](.claude/rules/game-client.md)
- **測試政策：** [`.claude/rules/testing.md`](.claude/rules/testing.md)
- **開發流程與 OQ 書寫：** [`.claude/rules/development-workflow.md`](.claude/rules/development-workflow.md)
- **Java 21 / Boot 3.5 風格：** [`.claude/rules/coding-style.md`](.claude/rules/coding-style.md)
- **Flyway migration 版本號：** [`.claude/rules/flyway-migration.md`](.claude/rules/flyway-migration.md)
- **分支與提交：** [`.claude/rules/git-workflow.md`](.claude/rules/git-workflow.md)（**測試分支的程式碼禁止回流開發分支**）

---

## 2. 不可妥協紅線

> 這裡**只有工程紅線**。業務規則（怎麼算、怎麼連、怎麼觸發）在 `spec.md`，而且你有權改。
> 下面這八條不行 —— 改了就不是「對的軟體」了。

1. **後端權威**（I1）：盤面、中獎線、金額一律後端決定；後端不接受前端送來的結果類欄位。
   判準：**把前端整包換成亂寫的程式，後端的帳仍須完全正確。**
2. **錢包唯一**（I2）：不得自建餘額儲存，只能透過錢包介面查／扣／派。
3. **入帳不依賴前端**（I3）：派彩由後端自行完成，不得掛在「動畫播完」上。玩家斷線也要拿到錢。
4. **單局冪等**（I4）：重複請求錢只動一次；重試用同一個識別碼。批量與特殊流程每一局各自有碼。
5. **金額用整數**（I5）：禁止浮點數。
6. **資金守恆可對帳**（I6）：有累積性質的池子任何時刻 `注入 − 派出 = 餘額`。
7. **開獎留痕可回放**（I7）：任何一局事後都要能完整重演。
8. **試玩模式無真金流路徑**（I8）。
9. **規則要指得出依據**（`rules/fidelity.md`）：每條玩法規則的實作旁標 spec 編號。
   spec 沒有這條 → **自己補進 spec**，不是放著不標。
10. **改了企劃文件就要回寫**（`rules/plan-authority.md`）：只存在對話或程式碼裡的決定不算數。
11. **每一則 OQ 都要國中生讀得懂；能自己決定的就不要問**（`rules/development-workflow.md`）。

---

## 3. 可用工具與 Sub-agents

- **自訂 Skills**：`/fidelity-check`、`/payout-verify`、`/rtp-sim`、`/arch-check`、`/strategic-compact`
- **Sub-agents**：

| Agent | 職責 |
|-------|------|
| `planner` | 取 backlog 任務、拆步驟、補規格洞、規劃驗收測試 |
| `fidelity-reviewer` | **依據守門**：規則指不指得出 spec 編號、spec 有沒有同步 |
| `payout-guard` | **金錢守門**：時序、冪等、整數運算、資金守恆（M-5 的執行者） |
| `rng-rtp-reviewer` | **開獎守門**：隨機來源、參數可設定化、留痕可回放、RTP 模擬 |
| `arch-guard` | **邊界守門**：前端不算錢、餘額歸屬、判定引擎可獨立測試 |
| `game-client-reviewer` | **前端守門**：越界算錢、動畫與入帳、行為對 AC |
| `code-reviewer` | 通用 Java：結構、命名、資源與併發、投機性複雜度 |
| `build-error-resolver` | Maven / Spring Boot 3.5 編譯與啟動錯誤診斷 |

**派工原則：** 動到玩法規則 → `fidelity-reviewer`；動到錢 → `payout-guard`；動到 RNG／參數／彩池 → `rng-rtp-reviewer`；動到結構或前後端介面 → `arch-guard`；動到前端 → `game-client-reviewer`。**五者可平行。**

---

## 4. 提交前固定動作

1. `./mvnw test` 綠燈（含整合測試）。
2. 動到玩法規則 → 跑 `/fidelity-check`。
3. 動到判定引擎、派彩、替代、徽章 → 跑 `/payout-verify`（對應 T-09 / AC-3.9）。
4. 動到權重或彩池注入 → 跑 `/rtp-sim`，報告附在 MR（**必須標明 RTP 口徑**）。
5. 動到結構或前後端介面 → 跑 `/arch-check`。
6. 改過 `plan/` 任何文件 → 確認已回寫、編號一致、連帶影響已標記。
7. 回填 `backlog.md` 任務狀態。**沒回填 = 任務未完成。**

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
