# Agent 協作編排（sicbo）

> Agent 定義位於 `.claude/agents/`，此 rule 規範使用原則與路由。

---

## 編排模型

```
使用者需求
   │
   ▼ 越界先攔（見 CLAUDE.md 跨 prompt-setup 路由；Go 端 / baccarat 皆非本職）
[段別定位] — 查 rules/pipeline.md §1，鎖定管線段別 + 預判 L 層
   │
   ▼
[spec-review] — 涉及辨識行為 / 輸出契約 / 部署介面時的 gate
   │
   ▼ CONFIRM
[planner] — 拆步驟 + 寫驗證計畫（L1 強制）
   │
   ▼
[code-reviewer]
   │
   ▼ 視內容平行
[cv-pipeline-reviewer] [detector-contract-reviewer] [deployment-reviewer]
   │
   ▼
提交（含文件同步）
```

### 何時繞過

- **Bug 修復（非辨識行為）**：省 `spec-review`，直接 `planner` → 實作。
- **純繪圖 / 文案 / 註解**：省整個流程，改完 `code-reviewer` 輕掃。
- **建置或執行期錯誤**：直接派 `build-error-resolver`。

---

## 需求入口：先定位段別（硬規則）

1. **越界先攔**：
   - 需求本質是「新遊戲類型 / 新輸出協議 / 商業規則」→ 提示 `prompt-setup 專案企劃`。
   - 需求是改 **Go 端**（`casino_dealer_client`）→ **不屬本範本**，回報使用者這是跨 repo 的另一邊。
   - 需求是改 **`baccarat_3type` / `xocdia`** → 同 repo 但**不同子專案**，明確回問要改哪一個，不要順手一起改。
2. **查 `rules/pipeline.md` §1** 鎖定段別（資料 / 訓練 / 晉升 / 推論 / 輸出 / 部署）。該段的檔案清單 = grep / Read 範圍上限。
3. **立即預判 L 層**並輸出給使用者確認（例：`預判 L 層：L1（推論參數 + 開盅判定）`），寫入 spec §風險評估。planner 只確認不得降級。
4. **驗證現況而非文件**：本專案有 9 項已知落差（`CLAUDE.md` §7），任何「文件說有 X」都要先 grep 驗證再往下走。

---

## L 層定義

| L 層 | 範圍 | 為什麼 |
|------|------|--------|
| **L1** | 推論 9 步參數 / 開盅判定 / TCP 輸出契約與接線 / 部署介面（CLI、埠、串流源、打包清單） | 錯了會**開錯盅**或**Go 端收不到**，直接影響現場結算 |
| **L2** | 串流讀取與重連 / 訓練參數與資料處理 / ML backend / 效能 | 影響穩定度與模型品質，但不會直接產出錯誤點數 |
| **L3** | 繪圖樣式 / 畫面文案 / 註解 docstring / 設定值搬移 / 純重構 | 不影響輸出 |

**有疑問升級不降級。** L2/L3 邊界模糊取 L2。

---

## Agent 清單與路由

| Agent | 職責 | 觸發 |
|-------|------|------|
| **code-reviewer** | Python 品質、結構、可維護性、過度工程、資源釋放 | 寫完程式碼後第一輪 |
| **cv-pipeline-reviewer** | 推論 9 步順序與參數、追蹤、穩定判定、準確度回歸風險 | 動到 `recognize_sicbo_stream.py` 的偵測 / 過濾 / 追蹤 / 判定段 |
| **detector-contract-reviewer** | TCP 契約、JSON 格式、送出時機與去重、Go 端相容性 | 動到 `tcp_broadcaster.py`、廣播接線、開盅判定 |
| **deployment-reviewer** | 主程式 ↔ 啟動腳本 ↔ `deployment_guide.md` ↔ `pack_prod.sh` 四者一致性、跨平台 | 動到 CLI / 埠 / 串流源 / 打包清單 / 字型 / device 選擇 |
| **build-error-resolver** | Python import / 相依 / CUDA-MPS / OpenCV 執行期錯誤診斷 | `py_compile` 或執行失敗 |
| **planner** | 實作計畫拆解（含驗證計畫） | 已定方案，要拆步驟 |

### 依 L 層決定 reviewer 數

| L 層 | reviewer 配置 |
|------|---------------|
| **L3** | `code-reviewer` × 1（輕掃） |
| **L2** | `code-reviewer` + 擇一領域（多為 `cv-pipeline-reviewer`） |
| **L1** | `code-reviewer` + **必要領域全上**，平行啟動：<br>· 動推論參數 / 判定 → `cv-pipeline-reviewer`<br>· 動廣播 / 契約 → `detector-contract-reviewer`<br>· 動介面 / 部署 → `deployment-reviewer` |

