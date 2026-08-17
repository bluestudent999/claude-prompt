# 程式碼風格與 Token 紀律（Python）

> 本文規範 sicbo 的 Python 風格、命名、註解語言、例外處理、大檔讀取，以及最小可行實作。
> **對齊既有寫法優先**：這是維護專案，一致性比「更好的寫法」重要。

---

## 1. 格式與工具

- **Python 3.12+**；縮排 4 空白。
- 專案**未配置** ruff / black / mypy —— **不要為了跑 lint 而擅自引入工具鏈與設定檔**（那是獨立 TASK，需先確認）。
- 品質靠 `python -m py_compile` + `code-reviewer` 把關。
- **型別註解**：既有程式碼已普遍使用（`-> Optional[Path]`、`Dict[str, Any]`、`List[int]`）。新增或修改的函式**必須**跟上，不要退化成無註解。

---

## 2. 命名（沿用既有慣例）

- 函式 / 變數：`snake_case`（`find_latest_train_model`、`stable_since`、`real_dice_count`）
- 類別：`PascalCase`（`TCPBroadcaster`）
- 模組級常數：`UPPER_SNAKE_CASE` 且**帶型別註解**，沿用既有寫法：
  ```python
  AI_CONF_THRESHOLD: float = 0.40
  MATCH_DIST_THRESHOLD: float = 60.0
  FRAME_QUEUE_SIZE: int = 2
  ```
- 路徑常數統一以 `BASE_DIR = Path(__file__).parent.resolve()` 為基準，**用 `pathlib` 不用字串拼接**。

---

## 3. 註解與訊息語言

- **docstring 與行內註解：繁體中文**（技術術語保留英文：YOLO、IoU、TCP、FPS、bounding box）。
  - 既有 docstring 採 Google style（`Args:` / `Returns:`），沿用。
- **輸出訊息（`print`）**：沿用既有前綴慣例，**不要自創新格式**：

  | 前綴 | 用途 |
  |------|------|
  | `[INFO]` | 正常狀態轉換（模型載入、串流連線、偵測到骰子、開盅確認、存檔） |
  | `[WARN]` | 可自我修復或降級（讀取失敗重連、找不到指定模型改用 fallback、低信心度） |
  | `[ERROR]` | 阻斷性錯誤（串流開不了、串流中斷） |
  | `[TCP]` | `tcp_broadcaster.py` 專用 |

- 訊息內容中文英文皆有（既有即如此），**不強制統一**——但同一個檔案內保持一致。

---

## 4. 例外與失敗處理

- **失敗不靜默**：串流中斷、模型載不到、廣播送出失敗，都必須有 `print` 留痕。既有程式碼已這樣做，**不要在重構時把它們吞掉**。
- **禁止**裸 `except:` 或 `except Exception: pass`。既有程式碼捕捉的是具體型別（`OSError`、`queue.Empty`、`IOError`、`ValueError`），沿用這個精度。
- **fallback 必須說出口**：找不到指定模型時 fallback 到 `yolov8n.pt` 是既有行為，但它會讓辨識完全失準——這種降級**必須**印 `[WARNING]`（既有已有，不要拿掉）。

---

## 5. 執行緒與資源

- 串流讀取在 daemon thread、TCP accept 迴圈在 daemon thread —— 沿用。
- **共享狀態必須加鎖**：`TCPBroadcaster._clients` 已用 `self._lock` 保護，新增共享結構時比照辦理。
- **每一條退出路徑都要釋放資源**：`cap.release()`、`cv2.destroyAllWindows()`、`broadcaster.stop()`。新增 early return 或例外分支時，確認資源仍會被釋放。

---

## 6. 大檔案讀取策略（Token 硬規則）

| 檔案 | 行數 | 可否 full read |
|------|-----:|---------------|
| `recognize_sicbo_stream.py` | 584 | ❌ |
| `local_train.py` | 441 | ❌ |
| `yolo_ml_backend.py` | 226 | ✅ |
| `tcp_broadcaster.py` | 127 | ✅ |
| `pack_prod.sh` / `setup_env.sh` / `start_*` | < 80 | ✅ |
| `config/dataset.yaml`、`requirements.txt` | 小 | ✅ |

**> 300 行的流程：** 先建行號索引再分段讀。

```bash
grep -nE "^def |^class |^[A-Z_]{3,} *[:=]|^# ─" recognize_sicbo_stream.py   # 函式與常數索引
grep -n "<你要找的行為關鍵字>" recognize_sicbo_stream.py                      # 定位到具體行
```

再 `Read(offset=<行號-5>, limit=<需要的範圍>)`。**第一次讀完把行號索引留在對話**，後續直接用。

> **禁止**把整幀影像、完整 YOLO 輸出、大量 log 貼進對話。需要保留就寫檔，對話只留路徑與結論。

---

## 7. 最小可行實作（反過度設計）

> 前面幾節管「**怎麼寫**」，這節管「**寫多少**」。`code-reviewer` 的「過度工程」檢查項就是在驗這條。
> **對這個專案特別重要**：它是 4 個腳本撐起來的服務，不是框架。任何額外的抽象層都會讓下一個接手的人多讀 200 行才看懂骰子怎麼被數出來的。

**原則：能解決問題的最少程式碼，不做任何投機性設計。**

- **不做 spec / plan 沒要求的功能**。plan §2 的檔案清單就是範圍上限。
- **只用一次的程式碼不要抽象**。介面、策略模式、抽象基類等到**第二個實作出現**時再抽。
  - **反例（本專案特別容易犯）**：為了接一個 TCP 輸出，先造一套 `OutputSink` 抽象 + 註冊機制 + 設定驅動的 factory。目前只有一個消費端（Go），直接呼叫 `TCPBroadcaster` 即可。
  - **另一個反例**：為了改一個門檻值，先造一套 config 載入器 + schema 驗證 + 環境覆寫。目前常數就寫在模組頂端且**有型別註解**，那已經夠好了。
- **不做沒人要求的「彈性」與「可設定化」**。要把常數搬進設定檔前先問：現在有人要在不改 code 的情況下切換它嗎？
- **不為不可能發生的情境寫防禦**。但**可預期**的失敗（串流斷、模型缺、Go 端斷線、點數超範圍）仍要處理——見 §4，兩者不衝突。
- **不預先為 baccarat / xocdia 抽共用**。它們是**不同專案、不同模型、不同契約**，硬抽共用層只會讓三邊互相綁死。要參考就複製一份改，這是刻意的。

**寫完自問兩題（過不了就重寫）：**

1. 「這 200 行能不能是 50 行？」——能 → 重寫。
2. 「資深工程師會不會說這寫得太複雜？」——會 → 簡化。

> **與「已知落差」的關係：** `CLAUDE.md` §7 列了 9 項落差，很容易一時興起全部重寫成一個乾淨架構。**不要。** 一次修一項、各自走完流程、各自驗證、各自 commit——這樣壞了才知道是哪一項壞的。
