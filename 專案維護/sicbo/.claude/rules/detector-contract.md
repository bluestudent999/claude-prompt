# 輸出契約與文件同步（最高紅線）

> 本專案存在的唯一理由，是**讓 Go 端荷官系統拿到正確的開盅點數**。畫面好不好看、辨識率多高，都在這個目的之下。
> 契約破了，Go 端不會報錯——它會**收到錯的點數或什麼都收不到**，而現場是真實的賭桌結算。

---

## 1. TCP 輸出契約（不可片面變更）

**唯一事實來源：** `tcp_broadcaster.py` 的模組 docstring（它記錄了 Go 端的解析方式）。改契約前先讀它。

| 項目 | 規格 |
|------|------|
| 傳輸 | raw TCP，Python 端為 **Server**，Go 端為 Client 主動連入 |
| 預設埠 | **9003** |
| 訊息格式 | 單一 JSON 物件：`{"value":"123"}` |
| `value` | **恰好 3 個字元**，每個字元是一顆骰子點數 **1–6** |
| 分隔符 | **無**。Go 端 `extractor.go` 以掃描 `{` / `}` 邊界切分，故每次送出必須是**完整且獨立**的 JSON 物件 |
| Go 端對應 | `GameName = sicbo`；`detector.BytesToEvent()` 讀 `value[0..2]` → `ThreeDiceGameResult[0..2]`；`ThreeDiceGameResult.Check()` 再驗一次 1–6 |
| Go 端設定 | `table_settings.detector_address = <IP>:9003`、`game_name = sicbo` |

### 紅線

1. **禁止片面改變 JSON 結構、欄位名或 `value` 語意**。Go 端在**不同 repo**，不會跟著你改；它拿到不認識的欄位不會報錯，只會解析失敗或取到垃圾值。
2. **禁止一次送出多筆或半筆 JSON**。Go 端靠大括號配對切分，被截斷的訊息會污染後續解析。
3. **禁止送出未通過驗證的結果**：非 3 顆、點數不在 1–6、或未達穩定條件者一律不送。寧可**不送**，不可**送錯**——Go 端收不到只是這局沒結果，收到錯的是結算錯誤。
4. **要改契約 → 停手，回報使用者協調 Go 端**。這是跨 repo 的雙邊變更，必須兩邊一起改、一起部署。本範本**不得**修改或臆測 Go 端行為。

### `tcp_broadcaster.py` 既有的自我防護（不要拿掉）

`send_dice_result()` 已內建兩道檢查，它們是最後一道防線：

- `len(dice_values) != 3` → 印錯誤並**不送**
- 任一值不在 `1 <= v <= 6` → 印錯誤並**不送**

改動這個函式時，**這兩道檢查必須保留**。

---

## 2. 開盅判定規則（決定「何時送」）

當前主程式（`recognize_sicbo_stream.py`）的判定條件：

```
偵測到「剛好 3 顆」真實骰子（非虛擬框）
  且 該狀態穩定滿 1.5 秒（stable_elapsed >= 1.5）
  且 本次穩定期間尚未擷取過（captured_this_stable_period == False）
→ 判定為一次有效開盅
```

回合結束條件：`has_dices_in_round == True` 且 `len(round_dices) == 0`（骰盅蓋上／畫面無骰子）。

### 紅線

- **一回合只送一次**。`captured_this_stable_period` 就是防重送的旗標，改動穩定判定時必須確認它仍然有效。
- **調整 `1.5` 秒穩定門檻 = L1 變更**。太短 → 搖骰過程中的瞬間 3 顆會被誤判為開盅；太長 → 荷官已收骰但還沒送出。改它必須用留存驗證圖回放驗證（見 `pipeline.md` §5）。
- **`real_dice_count` 必須排除虛擬框**（`is_virtual`）。用虛擬框湊滿 3 顆再送出 = 送出猜測值，等同造假。

---

## 3. ⚠️ 當前狀態：廣播尚未接線

**事實：** `recognize_sicbo_stream.py` 目前**沒有 import 或使用 `TCPBroadcaster`**（`grep -n "TCPBroadcaster\|tcp_broadcaster" recognize_sicbo_stream.py` 零命中）。開盅判定成立時，程式只做了「存驗證截圖」與「收集低信心度素材」，**沒有任何 TCP 送出**。

