# Check：狀態機轉換合法性

> **適用 reviewer**：`business-reviewer`（L1 場景 model=opus）
> **severity**：CRITICAL（不可逆 / 金額相關狀態）/ HIGH（一般業務狀態）
> **confidence 上限**：需對照 spec 才知合法轉換集 → ≤ 80；spec 有明列狀態表 → 可到 90
> **規範**：`reviewer-checklists.md` §business-reviewer

狀態寫錯不會拋例外，只會讓資料靜靜地錯，通常在對帳或客訴時才被發現。

## 1. 更新狀態時 WHERE 未帶前置狀態 → CRITICAL

```bash
# 找狀態更新
grep -nE 'set(Status|State)\(|updateStatus|status\s*=' <file>
# 對應的 mapper / SQL
grep -rnE 'UPDATE .* SET .*status' <module>/src/main/resources/ <module>/src/main/java/ | head -20
```

`UPDATE t SET status = 已派彩 WHERE id = ?` 沒帶 `AND status = 待派彩`，在併發或重送時會把終態改回去，或重複觸發下游動作。

**正確**：`UPDATE t SET status = ? WHERE id = ? AND status = ?`，並**檢查回傳的影響筆數**：

```bash
grep -nE 'int\s+\w+\s*=\s*\w+(Dao|Mapper)\.(update|modify)' <file>
```

拿到影響筆數卻沒判斷 `== 0` → HIGH（等同沒防護）。

## 2. 缺少非法轉換的拒絕分支 → CRITICAL / HIGH

合法轉換集必須明確列舉。看到下列形態即為問題：

- 直接 `setStatus(X)` 沒有任何前置檢查
- 有檢查但只 `if (status != A) return;` 靜默返回（無 log、無例外）→ 同時命中 `silent-failure.md`

**severity 判定**：目標狀態是**終態 / 不可逆**（已派彩、已出款、已核銷、已退款）→ CRITICAL；一般中間狀態 → HIGH。

## 3. 新增 enum 值未補下游分支 → HIGH

```bash
# 找到 enum 定義後，搜所有 switch / if-else 分派點
grep -rn "OrderStatus\.\|<EnumName>\." <module>/src/main/java/ | grep -E 'switch|case|=='
```

新增狀態值卻沒補 `switch` 的 `case`，會 fall-through 到 `default` 走錯邏輯。**`default` 分支若只是 `break` 或回預設值而不記錄異常 → 一併標 HIGH**（依 `rules/coding-style.md` §4，不應發生的狀態應 `log.error`）。

跨模組連動 grep pattern 見 `skills/cross-module-changes/SKILL.md`。

## 4. 狀態與金額異動的順序 → HIGH

本專案慣例是**先變更狀態、後寫流水**，搭配 `@Transactional` rollback。順序顛倒時，若狀態更新失敗，流水已寫入 → 對帳出現無主流水。

## 5. 狀態欄位用 magic number → MEDIUM

```bash
grep -nE 'status\s*==\s*[0-9]|setStatus\([0-9]' <file>
```

應使用 enum 或常數類。

## 反例（不要報）

- 初始建立（`INSERT` 帶初始狀態）不需要前置狀態檢查
- 管理後台的人工強制改狀態（有權限控管 + 稽核 log）→ 這是有意設計，確認有 log 即可，不報
- 查詢用的 status filter → 不是轉換

## Fix 方向

- 定義合法轉換表（enum 內建 `canTransitionTo`）
- `UPDATE ... WHERE id = ? AND status = ?` + 檢查影響筆數，為 0 時拋業務例外
- 新增 enum 值時，用上方 grep 掃全部分派點
