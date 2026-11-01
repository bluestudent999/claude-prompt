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

**業務規則有疑問 → 回企劃（PM），不自行改 spec。** 技術決策要翻案 → 停手回報使用者。ticket 檔由 `_generate.py` 產生、**不手改內容**；只改「狀態」欄（§Step 5）。

---

## 三類工作（同一套流程，驗收依據不同）

| 類 | 什麼 | 怎麼認 | 驗收依據 |
|----|------|--------|---------|
| **A · 後端 API** | 資料、API、Kafka、Redis、推送、排程、collector | ticket 主責「後端」；或主責「前端」但畫面在 H5／App（只做後端部分） | AC + `testing.md` §1 的 API 測試 + 不變量測試 |
| **B · 後台前端** | `web/admin` 的總控與業主後台畫面 | ticket 主責「前端」且畫面在總控或業主後台（S4、S5 多數；S1-T6、S1-T10 等） | AC + 畫面三態 + 對應後端 API 測試 |
| **C · 契約交付** | OpenAPI、realtime 契約、給另一部門的文件 | 任何 A 類 ticket 動到 `/api/front/**` 或 WebSocket | `/contract-export` 產出 + `contract-reviewer` |

判定寫在 plan §0。**H5／App 畫面不在本 repo**：ticket 的「前端」分工若是 H5／App，plan 裡標「畫面：另一部門」，本 repo 只交 API 與契約。

---

## Step -1：Preflight（每個 session 第一次動工前）

```bash
go version | grep -E "go1\.2[3-9]" || echo "[preflight] Go 版本不符"
grep -n "sp-framework" go.mod | grep -E "v[0-9]+\.[0-9]+\.[0-9]+" || echo "[preflight] sp-framework 未鎖 tag（D2a）"
test -f go.work && grep -q "sp-framework" go.work && echo "[preflight] go.work 指向同層 checkout（D2a 禁止）"
go build ./... || echo "[preflight] HEAD 編譯失敗 — 必修"
docker compose -f deploy/docker-compose.yml ps 2>/dev/null | grep -q mysql || echo "[preflight] 整合環境未起（整合測試會跳過）"
```

| 失敗 | 處置 |
|------|------|
| Go 版本不符、框架未鎖 tag、go.work 違規 | **必修，不動工** |
| 編譯失敗 | **必修** —— HEAD 本身壞掉，疊上去的改動無效 |
| compose 未起 | 可做單元層；整合測試前要起 |

---

## Step 0：讀 ticket 與研究（禁 full read）

```bash
T=S2-T8   # 換成實際編號
sed -n 1,40p plan/on-sports-lite/tickets/$T.md                 # 整張 ticket 都要讀（它本來就短）
grep -n "^## 只讀這幾節" -A 2 plan/on-sports-lite/tickets/$T.md  # Required Spec Sections
grep -nE "^#{2,4} " plan/on-sports-lite/spec/spec-2a-match-live.md   # 先建索引，再 Read(offset, limit) 讀指定節
```

1. **讀整張 ticket**：Scope 含／不含、Depends On、跨 Backlog 前置、AC、部門分工。
2. **只讀 Required Spec Sections**。spec 每份 300～560 行，**禁止通讀**。發現自己在讀不相干的節，就是沒照做。
3. **確認前置 ticket 已完成**（看前置 ticket 檔的「狀態」）；未完成 → 停手回報 `Blocked By: <ticket>`。標「（驗收）」的前置只卡驗收，可開工。
4. **查已鎖定決策與不變量**：這張會碰到哪些 D、哪些 I？（`locked-decisions.md`、`invariants.md`）
5. **查租戶資料類**：碰到的表在 `tenant-isolation.md` §2 哪一欄？
6. **查契約影響**：會不會新增或改 `/api/front/**`、WebSocket destination、Kafka 封包？

---

## Step 1：規劃（planner）

產出 `plan/task-<ticket>-plan.md`（例：`plan/task-S2-T8-plan.md`），**必含** `agents/planner.md` 的 §0～§8。重點：

