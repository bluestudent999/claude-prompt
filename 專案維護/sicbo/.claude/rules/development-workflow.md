# 開發工作流程（sicbo）

> 開發流程層規範（環境、研究、規格、規劃、驗證、審查）。git 操作見 [git-workflow.md](./git-workflow.md)。

---

## 需求提交格式（使用者端）

**軟性格式**（缺欄位不擋工，由 `spec-review` 以 `⏳` 補問）。建議 6 欄位：

| 欄位 | Claude 端用途 |
|------|------------|
| **需求類型** | 路由 Step 1 gate：辨識行為變更 / 新功能 → `spec-review`；bug fix（非辨識行為）→ 跳過；純重構 → 跳過 spec；typo / 文案 → 全略 |
| **需求簡述** | 交叉驗證需求類型 |
| **落在哪一段** | 資料 / 訓練 / 晉升 / 推論 / 輸出 / 部署（見 `pipeline.md` §1）→ 觸發 L 層判定與 reviewer 路由 |
| **觸發情境** | 哪一桌、哪個串流、什麼光線、幾點發生 → Step 0 研究起點；**辨識類問題沒有情境等於沒有需求** |
| **預期結果** | 可觀察的變化（「Go 端每局收到一次」「漏判從 3/10 降到 0/10」）；缺 → **必問** |
| **證據** | 出問題的**截圖 / 原始影像 / log 片段 / Go 端收到的 payload**；辨識類問題**強烈建議附**，否則只能憑描述猜 |

### 缺欄位時的處置

| 缺欄位 | 處置 |
|-------|------|
| 落在哪一段缺 | 依需求簡述推測並輸出給使用者確認，寫入 spec §影響範圍 |
| 觸發情境缺（辨識類） | **必問** — 「辨識不準」沒有情境無法定位是資料問題、參數問題還是光線問題 |
| 預期結果缺 | **必問** — 無可觀察變化等於無法驗收 |
| 證據缺（辨識類） | 提醒使用者可用 `data/verified_rounds_sicbo/` 的留存圖或按 `s` 手動截圖；沒有證據時**降低 confidence 並在 spec 註明結論可能不準** |

---

## Step -1：環境 Preflight（每個 session 第 1 次動工前）

```bash
# 1. 啟用虛擬環境（sicbo 專用；label-studio 是另一個 detector/dice_env）
cd /path/to/detector/sicbo
source venv/bin/activate
python --version            # 需 3.12+

# 2. 語法 smoke（不跑模型，秒級）
python -m py_compile recognize_sicbo_stream.py tcp_broadcaster.py local_train.py yolo_ml_backend.py

# 3. 確認生產模型存在（涉及推論或部署時）
ls -l models/best.pt 2>/dev/null || echo "[preflight] models/best.pt 不存在，推論會 fallback 到 runs/ 或 yolov8n.pt"
```

視情境再跑：

```bash
# 涉及 GPU / 效能議題
python -c "import torch; print('cuda', torch.cuda.is_available(), '| mps', torch.backends.mps.is_available())"
# 涉及串流
ffplay -autoexit -t 3 "<stream-url>"   # 或用 VLC 驗證串流可達
```

| 失敗情境 | 處置 |
|---------|------|
| venv 未啟用 / Python < 3.12 | **必修，不動工** |
| `py_compile` 失敗 | **必修** — 代表 HEAD 本身壞掉 |
| `models/best.pt` 不存在 | 不阻塞（會 fallback），但**涉及推論行為的驗證結果不可信**，先補模型 |
| 串流不可達 | 不阻塞 code 修改，但**無法做 L1 驗證**；在 plan 標明「未經實測」 |

---

## Step 0：研究與重用

1. **先看 `baccarat_3type`**：同 repo 的姊妹專案，成熟度更高（1280/corner 變體、`eval_confusion.py`、`captures/` 驗證機制、`docs/`）。要做的事它多半做過。
   ```bash
   ls ../baccarat_3type/
   grep -rn "<關鍵字>" ../baccarat_3type/*.py | head
   ```
   **決策矩陣**：完全匹配 → 採用作法｜部分匹配 → 對齊其模式再改｜找不到 → 自建（並在 plan 說明為何不沿用）。
2. **確認現況而非文件**：本專案文件與程式碼有已知落差（`CLAUDE.md` §7）。**任何「文件說支援 X」都要先 `grep` 驗證**。
   ```bash
   grep -n "<旗標或函式名>" recognize_sicbo_stream.py || echo "文件描述的功能不存在於程式碼"
   ```
3. **大檔案讀取限制**：`recognize_sicbo_stream.py`(584) 與 `local_train.py`(441) **超過 300 行禁止 full read**——先 `grep -n` 建行號索引再 `Read(offset, limit)`（見 [`coding-style.md`](./coding-style.md) §6）。

---

## Step 1：規格確認

**強制走 `spec-review` 的情形：**
- 改動任一推論參數或開盅判定（`pipeline.md` §2）
- 改動 TCP 輸出契約或接線方式（`detector-contract.md`）
- 改動部署介面（CLI、埠、串流來源、打包清單）
- 新增管線能力（新輸出通道、新遊戲類型、無頭模式…）

