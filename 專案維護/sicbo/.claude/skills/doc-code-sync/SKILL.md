---
name: doc-code-sync
description: 稽核主程式、啟動腳本、deployment_guide.md、pack_prod.sh 四者的落差。改動介面/埠/串流源/打包清單後、提交前，或接手專案想知道文件哪裡不能信時使用。
---

# doc-code-sync — 文件↔程式碼落差稽核

**這是本專案最容易出事的地方。** 運維只讀 `.plan/deployment_guide.md`，文件寫的介面若不存在，他配置出來的服務**不會報錯，只會安靜地不工作**。

**用法：** `/doc-code-sync`（提交前必跑，若本次動到介面、埠、串流源、打包清單、字型或 device 選擇）

---

## 步驟

### 1. 建立現況事實（以程式碼為準，不看文件）

```bash
cd /path/to/detector/sicbo

echo "=== 主程式接受什麼參數 ==="
grep -n "argparse\|add_argument\|sys.argv" recognize_sicbo_stream.py

echo "=== 主程式的常數（埠 / 串流 / 門檻）==="
grep -nE "^[A-Z_]{3,} *[:=]|STREAM_URL|9003|9094" recognize_sicbo_stream.py

echo "=== 是否接了廣播 ==="
grep -n "TCPBroadcaster\|tcp_broadcaster\|send_dice_result" recognize_sicbo_stream.py || echo "  未接線"

echo "=== device 選擇 ==="
grep -n "cuda\|mps\|device" recognize_sicbo_stream.py

echo "=== 字型 ==="
grep -rn "font\|ttf\|ttc\|DroidSans" --include="*.py" .
```

### 2. 收集文件與腳本的宣稱

```bash
echo "=== 啟動腳本實際傳什麼 ==="
grep -n "recognize_sicbo_stream.py" start_recognize.bat start_recognize.sh

echo "=== 文件宣稱什麼 ==="
grep -n "recognize_sicbo_stream.py\|--stream-url\|--port\|--weights\|9003\|best.pt" .plan/deployment_guide.md

echo "=== 打包清單 ==="
grep -n "REQUIRED_FILES" -A 12 pack_prod.sh
```

### 3. 產出四者對照表

| 項目 | 主程式實況 | `start_recognize.bat` | `start_recognize.sh` | `deployment_guide.md` | 一致？ |
|------|-----------|----------------------|---------------------|----------------------|--------|
| CLI 參數 | | | | | |
| 監聽埠 | | | | | |
| 串流來源 | | | | | |
| 模型路徑 | | | | | |
| TCP 廣播 | | | | | |
| device / GPU | | | | | |
| 中文字型 | | | | | |

### 4. 交叉檢查

- **打包了卻沒被使用的檔案**：`pack_prod.sh` 的 `REQUIRED_FILES` 逐個 grep 是否真的被 import / 讀取。
- **使用了卻沒被打包的檔案**：主程式讀取的任何路徑（模型、字型、設定）是否都在打包清單內。
- **文件描述但程式沒有的行為**：逐條標記為「文件超前」。
- **程式有但文件沒寫的行為**：標記為「文件落後」（運維不知道有這個能力，或不知道某個預設值）。

### 5. 輸出報告

```markdown
## doc-code-sync 稽核結果（<日期>）

### 四者對照
<上表>

### 落差清單
| # | 落差 | 運維會踩到什麼 | 建議對齊方向 |
|---|------|--------------|-------------|
| 1 | 文件寫 `--port 9003`，主程式無 argparse | 改埠改不動，以為改了其實沒改 | 補程式碼支援（運維已照文件配置）／或改文件降級 |

### 打包清單交叉檢查
- 打包但未使用：<清單>
- 使用但未打包：<清單>

### 結論
- 本次變更引入的新落差：<n> 項  ← **必須修掉才能提交**
- 既有落差：<n> 項              ← 記錄即可，另開 TASK
```

---

## 判定紀律

| ❌ | ✅ |
|---|---|
| 以文件為準判斷程式該長怎樣 | **以程式碼為準**，文件是被稽核對象 |
| 看到落差就自己決定改哪邊 | **文件超前 vs 程式落後的對齊方向是產品決策**，列給使用者裁決 |
| 把既有落差算成本次的錯 | 區分「本次引入」與「既有」；只有前者擋提交 |
| 順手把所有落差一次修完 | 一次修一項（`coding-style.md` §7） |

---

## 已知落差基準（2026-08 盤點）

跑完稽核後與這份基準比對，**新增的才是本次引入的**：

1. 主程式無 argparse，`sys.argv[1]` 當模型版本名；`--stream-url` / `--port` / `--weights` 全部靜默忽略
2. 主程式未 import `TCPBroadcaster`，開盅時不廣播
3. `STREAM_URL` 硬編碼於主程式常數區
4. `device` 只判斷 `mps`，無 cuda 分支
5. `DroidSansFallback.ttf` 被打包但無任何 `.py` 引用；字型路徑硬編碼 macOS
6. `config/dataset.yaml` 的 `path:` 仍指向舊位置 `python/machineLearning/sicbo`
7. `.plan/architecture.md` 的 `file://` 連結指向舊位置
8. `.plan/architecture.md` 宣稱的 `src/` `tests/` `notebooks/` `outputs/` 不存在
9. `tcp_broadcaster.py`、`pack_prod.sh`、`models/`、`start_recognize.bat`、`deployment_guide.md`、`DroidSansFallback.ttf` 未進版控

> 修掉其中任一項後，**回來更新這份基準**，否則下次稽核會把已修的當成還沒修。
