# Check：filter 放行分支（已發生過實際入侵）

> **適用 reviewer**：`security-reviewer`（主）、`code-reviewer`（動到 filter 時的第一道）
> **觸發**：變更範圍含 `*Filter.java`、`filter/` 目錄、放行清單 / 白名單設定（yml 的 bypass / whitelist / exclude 類設定）、`isUriContains` 類判斷
> **severity**：CRITICAL（新增或擴充可被請求端控制的放行條件 / 檢查失敗未中止）/ HIGH（放行比對未正規化）
> **confidence 上限**：需確認容器實際分派路徑（`server.servlet` 設定、前置 nginx）→ ≤ 70；單檔可見「副檔名 / 子字串放行」→ 無上限
> **規範**：`rules/security.md` §filter 防線

**事故**：認證 filter 曾被實際繞過，成因是帶 `.do` 的請求直接放行、完全不檢查。
這一類**偽裝成「有防線」**——filter 存在、也真的在檢查登入，只是某些請求根本走不到那段檢查。
所以本 check 的原則與其他 check 相反：**證明不了「擋得住」就不放行。**

## 1. 防線有效性三問（逐一回答，寫出依據的行號）

對變更範圍內每一個「提早放行」分支（`filterChain.doFilter(...)` 之後緊接 `return`、或跳過檢查的 `if`）：

| # | 問題 | 答不出來 → |
|---|---|---|
| ① | 請求**一定**會走到檢查那一段嗎？有沒有更早的放行分支？ | 標 CRITICAL，c ≤ 70，列出分支行號 |
| ② | 放行條件是**精確比對完整路徑**，還是副檔名 / `contains` / `startsWith` 片段 / 正規式部分符合？比對前有沒有正規化？ | 片段比對 → CRITICAL；未正規化 → HIGH |
| ③ | 檢查失敗後**真的中止**請求嗎（`return` / 拋例外 / 回錯誤碼），還是只記 log 繼續往下？ | 未中止 → CRITICAL |

```bash
# 提早放行分支
grep -nB4 'filterChain.doFilter\|chain.doFilter' <file>
# 副檔名 / 片段比對
grep -nE '\.(contains|endsWith|startsWith|indexOf|matches)\(|isUriContains|\.do\b' <file>
# 檢查失敗後的處理
grep -nA4 -E 'if\s*\(!.*(valid|check|verify|sign|login|token)' <file>
```

## 2. 新增或擴充放行條件 → CRITICAL

| 寫法 | 判定 |
|---|---|
| 新增以副檔名放行（`.do`、`.html`、`.json`、`.js`…） | CRITICAL —— 副檔名是請求端可任意加的字串 |
| 新增 `uri.contains("xxx")` / `startsWith` 片段放行 | CRITICAL —— `/api/admin/x;sync`、`/sync/../admin` 之類就能命中 |
| 在既有的副檔名 / 片段放行清單**加一項** | CRITICAL —— 擴大已知事故面 |
| 新增精確路徑放行，且比對前已正規化 | ✅ 可接受，仍需確認該路徑本身不需登入 |

## 3. 正規化 → HIGH

比對用的字串必須與容器分派用的一致：`getRequestURI()` 含 `;jsessionid=` 類參數、`//`、`..`、URL 編碼與大小寫差異。
用未正規化的 `getRequestURI()` 做放行比對 → HIGH。

## 反例（不要報）

- **未變更的既有放行分支**：不屬本次 MR 範圍 → 不計入 Counts，但在 Artifacts 以 LOW 附一行「既有事故型放行分支，建議由資安修復單處理」，**不要求本 MR 修**
- 靜態資源 / 健康檢查端點以**完整精確路徑**放行 → 正確
- 驗簽 filter 對「明確列舉、文件化的公開回調」放行，且該回調在 controller 層另有驗簽 → 降為 LOW

## Fix 方向

- 放行清單改為明確列舉的完整路徑，精確比對
- 比對前正規化路徑，並與容器分派的字串一致
- 檢查失敗一律中止請求
- 既有片段放行要移除時，屬另開修復單（影響全站入口，需回歸所有被放行的端點）
