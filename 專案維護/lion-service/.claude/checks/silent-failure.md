# Check：靜默失敗

> **適用 reviewer**：`code-reviewer` / `java-reviewer`
> **severity**：HIGH（金額 / 狀態路徑）/ MEDIUM（其餘）
> **confidence 上限**：單檔可見 → 無上限
> **規範**：`rules/coding-style.md` §3 例外不吞、§4 Log 規範

吞掉的例外不會出現在告警，問題只會在使用者客訴時浮現，且此時已無法追溯根因。

## 1. 空 catch → HIGH

```bash
grep -nA3 'catch\s*(' <file> | grep -B1 -E '^\s*\}'
grep -nA2 'catch\s*(' <file> | grep -E 'e\.printStackTrace|^\s*$'
```

`catch (Exception e) {}` 或只有 `printStackTrace()` → 生產環境 stdout 沒人看。

## 2. catch 後回傳預設值掩蓋錯誤 → HIGH

```bash
grep -nA5 'catch\s*(' <file> | grep -E 'return (null|false|0|BigDecimal\.ZERO|new ArrayList|Collections\.empty)'
```

**金額路徑回 `BigDecimal.ZERO` 是最危險的形態** —— 呼叫端會把「查詢失敗」當成「餘額為 0」繼續往下算。

## 3. catch 只 log 不處理 → 依情境

```bash
grep -nA4 'catch\s*(' <file> | grep -E 'log\.(info|warn|debug)'
```

判定：

| 情境 | severity |
|---|---|
| 金額 / 狀態機路徑 catch 後繼續往下執行 | HIGH |
| 應失敗的操作被降級為 `log.warn` 後正常返回 | HIGH |
| 通知 / 推播等非關鍵路徑 catch 後 log 並繼續 | 不報（這是正確降級） |
| 用 `log.info` 記錄例外 | MEDIUM（等級錯誤，依 `coding-style.md` §4） |

## 4. log 未帶上下文 → MEDIUM

```bash
grep -nE 'log\.error\("[^"]*"\s*\)' <file>
```

`log.error("failed")` 無法定位。至少要有業務識別（userId / orderNo）與例外物件本身。**注意脫敏**：手機、卡號、token 不得直接進 log（`rules/security.md`）。

## 5. 忽略回傳值 → HIGH

```bash
grep -nE '^\s*\w+(Dao|Mapper|Service)\.(update|delete|insert|save)\w*\(' <file>
```

DAO 的 `update` / `delete` 回傳影響筆數卻沒接、沒判斷 → 更新失敗（例如 WHERE 條件沒命中）時程式繼續當成成功走下去。狀態機場景見 `state-machine-transition.md` §1。

## 6. 例外被轉成無資訊的新例外 → MEDIUM

```bash
grep -nE 'throw new \w+Exception\([^)]*\)' <file> | grep -v 'e\)'
```

`catch (Exception e) { throw new BizException("失敗"); }` 丟失原始 stack trace，應把 `e` 傳入或用既有 framework Exception 保留 cause。

## 反例（不要報）

- `catch` 後明確 `throw`（含包裝並帶 cause）→ 正確
- 重試迴圈中 catch 後 continue，且最終失敗有拋出 / 告警 → 正確
- 資源關閉的 `catch` → 不報
- 已有 `// 忽略：<原因>` 註解說明為何可安全忽略 → 降為 LOW

## Fix 方向

- 決定語意：要往上拋、要降級（且有告警）、還是可安全忽略（必附 why 註解）
- 不確定就往上拋 —— 讓錯誤停在能處理它的那層
- log 帶業務識別 + 例外物件，等級依 `coding-style.md` §4（`error` 為需追查的失敗）
