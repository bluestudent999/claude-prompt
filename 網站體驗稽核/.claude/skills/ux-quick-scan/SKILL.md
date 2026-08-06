---
name: ux-quick-scan
description: 對 1~3 個指定頁面做快速 UX 快掃（桌機 + 行動雙視窗），不跨頁走流程，快速產出 5~15 條有證據的 UX 問題與建議。只想快點知道某幾頁有什麼問題時使用。
---

# ux-quick-scan — 單頁／少數頁快掃

**用法**：`/ux-quick-scan <網址>`（可給多個網址）

**與 `/ux-audit` 的差別**：快掃**不走跨頁流程、不定 Persona 矩陣、不寫 Journey 紀錄**。它回答的是「這幾頁本身有什麼問題」，不是「使用者辦得成事嗎」。

**紀律**：使用者要快掃就不要擅自升級成深度走查。若掃完發現問題明顯集中在跨頁流程上，**在回報時建議跑 `/ux-audit`**，不要自己直接跑下去。

---

## Step 0 · Preflight（精簡版）

1. 確認 Chrome DevTools MCP 可用。
2. 確認環境模式（快掃通常不涉交易，但表單試錯仍受模式約束）。
3. 建資料夾：`ux-reports/<YYYY-MM-DD>-<站點簡稱>-quickscan/`（含 `findings/`、`evidence/screenshots/`、`evidence/logs/`）。日期用 `date +%F`。
4. 開頁確認可達。不可達 → 中止並回報。

---

## Step 1 · 蒐證（每頁 × 每視窗，你自己做，不派 sub-agent）

對**每個指定頁面**，在 **desktop 1440×900** 與 **mobile 390×844** 各跑一次 `observation-protocol.md` §4 的標準蒐證動作：

1. `navigate_page` → `wait_for`（等關鍵元素，不要用固定睡眠）
2. `take_snapshot`
3. `take_screenshot` → 落地 `evidence/screenshots/<page>-<viewport>.png`
4. `list_console_messages` → 有 error/warning 就落地
5. **首屏判讀**：不滾動時看得到什麼、主要行動點是什麼、有無被彈窗／同意條款／廣告遮擋
6. **量測包**（`observation-protocol.md` §4.5）→ 落地 `evidence/logs/metrics-<page>-<viewport>.md`
7. 有表單的話：**試填一次錯誤格式**，截錯誤狀態（這是快掃性價比最高的一個動作）
8. 疑似效能問題才追加 `performance_start_trace` / `performance_stop_trace`

> 快掃可省略鍵盤走查與弱網模擬，但**必須在報告限制中註明未覆蓋**。

---

## Step 2 · 評估（可平行，離線讀證據）

**平行**調用三個評估角色，派工指定 id 號段：

| Agent | id 號段 |
|---|---|
| `heuristic-evaluator` | 001-099 |
| `visual-critic` | 100-199 |
| `a11y-perf-inspector` | 200-299 |

派工時明確告知：**這是快掃，沒有 Journey 紀錄**，輸入是頁面截圖 + 量測包 + console/network log + 你的首屏判讀筆記。

> 沒有 Journey 紀錄，`heuristic-evaluator` 的 `FRM`/`FBK` 維度會受限（沒走流程就看不到多步表單與成功/失敗回饋）。這是快掃的固有限制，要寫進限制章節。

---

## Step 3 · 守門

平行跑 **`evidence-auditor`** 與 **`recommendation-reviewer`**。依判定修正後重跑一次。

**閘門**（同深度走查）：evidence-coverage 100%、欄位齊全 100%、空話建議 0、無 `Low`+`Blocker`、無機密洩漏。

---

## Step 4 · 報告

調用 **`report-writer`**，告知這是快掃模式。報告結構同 `references/report-standard.md`，但：
- **省略「Journey 走查紀錄」章節**（改寫一句「本次為快掃模式，未執行跨頁旅程走查」）。
- 「稽核限制」必須列出：未走跨頁流程、未做鍵盤走查、未做弱網模擬、只掃了哪幾頁。

回報格式：

```
報告：<路徑>
掃描頁面：<n> 頁 × 2 視窗
Finding：<總數>（Blocker n / Major n / Minor n / Suggestion n）
證據：<n> 個檔案
本次限制：快掃模式，未走跨頁流程
最該先修的三件事：1. … 2. … 3. …
建議後續：<若問題集中在流程層，建議跑 /ux-audit>
```

---

## 快掃的性價比重點

時間有限時，這幾個動作命中率最高——**優先做這幾件**：

1. **首屏三問**（CNT-1）：這是什麼、對我有什麼用、我該做什麼——答不出來就是 Major 起跳。
2. **手機截圖掃破版**（VIS-7、MOB-2、MOB-3）：破版幾乎都在窄視窗。
3. **表單填錯一次**（FRM-3、FRM-4、FBK-3）：錯誤訊息的品質是 UX 水平最快的指標。
4. **量測包的超標項**（A11Y-1 對比、MOB-1 觸控目標、VIS-5 字級）：白紙黑字的數字，最好交辦。
5. **Console 有沒有 error**（PRF-4、FBK-6）：有 error 卻畫面無提示 = 無聲失敗，通常是 Major。
