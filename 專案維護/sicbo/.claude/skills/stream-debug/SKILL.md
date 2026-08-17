---
name: stream-debug
description: 分層排查手冊——串流拉不到、辨識不準、Go 端收不到結果、FPS 太低、中文亂碼。收到「辨識有問題」但不知道問題在哪一段時使用。
---

# stream-debug — 分層排查

**原則：由外而內、逐層排除，每層先確認「這一層是好的」再往下。** 不要一開始就改參數——多數「辨識不準」的回報，根因不在辨識。

---

## 0. 先問清楚（沒有這些資訊只能瞎猜）

| 要問 | 為什麼 |
|------|--------|
| 哪一桌、哪個串流位址 | 不同桌光線與攝影機角度差很多 |
| 什麼時間發生 | 對照 `data/verified_rounds_sicbo/` 的留存圖 |
| 症狀是「完全沒反應」還是「點數錯」 | 前者往往在串流或部署層，後者才在辨識層 |
| Go 端有沒有收到東西 | 分水嶺：收到但錯 vs 完全沒收到 |
| 有沒有截圖 / log / payload | 沒有證據時結論可信度要降級並註明 |

---

## L0：服務有沒有在跑

```bash
# Linux
sudo systemctl status sicbo-detector
journalctl -u sicbo-detector.service -n 100 --no-pager
# Windows
nssm status sicbo-detector
```

**看 log 的第一件事**：有沒有 `[INFO] 載入模型：<path>`。

- 載入的是 `yolov8n.pt` → **模型 fallback 了**，辨識必然全錯（yolov8n 是通用物件模型，不認得骰子點數）。往 L1 查。
- 載入的是 `runs/detect/train-N/...` 而非 `models/best.pt` → 生產環境不該依賴 `runs/`，往 L1 查。

> ⚠️ **無頭環境**：服務化執行時沒有桌面 session，`cv2.imshow` 可能直接讓程式崩潰並被 `Restart=always` 無限重啟。log 若出現反覆啟動 → 這是部署形態問題，不是辨識問題（見 `detector-contract.md` §5）。

---

## L1：模型有沒有正確載入

```bash
ls -l models/best.pt
grep -n "sys.argv\|find_latest_train_model\|possible_folders" recognize_sicbo_stream.py
```

**已知陷阱：** 主程式把 `sys.argv[1]` 當作**模型版本資料夾名**，而 `start_recognize.bat` 傳的是 `models\best.pt`。它會去找 `runs/detect/models\best.pt/weights/best.pt`，找不到 → fallback 到最新 train → 再找不到 → `yolov8n.pt`。

**確認實際載入了什麼**：直接看 log 的 `[INFO] 載入模型：` 那行，**不要相信啟動指令看起來傳了什麼**。

---

## L2：串流通不通

```bash
# 串流本身是否可播（與程式無關）
ffplay -autoexit -t 5 "<stream-url>"
# 或
vlc "<stream-url>"
```

- 播不出來 → **問題不在本專案**，是串流服務或網路。
- 播得出來但程式報 `[ERROR] 無法開啟串流` → OpenCV FFMPEG backend 問題，查 `libgl1` / `ffmpeg` 是否安裝（`deployment_guide.md` §2.1）。
- 程式報 `[WARN] 讀取失敗，嘗試重連` 反覆出現 → 網路不穩或串流間歇中斷；`read_stream()` 有重連機制，但重連期間不會辨識。

---

## L3：辨識層（確認 L0-L2 都正常才進來）

### 先看留存證據，不要先改參數

```bash
ls -lt data/verified_rounds_sicbo/ | head          # 開盅驗證圖（含框與點數）
ls -lt data/verified_rounds_sicbo/origin/ | head   # 對應的原始圖
ls -lt data/raw/collected_data_sicbo/ | head       # 低信心度自動收集 + 手動 s 截圖
```

