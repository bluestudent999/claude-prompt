# 管線分段、參數與影響面

> 本文是「改動落在哪一段、會影響什麼」的地圖。動手前先定位段別，再看該段的參數表與影響面。

---

## 1. 五段管線

```
[1 資料]  Label Studio 匯出 zip → 解壓清洗 → 80/20 分割
   ↓
[2 訓練]  local_train.py → runs/detect/train-N/weights/best.pt
   ↓
[3 晉升]  cp best.pt → models/best.pt → pack_prod.sh → sicbo_prod.zip
   ↓
[4 推論]  recognize_sicbo_stream.py：拉流 → YOLO → 過濾 → 追蹤 → 開盅判定
   ↓
[5 輸出]  tcp_broadcaster.py → TCP 9003 → Go casino_dealer_client
```

**旁支：** `yolo_ml_backend.py`（port 9094）供 Label Studio 自動預標註，只影響 [1]，不影響線上辨識。

**單向紀律：** 下游不得回頭改上游的產物。推論階段發現辨識不準 → 回 [1]/[2] 補資料重訓，**不要在 [4] 加特例規則硬掰**（例如「若只偵測到 2 顆就補一顆平均值」）。

---

## 2. [4] 推論段：處理順序與參數（改這裡 = L1）

主程式每一幀的處理順序，**順序本身就是規格**：

| # | 步驟 | 參數／常數 | 改動影響 |
|---|------|-----------|---------|
| 1 | YOLO 推論 | `model(frame, verbose=False)` | — |
| 2 | 信心度過濾 | `AI_CONF_THRESHOLD = 0.40` | 調高 → 漏判（少於 3 顆，不開盅）；調低 → 誤判雜訊為骰子 |
| 3 | 歸一化高度過濾 | `MIN_DICE_HEIGHT = 0.01` | 防遠處雜訊；調高會濾掉小畫面骰子 |
| 4 | 面積過濾 | `STANDARD_DICE_AREA = 400.0`（px²） | 同上，與解析度綁定，換攝影機要重估 |
| 5 | IoU 去重 | 閾值 `0.5`（硬編碼於迴圈內） | 兩顆骰子靠得近時可能被誤合併 |
| 6 | 跨幀追蹤 | `MATCH_DIST_THRESHOLD = 60.0`（中心點距離） | 太小 → 同一顆被當新骰子、時間戳重置；太大 → 兩顆互換身分 |
| 7 | 依 X 座標排序分配槽位 1~3 | `slot_num <= 3` | 決定 `value` 三個字元的**順序** |
| 8 | 穩定判定 | `stable_elapsed >= 1.5` 秒 | 見 `detector-contract.md` §2 |
| 9 | 低信心度收集 | `conf <= 0.85` → Active Learning | 調整只影響收集量，不影響辨識 |

### 紅線

- **這 9 個參數都是 L1**。它們共同決定「會不會開錯盅」，而錯的開盅在現場等於結算錯誤。
- 改任一參數 **必須**用留存驗證圖回放比對（§5），並在 plan 記錄「改前 / 改後」數字。
- **禁止為了讓某一支特定影片好看而調參**。過擬合單一場景在換桌／換光線後會全面失效。
- 骰子點數來源是 `get_dice_value(cls_name)`——它從類別名稱中**取第一個 1-6 的數字字元**。改類別命名（`config/dataset.yaml` 的 `names`）會直接影響它，兩者必須同步。

---

## 3. [4] 串流段（L2）

- `read_stream()` 於獨立 thread 拉流，`cv2.VideoCapture(url, cv2.CAP_FFMPEG)`。
- 讀取失敗 → `release()` 後重連；再失敗 → `put(None)` 通知主迴圈中斷。
- `frame_queue` 大小 **2**，且每次 put 前**清空舊幀**——這是刻意的「只處理最新幀」策略，避免推論慢造成延遲累積。**不要改成大 queue**，那會讓開盅結果延遲數秒送出。
- 串流位址目前**硬編碼**於 `STREAM_URL`（見 `detector-contract.md` §4）。

---

## 4. [1][2] 資料與訓練段（L2）

