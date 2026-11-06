# 開發工作流程（ticket 驅動）

> 工單來源是企劃產出的 **`plan/on-sports-lite/tickets/`**（129 張開發 ticket，S1-T1 ～ S6-T15b；16 張開工前置 `prep/P-01 ～ P-16`）。
> **一次一張 ticket。** 不要因為「這兩張很像」就合併做，ticket 的粒度就是驗收與回填的粒度。
> 開工前的骨架（repo 初始化、框架 tag、profile、compose、模擬器）不是 ticket，走 `/bootstrap`（B-01 ～ B-10）。

---

## 文件優先序（衝突時的裁決）

```
plan/on-sports-lite/tickets/<id>.md        ← 範圍、Required Spec Sections、AC：以此為準
        ↑ 衍生自
plan/on-sports-lite/backlog-spec-N.md      ← Scope 邊界、依賴、估算
        ↑ 承接
plan/on-sports-lite/spec/spec-*.md         ← 業務規則 R#、邊界 E#、驗收 AC#：業務行為以此為準
        ↑ 承接
plan/on-sports-lite/brief.md               ← 範圍與成功指標
────────────────────────────────────────────
plan/on-sports-lite/tech-decisions.md      ← 技術 How 的已定案（本範本 rules/ 是它的執行版）
plan/on-sports-lite/master-plan.md         ← 波次、里程碑、外部等待；只決定「先做哪張」，不決定「怎麼做」
```

**業務規則有疑問 → 回企劃（PM），不自行改 spec。** 技術決策要翻案 → 停手回報使用者。ticket 檔由 `_generate.py` 產生、**不手改內容**；只改「狀態」欄（「回填與提交」步驟）。

---

## 三類工作（同一套流程，驗收依據不同）

> **部門分工 v4（2026-11-02）**：總控與業主後台的全部畫面歸後端部門 = 本 repo；前端部門只做 H5 與 App。判定只看 ticket 的「部門分工」段：**後端條目寫的全是我們的**（含畫面），**前端條目全是另一部門的**。

| 類 | 什麼 | 怎麼認（看 ticket「部門分工」段） | 驗收依據 |
|----|------|--------|---------|
| **A · 後端 API** | 資料、API、Kafka、Redis、推送、排程、collector、環境 | 後端條目的非畫面部分 | AC + `testing.md` §1 的 API 測試 + 不變量測試 |
| **B · 後台前端** | `web/admin` 的總控與業主後台畫面 | 後端條目含畫面字樣（頁、表單、列表、匯出、預覽…）；S4 全部 22 張、S5 的後台部分、S1 的總控／業主頁。混合 ticket（S1-T3、S1-T5、S1-T6、S5-T15、S5-T16、S5-T19）前台欄歸前端部門、後台欄歸我們 | AC + 畫面三態 + 對應後端 API 測試 |
| **C · 契約交付** | OpenAPI、realtime 契約、給另一部門的文件 | 任何 A 類 ticket 動到 `/api/front/**` 或 WebSocket | `/contract-export` 產出 + `contract-reviewer` |

判定寫在 plan §0。**H5／App 畫面不在本 repo**：ticket 的「前端」條目一律標「畫面：另一部門」，本 repo 只交 API 與契約。

**先做哪張**（總計畫 v4.3，後端是唯一瓶頸）：① M1 的 9 張（S1-T1～T3、S4-T1～T4、S2-T1）插隊優先 → ② 關鍵路徑（§2.2）→ ③ 回歸第 1 組基準（S2-T1～T4、S3-T5～T7、S3-T18）→ ④ 其餘依波次。`internal/realtime` 的第一張 ticket 前必須先做完 **P-17**（有界佇列）。

---

## 六個步驟（可執行版在 `/ticket-run`，本節只放判準）

| 步驟 | 誰做 | 判準（細節與指令見 `skills/ticket-run/SKILL.md`） |
|------|------|------|
| **Preflight** | 主流程 | 分支、Go 版本、go.work 與框架版本（`setup-go-work.sh --check`）、編譯；分支不對或環境不符 → 不動工 |
| **規劃** | `planner` | 讀 ticket 與 Required Spec Sections 全專案只做一次（2026-11-04 決策 A）；產出 `plan/task-<ticket>-plan.md` 並回傳摘要；主流程不重讀 ticket |
| **實作** | `implementer`／`web-implementer` | **Golden Rule：依計畫實作**，範圍上限是 plan §2；不自行新增表、topic、destination、對外欄位、設定鍵；不順便重構；文件互相矛盾 → 停手回報（Stop Rule） |
| **驗收** | 實作代理自跑，主流程看結果 | build／vet／lint／單元／（動 dao、consumer 時）整合、`/arch-check`；**DoD 七條**（`testing.md` §8） |
| **審查** | reviewer 平行 | 第一輪依 `/ticket-run` Step 4 表派；第二輪起只重派有 CRITICAL／HIGH 的 reviewer，只給增量 diff |
| **回填與提交** | 主流程 | plan §8 + ticket 狀態欄（DoD 第 7 條）；`plan/` 無 `⏳ 待決`；同一個 commit；push 分支後合併回 `developing`：本機 `git merge --no-ff` 後 push（2026-11-05 使用者指定，審查通過即可自行執行），或開 MR（目標確認是 `developing`）；步驟見 `git-workflow.md` §1.2；**不在本機合併進 `main`** |

