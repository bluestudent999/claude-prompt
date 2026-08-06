# 證據紀律與 Finding 資料契約

> 本文是本範本的**核心資料契約**。所有蒐證角色、評估角色、守門角色、報告角色都以 `Finding Block` 作為唯一交接格式。

---

## 1. 證據的定義（什麼才算證據）

**算證據**（可被第三人在不重跑一次的情況下複驗）：

| 種類 | 落地形式 | 取得方式 |
|---|---|---|
| 截圖 | `evidence/screenshots/<name>.png` | `take_screenshot`（整頁或指定 uid 的元素截圖） |
| 結構快照 | 引用 `take_snapshot` 中的節點 uid + 可見文字錨點 | `take_snapshot` |
| Console 訊息 | `evidence/logs/console-<page>.md` | `list_console_messages` |
| 網路記錄 | `evidence/logs/network-<page>.md`（URL / status / 耗時 / 大小） | `list_network_requests`、`get_network_request` |
| 效能數據 | `evidence/logs/trace-<page>.md`（LCP / CLS / INP / TBT 等實測值） | `performance_*` |
| DOM 片段 | 直接內嵌於 Finding 的程式碼區塊（≤ 15 行） | `evaluate_script` |

**不算證據**：
- 「一般來說這種頁面通常會……」——通則不是觀察。
- 「使用者可能會覺得困惑」——沒有證據支撐的心理推測。
- 「看起來載入很慢」——沒有實測數字。要嘛給 `trace` 數據，要嘛不寫。
- 憑記憶或憑站點類型腦補的頁面內容。

---

## 2. 觀察 / 推論分離（本範本最重要的結構性紀律）

每條 Finding 必須拆成兩層，**不得混寫**：

| 欄位 | 寫什麼 | 檢驗方式 |
|---|---|---|
| `observed` | **我實際看到的客觀事實**。含具體數值、文字、位置、選擇器。 | 第三人拿著證據檔能不能確認這句話為真？不能 → 寫錯層了 |
| `why_it_hurts` | **據此推論的使用者代價**，並對映一條準則 ID。 | 有沒有指出「哪種使用者、在哪個情境、會付出什麼代價」？ |

**反例（禁止）**

```
observed: 導航列的資訊架構很混亂，使用者找不到想要的功能
```

「混亂」「找不到」是推論不是觀察。

**正例**

```
observed: 主導航列共 11 個一級項目，其中「服務」「解決方案」「產品」三項的
          下拉選單有 6 個重複的子項（截圖 FND-003-nav.png，紅框處）。
why_it_hurts: [NAV-2 分類互斥性] 同一目標存在三條入口路徑，首次到訪者需逐一
          展開比對才能判斷該點哪個，增加決策成本；且三處內容若各自維護，
          長期會出現不一致。
```

---

## 3. Finding Block 格式（Agent 間唯一交接契約）

每條 Finding 存成 `findings/FND-<3位序號>.md`，內容為**一個** ```finding 區塊。欄位順序固定、不得增刪欄位名。

````markdown
```finding
id: FND-001
title: <一句話講清楚「哪裡」出了「什麼」問題，≤ 30 字，不含解法>
severity: Blocker | Major | Minor | Suggestion
category: Navigation | Form | Content | Visual | Accessibility | Performance | Feedback | Consistency | Mobile | Trust
persona: <哪個 Persona 撞到的；快掃模式填 Visitor>
journey_step: <第幾步 / 哪個環節；單頁檢視填 N/A>
url: <出問題的完整 URL>
viewport: <desktop 1440x900 | mobile 390x844 | 其他實際使用值>
evidence:
  - evidence/screenshots/FND-001-nav.png · 紅框：主導航第 4~6 項
  - evidence/logs/console-home.md · L12-L14
observed: |
  <客觀所見，含具體數字/文字/選擇器。禁止形容詞式判斷。>
why_it_hurts: |
  [<準則ID>] <哪種使用者 · 在什麼情境 · 付出什麼代價>
recommendation:
  what: <改哪裡：具體到頁面 + 元件 + 選擇器或可見文字>
  how: <改成什麼：可交辦的具體動作，含建議文案/數值/結構>
  expected_effect: <預期效果，可觀測；若能量化就量化>
effort: S | M | L
confidence: High | Medium | Low
```
````

**欄位規則**

- `id`：全域唯一、遞增，一經指派**不得**變更（回歸驗證要對得上）。
- `evidence`：**至少一項**，且路徑必須是真實存在的檔案（守門會逐一驗）。每項附一句定位說明（紅框在哪、第幾行）。
- `effort`：`S` ≤ 半天、`M` 半天~3 天、`L` > 3 天或需跨團隊。判不準寫 `M` 並在 `confidence` 降級。
- `confidence`：證據直接且充分 = `High`；證據間接或樣本只有一次 = `Medium`；靠單張截圖推論 = `Low`。**`Low` 的 Finding 一律不得標 `Blocker`。**
- 所有自由文字用**繁體中文**；URL、選擇器、程式碼、專有名詞保留原文。

---

## 4. 去重與合併

- **同一根因、多處表現** → 合併成一條 Finding，`evidence` 列多筆，`observed` 說明出現在哪幾處。
- **同一位置、不同根因** → 拆成多條。
- 合併時保留**最小的 id**，並在報告附錄記錄被併入的 id（回歸驗證會查）。

---

## 5. 守門規則（evidence-auditor 據此判定）

| 檢查項 | 標準 |
|---|---|
| evidence-coverage | 每條 Finding 的每個 `evidence` 路徑**檔案實際存在** = **100%** |
| 欄位齊全 | 契約中所有欄位皆非空，`severity` / `category` / `effort` / `confidence` 為合法列舉值 |
| 觀察純度 | `observed` 不含判斷性形容詞（混亂、不直覺、不友善、太慢、很醜）與心理推測 |
| 準則對映 | `why_it_hurts` 開頭有 `[準則ID]`，且該 ID 存在於 `references/ux-heuristics.md` |
| 建議可執行 | `recommendation.what` 能定位到具體元件；`how` 是動作不是願望 |
| 一致性 | `confidence: Low` 不得搭配 `severity: Blocker` |

任一項不通過 → 該 Finding **退回修正或刪除**，不得帶進 `report.md`。
