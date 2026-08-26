---
name: step-run
description: 執行實作步驟企劃書的某一個 Sxx——讀步驟、拆計畫、實作、驗收、回填進度。要開始做某個步驟時使用。
---

# step-run — 執行一個實作步驟

**用法：** `/step-run S12`（A 軌 · 服務端）｜ `/step-run T7`（B 軌 · 維運後台）

本 repo 雙軌推進，兩軌共用同一套流程，差別只在 **Step 1 讀什麼工單**與 **Step 5 驗收依據**。

| 軌 | 編號 | 工單來源 |
|---|------|---------|
| **A · 服務端** | S01 ~ S38 | `plan/2026-08-17-crypto-node-implementation-steps.md` |
| **B · 維運後台** | T1a ~ T13c-ii | `plan/crypto-node-web/backlog.md` |

---

## Step 0 · Preflight

```bash
java -version 2>&1 | grep -E '"21' || echo "[preflight] JDK 未對齊 21 — 必修不動工"
./mvnw -q -DskipTests compile || echo "[preflight] HEAD 編譯失敗 — 必修"
grep -n "spring-boot" pom.xml | head -3   # 應為 3.5.x（本範本覆蓋 plan D18）
```

---

## Step 1 · 讀工單（禁 full read）

### A 軌（S 步驟）

```bash
grep -nE "^### S" plan/2026-08-17-crypto-node-implementation-steps.md | head -45
grep -n "^### S12" -A 45 plan/2026-08-17-crypto-node-implementation-steps.md
grep -n "^## 二、進度總表" -A 20 plan/2026-08-17-crypto-node-implementation-steps.md
```

確認：**前置已完成**（否則 `Blocked By: Sxx`）／**涉及哪些不變量**（§1.4 對照表）／**驗收測試有哪些**。

### B 軌（T 任務）

```bash
# 取該顆任務列（含 Required Spec Sections / Depends On / 對應 AC）
grep -n "^| \*\*T7\*\*" plan/crypto-node-web/backlog.md
# 全局約束（所有 TASK 一律適用，不重複寫在每顆）
grep -n "^## 全局約束" -A 12 plan/crypto-node-web/backlog.md
# 依 Required Spec Sections 分節讀 spec —— 只讀那幾節
grep -nE "^#{3,4} " plan/crypto-node-web/spec.md      # 先建索引
```

確認：**前置 TASK 已完成**（否則 `Blocked By: Txx`）／**Required Spec Sections 是哪幾節**／**對應 AC 編號**／**是否有 `⏳ 等外部`**。

> ⚠ **`spec.md` 有 480 行、60KB，禁止 full read。**
> **`Required Spec Sections` 就是上下文預算** —— 企劃已經切好，照著讀就不會爆。發現自己在通讀整份 spec，就是沒照做。

---

## Step 1.5 · B 軌專屬：補技術設計（How）

**T 任務是企劃層產出，只有業務語言。** 動工前 planner 必須先補：

- 這顆落在**前端**、**後台後端**、還是兩者都有？
- 需要呼叫哪些 **crypto-node Admin API**？該 API 是否已存在（不存在 → 那是服務端變更，見 `web-integration.md` §4）
- 授權判定寫在哪（**必須在後端**，`web-integration.md` §3）
- 對映的 **AC 編號**要怎麼驗

**OQ-9 六項已決五項半**（2026-08-26）；**僅剩第 6 項的定址手段待確認**（`web-integration.md` §5、§6）。碰到其餘任何一項 → 決議已在 `locked-decisions.md`，**照決議做，不要重新選**。

---

## Step 2 · 檢查是否踩到已鎖定決策

對照 `rules/locked-decisions.md`。特別注意這個步驟會不會誘使你實作：

- WebSocket（D2 已排除）
- Webhook 推送 / Dispatcher / HMAC / 重試（D16 已改 Pull-only）
- Reorg 回溯 / `payment.reorged` / `pending` 狀態（D17 已取消）
- `confirmations` 欄位（D4 改為讀取時計算）
- web3j / MQ / Quartz（D10 禁止）

同時查 `rules/architecture.md`：本步驟的產出落在**哪個模組、哪一層**？需要新增 Port 嗎？

**B 軌另外查** `rules/web-frontend.md` 與 `rules/web-integration.md`：
- 這顆是否涉及**危險操作**（七項清單）→ 二次確認 + ≥10 字理由 + 白話後果文案（**文案須人審**）
- 是否涉及**憑證明文**（R9）→ 不得落地、不得入網址／log／狀態管理
- 是否涉及**清單／下拉／查詢**→ 租戶範圍過濾必須在查詢層
- 是否會產生**半成品狀態**（R1a）→ 必須在畫面明示

> 企劃書某些步驟的文字可能殘留 D17 之前的語彙。**撞到就列 OQ，不要照著實作。**

---

## Step 3 · 規劃

調用 `planner`，產出 `plan/task-Sxx-plan.md`。

**閘門：** plan §4 必須寫出**具體的測試類別與方法名**，不是「補測試」。涉及查詢或事件的步驟，必須指明使用**兩租戶 fixture**。

**OQ 未決不得開始寫業務代碼。** 本專案典型必問見 `agents/planner.md`。

---

## Step 4 · 實作

**Golden Rule：依計畫實作。** 範圍上限是 plan §2 的檔案清單。

實作時每一步問自己：