因此：
- `pack_prod.sh` 會把 `tcp_broadcaster.py` 打包進生產包 —— 但它不會被載入。
- `.plan/deployment_guide.md` §1.1、§7、§8 Q4/Q6 描述的 TCP 行為 **目前不成立**。
- Go 端連得上 9003 嗎？**連不上**——沒有人 `start()` 那個 server。

**接線時的必辦事項**（這是一次 L1 變更，不是順手加兩行）：

1. 在 `main()` 建立 `TCPBroadcaster` 並 `start()`，程式結束路徑（`q`、串流中斷、例外）都要 `stop()`。
2. 在**開盅判定成立處**（`stable_elapsed >= 1.5 and real_dice_count == 3 and not captured_this_stable_period`）呼叫 `send_dice_result(dice_values)`，且 `dice_values` 必須來自**非虛擬**的 3 顆骰子、依畫面位置排序後的點數。
3. **順序不可顛倒**：先確認 3 顆有效再送，不要在迴圈中對每顆各送一次。
4. 同步更新 `.plan/deployment_guide.md`（把「目前未接線」的註記移除）。
5. 用「實際起一個 TCP client 連 9003 收一筆」做 smoke（見 `skills/stream-debug`）。

---

## 4. 文件↔程式碼一致性（本專案最大實際問題）

`.plan/deployment_guide.md` 是**運維人員唯一會讀的東西**。它現在描述了一個不存在的介面：

| 文件／腳本描述 | 程式碼實況 |
|---|---|
| `recognize_sicbo_stream.py models/best.pt --stream-url "..." --port 9003` | 主程式**無 argparse**；`sys.argv[1]` 被當「模型版本資料夾名」，`--stream-url` / `--port` **靜默忽略** |
| `start_recognize.bat` 傳 `models\best.pt --stream-url ... --port 9003` | argv[1]=`models\best.pt` 找不到對應資料夾 → fallback 到最新 train 或 `yolov8n.pt` |
| `start_recognize.sh` 傳 `--weights train-2` | argv[1]=`--weights`，同樣誤解析 |
| systemd / NSSM 設定範例帶 `--stream-url` `--port` | 同上，全部無效 |
| 「GPU 環境請安裝 CUDA 版 PyTorch」 | 程式只判斷 `mps`，NVIDIA 機器**靜默跑 CPU** |
| 「已隨附 `DroidSansFallback.ttf` 作為後備字型，會自動偵測系統中文字型」 | **沒有任何 `.py` 引用該檔**；字型路徑硬編碼 macOS `STHeiti Medium.ttc` |

### 硬規則

1. **改主程式的 CLI 介面、埠、串流來源、模型載入方式 → 必須在同一次變更內同步**：
   - `.plan/deployment_guide.md`
   - `start_recognize.bat`（Windows 生產）
   - `start_recognize.sh`（本機）
   - `pack_prod.sh` 的 `REQUIRED_FILES` 清單（若檔案增減）
2. **反向不成立**：改文件**不等於**改了行為。看到文件寫某個旗標，先 `grep` 確認程式真的支援再用。
3. **交付前跑 `/doc-code-sync`**，逐項比對三者是否一致。
4. 修「文件描述不存在的行為」這類落差時，**先問使用者要往哪邊對齊**：補程式碼支援該介面（推薦，運維已照文件配置），還是改文件降級為現況。這是產品決策不是技術決策。

---

## 5. 跨平台事實（macOS 開發 / Windows + Linux 生產）

| 面向 | macOS（開發） | Windows / Linux（生產） | 現況風險 |
|------|--------------|------------------------|---------|
| 推論裝置 | `mps`（Apple Silicon） | 應為 `cuda`，實際落到 `cpu` | FPS 遠低於預期 |
| 中文字型 | `/System/Library/Fonts/STHeiti Medium.ttc` | **不存在** → `load_default()` 無中文 | 畫面文字變方框 |
| 路徑分隔 | `/` | `\`（`start_recognize.bat` 用 `models\best.pt`） | 傳入主程式後當字串比對 |
| 視窗顯示 | `cv2.imshow` 正常 | 服務化（systemd / NSSM）後**無 GUI** | 無頭環境呼叫 `imshow` 會失敗 |

> **無頭環境是實際部署形態**（systemd / NSSM 都沒有桌面 session）。改動繪圖或視窗相關程式碼時，必須考慮「生產環境根本不會顯示視窗」——那些程式碼在生產只是白白消耗 CPU，甚至拋例外。要動這塊，先確認是否該加無頭模式開關。
