# 瀏覽器操作與蒐證協議（Chrome DevTools MCP）

> 本文規範「怎麼用瀏覽器體驗網站」與「怎麼把看到的東西變成可複驗的證據」。

---

## 1. 能力確認與降級（開工第一步）

1. 確認 Chrome DevTools MCP 可用（列出可用工具，確認有 `navigate_page` / `take_snapshot` / `take_screenshot`）。
2. **工具名稱以實際列出的清單為準**——本文的名稱依 `chrome-devtools-mcp` 慣例書寫，若實際命名不同，以實際為準，不要硬套。
3. **不可用時的降級**：
   - MCP 完全不可用 → **停止並告知使用者**如何啟用，不要改用 `curl` 抓 HTML 假裝有體驗過。靜態 HTML 看不到 JS 渲染結果、互動狀態與版位，用它產 UX 報告等同編造。
   - 僅部分工具可用（例如沒有 `performance_*`）→ 照跑其餘維度，並在報告「稽核限制」明列缺少的觀察維度。

---

## 2. 單一瀏覽器佔用（硬規則）

- MCP 背後是**同一個瀏覽器實例**。同一時刻**只有一個角色**能操作它。
- **禁止**平行啟動兩個以上會導航／點擊／截圖的 agent；狀態會互相踩掉，證據將不可信。
- 蒐證與評估**在時間上分離**：先由蒐證角色序列跑完、把證據落地成檔案，再讓評估角色平行讀檔。
- 交棒時要留下「目前頁面在哪、登入狀態為何」的一行狀態記錄。

---

## 3. 常用工具對映

| 目的 | 工具 |
|---|---|
| 開頁 / 換頁 / 上下頁 | `new_page`、`navigate_page`、`navigate_page_history`、`list_pages`、`select_page`、`close_page` |
| 讀頁面結構（取得可互動元素的 uid） | `take_snapshot` |
| 截圖（整頁或指定 uid 的元素） | `take_screenshot` |
| 互動 | `click`、`hover`、`fill`、`fill_form`、`drag`、`upload_file`、`handle_dialog` |
| 等待 | `wait_for` |
| 取任意資訊 / 量測 | `evaluate_script` |
| 錯誤與警告 | `list_console_messages` |
| 網路 | `list_network_requests`、`get_network_request` |
| 效能實測 | `performance_start_trace`、`performance_stop_trace`、`performance_analyze_insight` |
| 視窗與環境模擬 | `resize_page`、`emulate_cpu`、`emulate_network` |

---

## 4. 每個頁面的標準蒐證動作（Page Observation Set）

進到任一要評估的頁面，**依序**完成：

1. `navigate_page` → `wait_for`（等關鍵文字或元素出現，不要用固定睡眠時間當作載入完成）。
2. `take_snapshot` — 拿到結構與可互動元素的 uid。這是後續互動與定位的基礎。
3. `take_screenshot` — 整頁截圖，落地 `evidence/screenshots/<page>-<viewport>.png`。
4. `list_console_messages` — 有 error / warning 就落地 `evidence/logs/console-<page>.md`。
5. **首屏判讀**：不滾動的情況下，記錄「使用者第一眼能看到什麼、主要行動點是什麼、有無被彈窗／同意條款／廣告遮擋」。
6. 針對疑點才追加：`list_network_requests`（抓 4xx/5xx、過大資源）、`performance_start_trace`+`performance_stop_trace`（要講載入或互動延遲**必須**有實測數字）。

> **每個 viewport 都要重跑一次這組動作**，不要拿桌機截圖去推論手機版行為。

---

## 4.5 量測包（Metrics Pack）— 蒐證階段必做

**為什麼必做：** 評估角色是**離線讀證據**的，不能自己開瀏覽器量東西。對比度、字級、行高、觸控目標尺寸、橫向溢出這些數字，若蒐證階段沒抓，評估階段就只能「目測」——而目測出來的數字不算證據。

每個頁面 × 每個 viewport 用 `evaluate_script` 抓一次，落地 `evidence/logs/metrics-<page>-<viewport>.md`。**要抓的項目**：

