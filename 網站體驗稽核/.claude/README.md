# 網站體驗稽核 — 使用指南

讓 Claude Code 自己**當 UX 稽核員**：實際開瀏覽器逛你的網站、以真實使用者視角走完流程、蒐集可複驗的證據，最後產出一份可直接開成工單的 **UX 修改建議報告**。

這是**純 Prompt 規範**——沒有程式碼、沒有要安裝的套件、沒有要跑的腳本。Claude Code 讀這些規範，用 Chrome DevTools MCP 當眼睛和手。

---

## 一次性設定（3 步）

### 1. 部署範本

```bash
cd /path/to/任一工作目錄
prompt-setup 網站體驗稽核
```

### 2. 裝 Chrome DevTools MCP

這是 Agent 的眼睛和手，**沒有它整套跑不起來**（Agent 會直接停下來要你裝，不會改用抓 HTML 假裝有體驗過）。

```bash
claude mcp add chrome-devtools -- npx -y chrome-devtools-mcp@latest
```

驗證：在 Claude Code 裡跑 `/mcp`，看到 `chrome-devtools` 為 connected 即可。

### 3. 填稽核目標

編輯 `.claude/audit-target.md`：目標站、**環境模式**、授權網域、登入憑證的環境變數名稱、關注目標。

需要登入的話，憑證用環境變數（**不要寫進檔案**）：

```bash
export UX_AUDIT_USER='your-test-account'
export UX_AUDIT_PASS='your-test-password'
```

---

## 開始稽核

```bash
claude
```

| 想做什麼 | 指令 | 大概花多久 |
|---|---|---|
| 完整稽核一個網站 | `/ux-audit https://your-site.com` | 長（探勘 + 多條流程 + 多視角評估） |
| 快速看幾頁有什麼問題 | `/ux-quick-scan https://your-site.com/pricing` | 短 |
| 深入檢視一條流程 | `/ux-journey 從首頁完成註冊並登入` | 中 |
| 改完之後回歸驗證 | `/ux-verify ux-reports/2026-07-31-yoursite/report.md` | 中 |

直接用自然語言講也可以（「幫我稽核這個網站的下注流程」），Agent 會自己判定模式。

---

## 產出長什麼樣

```
ux-reports/2026-07-31-yoursite/
├── report.md          ← 交付物。決策者看前一頁，工程師看 Finding 明細
├── audit-plan.md      ← Persona × Journey 計畫（深度走查才有）
├── journeys/          ← 逐步體驗紀錄：「我想 → 我看到 → 我做了 → 結果」
├── findings/          ← 一條問題一個檔（Agent 間的交接契約）
└── evidence/
    ├── screenshots/   ← 每條 Finding 的證據
    └── logs/          ← console / network / 效能 trace / 量測數據
```

`report.md` 的結構：摘要 → **最該先修的三件事** → **Quick Wins** → Finding 總覽 → Finding 明細（含內嵌截圖）→ Journey 走查紀錄 → 稽核限制 → 附錄。

---

## 這套東西的設計重點

**1. 沒有證據就沒有結論**
每條問題都必須附真實落地的截圖 / log / 量測數字。交付前 `evidence-auditor` 會逐條驗證檔案是否真的存在——路徑寫錯的 Finding 直接作廢。這是為了擋掉 LLM 最擅長的「看起來很專業但其實沒根據的 UX 建議」。

**2. 觀察與推論強制分離**
每條 Finding 拆成 `observed`（我實際看到什麼，含數字）與 `why_it_hurts`（據此推論的使用者代價 + 準則 ID）。守門會掃 `observed` 裡有沒有「混亂」「不直覺」這類判斷詞——有就退回。

**3. 建議必須可交辦**
`recommendation-reviewer` 會擋掉「優化使用者體驗」「加強引導」這類空話。合格的建議長這樣：改哪個元件、改成什麼（能給文案就給）、預期效果可觀測。

**4. 測試環境要走到底**
預設 `environment: test`，交易流程一律送出到成功頁，並**刻意試錯**（填錯格式、餘額不足、重複送出、中途返回）。「處理中／失敗／成功」這三個畫面是 UX 問題最密集、也最少被設計好的地方——只在生產環境稽核的人永遠看不到它們。