| 情境 | 必問 |
|------|------|
| 新增寫入路徑 | 「這條路徑被執行兩次會怎樣？」（I6 冪等） |
| 新增查詢 | 「它有沒有依訂閱者的租戶範圍過濾？」（I8） |
| 動到區塊處理 | 「這四項寫入還在同一個事務裡嗎？」（I1） |
| 動到高度推進 | 「有沒有任何路徑會讓它後退？」（I2） |
| 寫 Spring 相關程式碼 | 「這個 API 在 Boot 3.5 存在嗎？」（不是 Boot 4） |
| **（B 軌）寫任何清單／查詢** | 「租戶範圍過濾在查詢條件裡嗎？範圍外的會不會出現？」（R2） |
| **（B 軌）處理 API 失敗** | 「失敗會不會被渲染成空清單？」（E1 —— 本專案最容易犯的錯） |
| **（B 軌）碰到憑證明文** | 「它會不會落到 storage／網址／log／狀態管理？」（R9、R10） |
| 新增任何類別 | 「它屬於哪一層？依賴方向對嗎？」（`architecture.md` §1） |
| 想用 `@ApplicationModuleListener` | 「這件事落在 I1 的四項寫入範圍內嗎？」是 → **不能用**（`architecture.md` §4） |

**Stop Rule：** 文件互相矛盾（bigpicture vs 開發企劃書、I7 vs D17）→ **立即停止並回報**，不要挑一個猜。

---

## Step 5 · 驗收

```bash
./mvnw test                                  # 含 *IT + ArchitectureTests
./mvnw -q checkstyle:check spotbugs:check    # 依專案實際外掛調整
```

**DoD 七條全滿足：**
1. 該步驟驗收測試全過
2. 既有測試無變紅
3. 靜態檢查過
4. 涉及不變量的測試也過
5. **`ArchitectureTests` 通過**（`modules.verify()` + Domain 純度 + 依賴方向）
6. 涉及 migration：**版本號驗證器通過**
7. 企劃書已回填

動到類別 / package / 相依 → 跑 `/arch-check`；涉及不變量 → 跑 `/invariant-check`（兩者都確認測試**確實存在且通過**）。

---

## Step 6 · 審查

| 情境 | reviewer |
|------|---------|
| 一律 | `code-reviewer` |
| **（B 軌）後台前端 / 後台後端 / Admin API 呼叫** | + `web-reviewer` |
| package 結構 / 新增類別 / 跨模組呼叫 / 引入相依 | + `arch-guard` |
| 掃描迴圈 / 事務 / 冪等 / 高度推進 | + `invariant-guard` |
| 查詢 / 認證 / 歸屬解析 / 拉取 API | + `tenant-isolation-reviewer` |
| `/v1/events` 或事件欄位 | + `contract-reviewer` |

領域 reviewer **平行啟動**（同一則訊息）。

---

## Step 7 · 回填（DoD 第 7 條，不可略）

在實作步驟企劃書中：

**A 軌**：
1. 該步驟標記完成，依實作步驟企劃書 §0.2 的完成紀錄範本填寫。
2. **更新 §2 進度總表**的完成數（`n / 38`）。

**B 軌**：
1. 在 `plan/crypto-node-web/backlog.md` 標記該 T 任務完成。
2. 記錄**實際的 AI 產出與人介入**（供 `task-planning.md` §3.5.6 校正估算）。
3. 若對映的 AC 有未涵蓋者，明確標出。
3. 與程式碼**同一個 commit** 提交——分開就會忘。

---

## Step 8 · 回報

```
工單：Sxx / Txx <名稱>（A 軌階段 Pn ／ B 軌波次）
狀態：完成 / 受阻
涉及不變量：I2、I7 → 測試 <類別#方法> PASS
模組 / 分層：<模組名> · domain+application ｜ ArchitectureTests PASS
驗收測試：<n>/<n> 通過
迴歸：./mvnw test 全綠
契約影響：無 / 有（<需下游同步的說明>）
進度：A 軌 <n> / 38 ｜ B 軌 <n> / 19
（B 軌）對映 AC：<編號> 已驗 / 未驗
Remaining Work：<或 Blocked By: Sxx>
```

---

## 常見誤區

| ❌ | ✅ |
|---|---|
| 一次做好幾個步驟 | 步驟的粒度就是驗收與回退的粒度 |
| 照 bigpicture 實作 | 先讀它的「取代對照表」——多處已被 D2/D16/D17/D4 取代 |
| 抄 plan D18 或網路上的 Boot 4 寫法 | 本專案鎖 Boot 3.5，API 不同 |
| 單租戶 fixture | 隔離 bug 在單租戶下 100% 測不出來 |
| （B 軌）通讀整份 spec.md | 480 行 / 60KB。照 `Required Spec Sections` 分節讀 |
| （B 軌）前端隱藏按鈕就當授權做完了 | 那是 UX 不是安全邊界，後端必須重新判定 |
| （B 軌）自己猜「全叢集是否切完」 | 服務端尚未提供逐台能力，猜就是編造 |
| 為未來的 WebSocket / Webhook 留接縫 | 留了就會有人來填。已被移除的範圍不鋪路 |
| 測試過了就結束 | DoD 有七條，第 7 條是回填企劃書 |
| 讓 Domain import 一下 Spring「這次特殊」 | 例外一開就回不去，後續程式碼會照抄 |
| 模組間直接注入對方 Service | 走事件；需同步回傳值代表模組切分要重看，列 OQ |
| 驗收標準過不了就放寬標準 | 驗收標準是規格。列 OQ 讓使用者裁決 |
