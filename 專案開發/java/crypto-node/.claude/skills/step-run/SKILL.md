---
name: step-run
description: 執行實作步驟企劃書的某一個 Sxx——讀步驟、拆計畫、實作、驗收、回填進度。要開始做某個步驟時使用。
---

# step-run — 執行一個實作步驟

**用法：** `/step-run S12`

本專案由 **S01 ~ S38** 推進。這個 skill 是完整的單步驟流程。

---

## Step 0 · Preflight

```bash
java -version 2>&1 | grep -E '"21' || echo "[preflight] JDK 未對齊 21 — 必修不動工"
./mvnw -q -DskipTests compile || echo "[preflight] HEAD 編譯失敗 — 必修"
grep -n "spring-boot" pom.xml | head -3   # 應為 3.5.x（本範本覆蓋 plan D18）
```

---

## Step 1 · 讀步驟（禁 full read）

```bash
# 標題索引
grep -nE "^### S" plan/2026-08-17-crypto-node-implementation-steps.md | head -45
# 只讀目標步驟
grep -n "^### S12" -A 45 plan/2026-08-17-crypto-node-implementation-steps.md
# 進度總表：確認前置已完成
grep -n "^## 二、進度總表" -A 20 plan/2026-08-17-crypto-node-implementation-steps.md
```

確認三件事：
1. **前置步驟已完成** —— 未完成則停手，回報 `Blocked By: Sxx`
2. **涉及哪些不變量**（§1.4 對照表）
3. **驗收測試有哪些**

---

## Step 2 · 檢查是否踩到已鎖定決策

對照 `rules/locked-decisions.md`。特別注意這個步驟會不會誘使你實作：

- WebSocket（D2 已排除）
- Webhook 推送 / Dispatcher / HMAC / 重試（D16 已改 Pull-only）
- Reorg 回溯 / `payment.reorged` / `pending` 狀態（D17 已取消）
- `confirmations` 欄位（D4 改為讀取時計算）
- web3j / MQ / Quartz（D10 禁止）

同時查 `rules/architecture.md`：本步驟的產出落在**哪個模組、哪一層**？需要新增 Port 嗎？

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
| package 結構 / 新增類別 / 跨模組呼叫 / 引入相依 | + `arch-guard` |
| 掃描迴圈 / 事務 / 冪等 / 高度推進 | + `invariant-guard` |
| 查詢 / 認證 / 歸屬解析 / 拉取 API | + `tenant-isolation-reviewer` |
| `/v1/events` 或事件欄位 | + `contract-reviewer` |

領域 reviewer **平行啟動**（同一則訊息）。

---

## Step 7 · 回填（DoD 第 7 條，不可略）

在實作步驟企劃書中：

1. 該步驟標記完成，依 §0.2 的完成紀錄範本填寫。
2. **更新 §2 進度總表**的完成數（`n / 38`）。
3. 與程式碼**同一個 commit** 提交——分開就會忘。

---

## Step 8 · 回報

```
步驟：Sxx <名稱>（階段 Pn）
狀態：完成 / 受阻
涉及不變量：I2、I7 → 測試 <類別#方法> PASS
模組 / 分層：<模組名> · domain+application ｜ ArchitectureTests PASS
驗收測試：<n>/<n> 通過
迴歸：./mvnw test 全綠
契約影響：無 / 有（<需下游同步的說明>）
進度：<n> / 38
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
| 為未來的 WebSocket / Webhook 留接縫 | 留了就會有人來填。已被移除的範圍不鋪路 |
| 測試過了就結束 | DoD 有七條，第 7 條是回填企劃書 |
| 讓 Domain import 一下 Spring「這次特殊」 | 例外一開就回不去，後續程式碼會照抄 |
| 模組間直接注入對方 Service | 走事件；需同步回傳值代表模組切分要重看，列 OQ |
| 驗收標準過不了就放寬標準 | 驗收標準是規格。列 OQ 讓使用者裁決 |
