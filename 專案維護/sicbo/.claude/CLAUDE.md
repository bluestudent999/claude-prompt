# sicbo

骰寶（Sicbo）骰子辨識服務：Python 3.12+ / YOLOv8 電腦視覺，從直播串流即時辨識 3 顆骰子點數，並以 TCP 廣播開盅結果給 Go 端荷官系統。本文件是 `.claude/` 規範集的入口索引；細節請依連結深入閱讀。

> **語言慣例：** AI 回覆與程式碼註解／docstring 一律**繁體中文**（技術術語保留英文）；`print` / log 訊息沿用既有慣例（`[INFO]` / `[WARN]` / `[ERROR]` 前綴）。

---

## 0. 快速上手導引

當使用者說出「如何開始」「怎麼開始」「要提供哪些資訊」「如何提需求」等關鍵詞時，
用 `grep -n "## 快速開始" .claude/README.md` 取得行號 N，再 Read offset=N limit=25，將內容直接輸出給使用者。

---

## 1. 專案概覽

- **位置**：`sicbo/` 是 **monorepo `detector/` 底下的一個子專案**（同層還有 `baccarat_3type`、`xocdia`、`ai_magic`）。git repo 根在 `detector/`，主要分支 `dev`。
- **Python**：3.12+ ／ 虛擬環境 `sicbo/venv`（標註工具 label-studio 另用 `detector/dice_env`）
- **核心相依**：`ultralytics`(YOLOv8)、`opencv-python`、`torch`、`pillow`、`numpy`（`requirements.txt` 僅 5 行，無版本鎖定）
- **參考專案**：`baccarat_3type`（同 repo，較成熟：有 1280/corner 變體、`eval_confusion.py`、`captures/` 驗證機制）—— 找不到 sicbo 的做法時**先去看它怎麼做**，不要自創第二套。
- **下游消費者**：Go 專案 `casino-dealer/casino_dealer_client`（**不同 repo**），透過 TCP 9003 接收開盅結果。

### 檔案地圖

| 檔案 | 行數 | 職責 |
|------|-----:|------|
| `recognize_sicbo_stream.py` | 584 | **即時辨識主程式**：拉流 → 推論 → 過濾 → 追蹤 → 開盅判定 → 存驗證圖 |
| `local_train.py` | 441 | 本機訓練：解壓 Label Studio zip → 清洗標籤 → 80/20 分割 → YOLO 訓練 |
| `yolo_ml_backend.py` | 226 | Label Studio ML Backend（port 9094）自動預標註 |
| `tcp_broadcaster.py` | 127 | **TCP Server（port 9003）**，廣播 `{"value":"123"}` 給 Go 端 |
| `pack_prod.sh` | 72 | 生產環境最小化打包 → `sicbo_prod.zip` |
| `config/dataset.yaml` | 10 | YOLO 資料集定義（`nc: 6`，類別 `'1'`~`'6'`） |
| `.plan/*.md` | — | 設計文件：`big_picture` / `architecture` / `task_list` / **`deployment_guide`（運維聖經）** |

---

## 2. 模組路由（接到任務時優先查這裡）

完整管線分段、各段契約與參數表 → [`.claude/rules/pipeline.md`](.claude/rules/pipeline.md)

| 需求關鍵字 | 落在哪一段 | 主要檔案 | 風險 |
|-----------|-----------|---------|------|
| 開盅 / 廣播 / Go 端 / 收不到結果 / JSON 格式 | 輸出 | `tcp_broadcaster.py` + 主程式接線處 | **L1** |
| 辨識不準 / 漏判 / 誤判 / 信心度 / 重疊框 / 追蹤 | 推論與後處理 | `recognize_sicbo_stream.py` | **L1** |
| 串流斷線 / 拉不到流 / 畫面卡頓 / FPS | 串流 | `recognize_sicbo_stream.py::read_stream` | L2 |
| 訓練 / 資料集 / 標註 / 增強參數 / mAP | 訓練 | `local_train.py`、`config/dataset.yaml` | L2 |
| 自動預標註 / Label Studio | 標註輔助 | `yolo_ml_backend.py`、`start_backend.sh` | L3 |
| 打包 / 部署 / systemd / NSSM / 防火牆 | 部署 | `pack_prod.sh`、`start_recognize.*`、`.plan/deployment_guide.md` | **L1** |
| 畫面文字 / 中文亂碼 / 外框樣式 | 視覺化 | `recognize_sicbo_stream.py` 繪圖段 | L3 |

---

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

> **你在這裡：維護 · sicbo（骰寶辨識）**（表格第 8 列為本職，不適用切換）。
> 切換提示範例：「這是 `baccarat_3type`（百家樂牌型）的維護，本範本是 sicbo，兩者是同 repo 的**不同子專案**，模型與管線不共用；請另開對應範本或明確指定要改 baccarat。」「這是一段全新需求（新遊戲類型 / 新輸出協議），請先 `prompt-setup 專案企劃` 收斂範圍。」
> **跨 repo 邊界：** Go 端 `casino_dealer_client` **不在本範本職責內**。本專案只負責「照契約送出正確的 JSON」；Go 端要改解析、改欄位、改遊戲類型 → 那是 Go 專案的工作，本範本**不得**代為修改或臆測其行為（見 `rules/detector-contract.md`）。

---

## 3. 硬性規範（合入前必查）

