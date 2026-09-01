# Git 工作流與大檔紀律（sicbo）

> **重要前提：** git repo 根在 **`detector/`**，不是 `sicbo/`。同 repo 還有 `baccarat_3type`、`xocdia`、`ai_magic`。
> 所有 git 指令都在 `detector/` 執行，路徑要帶 `sicbo/` 前綴。

---

## 1. 分支

| 分支 | 用途 |
|------|------|
| `dev` | 目前的主要工作分支（`git log` 顯示各子專案的變更都直接落在此） |
| `feature/sicbo-<描述>` | 較大的變更建議切分支，避免與其他子專案的提交交錯 |

**紀律：**
- 提交前先 `git pull`，因為**其他子專案（baccarat / xocdia）可能同時在動**。
- **只 commit `sicbo/` 底下的變更**。`git add -A` 在這個 repo 很危險——會把別人正在改的 baccarat 檔案一起帶走。用明確路徑：
  ```bash
  git add sicbo/recognize_sicbo_stream.py sicbo/.plan/deployment_guide.md
  ```
- 提交前務必 `git status sicbo` 確認範圍。

<!-- shared:test-branch-one-way -->
### 測試分支單向流動（紅線）

**程式碼只能從開發分支流向測試分支，永遠不能回流。**

| 方向 | 允許？ |
|------|--------|
| 開發分支 / 功能分支 → 測試分支 | ✅ 正常流程 |
| 測試分支 → 開發分支 / 功能分支 | ❌ 一律禁止 |

**測試分支** ＝ 名稱為 `developing_test`、`developing-test`（或其他 `*_test` / `*-test` 變體）的分支。無法判斷某分支是不是測試分支時**問使用者**，不要自行認定。

**禁止的具體動作**（在開發分支、或從開發分支切出的功能分支上）：

| ❌ 動作 | 說明 |
|---|---|
| `git merge developing_test` | 含在開發分支上 `git pull` 誤拉測試分支來源 |
| `git cherry-pick <測試分支的 commit>` | 「只挑一個 commit」一樣是污染 |
| `git rebase` / `git reset --hard` 到測試分支 | 同上，且會改寫開發分支歷史 |
| `git checkout developing_test -- <path>`、手工複製測試分支的檔案內容 | 繞過 git 一樣算回流 |
| 從測試分支切出新的功能分支 | 新分支一開始就帶著整包待測程式碼 |

**為什麼是紅線：** 測試分支匯集的是**所有待測功能**，其中包含這次不打算上線的東西。一旦回流，這些未核准的變更就混進開發分支，上線時**夾帶沒有要上線的代碼**；而且混入之後已無法從 diff 分辨哪些屬於本次上線範圍，只能靠人記憶，必然出錯。

**遇到「我要的修改只存在於測試分支」時：**

1. 停手，先告知使用者「這個修改只在測試分支上」。
2. 正解是**從開發分支切出功能分支重新實作**（可以讀測試分支的 diff 當參考，但不 merge、不 cherry-pick），再照正常流程合併回測試分支。
3. 只有使用者明確授權才例外——那是使用者的決策，agent **不得自行判斷「這次應該沒關係」**。
<!-- /shared -->

> 本 repo 目前只有 `dev` 一條主線，沒有獨立測試分支；日後若新增，上述紅線一體適用。

---

## 2. Commit 訊息

沿用 repo 既有慣例（見 `git log`）：**子專案前綴 + 動作描述**。

```
sicbo: <一句話說明改了什麼行為>

[可選 body：為什麼改、影響哪一段管線、驗證結果]
```

repo 內既有範例：
- `baccarat_3type: remove P2 (yolov8s-p2p3p4) experiment — no accuracy gain, ~2x slower`
- `baccarat_3type: add local_train_1280_corner_p2.py`