- **§0** 工作類別 A／B／C、涉及不變量、租戶表、契約影響、前置狀態。
- **§2 變更檔案清單**是單一事實來源；§4 **逐一列出每個新增或修改的 API 的測試函式名**（`testing.md` §1）。
- **OQ 硬規則**：可用 grep／Read／跑測試驗證的 → planner 自答；需要判斷的 → 列 OQ，**未解答前禁止寫業務程式碼**；決議回寫 plan（原文加刪除線 + ✅）。業務疑問 → 回企劃。
- **本專案典型必問**：停更門檻實際值（R62 要回填）、簡訊供應商介面（P-06 到位前只能 mock）、推播在中國大陸 Android 的處理（tech-decisions §6 第 2 項）、影片套餐是否可用（第 4 項）。

---

## Step 2：實作

**Golden Rule：依計畫實作。** 禁止自行重設計、優化架構、新增未經計畫的需求。唯一真理來源是 `plan/`。

- **最小化讀取**：只讀本 ticket 需要的檔案。
- **禁止越權決策**：不自行新增表、Kafka topic、destination、對外欄位、設定鍵。
- **禁止順便重構**：不改與本 ticket 無關的檔案；既有 dead code 不刪，記進 Remaining Work。
- **Stop Rule**：文件互相矛盾（ticket vs spec、tech-decisions vs 方案 A 圖）→ **立即停止並回報**，不要挑一個猜。

**每次寫查詢問：** 「它經過 `tenant.Scope` 了嗎？」（I1）
**每次套用更新問：** 「它用 `pv` 做 compare-and-set 了嗎？」（I3）
**每次寫 handler 問：** 「它的 `_test.go` 在哪？」（testing §1）
**每次 Emit 問：** 「key 是 `match_id` 嗎？」（I2）
**每次讀即時資料問：** 「讀的是 Redis 快照嗎？」（I9）

---

## Step 3：驗收

```bash
go build ./... && go vet ./... && golangci-lint run
go test ./internal/...                                      # 單元（含每個 API 的測試）
go test -tags=integration ./test/...                        # 動到 dao／consumer 時
/arch-check                                                 # import 方向、禁用依賴、handler 有測試、租戶 dao 經 Scope
/tenant-check                                               # 動到租戶表時
/contract-export                                            # 動到契約時
```

**DoD 七條**（`testing.md` §8）全滿足才算完成。

---

## Step 4：審查

| 情境 | reviewer |
|------|---------|
| 一律 | `code-reviewer` |
| 動到包結構、新增包、跨包 import、引入相依、角色組裝 | + `arch-guard` |
| 動到租戶表查詢、認證、Host 解析、總控指派範圍、WebSocket 握手 | + `tenant-isolation-reviewer` |
| 動到 `/api/front/**`、WebSocket destination 或訊息、Kafka 封包 | + `contract-reviewer` |
| 動到 collector、`realtime-core`、`persist`、合流、快照、賠率歷史 | + `data-pipeline-reviewer` |
| 動到 `web/admin` | + `web-reviewer` |

領域 reviewer **可平行**（同一則訊息啟動）。

**完成輸出格式：** `Completed Files`、`Modified Files`、`Tests (PASS)`（逐一列出 API 測試名）、`涉及不變量與其測試`、`架構檢查結果`、`契約變更`（無／相容／破壞性）、`Remaining Work`（阻塞註明 `Blocked By: <ticket>`）。

---

## Step 5：回填與提交

1. **回填 plan**：`plan/task-<ticket>-plan.md` §8 完成紀錄（日期、測試結果、契約變更、Remaining Work）。
2. **回填 ticket 狀態**：把 `plan/on-sports-lite/tickets/<id>.md` 的 `| 狀態 | 待開工 |` 改為 `| 狀態 | 已完成（<日期>） |`；阻塞時改 `阻塞：<原因>`；進行中改 `實作中`。**只改這一格**，其他內容不動。
   > ⚠ 企劃的 `_generate.py` 重跑會覆蓋開發 ticket 的狀態欄（它只保護 prep ticket）。已回報 PM 改腳本；在那之前，**plan 檔的 §8 是進度的真相**，ticket 狀態欄是副本。
3. 確認 `plan/` 無「⏳ 待決」OQ（否則 git hook 攔截）。
4. Commit（`git-workflow.md`）；**不加 `.claude/` 與 `CLAUDE.md`**（hook 會攔）。

> **回填是 DoD 第 7 條。** 沒回填 = 未完成，不要跳到下一張。

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