**可跳過的情形：** 純繪圖樣式、註解 / docstring、單一文案、設定值搬移。

**Mental Model Check（≤100 字，寫 spec 前先給使用者確認）** 必含：
1. **現況真相**（引用 grep 證據）：例「主程式目前未 import TCPBroadcaster，開盅時只存圖」
2. **關鍵檔案與行號**：例「`recognize_sicbo_stream.py:512` 是開盅判定處」
3. **鎖定的實作方向**：例「在 512 判定成立處呼叫 send_dice_result，main() 開頭 start()、結束路徑 stop()」

使用者回「方向錯了」→ 回 Step 0 重查，**不要直接寫完整 spec**。

**CONFIRM gate：** 所有 ⏳ 已決議 + 使用者顯式 CONFIRM 才進 Step 2。

---

## Step 2：規劃

- 用 `planner` agent 產出 `plan/YYYY-MM-DD_<功能名>_plan.md`。
- **必含章節**：§1 Investigation（含 grep 證據）／§2 變更檔案清單（單一事實來源）／§3 實作步驟／§4 驗證計畫（依 `pipeline.md` §5 寫明要回放哪批圖、要做哪個 smoke）／§5 風險／§6 Sequencing／§7 Open Questions／§8 Success Criteria。
- **§4 驗證計畫對 L1 是強制的**，且必須寫出「改前基準數字從哪來」。

**OQ 硬規則：**
- 可用 grep / read / 跑一次驗證的問題 → planner **自答鎖定**，不丟給使用者。
- 需要判斷的問題 → **必列 OQ，嚴禁推測**。本專案典型的必問 OQ：
  - 文件與程式碼衝突時要**往哪邊對齊**（補程式碼 vs 降級文件）——這是產品決策
  - 穩定門檻／信心度門檻的取捨（漏判 vs 誤判，哪個代價高）
  - 是否要支援無頭模式（生產是服務化，但開發需要看畫面）
  - 是否協調 Go 端一起改契約
- OQ 決議必回寫 plan（原文加刪除線 + ✅ 決議），只存 chat 不算數。

**回流硬規則：** plan 階段發現 spec 漏了辨識行為的定義 → **暫停 plan，回 Step 1 補 spec 重 CONFIRM**，禁止在 plan 內偷補行為定義。

---

## Step 3：實作與驗證

**實作紀律：**
- **依計畫實作**。禁止自行重設計、順手優化、或在修 A 的同時修 B（`CLAUDE.md` §7 列了 9 項落差，**一次只修一項**）。
- **不在推論段加特例硬掰**（見 `pipeline.md` §1 單向紀律）。
- **Stop Rule**：遇到文件 / 程式碼 / 契約三者衝突且 plan 沒交代 → **立即停止並回報**，不要猜。

**驗證：** 依 [`pipeline.md`](./pipeline.md) §5 的 L1 / L2 / L3 分層執行。L1 的回放比對結果（改前 / 改後）必須記錄在 plan §4 或 commit 訊息中。

---

## Step 4：審查

依 L 層派 reviewer，見 [`agents.md`](./agents.md)。

**Definition of Done：**
- `py_compile` 通過；涉及 shell 腳本者 `bash -n` 通過
- L1：驗證圖回放已執行且差異可解釋；契約 smoke 已收到合法 payload
- **文件同步已完成**（改介面 → `deployment_guide.md` + `start_recognize.*` + `pack_prod.sh` 已同步，見 `detector-contract.md` §4）
- 無 TODO / FIXME / 註解掉的死碼
- **Dead Code 只清自己造成的**：本次改動造成的未使用 import / 變數 / 函式必須清掉；**既有** dead code 僅記錄回報，不主動刪除
- 未新增大型二進位檔進版控（見 [`git-workflow.md`](./git-workflow.md)）

**完成輸出格式：** `Completed Files`、`Modified Files`、`驗證結果`（回放比對 / smoke 結果）、`文件同步`、`Remaining Work`。

---

## Step 5：提交

見 [`git-workflow.md`](./git-workflow.md)。提交前確認：

1. 文件、部署腳本、主程式三者一致（跑 `/doc-code-sync`）
2. 沒有把 `runs/`、`data/`、`*.pt`、`*.zip` 新增進版控
3. commit 訊息說明「改了什麼行為」而不只是「改了哪個檔」

---

## 操作原則（工具硬規則）

- **同一工具同參數失敗 ≥ 2 次 → 停手換工具 / 解根因**，不第三次重試。
- **大檔案 > 300 行禁 full read**：先 `grep -n` 定位再 `Read(offset, limit)`。
- **平行化**：獨立的 tool call 在同一則訊息中平行啟動。
- **Context 管理**：一個工單 = 一個 session，完成 `/clear`；讀過 ≥ 3 個實作檔或跑過 ≥ 2 輪 reviewer → 評估 `/strategic-compact`。
- **不要把整份影像 / 大量 log 留在 context**：需要時寫檔，對話只留結論與路徑。
