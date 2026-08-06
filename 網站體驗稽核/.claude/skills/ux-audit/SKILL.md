---
name: ux-audit
description: 對一個網站執行完整的 UX 深度走查：探勘站點 → 定 Persona × Journey → 實際走完流程蒐證 → 多視角評估 → 守門 → 產出 UX 修改建議報告。要一份完整 UX 稽核報告時使用。
---

# ux-audit — 完整 UX 深度走查

**用法**：`/ux-audit <目標網址>`（可附「重點看註冊流程」「這是測試站可以隨便下單」等補充）

**你是總指揮**。你負責驅動瀏覽器、派工給 sub-agent、把關閘門。**sub-agent 不會自己開瀏覽器**（除了 `site-scout` 與 `journey-runner`）。

---

## Step 0 · Preflight

1. **MCP 能力確認**：確認 Chrome DevTools MCP 可用（`observation-protocol.md` §1）。不可用 → **停下來告知使用者怎麼啟用**，不要改用抓 HTML 假裝有體驗。
2. **環境模式**：讀 `.claude/audit-target.md` 的「環境模式」。未指定且網域看不出是測試站 → **問使用者一句**（`test` 可完整下單／`production` 停在可逆畫面）。
3. **範圍與憑證**：確認授權網域；需登入時確認憑證環境變數已設（未設 → 只跑訪客範圍並留痕）。
4. **建資料夾**：
   ```
   ux-reports/<YYYY-MM-DD>-<站點簡稱>/
     ├── findings/  journeys/
     └── evidence/screenshots/  evidence/logs/
   ```
   日期用 `date +%F` 取，不要憑記憶寫。
5. **可達性**：開起始頁確認渲染正常。不可達 → **中止，不產半套結論**。

**宣告**：一句話說明本次模式、環境模式、產出路徑，然後繼續。

---

## Step 1 · 探勘與計畫

調用 **`site-scout`**（獨佔瀏覽器），產出 `audit-plan.md`。

**閘門 G1**：每條 Journey 有可判定的成功條件；交易環節已標明處置（`test` 走到底的終點畫面 / `production` 停止點）；`test` 模式下有至少 3 個刻意試錯點；Journey 總數 ≤ 8。

把計畫摘要給使用者看一眼（Persona、Journey 清單、不做清單）。**使用者沒異議就直接繼續，不要停下來等**——除非計畫與需求明顯矛盾。

---

## Step 2 · 蒐證（序列，絕不平行）

依 `audit-plan.md`，**一條一條**調用 **`journey-runner`**。

> ⚠️ **單一瀏覽器佔用**：Chrome DevTools MCP 背後是同一個瀏覽器實例。**同時跑兩個 `journey-runner` 會互相踩掉頁面狀態，證據全部作廢。** 一次一條，跑完交棒。

每條之間：
- 接收交棒狀態（目前頁面、登入狀態、購物車狀態）。
- 每完成 2~3 條，跑 `/strategic-compact` 把已落地的證據從 context 卸掉。

**別忘了量測包**：每個要評估的頁面 × viewport，用 `evaluate_script` 抓一次量測包落地（`observation-protocol.md` §4.5）。**沒有它，`visual-critic` 與 `a11y-perf-inspector` 只能目測，等於廢掉兩個評估角色。**

**別忘了鍵盤走查**：主要互動元素連續按 Tab 走一輪，記錄焦點順序與看不見焦點的元素（深度走查必做）。

**閘門 G2**：每條 Journey 有結果標記與逐步證據；`ls evidence/screenshots/` 確認檔案真的都在；卡點都已記錄。

---

## Step 3 · 評估（可平行）

**平行**調用三個評估角色（都只讀檔案、不碰瀏覽器，所以安全）。派工時**指定 id 號段避免撞號**：

| Agent | id 號段 | 維度 |
|---|---|---|
| `heuristic-evaluator` | 001-099 | NAV / FRM / FBK / CTL / CNT / CON(語意) / TRS |
| `visual-critic` | 100-199 | VIS / MOB / CON(視覺) / A11Y-1 對比度 |
| `a11y-perf-inspector` | 200-299 | A11Y-2~10 / PRF |

派工內容須含：產出資料夾、id 號段、要讀的 Journey 檔與證據檔清單、環境模式。

**收攏後處理三件事**：
1. 各角色的**補證需求** → 判斷值不值得再開瀏覽器補（值得就回 Step 2 補一輪，序列執行）。
2. 各角色「刻意沒開的 Finding」 → 裁決歸屬，指派給對應角色補寫，或自己補。
3. 各角色的**未覆蓋維度** → 記下來，Step 5 要寫進稽核限制。

**閘門 G3**：每條 Finding 有真實證據、`observed` 與 `why_it_hurts` 已分離、有準則 ID。

---

## Step 4 · 守門

**平行**調用 **`evidence-auditor`** 與 **`recommendation-reviewer`**（互不依賴）。

依判定修正：`REJECT` → 補蒐證或刪除；`FIX` → 依要求的修正動作改寫。改完**重跑守門一次**。

**閘門 G4（交付硬門檻）**：

| 指標 | 標準 |
|---|---|
| evidence-coverage | 100% |
| 欄位齊全率 | 100% |
| 空話建議數 | 0 |
| `confidence: Low` + `severity: Blocker` | 0 |
| 機密／未遮蔽個資 | 0 |

**任一項未達標不得進 Step 5。**

去重：依 `evidence-discipline.md` §4 合併同根因 Finding，記錄合併對照。

---

## Step 5 · 報告

調用 **`report-writer`**，產出 `report.md`。

回報使用者（用 `report-writer` 的交付摘要格式）：報告路徑、Finding 數與分佈、Journey 結果、證據數、本次限制、最該先修的三件事。

---

## 常見誤區（每次開工前掃一眼）

| ❌ 別做 | ✅ 該做 |
|---|---|
| 平行跑多個 `journey-runner` 加速 | 序列跑。平行 = 證據全毀 |
| 用網址直接跳到目標頁 | 從導航走。跳過導航就看不到導航的問題 |
| 只跑桌機、手機用推論 | 每條 Journey 的關鍵步驟在 mobile 重走 |
| 交易流程停在確認頁就算走完（test 環境） | 送出 → 截「處理中」→ 截成功/失敗 → 回列表確認狀態更新 |
| 只走順風路 | 刻意試錯：填錯、餘額不足、重複送出、中途返回 |
| 忘記抓量測包 | 每頁每視窗抓一次，否則兩個評估角色廢掉 |
| Journey 標「完成」就當沒問題 | 走完但繞路／來回／看不懂，一樣開 Finding |
| 把整份 snapshot 留在 context | 用完就丟，只留 uid 與定位文字 |