**寫法要求：**
- 說明**改了什麼行為**，不是「改了哪個檔」（檔名 diff 已經看得到）。
- 涉及參數調整 → **在 body 寫改前 / 改後的值與驗證結果**：
  ```
  sicbo: raise stable threshold 1.5s -> 2.0s to cut mid-shake false opens

  回放 data/verified_rounds_sicbo/origin/ 共 24 局：
  誤開盅 3 -> 0，漏開盅 0 -> 0。
  同步更新 .plan/deployment_guide.md §8 Q6。
  ```
- 涉及輸出契約 → **必須在 body 註明是否需要 Go 端同步**。
- **禁止**在 commit 訊息出現串流帳密、伺服器 IP、內部網域憑證。

---

## 3. 大型檔案紀律（本專案的現實問題）

### 現況（已經發生，不要惡化）

| 已進版控 | 大小 | 評語 |
|---------|-----:|------|
| `sicbo/data/yolo_zip/project-9-*.zip` | **39 MB** | 訓練資料集，不該進版控 |
| `sicbo/yolov8n.pt` | 6.4 MB | 官方預訓練權重，可隨時下載 |
| `sicbo/runs/detect/train*/weights/*.pt` | 6.1 MB × 4 | 訓練產物 |
| `sicbo/runs/detect/train*/*.jpg` `.png` | 36 檔 ~25 MB | 訓練批次圖與評估圖 |

### 硬規則

1. **不得再新增**任何 `*.pt`、`*.zip`、訓練批次圖、資料集進版控。
2. `.gitignore` 目前已排除 `sicbo/data/dice_dataset`、`sicbo/data/raw`、`sicbo/data/verified_rounds_sicbo`、`sicbo/ml_backend`、`sicbo/.idea`——**新增輸出目錄時要同步補 `.gitignore`**。
3. **既有的大檔不要順手清理**。移除已追蹤的大檔會改寫大量歷史或產生巨大 diff，屬於獨立決策，**必須先問使用者**（`coding-style.md` 最小可行實作、「不主動刪既有 dead code」同理）。
4. `sicbo_prod.zip`（7 MB，打包產物）**永遠不進版控**——它由 `pack_prod.sh` 隨時可重建。

---

## 4. ⚠️ 未進版控的關鍵檔案（先確認再動）

以下檔案**目前是 untracked**，只存在於這台機器上：

```
sicbo/tcp_broadcaster.py          ← 輸出契約的實作本體
sicbo/pack_prod.sh                ← 生產打包腳本
sicbo/models/                     ← 生產模型 best.pt
sicbo/start_recognize.bat         ← Windows 生產啟動腳本
sicbo/.plan/deployment_guide.md   ← 運維聖經
sicbo/DroidSansFallback.ttf       ← 跨平台字型（3.5 MB）
```

**這代表整條生產部署路徑都沒有備份。** 動到它們之前：

1. **先確認使用者是否打算納入版控**——這是決策不是技術問題（`DroidSansFallback.ttf` 3.5 MB 是否值得進版控、`models/best.pt` 是否該用其他方式管理）。
2. **不要在它們身上做大改而不提醒**。改壞了沒有版本可回。
3. 若要納入版控，建議分兩批：**程式碼與文件**（`tcp_broadcaster.py`、`pack_prod.sh`、`start_recognize.bat`、`deployment_guide.md`）先進；**二進位**（`models/`、`.ttf`）另行決定。

---

## 5. 提交前檢查清單

```bash
cd /path/to/detector

# 1. 範圍：只有 sicbo 底下的預期檔案
git status sicbo

# 2. 沒有意外的大檔
git diff --cached --stat | tail -5
git diff --cached --name-only | grep -E "\.(pt|zip|jpg|png)$" && echo "⚠️ 有二進位檔要進版控，確認是否正確"

# 3. 語法
python -m py_compile sicbo/*.py
bash -n sicbo/*.sh

# 4. 文件同步（改過介面才需要）
#    → 跑 /doc-code-sync
```

**紅線：** 若本次改動了 CLI 介面、埠、串流來源、打包清單或輸出契約，**`.plan/deployment_guide.md` 必須在同一個 commit 內同步**。運維只讀那份文件；文件與程式碼分兩次提交，中間那段時間就是事故窗口。
