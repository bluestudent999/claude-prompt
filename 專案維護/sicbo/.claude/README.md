# sicbo 維護範本 — 使用指南

骰寶（Sicbo）骰子辨識服務的 AI Agent 維護規範。目標專案：`detector/sicbo`（Python 3.12+ / YOLOv8 / OpenCV），從直播串流即時辨識 3 顆骰子點數，以 TCP 廣播給 Go 端荷官系統。

---

## 部署

```bash
cd ~/python/detector/sicbo       # 換成你本機 sicbo 的 clone 路徑
prompt-setup 專案維護 sicbo
claude
```

> ⚠️ **部署到 `sicbo/` 子目錄，不是 repo 根**。git repo 根在 `detector/`（同層還有 `baccarat_3type`、`xocdia`、`ai_magic`），但規範是為 sicbo 寫的。

---

## 快速開始

提需求時建議帶這 6 欄（缺欄不擋工，Claude 會用 `⏳` 補問）：

```
需求類型：辨識行為變更 / Bug 修復 / 部署調整 / 訓練 / 純重構 / 文案
需求簡述：（一句話）
落在哪一段：資料 / 訓練 / 晉升 / 推論 / 輸出 / 部署
觸發情境：（哪一桌、哪個串流、什麼時間、什麼光線）
預期結果：（可觀察的變化，如「Go 端每局收到一次」「漏判 3/10 → 0/10」）
證據：（截圖 / 原始影像路徑 / log 片段 / Go 端收到的 payload）
```

**辨識類問題沒有「觸發情境」和「證據」等於沒有需求**——Claude 只能憑描述猜，結論不可信。
留存證據在：`data/verified_rounds_sicbo/`（開盅驗證圖 + `origin/` 原始圖）、`data/raw/collected_data_sicbo/`（低信心度自動收集 + 手動按 `s` 截圖）。

---

## Skills

| 指令 | 什麼時候用 |
|------|-----------|
| `/spec-review` | 動辨識行為 / 輸出契約 / 部署介面前（強制） |
| `/doc-code-sync` | **提交前必跑**（若動到介面）；或接手時想知道文件哪裡不能信 |
| `/model-promote` | 訓練完成，要把新權重推上生產 |
| `/stream-debug` | 收到「辨識有問題」但不知道在哪一段 |
| `/strategic-compact` | 讀了 ≥3 檔或跑了 ≥2 輪 reviewer 之後 |

---

## Sub-agents

| Agent | 管什麼 |
|-------|--------|
| `code-reviewer` | Python 品質、過度工程、例外精度、資源釋放 |
| `cv-pipeline-reviewer` | 推論 9 步順序與參數、追蹤、穩定判定、準確度回歸風險 |
| `detector-contract-reviewer` | TCP 契約、送出時機與去重、Go 端相容性 |
| `deployment-reviewer` | 主程式 ↔ 啟動腳本 ↔ 部署文件 ↔ 打包腳本四者一致性、跨平台、無頭環境 |
| `build-error-resolver` | import / 相依 / CUDA-MPS / OpenCV 執行期錯誤 |
| `planner` | 拆步驟 + 寫**可執行的驗證計畫**（L1 強制） |

L3 → `code-reviewer` × 1；L2 → + 擇一領域；L1 → + 必要領域全上，平行啟動。

---

## 這套規範在防什麼

**1. 送錯點數比送不出去更嚴重**
現場是真實賭桌。Go 端收不到只是這局沒結果，**收到錯的是結算錯誤**。所以 `detector-contract-reviewer` 的偏誤方向是寧可擋下也不放行，`send_dice_result` 的「3 顆 + 1-6」兩道檢查列為不可移除。

**2. 文件不可信，必須 grep 驗證**
`.plan/deployment_guide.md` 是運維唯一會讀的東西，而它目前描述了一個**不存在的介面**（見下）。規範要求任何「文件說支援 X」都要先 grep 確認，並在改介面時強制同步 4 處。

**3. 沒有自動化測試，驗證方式是回放**
專案無 pytest、無 `tests/`。L1 的驗證是「用 `data/verified_rounds_sicbo/origin/` 的留存影像重跑一次比對」+「起 TCP client 收一筆」。規範要求 planner 的 §4 必須寫出**改前基準從哪來**與**通過門檻**——寫不出來的 plan 不該被批准。