**5. 瀏覽器是單一實例，蒐證絕不平行**
Chrome DevTools MCP 背後只有一個瀏覽器。同時跑兩個蒐證 agent 會互相踩掉頁面狀態、證據全毀。所以：**蒐證序列、評估平行**——蒐證角色一條一條跑並把證據寫成檔案，三個評估角色再離線平行讀檔。

---

## 角色分工

| 階段 | 角色 | 碰瀏覽器 | 做什麼 |
|---|---|:---:|---|
| 探勘 | `site-scout` | ✅ 序列 | 摸清站點、定 Persona × Journey 計畫 |
| 蒐證 | `journey-runner` | ✅ 序列 | 以 Persona 身分實走一條流程，逐步蒐證 |
| 評估 | `heuristic-evaluator` | ❌ | 導航 / 表單 / 回饋 / 錯誤處理 / 文案 / 信任 |
| 評估 | `visual-critic` | ❌ | 視覺層級 / 間距 / 對比 / 破版 / 手機觸控 |
| 評估 | `a11y-perf-inspector` | ❌ | WCAG AA / 鍵盤 / Console / 網路 / 效能實測 |
| 守門 | `evidence-auditor` | ❌ | 驗證據存在、欄位齊全、觀察純度 |
| 守門 | `recommendation-reviewer` | ❌ | 驗建議可交辦、對症、不越權 |
| 產出 | `report-writer` | ❌ | 去重、排序、寫報告 |

---

## 檔案結構

```
.claude/
├── CLAUDE.md            ← 部署後會被搬到專案根目錄（入口：紅線、模式、路由）
├── README.md            ← 本檔
├── audit-target.md      ← 唯一要手填的設定
├── settings.json        ← 權限白名單 + 開工提醒
├── rules/               ← 每次 session 自動注入（刻意保持精簡）
│   ├── audit-workflow.md        生命週期 Step 0~5 與退出閘門
│   ├── observation-protocol.md  MCP 操作、標準蒐證動作、量測包、視窗矩陣
│   ├── evidence-discipline.md   Finding 資料契約（Agent 間唯一交接格式）
│   └── scope-safety.md          環境模式、操作邊界、憑證與個資、誠實義務
├── references/          ← 按需讀取的知識庫（不常駐，省 token）
│   ├── ux-heuristics.md         準則庫：NAV/FRM/FBK/CTL/CNT/VIS/CON/MOB/A11Y/PRF/TRS
│   ├── severity-priority.md     Severity 判定 + Impact×Effort 排序 + Quick Wins
│   └── report-standard.md       報告結構契約與禁用語表
├── agents/              ← 8 個角色定義
├── skills/              ← /ux-audit /ux-quick-scan /ux-journey /ux-verify /strategic-compact
└── templates/           ← report-template.md、journey-spec-template.md
```

---

## 常見問題

**Q：不用 Chrome DevTools MCP，改用 Playwright MCP 可以嗎？**
可以，但 rules 裡的工具名稱是照 `chrome-devtools-mcp` 寫的（`observation-protocol.md` §1 已註明「工具名稱以實際清單為準」）。純換工具名不影響流程紀律；只是 Console / Network / 效能 trace 這幾項要確認新工具拿不拿得到，拿不到就會在報告的稽核限制中標為未覆蓋。

**Q：為什麼報告條數這麼少？**
守門會退掉沒證據、沒數字、空話建議的 Finding。**6 條紮實的比 30 條有 10 條是編的有用。** 想擴大覆蓋就擴大範圍（多跑幾條 Journey），不要放寬守門。

**Q：Agent 會不會把我的測試站弄壞？**
`test` 模式下它會照著使用者行為下單、送表單。它**不會**改測試帳號密碼、註銷帳號、壓測或掃描（`scope-safety.md` §2 明文禁止）。產生的訂單／注單編號會列在報告附錄，方便你清理。

**Q：想把建議實作進 code？**
本範本只交付報告，不改產品程式碼。切到對應的開發／維護範本，把 `report.md` 當需求輸入：

```bash
cd /path/to/產品專案 && prompt-setup 專案維護 cx-sports
```

**Q：報告可以拿來當回歸基準嗎？**
可以，這是 `/ux-verify` 的設計目的。它會逐條重走、附**新證據**判定「已修復 / 部分修復 / 未修復 / 退步 / 無法複驗」。新證據落在新資料夾，舊證據**絕不覆蓋**——它是判定「退步」的唯一基準。
