# lion-service 資安掃描範本 — 使用指南

> 一句話定位：**掃 lion-service 的原始碼與設定，產一份維護工程師拿了就能修的報告。不碰線上，不改 code。**

---

## 部署

```bash
prompt-setup 資訊安全 lion-service
```

部署到 `lion-service` repo 根目錄。**它已經有自己的 `.claude/`（開發用），要先備份或改用 worktree** ——
`prompt-setup --force` 是乾淨取代，會清掉原有的那套。

> 建議做法：另開一個 worktree 或另 clone 一份專做資安掃描，避免跟開發用的 `.claude/` 互相覆蓋。

---

## ⚠ 三件開工前必知

### 1. 這是靜態稽核，不是滲透測試

`scan-target.md` 宣告的模式是**原始碼與設定的靜態稽核**。在這個模式下：

**不發 HTTP、不啟服務、不連 DB/Redis/ES、不跑掃描工具打網路目標、不用真實憑證。**

要做動態測試，先拿書面授權 + 專用測試環境，更新 `scan-target.md` 的授權欄。
未更新前一律視為越界（`rules/scope-safety.md` 紅線 1）。

### 2. 只產報告，不改 lion-service 的 code

唯一可寫入的位置是 `sec-reports/<日期>/`。即使看到「顯然該修」的漏洞也不改。

三個理由：沒有完整業務上下文改了可能壞別的；修復要走 lion-service 自己的流程（它有自己的
`.claude/`、測試與 review）；**稽核者同時是修復者，等於自己審自己，報告就失去意義了。**

### 3. 誤報比漏報更傷

AI 做資安掃描最大的失敗模式不是漏掉漏洞，是**產出一堆看起來很合理的誤報**。

一份 30 條 finding、其中 20 條是誤報的報告，結果是維護方**連真的那 10 條也不看了**。
所以本範本把「對抗式驗證」做成獨立且不可省的階段 3 —— `finding-verifier` 的立場是
**證明這條 finding 是假的**，證不倒才放行。

---

## 這個平台最特別的一條風險

lion-service 是**包網（白標）**平台：一套系統服務多家包網商，彼此是商業競爭對手。

> **A 包網商能看到 B 包網商的任何東西，就是事故。**
> 不只是資料外洩 —— 是把客戶的營運機密交給他的競爭對手。

而且它有一個很糟的性質：**在單一包網商的測試環境裡 100% 測不出來。**
功能全過、測試全綠，上線才爆。它不會被既有的開發流程攔到，只能靠這一軸。

所以：

- `tenant-isolation-auditor` 是優先序最高的 auditor
- 跨 `platformId` 失守一律判 **CRITICAL**，即使只是唯讀
- 「在單平台測試環境測不出來」的問題一律**升一級**

`platformId` 在這個 repo 有約 5,800 處引用，這條軸的工作量最大，但也最值得。

---

## 八條掃描軸

| 軸 | 看什麼 | 誤報陷阱 |
|---|---|---|
| **包網商隔離** | `platformId` 能否被請求方影響 | 下層沒檢查但上層／AOP 已覆寫 |
| **過濾器繞過** ⚠ | 那道防線**擋不擋得住** —— 提早放行分支、路徑比對方式 | 反過來才是陷阱：看到有 filter 就當有防護 |
| **認證授權** | 功能級、**物件級**、代理層級、多後台一致性 | 認證可能在 SecurityConfig／Filter／nginx，不在註解上 |
| **金流** | 金額可控性、異動時序、鎖、冪等、精度 | 純統計用 `double` 是規範允許的 |
| **注入** | MyBatis `${}`、上傳、路徑穿越、反序列化、SSRF | `${}` 多數是欄名／排序且來自內部常數 |
| **機密與設定** | 硬編憑證、Log 脫敏、錯誤外洩、端點暴露 | `toString()` 可能已排除敏感欄位 |
| **第三方回調** | 驗簽涵蓋範圍、IP 白名單在哪一層、防重放、冪等 | 應用層白名單在 nginx 之後可能形同虛設 |
| **依賴 CVE** | 版本 + **受影響元件是否實際被使用** | CVE 存在 ≠ 本專案受影響（誤報率最高） |

詳見 `references/scan-axes.md`。

---

## ⚠ 已發生過的事故：filter 繞過

**這條不是理論風險。** 認證 filter 存在繞過漏洞而被實際入侵，
成因是**帶特定副檔名的請求被直接放行、完全不做檢查**。

它難抓的地方在於 —— **它偽裝成「有防線」**：filter 確實存在、確實在檢查登入。
任何「看到上游有 filter 就判誤報」的稽核紀律，都會直接放過它。

所以本範本做了一個刻意的例外：

> 判「上游 filter 擋掉了 → 誤報」之前，**必須先過防線有效性三問**：
> ① 請求真的會走到那段檢查嗎（有無提早放行分支）？
> ② 是精確比對還是 `startsWith` / `endsWith` / `contains`？有無正規化？
> ③ 檢查失敗後有沒有真的 `return`？
>
> 三項都確認才可判誤報，且理由要寫成「在哪一行、怎麼比對的」。
> 任一項確認不了 → 不判誤報，交 `filter-bypass-auditor`。