**4. 辨識不準的第一反應是補資料，不是調參數**
調參數只是把漏判換成誤判。只有確認門檻本身不合理（換攝影機、換解析度）才調，且必須回放驗證。

**5. 一次只修一項**
下面列了 9 項已知落差，很容易一時興起全部重寫成乾淨架構。規範明令一次一項、各自驗證、各自 commit——這樣壞了才知道是哪一項壞的。

---

## ⚠️ 已知落差（接手前必讀）

這些是**當前程式碼與文件的實際落差**，不是待辦幻想：

| # | 落差 |
|---|------|
| 1 | **TCP 廣播未接線**：主程式沒有 import `TCPBroadcaster`。`pack_prod.sh` 打包它、文件詳述它、Go 端等它，但**主程式不會廣播** |
| 2 | **CLI 參數不存在**：主程式無 argparse，`sys.argv[1]` 當「模型版本資料夾名」。`start_recognize.bat` 傳 `models\best.pt --stream-url ... --port 9003` → 全部誤解析／靜默忽略 |
| 3 | 串流位址硬編碼於 `STREAM_URL`，換串流要改 code |
| 4 | **無 CUDA 分支**：只判斷 `mps`。部署指南教運維裝 CUDA 版 PyTorch，但程式不會用 GPU |
| 5 | 字型硬編碼 macOS 路徑；`DroidSansFallback.ttf` 被打包卻**無任何 `.py` 引用** |
| 6 | `config/dataset.yaml` 與 `.plan/architecture.md` 仍指向舊路徑 `python/machineLearning/sicbo` |
| 7 | **關鍵檔案未進版控**：`tcp_broadcaster.py`、`pack_prod.sh`、`models/`、`start_recognize.bat`、`deployment_guide.md`、`DroidSansFallback.ttf` 全是 untracked |
| 8 | `.plan/architecture.md` 宣稱的 `src/` `tests/` `notebooks/` `outputs/` 不存在 |
| 9 | 無任何自動化測試 |

> 修任一項前先跑 `/doc-code-sync` 確認基準，修完回來更新這份清單與 skill 內的基準表。

---

## 檔案結構

```
.claude/
├── CLAUDE.md            ← 部署後搬到 sicbo/ 根目錄（入口索引 + 路由 + 已知落差）
├── README.md            ← 本檔
├── settings.json        ← 權限白名單 + 開工提醒 + autoMode 邊界
├── rules/               ← 每次 session 自動注入
│   ├── detector-contract.md    最高紅線：TCP 契約、開盅判定、文件同步義務、跨平台
│   ├── pipeline.md             五段管線、推論 9 步參數表、驗證方式、資料目錄語意
│   ├── development-workflow.md 需求格式、preflight、5 步、OQ 規則
│   ├── coding-style.md         Python 風格、大檔讀取、最小可行實作
│   ├── git-workflow.md         monorepo 分支紀律、commit 格式、大檔與未進版控清單
│   └── agents.md               L 層定義、reviewer 路由、Harness Output Contract
├── agents/              ← 6 個角色
└── skills/              ← spec-review / doc-code-sync / model-promote / stream-debug / strategic-compact
```

---

## 常見問題

**Q：為什麼不共用 `baccarat_3type` 的規範？**
兩者是同 repo 的**不同子專案**——不同模型、不同輸出契約（百家樂牌型 vs 三顆骰子）、不同管線參數。刻意不抽共用；要參考就去看它怎麼做再複製一份改（`coding-style.md` §7）。

**Q：Go 端 `casino_dealer_client` 出問題也找這個範本嗎？**
不。本範本只負責「照契約送出正確 JSON」。Go 端要改解析、改欄位、改遊戲類型是**另一個 repo 的工作**，本範本不代改也不臆測其行為。

**Q：想動 TCP 契約？**
停手。那是跨 repo 雙邊變更，必須兩邊一起改、一起部署。`detector-contract-reviewer` 會擋下並要求你去協調。

**Q：`git add -A` 為什麼被列為 soft_deny？**
repo 根在 `detector/`，`git add -A` 會把同事正在改的 `baccarat_3type` / `xocdia` 一起帶走。永遠用明確路徑 `git add sicbo/...`。
