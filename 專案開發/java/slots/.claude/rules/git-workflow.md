# Git 工作流與提交規範

---

## 1. 分支策略

- **`main`**：穩定分支
- **`developing`**：集成分支（開發主線）
- **測試分支**（`developing_test` / `developing-test`，若專案有）：**只收 merge、不回流**（見下方紅線）
- **功能分支**：`feature/Sxx-<描述>`，對應實作步驟編號（如 `feature/S12-scan-range-calc`）
- **修復分支**：`hotfix/<描述>`

**一步驟一分支。** 步驟的粒度就是 review 與回退的粒度。

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

---

## 2. Commit 訊息（Conventional Commits）

```
<type>(<scope>): <subject>

[body：改了什麼行為、涉及哪些不變量、驗收結果]
```

**scope 對映模組**（見 `architecture.md` §4）：`reel`（盤面與開獎）／ `payline`（連線與派彩）／ `jackpot`（彩池）／ `wallet`（錢包接縫）／ `record`（記錄）／ `reward`（獎勵事件）；前端用 `client`；建置與骨架類用 `build` / `arch`

> **前後端同一個需求就放同一個 commit / MR** —— 介面與消費端一起改、一起 review、一起回退。不要拆成兩個再靠人記得配對。

```
feat(payline): T-07 WILD 替代並取最高解讀

- 依據：spec.md §1.4 R-3、R-11｜AC-3.5, 3.6, 3.8
- 不變量：I1（後端權威）
- 企劃文件：無變更
- 測試：WildSubstitutionTest（逐條對拍）、PayoutRegressionTest 全綠
- 分層：判定引擎維持純計算，不依賴 Spring 與資料庫
```

**紅線：**
- commit 訊息**嚴禁**含 API Key、錢包憑證、資料庫密碼。
- 動到玩法規則 → **body 必須寫出 `spec.md` 的 R／E／AC 編號**（沒有編號的規則改動不得提交）。
- 改過 `plan/` 任何企劃文件 → **body 必須列出改了哪份、哪一條**（`rules/plan-authority.md` §2）。
- 涉及不變量的變更 → **body 必須列出涉及哪幾條 + 對應測試**。
- 動到派彩或權重 → **body 註明 `/payout-verify` 與（若涉權重）`/rtp-sim` 的結果**。

---

## 3. 提交前檢查

```bash
./mvnw test                                   # 含 *IT（Testcontainers）
./mvnw -q test -Dtest='*PayoutRegression*'    # §S3.3 實測案例必須吐出 60
./mvnw -q checkstyle:check spotbugs:check     # 依專案實際外掛調整
git diff --cached --name-only | grep -E "\.(env|key|pem)$" && echo "⚠️ 有憑證檔"
```

**checklist：**
- [ ] 提交前閘門全滿足（`testing.md` §5）
- [ ] `plan/` 無「⏳ 待決」OQ（否則 git hook 攔截）
- [ ] **實作步驟企劃書已回填**完成紀錄與進度總表
- [ ] 動到類別 / package / 相依 → `/arch-check` 通過
- [ ] 涉及契約 → `contract-reviewer` 已放行
- [ ] 無憑證、無 API Key 進版控

---

## 4. Merge Request

**標題**：對齊步驟，例：`S12: 掃描區間計算（掃至 head - N）`

**描述**：
1. **變更摘要**：一句話說明改動與影響的模組
2. **涉及不變量**：I2、I7…及其對應測試
3. **測試結果**：`./mvnw test` PASS 證據（含 `*IT`）
4. **契約影響**：無 / 有（需下游同步的具體說明）
5. **進度**：實作步驟企劃書已回填至 `n / 38`
6. **AIDD 指標**（見 §5）

---

## 5. AIDD 開發指標（觀察用，非合入條件）

> **填寫時機**：實質實作的 MR 建議填；純設定 / 文案 / docstring 可省略。累積 10~20 個才有統計意義。

```markdown
### AIDD 指標
- 步驟：Sxx
- 涉及不變量：[I2、I7]
- Plan OQ 數：[3（自答 2、User 決議 1）]
- Reviewer 輪次：[code-reviewer 1 + invariant-guard 1]
- 審查發現：[CRITICAL=0 HIGH=1 MEDIUM=3]
- 估算 vs 實際工時：[企劃書 1 天 / 實際 1.5 天]
- 預估 Token 成本：[~80k]
- Context 壓縮次數：[1]
```

**指標解讀（累積後）：**
- 「估算 vs 實際」持續超出 → 實作步驟企劃書的工時估算需回頭校正
- Reviewer 的 HIGH 平均 ≥ 3 → plan 的 §4 驗收計畫寫得不夠細
- Plan OQ「User 決議」偏多 → 前期決策未拍板完全，回頭檢視 §11 待確認事項

---

## 6. 不要做的事

| ❌ | 為什麼 |
|---|--------|
| 一個 commit 涵蓋多個步驟 | 步驟是驗收與回退的粒度 |
| 把 plan 的回填與程式碼分開 commit | DoD 第 7 條；分開就會忘 |
| `--no-verify` 繞過 hook | hook 擋的是未決 OQ，繞過等於跳過決策 |
| 在功能分支上順手改無關檔案 | 見 `coding-style.md` §8 範圍紀律 |
| 從測試分支 merge / cherry-pick 回開發分支 | 上線會夾帶未核准的待測程式碼（§1 單向流動紅線） |
