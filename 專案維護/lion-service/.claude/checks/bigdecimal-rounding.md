# Check：金額運算精度

> **適用 reviewer**：`business-reviewer`（L1 場景 model=opus）
> **severity**：CRITICAL
> **confidence 上限**：單檔可見 → 無上限；需追上游 amount 來源才能判斷 → ≤ 80
> **規範**：`rules/security.md` §金額安全

金額算錯是不可逆的業務損失，且對帳前不會被發現。本 check 對「**任何**進入金額計算路徑的程式碼」執行。

## 1. `double` / `float` 參與金額運算 → CRITICAL

```bash
grep -nE '(double|float|Double|Float)\s+\w*(amount|money|balance|rate|fee|bonus|rebate|odds|commission)' <file>
grep -nE '\.doubleValue\(\)|Double\.parseDouble|Float\.parseFloat' <file>
```

二進位浮點無法精確表示十進位小數，`0.1 + 0.2 != 0.3`。**`BigDecimal` 中途轉 `double` 再轉回來同樣違規** —— 精度在轉換當下就已遺失。

## 2. 除法未指定 scale + RoundingMode → CRITICAL

```bash
grep -nE '\.divide\([^,)]+\)' <file>          # 單參數 divide
grep -nE '\.divide\([^)]+\)' <file>           # 全部 divide，人工確認參數
```

單參數 `divide()` 遇到無限循環小數會直接丟 `ArithmeticException`，線上等同該筆交易失敗。

## 3. RoundingMode 方向錯誤 → CRITICAL

```bash
grep -nE 'RoundingMode\.(HALF_UP|HALF_EVEN|CEILING|UP)' <file>
```

本專案規範**一律 `RoundingMode.DOWN`**。派彩 / 反水 / 佣金用 `HALF_UP` 或 `CEILING` 等於每筆多付，量大後是實質損失。

**例外**：計算「使用者要付出的金額」（例：手續費、扣款）時進位對公司有利，但**仍須在 code 附一行 why 註解說明為何不是 DOWN**，否則視為違規。

## 4. `equals` 比較 BigDecimal → HIGH

```bash
grep -nE '\.equals\(\s*BigDecimal|BigDecimal\.\w+\.equals' <file>
```

`BigDecimal.equals` 會比 scale，`0.10` 與 `0.1` 不相等。金額比較一律用 `compareTo(...) == 0`。

## 5. `new BigDecimal(double)` → HIGH

```bash
grep -nE 'new BigDecimal\(\s*[a-zA-Z_]*\s*\)' <file>
```

傳 `double` 進建構子會把浮點誤差原封不動帶進來（`new BigDecimal(0.1)` = `0.1000000000000000055511151231257827`）。應用 `BigDecimal.valueOf(...)` 或字串建構子。

## 反例（不要報）

- 賠率 / 機率的**顯示格式化**（`String.format("%.2f")`）不影響儲存值 → 不報
- 統計報表的百分比顯示 → LOW，不是 CRITICAL
- 既有 code 中未被本次 PR 觸及的 `double` → 依 `coding-style.md` §既有 convention，flag 為 LOW「建議獨立議題清理」

## Fix 方向

- 全鏈路 `BigDecimal`：DB 欄位 `decimal` → model → 計算 → VO，中途不落地成 `double`
- 除法：`divide(divisor, scale, RoundingMode.DOWN)`
- 比較：`compareTo(...) == 0` / `> 0` / `< 0`
- 建構：`BigDecimal.valueOf(x)` 或 `new BigDecimal("0.1")`