**這是本範本唯一一處「寧可留下誤報，也不要放過」的例外。**

`filter-bypass-auditor` 的主要產出是一張**放行分支盤點表** ——
即使某幾條判不出可不可達，那張表本身就能直接當人工審查清單交給熟悉該模組的工程師。

---

## 這套規範在防什麼

| 規範 | 防的事 |
|---|---|
| `scope-safety.md` 紅線 1 | 為了「驗證一下」而去打線上，打掛生產或碰到真實玩家資料 |
| `scope-safety.md` 紅線 3 | 把找到的 API Key 完整貼進報告 —— 洩漏範圍從一個 repo 擴大到所有讀報告的人 |
| `scope-safety.md` 紅線 6 | 宣稱「全面掃描完成」但只看了三成，讓人誤以為剩下七成是安全的 |
| `evidence-discipline.md` §3 | 報一堆程式碼裡看起來不安全、但外面根本打不到的東西 |
| `false-positive.md` | 21 處 MyBatis `${}` 整批報成 SQL injection，其中 18 處是內部常數 |
| `false-positive.md` §4 | 重工 SonarQube 已經會報的規則型缺陷，把報告洗版洗到看不到重點 |
| `false-positive.md` §2.5 | **看到有 filter 就判「上游擋掉了」，放過真正被利用過的繞過路徑** |
| `report-standard.md` §3 | 寫「建議加強驗證」這種沒人能照著做的修復建議 |
| `report-standard.md` §4 | 照嚴重度排優先序，結果第一條要重構整個模組，沒人動得了 |
| `severity-rubric.md` | 全部標 CRITICAL，等於沒有分級 |

---

## 快速開始

```bash
# 1. 先確認標的與授權範圍
cat .claude/scan-target.md

# 2. 完整掃描（四階段）
/sec-scan

# 3. 或只看一條軸
/sec-quick 隔離

# 4. 維護方修完之後
/sec-verify sec-reports/2026-09-24/report.md
```

---

## 四階段與九個 Agent

```
階段 1 盤點攻擊面        recon                          ← 沒做完不准進階段 2
階段 2 分軸掃描（平行）   tenant-isolation-auditor
                        filter-bypass-auditor
                        authz-auditor
                        money-flow-auditor
                        injection-auditor
                        config-exposure-auditor
                        dependency-cve-auditor          ← 產出「候選 finding」
階段 3 對抗式驗證        finding-verifier               ← 不可省
階段 4 產出報告          report-writer
```

auditor **不驗證自己的產出**，這是刻意的分離 —— 提報者與驗證者是同一個角色時，驗證形同虛設。

---

## 報告長什麼樣

```
lion-service/sec-reports/2026-09-24/
├── report.md              八個章節（含待查、已排除、掃描限制三章）
├── recon.md               攻擊面盤點
└── findings/
    └── SEC-001-xxx.md     逐條，含證據、攻擊路徑、修復方向、驗證指令
```

**每條 finding 都寫成可直接當工單的形狀。** 修復方向盡量對應到 lion-service 自己既有的規範條文
（`lion-service/.claude/rules/security.md`、`patterns.md`、`checks/`）—— 對得上，維護方就知道
這不是外人另訂一套標準，而是「你們自己的規則在這裡沒被遵守」，接受度最高。

---

## 檔案結構

```
.claude/
├── CLAUDE.md                     入口：三種模式、四階段、紅線、派工
├── scan-target.md                ★ 標的宣告與授權範圍（開工前先確認）
├── rules/
│   ├── scope-safety.md           ★ 六條紅線（不碰線上、不改 code、報告不得含機密）
│   ├── evidence-discipline.md    ★ 七個必備欄位、攻擊路徑、可達性硬要求
│   ├── false-positive.md         ★ 對抗式驗證、六種易誤判情況、**防線有效性三問**、不重工 Sonar
│   ├── report-standard.md        報告八章、修復方向可執行、優先序四象限、交接
│   └── scan-workflow.md          四階段、三種模式、OQ 兩條硬規則
├── references/
│   ├── threat-model.md           包網威脅模型：資產、攻擊者、六條信任邊界、**已知事故**
│   ├── scan-axes.md              七條軸各自的判準與誤報陷阱
│   └── severity-rubric.md        嚴重度 × 信心 × 修復成本
├── agents/                       10 個：recon + 7 auditor + verifier + report-writer
├── skills/                       /sec-scan /sec-quick /sec-verify /strategic-compact
├── templates/                    finding 與 report 範本
└── settings.json                 唯讀權限、禁網路與 DB 指令（**唯一進版控的檔案**）
```

---

## 一句話總結

**先畫地圖再掃，掃完一定要有人反過來證明它是假的，最後交一份對方看得懂、修得動的報告。**