| 項目 | 用途（對映準則） |
|---|---|
| `document.title`、`location.href`、`documentElement.lang` | 頁面識別、A11Y-10 |
| `document.documentElement.scrollWidth` vs `window.innerWidth` | MOB-2 橫向溢出 |
| 正文元素的 `font-size` / `line-height` / 單行字元數 | VIS-5 可讀性 |
| 文字元素的 `color` + 有效背景色（往上找非透明祖先） | A11Y-1 / VIS-6 對比度（附算出的比值） |
| 所有 `button`/`a`/`input` 的 `getBoundingClientRect()` 寬高與相鄰間距 | MOB-1 觸控目標 |
| `h1`~`h6` 的出現順序 | A11Y-6 標題階層 |
| `img` 的 `alt` 有無、`naturalWidth` vs 顯示寬度 | A11Y-5、PRF-6 圖片過大 |
| `input` 是否有關聯 `label` / `aria-label` / `autocomplete` / `inputmode` | A11Y-9、FRM-6 |
| 被移除 focus 樣式的元素（`outline: none` 且無替代） | A11Y-3 |
| `position: fixed/sticky` 元素的位置與尺寸 | MOB-3 遮擋 |
| `meta[name=viewport]` 內容 | A11Y-10 禁止縮放 |

**落地格式**：Markdown 條列或表格，**只寫有問題或接近門檻的項目**（例如只列對比 < 4.5:1 的文字、只列 < 44px 的可點元素），不要把整頁上千個元素全 dump 進來——那會讓評估角色讀爆 context。每項附**選擇器或可見文字**以便定位。

**鍵盤可達性（A11Y-2 / A11Y-3）**：無法靠一次量測取得，需在蒐證階段實際連續按 Tab 走一輪主要互動元素，記錄焦點順序與有無看不見焦點的元素（截圖 focus 狀態）。深度走查必做，快掃可省略並在限制中註明。

---

## 5. 視窗矩陣（Viewport Matrix）

| 名稱 | 尺寸 | 何時必跑 |
|---|---|---|
| `desktop` | 1440 × 900 | 一律必跑 |
| `mobile` | 390 × 844 | 一律必跑（`resize_page`） |
| `tablet` | 820 × 1180 | 深度走查時，若站點有明顯中斷點才跑 |
| `narrow-desktop` | 1024 × 768 | 深度走查時，若導航在此塌陷才跑 |

- 手機視窗要**額外**檢查：點擊目標尺寸、橫向溢出捲動、固定式頁首／頁尾遮擋內容、觸控手勢依賴、鍵盤彈出後表單是否被蓋住。

---

## 6. 以人的方式體驗（非 RPA 紀律）

**你的任務是「像一個帶著目標的人一樣用這個網站」，不是驗證某個斷言為真。**

- 每一步先問：「以這個 Persona 的認知，**下一步該點哪裡**？為什麼？」把這個判斷過程記下來——**找錯路本身就是最有價值的 Finding**。
- 出現猶豫、來回、找不到、看不懂、被打斷 → 立刻蒐證，這就是卡點。
- **禁止**直接用網址跳過流程（除非是刻意測試「深連結是否可用」）。跳過導航就看不到導航的問題。
- **禁止**寫成「步驟 → 斷言 → 通過」的測試腳本口吻。報告的語言是「我想做 X，我看到 Y，於是我 Z，結果 W」。
- 流程成功走完**不代表沒問題**：走完但走得很痛（多繞 3 步、錯誤訊息看不懂、按鈕位置反直覺）同樣要開 Finding。

---

## 7. 登入態稽核

1. 憑證從環境變數讀取（`.claude/audit-target.md` 有樣板）。**憑證缺失時不要嘗試猜測或註冊帳號**，改為只跑訪客範圍，並在報告註明「未提供憑證，僅完成訪客範圍稽核」。
2. 登入後**先確認真的進到會員區**（截圖為證），再繼續走登入後 Journey。
3. 遇到圖形驗證碼 / SMS / 2FA 卡關 → **停止嘗試**，留下卡關截圖，在報告「稽核限制」註明，並詢問使用者是否提供測試帳號或關閉驗證。
4. 登入後的截圖**必須**檢查個資（見 `scope-safety.md` §3）。

---

## 8. 證據落地規範

```
<稽核產出資料夾>/
├── report.md
├── audit-plan.md              # 深度走查：Persona × Journey 計畫
├── findings/FND-001.md ...    # 一條 Finding 一個檔
└── evidence/
    ├── screenshots/           # <page|FND-id>-<viewport>[-<說明>].png
    └── logs/                  # console-*.md / network-*.md / trace-*.md
```

- 檔名一律小寫連字號、可自我說明（`checkout-step2-mobile.png`，不要 `screenshot1.png`）。
- 截圖落地後**必須實際確認檔案存在**再寫進 Finding 的 `evidence`。守門會逐一驗，路徑寫錯等於該 Finding 作廢。
- 要指出「畫面上的哪一處」時，優先用**元素級截圖**（`take_screenshot` 指定 uid），比在全頁截圖上用文字描述位置精確得多。
