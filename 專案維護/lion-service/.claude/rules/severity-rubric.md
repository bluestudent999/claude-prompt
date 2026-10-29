# Severity Rubric — 全專案統一分級標準

> **適用**：所有 reviewer（code / java / business / security / database）與 `.claude/checks/*.md`。
> **目的**：讓 `CRITICAL` 永遠等於「必須擋合入」。分級標準分歧會讓主 agent 無法判斷哪個 finding 該先修，`CRITICAL` 一旦通膨就失去訊號價值。
> **搭配**：`agents.md` §Harness Output Contract（Status / Counts 判定）、`reviewer-checklists.md`（各 reviewer 檢查項）。

---

## 1. 五級定義

### 🔴 CRITICAL — 擋合入（block）

**必須同時滿足三條：**

1. **直接後果**：(a) 資安漏洞（認證 / 授權 / 注入）**或** (b) 金額算錯 / 資料毀損 **或** (c) 服務不可用
2. **已驗證的事故模式**：此類問題在本專案或同類系統確實出過事，非理論推測
3. **能指出定位**：reviewer 能指出 `file:line` 與失效機制（**不要求提供完整修法**）

**本專案典型範例：**

- 金額用 `double` 運算，或 `BigDecimal` 除法未指定 `RoundingMode` / 用了 `HALF_UP` 讓公司側吃虧
- 餘額異動無分散式鎖且無 DB 行鎖 → 併發超扣
- 訂單 / 派彩無 `orderNo` 唯一鍵去重 → 重複派彩
- `SqlUtil` / 字串拼接 SQL 直接帶入使用者輸入 → SQL 注入（lion 沒有 MyBatis）
- **跨 platformId 讀寫**（即使唯讀）：platformId 取自請求 SO / header 當授權依據、單筆查詢不帶 platformId（`rules/platform-isolation.md`）
- **filter 以副檔名 / 子字串放行**、檢查失敗未 `return`（已發生過實際入侵，`rules/security.md` §filter 防線）
- 賠率 / 限額 / 封盤判定取自請求端資料（`rules/security.md` §彩票）
- 明文密碼 / 完整 token / 銀行卡號進 log
- `@Transactional` 同類自呼叫 → 事務靜默失效，金額異動與流水不同步
- 狀態機允許非法轉換（例：已派彩 → 重新派彩）

**反例（不該標 CRITICAL）：**

- ❌ 一般第三方 HTTP 呼叫沒設 timeout → **HIGH**
- ❌ 沒有監控埋點 → **MEDIUM**
- ❌ 命名不符 VO / SO / BO 慣例 → **MEDIUM**
- ❌ 「未來可能有非交易 caller，建議加 `@Transactional`」→ **LOW**（防禦性建議，見 §5）

### 🟠 HIGH — 要求修改（warning）

**滿足任一：**

1. Runtime 風險明確，但有上游保護不會即刻爆炸
2. 規模壓力下會出事，當前流量暫時撐得住
3. 違反業務規範但無金額 / 資安後果

**典型範例**：外部呼叫缺 timeout、silent failure（空 catch / 吞例外後回預設值）、迴圈內查 DB、分片表 WHERE 缺分片鍵、非金額路徑缺冪等、新增 enum 值漏補下游 switch。

### 🟡 MEDIUM — 累積觸發要求修改

**滿足任一**：可維護性顯著下降、中期累積風險、規範違反但無 runtime 後果。

**典型範例**：命名不符 §patterns.md 資料物件慣例、方法過長（> 80 行）、結構重複、log 等級誤用（`warn` 應為 `error`）、magic number 未抽常數。

### 🟢 LOW — 可放行併附註

風格 / 一致性建議、微優化、對未來重構有提示價值但當前不修無妨。

**典型範例**：未使用的 import、inline FQCN（既有 code）、巢狀三元運算、防禦性 future-proofing 建議。

### ⚪ NIT — 不進統計

純風格偏好、作者自決。**不計入 `Counts`**。

---

## 2. Confidence 上限（依證據強度）

reviewer 對每條 finding 標 `confidence`（0-100）。以下情境**強制上限**：

| 判斷依據 | 上限 | 理由 |
|---|---|---|
| 單檔可見證據（grep + Read 直接看到） | 無上限 | 結構性證據充分 |
| 需跨檔 / 設定 / yml 才能確認 | **≤ 70** | 設定可能在別處覆寫 |
| 需 git diff / PR 內容才能確認 | **≤ 75** | 容易把 refactor 誤判為新增問題 |
| 需業務語意 / 對照 spec 判斷 | **≤ 80** | 語意推測有歧義 |
| 死碼 / 無 caller 判定 | **≤ 80** | Spring DI、反射、`@SingleWalletType` 自動註冊、商戶設定路由（新舊版並存）掃不到 |
| 索引 / 效能建議 | **≤ 60** | 需 DBA 用實際資料量驗證 |
| 「這個 pattern 在不在」的提示性檢查 | **≤ 65** | 用於提示而非斷言 |

**多條件取最低**：同時命中多個上限（例：需 diff + 需業務語意）→ 取較低者。

**未查證就報 = 直接扣到上限**：報「缺少某 annotation / 缺少某欄位」前，必須實際 Read 目標檔確認現況；只憑舊實作或印象推斷，confidence 不得超過 60。

---

## 3. Status 判定（接 Harness Output Contract）

只有 **confidence ≥ 85** 的 finding 進入 Status 判定：

| 條件 | Status |
|---|---|
| CRITICAL ≥ 1（confidence ≥ 85） | `block` |
| HIGH ≥ 1（confidence ≥ 85）或 SKIPPED > 0 | `warning` |
| 累計 MEDIUM ≥ 5（confidence ≥ 85） | `warning` |
| 其餘 | `approve` |

confidence < 85 的 finding **仍要列在 Artifacts**，但不影響 Status —— 它們是「供參考」，由主 agent 依 `agents.md` §主 agent 對 reviewer finding 的判斷責任決定是否採用。

---

## 4. 新增 check / reviewer 的校準義務

新增 `.claude/checks/*.md` 或修改 reviewer checklist 時**必須**：

1. 每條檢查項標預期 severity（依 §1）
2. 非顯而易見的 severity 附一句「為什麼會出事」
3. 依 §2 設 confidence 上限
4. context-dependent 的 severity 要列表說明（例：金流路徑 vs 一般查詢）

---

## 5. Anti-Patterns（禁止）

| ❌ | 為什麼 |
|---|---|
| 全部標 CRITICAL | 等於沒分級 |
| 用「這可能造成 X」「萬一 Y」當 CRITICAL 理由 | 理論風險上限是 HIGH |
| confidence < 80 卻標 CRITICAL | 不確定 + 高嚴重度 = 純雜訊 |
| 把「缺最佳實踐」標 HIGH 以上 | 除非已有事故案例，否則 MEDIUM 起跳 |
| **為了引起注意而升級 severity** | severity 是技術判斷不是溝通工具。想強調就在 issue 描述寫清楚，不要動級別 |
| 防禦性 / future-proofing 建議標 HIGH | 一律 LOW；且必須先驗「現在是否真的適用」（見 `agents.md`） |