**實作時每次問：** 查詢經過 `tenant.Scope` 了嗎（I1）？套用更新用 `pv` 做 compare-and-set 了嗎（I3）？handler 的 `_test.go` 在哪（testing §1）？Emit 的 key 是 `match_id` 嗎（I2）？讀即時資料讀的是 Redis 快照嗎（I9）？

> **回填是 DoD 第 7 條。** 沒回填 = 未完成，不要跳到下一張。
> ⚠ 企劃的 `_generate.py` 重跑會覆蓋開發 ticket 的狀態欄；**plan 檔 §8 是進度的真相**，狀態欄是副本。

---

## Session 與 token 紀律（2026-11-05 實測後加入）

> 實測：主 session 上下文中位數 35～60 萬 token、最高 96 萬；一個 session 連做十幾張 ticket，每一輪都重讀整段歷史。

- **一張 ticket 一個 session。** 合併回 `developing`（或 MR 開好）就收尾，「下一步執行」寫「清空上下文（`/clear`）後 `/ticket-run <下一張>`」；不在同一個 session 接著做下一張。
- **主流程只調度，不親手寫功能碼。** 讀程式碼、改檔、跑測試交給 `implementer`／`web-implementer`；主流程看的是它們回傳的摘要。
- **長輸出不進上下文。** 測試、lint、建置輸出一律只取結論：`go test ./internal/... 2>&1 | tail -40`；失敗才看完整的那一段。
- **規則按需載入。** 只跟特定目錄有關的規則已改成 `paths:`；要引用某一節但上下文裡沒有 → `grep -n "^## " .claude/rules/<檔>` 後只 Read 那一節，不整份讀。

---

## ticket 做不過時

- **不要為了讓測試過而放寬 AC。** AC 是規格。
- AC 本身有疑義 → 列 OQ，標明屬企劃職責，提示使用者切 `prompt-setup 專案企劃`。
- 卡住超過合理時間 → 回報並附「試過什麼、為什麼不行」；同一手法失敗 2 次就換路徑，不要無限重試。
- 外部等待（E1 憑證、E2 影片文件、E4 簡訊）→ 用模擬器或 mock 做完能做的部分，plan §8 標 `待外部：<項目>`，ticket 狀態改 `阻塞：待外部 <項目>`。

---

<!-- shared:oq-plain-language -->
## OQ 與「要問使用者」的兩條硬規則

### 一、用國中生聽得懂的話寫

每一則 `⏳` OQ、以及每一個你要丟給使用者的問題，都必須讓**一個國中生讀完就能直接回你 A 或 B**。
做不到就是寫壞了，**重寫**，不要送出去。

**每則必含三段：**

| 段 | 寫什麼 |
|---|---|
| **情況** | 什麼時候、什麼狀況下會遇到這件事 |
| **卡住什麼** | 不決定的話，哪個功能／流程做不下去 |
| **選項** | 每個一句話 + 它的代價；傾向的那個後面標「（建議：一句理由）」 |

**禁止：**

| ❌ | 為什麼不行 |
|---|---|
| 只寫「OQ-5 未決，無法繼續」 | 看的人不知道 OQ-5 是什麼 |
| 用內部代號當問題本體（任務編號、章節號、模組名、函式庫名） | 那是我們的編號，不是問題 |
| 用技術名詞而不解釋（冪等、併發、接縫、契約、回歸） | 要用就當場用一句話說明白 |
| 沒有選項，只寫「請指示」 | 沒選項等於要對方從零想，那是我們的工作 |

> **反例**：「彩池瓜分的比例演算法與時間窗未定義」
> **正例**：「大獎被好幾個人同時中時，錢怎麼分？」＋ 情況 ／ 卡住什麼 ／ A、B、C 各自的代價

### 二、沒問題就不要硬生問題

送出之前先自問：**這題我能不能從需求、既有文件、或本範本的既有慣例，推出一個合理的預設？**

- **能** → **直接採用預設**，在產出裡用一句話寫明「我採了什麼、為什麼」，然後繼續做。**不要開 OQ。**
- **不能，而且不同答案會導向實質不同的工作** → 這才是真的 OQ，照第一條的格式寫。

> **為什麼**：問題本身有成本。把自己判斷得出來的事丟回去，等於把工作推回給對方；
> 而且會**稀釋真正需要拍板的那一題** —— 一次丟五個問題，重要的那個就被淹掉了。
> **湊數的 OQ 比沒有 OQ 更糟。**

> 兩條不衝突：第二條決定**要不要問**，第一條決定**問了怎麼寫**。
<!-- /shared -->