| 主題 | 規範 |
|------|------|
| **Go 端 TCP 契約**（最高紅線） | [`rules/detector-contract.md`](.claude/rules/detector-contract.md)：`{"value":"NNN"}`、3 字元、每字元 1-6、開盅判定 3 顆穩定 1.5 秒 |
| **文件↔程式碼一致性**（本專案最大實際問題） | [`rules/detector-contract.md`](.claude/rules/detector-contract.md) §4：`.plan/deployment_guide.md`、`start_recognize.*`、`pack_prod.sh` 三者與主程式必須同步 |
| 管線分段與參數 | [`rules/pipeline.md`](.claude/rules/pipeline.md)：conf 0.40 / IoU 0.5 / 面積 400 / 追蹤距離 60 / 穩定 1.5s |
| 辨識準確度回歸 | [`rules/pipeline.md`](.claude/rules/pipeline.md) §5：改推論參數必須用**留存的驗證圖**回放比對，不得憑感覺調 |
| Python 風格 / Token 紀律 | [`rules/coding-style.md`](.claude/rules/coding-style.md)（> 300 行禁 full read、最小可行實作） |
| 分支 / commit / 大檔紀律 | [`rules/git-workflow.md`](.claude/rules/git-workflow.md)（**權重與資料集不得再新增進版控**；**測試分支禁止回流開發分支**） |
| Agent 路由 / 輸出契約 | [`rules/agents.md`](.claude/rules/agents.md) |

---

## 4. 開發工作流程（5 步 + preflight）

```
Step -1 Preflight（venv 啟用 + py_compile smoke + 模型與串流可達性）
Step 0  Research（先看 baccarat_3type 有無同款做法，避免重造）
Step 1  Spec   （涉及辨識行為或輸出契約時強制；spec-review skill）
Step 2  Plan   （planner agent → plan/YYYY-MM-DD_<feat>_plan.md）
Step 3  Verify （L1 → 驗證圖回放比對 / 契約 smoke；L2/L3 → 不強制）
Step 4  Review （依 L 層派 reviewer，平行啟動）
Step 5  Commit （type(sicbo): 描述；同步文件與部署腳本）
```

完整規範見 [`rules/development-workflow.md`](.claude/rules/development-workflow.md)。

> **本專案沒有自動化測試。** 因此 Step 3 的「驗證」不是跑 pytest，而是**用留存的 `data/verified_rounds_sicbo/` 影像回放**與**契約 smoke（實際起 TCP 連線收一筆）**。細節見 `rules/pipeline.md` §5。

---

## 5. Agent 路由

L3 → `code-reviewer` × 1；L2 → + 擇一領域；L1 → + `cv-pipeline-reviewer` / `detector-contract-reviewer` / `deployment-reviewer` 中必要者，**平行啟動**；所有 reviewer 須輸出 Harness Output Contract。
詳見 [`rules/agents.md`](.claude/rules/agents.md)。

---

## 6. Skills（按任務載入）

| Skill | 用途 |
|-------|------|
| `spec-review` | 開發前產出結構化規格讓人確認（涉及辨識行為 / 輸出契約時強制） |
| `doc-code-sync` | **稽核「文件、部署腳本、主程式」三者落差**——本專案最容易出事的地方 |
| `model-promote` | 訓練成果 → `models/best.pt` → `pack_prod.sh` 的完整晉升流程與檢查 |
| `stream-debug` | 串流拉不到 / 辨識不準 / Go 端收不到 的分層排查手冊 |
| `strategic-compact` | 在邏輯間隔點壓縮 context |

---

## 7. 已知落差（接手前必讀）

以下是**當前程式碼與文件的實際落差**，不是待辦幻想。動到相關區域時必須先確認現況，**不要相信文件描述的行為**：

1. **TCP 廣播未接線**：`recognize_sicbo_stream.py` 沒有 import 或使用 `TCPBroadcaster`。`pack_prod.sh` 會打包它、`deployment_guide.md` 詳述它、Go 端等它，但**主程式不會廣播任何東西**。
2. **CLI 參數不存在**：主程式無 `argparse`，`sys.argv[1]` 被當作「模型版本資料夾名」。而 `start_recognize.bat`（正式環境啟動腳本）傳的是 `models\best.pt --stream-url ... --port 9003`，`start_recognize.sh` 傳的是 `--weights train-2` —— **兩者都會被誤解析，額外旗標靜默忽略**。
3. **串流位址硬編碼**在主程式常數區（`STREAM_URL`），正式環境換串流要改 code。
4. **無 CUDA 分支**：`device = "mps" if torch.backends.mps.is_available() else "cpu"`。部署指南教運維安裝 CUDA 版 PyTorch，但程式**不會用 GPU**。
5. **字型 macOS 硬編碼**：`/System/Library/Fonts/STHeiti Medium.ttc`；`DroidSansFallback.ttf` 被打包進生產包卻**沒有任何 `.py` 引用**，Windows/Linux 中文會變方框或退回無中文的預設字型。
6. **舊路徑殘留**：`config/dataset.yaml` 的 `path:` 與 `.plan/architecture.md` 的連結仍指向 `python/machineLearning/sicbo`（專案已搬到 `python/detector/sicbo`）。
7. **關鍵檔案未進版控**：`tcp_broadcaster.py`、`pack_prod.sh`、`models/`、`start_recognize.bat`、`.plan/deployment_guide.md`、`DroidSansFallback.ttf` 目前都是 untracked。
8. **`.plan/architecture.md` 宣稱的目錄不存在**：`src/`、`tests/`、`notebooks/`、`outputs/` 皆無。
9. **無任何自動化測試**。

> 修這些落差時**一次只修一項**、走完整流程、同步更新文件。**禁止**在修 A 的 commit 裡順手改 B（見 `rules/coding-style.md` 最小可行實作、`rules/git-workflow.md`）。

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