**判定原則：**
- 先看 L 層再看情境；有疑問升級。
- 同一次改動派超過 3 個 reviewer → 先考慮是不是該拆成多個 TASK（`CLAUDE.md` §7 的落差就是要一次修一項）。
- **接線 TCP 廣播**這件事會同時命中三個領域 reviewer —— 那正是它是 L1 且應獨立成一個 TASK 的理由。

---

## 平行執行

獨立的 agent 呼叫**務必**在同一則訊息中平行啟動，不要循序等待。

---

## 主 agent context 保護

- `recognize_sicbo_stream.py`(584) / `local_train.py`(441) **禁 full read**——先 grep 建索引。
- 跨多檔搜尋、「baccarat 有沒有類似做法」、「這個變數在哪些地方被改」→ 委派 **Explore agent**（獨立 context，只回結論不回原始 grep 行）。
  - `quick` ≤ 300 字 / `medium` ≤ 800 字 / `thorough` ≤ 1500 字
- 明確檔案 + 明確字串的精準 grep 才主 agent 自做。

---

## 子 Agent 規範傳遞

子 Agent **不繼承父 context**、**不自動讀 skills**（rules 會自動注入）。**派子 Agent 必須自包含**：plan 路徑 + diff 片段（含行號）+ 規範摘要 + Harness Output Contract 提醒。**Briefing ≤ 500 字。**

### 平行 reviewer 分工聚焦

| reviewer | 聚焦 | 忽略 |
|---------|------|------|
| `code-reviewer` | 結構 / 命名 / 死碼 / 過度工程 / 資源釋放 / 例外精度 | 辨識演算法正確性 |
| `cv-pipeline-reviewer` | 9 步順序 / 參數合理性 / 追蹤與槽位 / 穩定判定 / 回歸風險 | 部署與文件 |
| `detector-contract-reviewer` | JSON 格式 / 3 顆 1-6 驗證 / 一回合一次 / 虛擬框排除 / Go 相容 | 繪圖與訓練 |
| `deployment-reviewer` | 四者一致性 / 跨平台 / 無頭環境 / 打包清單 | 演算法細節 |

### 規範摘要對照（按任務挑抄進 briefing）

| 任務類型 | 必抄條文 |
|---------|----------|
| 廣播 / 契約 | `{"value":"NNN"}` 3 字元 1-6、無分隔符靠 `{}` 配對、一回合一次、非 3 顆不送、`send_dice_result` 兩道檢查不可移除 |
| 推論參數 | conf 0.40 / IoU 0.5 / 面積 400 / 追蹤距離 60 / 穩定 1.5s；改動須回放驗證圖比對 |
| 部署 / 介面 | 主程式無 argparse（argv[1] 是模型版本名）；改介面須同步 4 處；生產為無頭環境 |
| 訓練 | imgsz=1280 / degrees=180 / hsv 0.3 的理由；不覆蓋既有 train 目錄；先 `--dryrun` |
| git | repo 根在 `detector/`；只 add `sicbo/` 路徑；不新增 `*.pt` `*.zip` |

---

## Harness Output Contract（reviewer / resolver 必須遵守）

最後一段固定輸出：

```
---
**Status:** approve | warning | block
**Summary:** {一句話 ≤ 80 字}
**Counts:** CRITICAL=N HIGH=N MEDIUM=N LOW=N
**Next actions:**
- [ ] {動作 — 誰改哪個檔做什麼}
**Artifacts:**
- {file}:{line} — {issue} | fix: {fix}
```

**Status 判定：** CRITICAL > 0 → `block`；HIGH > 0 → `warning`；其餘 → `approve`。小寫英文，不翻譯，不用 emoji。

| Agent 類型 | 版本 |
|-----------|------|
| Reviewer（code / cv-pipeline / detector-contract / deployment） | 完整版（5 欄位） |
| build-error-resolver | Resolver 變體（`fixed:` / `remaining:`） |
| planner | 豁免 |

### 本專案的 CRITICAL 判準（直接 block）

- 送出未通過 3 顆 / 1-6 驗證的結果，或移除 `send_dice_result` 的既有兩道檢查
- 用虛擬框（`is_virtual`）湊數後送出
- 一回合送出多次（`captured_this_stable_period` 失效）
- 改了 JSON 結構或欄位名而未標明需 Go 端同步
- 改了 CLI / 埠 / 串流源但未同步 `deployment_guide.md`
- 新增 `*.pt` / `*.zip` / 資料集進版控
- 把串流帳密或伺服器 IP 寫進程式碼或 commit 訊息