用出問題那個時間點的驗證圖，**肉眼確認**：

| 觀察到 | 指向 |
|--------|------|
| 框數 < 3 | 漏判 → conf 門檻太高 / 光線暗 / 骰子被遮 → **資料問題，補標註重訓**（不要直接降 conf） |
| 框數 > 3 | 誤判 → 雜訊被當骰子 → 面積或高度過濾門檻 |
| 框數正確但點數錯 | **模型能力問題** → 補該情境的標註資料重訓 |
| 兩顆骰子被框成一顆 | IoU 去重門檻（0.5）誤合併 |
| 框在跳動、點數反覆變化 | 追蹤問題 → `MATCH_DIST_THRESHOLD` |
| 沒有留存圖 | 該局根本沒達到「3 顆穩定 1.5 秒」→ 往穩定判定查 |

### 紅線

**「辨識不準」的第一反應應該是「補資料重訓」，不是「調參數」。** 調參數只是把錯誤從一種形式換成另一種形式（降 conf 減少漏判 → 增加誤判）。只有在確認是門檻設定不合理（例如換了攝影機、換了解析度）時才調參數，且必須回放驗證（`pipeline.md` §5）。

---

## L4：輸出層（Go 端收不到）

```bash
# 服務端有沒有在監聽？
netstat -tuln | grep 9003          # Linux
netstat -ano | findstr 9003        # Windows

# 手動連進去收一筆
nc localhost 9003
# 或
python3 -c "import socket;s=socket.create_connection(('127.0.0.1',9003));print(s.recv(4096))"
```

| 現象 | 根因 |
|------|------|
| **沒有任何行程在聽 9003** | **已知落差 #2**：主程式根本沒有 import/啟動 `TCPBroadcaster`。`grep -n "TCPBroadcaster" recognize_sicbo_stream.py` 確認。這不是設定問題，是功能未接線 |
| 有在聽但 Go 端連不上 | 防火牆（`deployment_guide.md` §7）／Go 端 `table_settings.detector_address` 設錯 |
| 連得上但收不到資料 | 沒有任何一局達到「3 顆穩定 1.5 秒」→ 回 L3 |
| 收到但 Go 端解析失敗 | JSON 格式被改動 → 查 `detector-contract.md` §1；確認是完整獨立的 `{"value":"NNN"}` |
| 一局收到多筆 | `captured_this_stable_period` 去重失效 → 契約違規，立即回報 |

---

## L5：其他症狀

| 症狀 | 排查 |
|------|------|
| FPS 很低 / 延遲高 | `python -c "import torch; print(torch.cuda.is_available())"`。**已知落差 #4**：程式只判斷 `mps`，NVIDIA 機器會跑 CPU。這是功能落差不是設定問題 |
| 中文顯示方框 | **已知落差 #5**：字型硬編碼 macOS 路徑；`DroidSansFallback.ttf` 被打包卻未被使用 |
| 開盅延遲數秒才送出 | 檢查 `frame_queue` 是否被改大（應為 2 且每次清空舊幀，見 `pipeline.md` §3） |
| 程式吃記憶體越來越多 | 檢查是否在迴圈內累積 list / 未釋放的影像；`round_dices` 是否正常在回合結束時 clear |

---

## 輸出格式

排查完回報：

```
症狀：<使用者描述>
排查層級：L0 ✓ / L1 ✓ / L2 ✓ / L3 ✗ ← 問題在這層
根因：<具體，含證據路徑或 grep 結果>
是否為已知落差：<CLAUDE.md §7 第 n 項 / 否>
建議處置：<補資料重訓 / 調參數（需回放驗證）/ 修落差（需走完整流程）/ 環境問題非程式碼>
證據：<截圖路徑、log 片段、grep 輸出>
```

**若根因是已知落差**：不要當場修。那是 L1 變更，要走 spec → plan → 驗證 → review（`development-workflow.md`）。