| 項目 | 現況 |
|------|------|
| 資料來源 | `data/yolo_zip/` 放 Label Studio 匯出 zip，`local_train.py` 自動取最新 |
| 標籤清洗 | Segment / OBB 格式 → 清洗為 YOLO 標準 5 欄位 |
| 分割 | 80% train / 20% val，輸出 `data/dice_dataset/` |
| 類別 | `nc: 6`，`names: ['1','2','3','4','5','6']` |
| 訓練參數 | `imgsz=1280`、`degrees=180.0`、`fliplr=0.5`、`flipud=0.5`、`batch=-1`、`patience=30`、`mixup=0.1`、`copy_paste=0.1`、`hsv_s=0.3`、`hsv_v=0.3` |
| 乾跑 | `python local_train.py --dryrun`（只驗資料集不訓練） |

**參數的理由（不要無故推翻）：**
- `degrees=180.0` + 雙向翻轉：骰子在桌面上是**任意角度**的，靠線上增強取代磁碟實體旋轉。
- `imgsz=1280`：骰子點數是**小特徵**，降解析度會直接掉點數判別率。
- `hsv_s/v=0.3`（偏保守）：壓克力骰盅**反光嚴重**，色彩擾動太大會讓模型學到錯誤的亮度特徵。

**紅線：** 改訓練參數前先跑 `--dryrun` 確認資料集完整；改完必須保留 `runs/detect/train-N/` 的評估產物（`results.png`、混淆矩陣）作為比較依據，**不要覆蓋既有 train 目錄**。

---

## 5. 驗證方式（本專案沒有自動化測試）

專案**無 pytest、無 tests/**。因此「驗證」指的是下列具體動作，依 L 層決定強度：

### L1（推論參數 / 開盅判定 / 輸出契約 / 部署介面）

1. **驗證圖回放**：`data/verified_rounds_sicbo/` 存有歷次開盅的標註圖與 `origin/` 原始圖。改動後用**同一批原始圖**跑一次，逐張比對辨識到的點數與框數是否一致。改前改後的差異必須能解釋。
2. **契約 smoke**：實際起服務，用一個 TCP client 連 9003，確認收到的 payload 是合法的 `{"value":"NNN"}`（3 字元、每字元 1-6），且**一回合只收到一次**。
3. **編譯檢查**：`python -m py_compile recognize_sicbo_stream.py tcp_broadcaster.py`
4. 若改到部署介面，額外跑 `bash -n start_recognize.sh` 與 `pack_prod.sh` 的乾跑檢查。

### L2（串流 / 訓練 / 資料處理）

- 訓練類：`python local_train.py --dryrun` 通過。
- 串流類：實際拉流跑 ≥ 1 個完整回合，確認不中斷、不卡頓。

### L3（文案 / 繪圖樣式 / 註解 / 設定）

- `py_compile` 通過 + `code-reviewer` 輕掃即可。

> **不要為了「有測試」而硬造 pytest 骨架**。這個專案的正確驗證方式是回放真實影像 + 契約 smoke。要引入自動化測試是獨立的一個 TASK，需先與使用者確認（見 `coding-style.md` 最小可行實作）。

---

## 6. 資料目錄語意（不要混用）

| 目錄 | 內容 | 誰寫入 | 進版控？ |
|------|------|--------|---------|
| `data/yolo_zip/` | Label Studio 匯出壓縮檔 | 人工 | ⚠️ 目前**有**（39MB），不應再新增 |
| `data/dice_dataset/` | 解壓分割後的訓練集 | `local_train.py` | ❌ 已 gitignore |
| `data/raw/collected_data_sicbo/` | 手動 `s` 截圖 + 低信心度自動收集（Active Learning 素材） | 主程式 | ❌ 已 gitignore |
| `data/verified_rounds_sicbo/` | 開盅驗證圖（含 `origin/` 原始圖） | 主程式 | ❌ 已 gitignore |
| `runs/detect/train-N/` | 訓練產物與權重 | `local_train.py` | ⚠️ 目前**有**（36 檔 ~25MB），不應再新增 |
| `models/best.pt` | **生產環境模型**（自 `runs/` 手動複製） | 人工 | ⚠️ 目前 untracked |

**紅線：** `verified_rounds_sicbo/` 與 `collected_data_sicbo/` 是**回歸驗證與再訓練的原料**，任何清理腳本或重構都不得刪除它們。要清理必須先確認已備份或已納入下一輪訓練集。
