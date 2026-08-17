---
name: model-promote
description: 訓練成果晉升為生產模型的完整流程——挑選 train-N、比較評估指標、複製為 models/best.pt、打包 sicbo_prod.zip、記錄來源。訓練完成後要上線新模型時使用。
---

# model-promote — 模型晉升生產

**換模型是本專案風險最高的例行操作**：它改變的是「骰子點數怎麼被判讀」，而且**沒有自動化測試會攔住你**。

**用法：** `/model-promote`（訓練完成、要把新權重推上生產時）

---

## Step 1：確認候選

```bash
cd /path/to/detector/sicbo
ls -lt runs/detect/                                   # 依時間列出訓練批次
ls -l runs/detect/train-*/weights/best.pt             # 確認權重存在
cat runs/detect/<候選>/args.yaml | head -20           # 這批是用什麼參數訓的
```

**記錄：** 候選批次名、訓練參數（`imgsz`、`epochs`、增強設定）、資料集來源 zip。

---

## Step 2：比較評估指標（不要跳過）

```bash
ls runs/detect/<候選>/          # results.png / results.csv / confusion_matrix*.png
tail -3 runs/detect/<候選>/results.csv
tail -3 runs/detect/<現行>/results.csv
```

比較 **候選 vs 現行**：

| 指標 | 看什麼 |
|------|--------|
| `mAP50` / `mAP50-95` | 整體提升還是退步 |
| 混淆矩陣 | **哪些點數互相搞混**（例如 6 被判成 5、2 被判成 3）——這比總分重要 |
| 各類別 recall | 有沒有某個點數特別容易漏 |

> **紅線：** 總 mAP 提升但某個點數的混淆變嚴重 → **不要晉升**。骰寶三顆骰子任一顆判錯，整局結算就錯了；平均分數掩蓋不了單一類別的退化。

---

## Step 3：實機回放驗證（本專案的「測試」）

```bash
# 用留存的原始圖，分別以現行與候選模型跑一次，比對辨識結果
ls data/verified_rounds_sicbo/origin/ | wc -l
```

- 取**至少 20 局**的原始圖，涵蓋不同光線與時段。
- 逐張比對：**顆數是否都是 3**、**點數是否一致**、**信心度分佈**。
- 差異必須能解釋。候選在某些局變差 → 找出共同特徵（暗光？反光？骰子疊在一起？），評估那些情境的實際發生頻率。

**通過門檻（建議，可依情境調整但要寫進紀錄）：**
- 顆數判定：候選的「3 顆」命中率**不低於**現行
- 點數判定：不出現現行正確而候選錯誤的案例；若有，必須逐案說明可接受的理由

---

## Step 4：晉升

```bash
mkdir -p models
cp runs/detect/<候選>/weights/best.pt models/best.pt
ls -l models/best.pt
```

**同時記錄來源**（否則三個月後沒人知道生產模型是哪來的）：

```bash
cat > models/MODEL_SOURCE.md <<EOF
# 生產模型來源

- 來源批次：runs/detect/<候選>/weights/best.pt
- 晉升日期：$(date +%F)
- 訓練資料：data/yolo_zip/<zip 檔名>
- 關鍵參數：imgsz=<n>, epochs=<n>, degrees=<n>
- 相對前一版（<現行>）：mAP50 <改前> → <改後>；混淆改善/退化：<說明>
- 回放驗證：<n> 局，顆數命中 <n>/<n>，點數一致 <n>/<n>
EOF
```

---

## Step 5：打包

```bash
bash -n pack_prod.sh      # 先語法檢查
./pack_prod.sh
```

腳本會驗證 7 個必要檔案存在，複製後壓成 `sicbo_prod.zip`：

```
recognize_sicbo_stream.py · tcp_broadcaster.py · requirements.txt
models/best.pt · .plan/deployment_guide.md · start_recognize.bat · DroidSansFallback.ttf
```

**打包前確認：**
- [ ] `models/best.pt` 是剛晉升的那份（`ls -l` 看時間戳）
- [ ] `.plan/deployment_guide.md` 內容與當前程式碼一致（跑 `/doc-code-sync`）
- [ ] `sicbo_prod.zip` **不進版控**（隨時可重建）

---

## Step 6：交付與記錄

回報格式：

```
生產模型已晉升
- 來源：runs/detect/<候選>/weights/best.pt
- 指標：mAP50 <改前> → <改後>
- 混淆變化：<哪些點數的互混改善 / 惡化>
- 回放驗證：<n> 局，顆數 <n>/<n>，點數 <n>/<n>
- 打包：sicbo_prod.zip（<大小>）
- 待辦：運維需依 deployment_guide.md 更新部署並重啟服務
```

---

## 紀律

| ❌ | ✅ |
|---|---|
| 看 mAP 變高就晉升 | 看**混淆矩陣的逐類別變化**，任一點數退化就不晉升 |
| 直接改 systemd 指向 `runs/detect/train-N/` | 生產只認 `models/best.pt`；`runs/` 是開發產物 |
| 覆蓋舊的 `train-N` 目錄重訓 | 開新批次，保留舊的作為比較基準 |
| 晉升後不記錄來源 | 寫 `models/MODEL_SOURCE.md`，否則無法回溯 |
| 把 `models/best.pt` 或 `sicbo_prod.zip` 加進版控 | 見 `git-workflow.md` §3；`models/` 目前 untracked，要納管需先與使用者確認方式 |
| 晉升同時改推論參數 | **分開做**。兩者同時改就無法判斷是模型還是參數造成的差異 |

---

## 回退

新模型上線後發現問題：

```bash
cp runs/detect/<前一版>/weights/best.pt models/best.pt
./pack_prod.sh
```

**這就是為什麼 Step 4 要記錄來源、Step 2 要保留舊批次。** 沒有記錄就沒有回退路徑。
