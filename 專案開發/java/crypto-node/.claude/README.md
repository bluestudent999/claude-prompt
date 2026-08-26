# crypto-node 開發範本 — 使用指南

**crypto-node**：自研的鏈下索引與事件中繼服務，介於 RPC 節點商與**多個支付系統（多租戶）**之間。支援 Ethereum / BSC / TRON。

只回答「鏈上發生了什麼」，**不判斷「這筆錢屬於哪張訂單」**。

---

## 部署

```bash
cd /Users/joel_java/java/crypto-node
prompt-setup 專案開發 java crypto-node --force
claude
```

> ⚠️ 目前 crypto-node 部署的是 **SDRP 範本**（`專案開發/java`），內容講的是 alignment-evaluator、Confidence Score、eval-m1——**跟本專案無關**。用 `--force` 乾淨取代。

---

## 快速開始

本 repo **雙軌推進**：

| 軌 | 交付物 | 工單 | 來源 |
|---|-------|------|------|
| **A · 服務端** | `crypto-node-service` | **S01 ~ S38** | 實作步驟企劃書 |
| **B · 維運後台** | `crypto-node-web`（前端 + 後台後端） | **T1a ~ T13c-ii**（19 顆） | `plan/crypto-node-web/backlog.md` |

兩軌共用同一套流程，差別在讀哪份工單與驗收依據（A 軌看驗收測試，B 軌看**對映的 AC 編號**）：

```
/step-run S01        ← A 軌：執行服務端步驟
/step-run T7         ← B 軌：執行後台任務（planner 會先補技術設計 How）
/arch-check          ← 架構邊界檢查（Modulith 模組 + 六角分層 + Domain 純度）
/invariant-check     ← 盤點 10 條不變量的測試覆蓋
/mock-rpc            ← Mock RPC 情境腳本設計
/vue3-console        ← B 軌：Vue 3 + Element Plus 實作模式（對映 spec 的 R#/E#）
/strategic-compact   ← 步驟完成後壓縮 context
```

直接說「執行 S12」也可以，Claude 會走同一套流程。

---

## 架構：六角 + Spring Modulith（D19）

**目的很直接：讓下一次 Spring Boot 升級只衝擊最外層 Adapter，Domain 零變更。** 本專案已經因 Boot 版本問題耗掉一輪決策成本，這套架構是對抗「框架升級無限輪迴」的結構性解法。

```
[ Infrastructure / Adapter ]  ← Spring Boot、JPA/JDBC、HTTP、Web、排程
            │ 依賴
            ▼
[ Application ]               ← Use Case、Ports、事務邊界
            │ 依賴
            ▼
[ Domain ]                    ← 純 Java。零框架。
```

**Domain 零框架是硬規則**：不得 import `org.springframework.*`（**含 Modulith 註解**）、`jakarta.persistence.*`、Jackson、Lombok。Domain 是不變量的家——確認深度、地址正規化、冪等鍵組成、金額換算，這些跟 Spring 幾版無關。

### ⚠ 兩個必須先知道的坑

**① `@ApplicationModuleListener` 與 I1 直接衝突**

它的語意是 `@Async` + `@TransactionalEventListener(AFTER_COMMIT)` + `@Transactional(REQUIRES_NEW)`——**在原事務 commit 之後、以新事務執行**。而 I1 要求區塊四項寫入在**單一事務**。

所以：**區塊寫入路徑不得用 Modulith 事件跨模組拆開**。若模組切分導致四項寫入落在不同模組，那是**模組切分錯了**，要收攏，不是改用事件把事務拆開。事件只用在可最終一致的動作（metrics、稽核、觸發對帳、告警）。

**② 兩個 Outbox 不要搞混**

| | Modulith Event Publication Registry | `events` 表 |
|---|---|---|
| 用途 | 模組間**內部**事件的最終一致性 | **對外業務事件**，下游拉取（D16） |
| 契約 | 內部，可自由演進 | **對外契約，不可片面變更** |

看到「既然 Modulith 有 Outbox，`events` 表是不是多餘的」→ 停手。`events` 表是對外契約的載體與下游游標依據。

### 判準：這個抽象隔離的是哪一個「已知的變動源」？

範本**沒有**「反過度設計」這種規則——那個框架會讓人下意識懷疑抽象，而這個專案的抽象正是價值所在。取而代之的是一條判準（`coding-style.md` §8）：

| 答得出變動源 | 答不出，只能說「以後可能會…」 |
|---|---|
| **結構性設計 → 必做，缺了才是缺陷** | **投機性複雜度 → 不做** |
| Outbound Port（Boot 版本、JPA↔JDBC、HTTP client）<br>Domain 零框架（框架世代）<br>鏈別 Adapter（已知三實作）<br>Modulith 模組（D11 言明日後可能拆） | Port 之上再疊 Factory / 註冊表<br>兩個 URL 的 Failover 造外掛框架<br>單一常數造設定載入器<br>為已移除的 WebSocket / Webhook / `reorged` 留接縫 |

**「現在只有一個實作」不構成質疑 Port 的理由**——那是用今天的視角砍掉明天的保險，而這個專案已經證明那個「明天」會來。

**兩個方向都會出事**：結構性設計不足 → 升級地獄（本專案要避免的）；投機性複雜度過多 → 沒人看得懂。`arch-guard` 管前者（包含**該有 Port 卻沒有**），`code-reviewer` 管後者，且明令不得以「只有一個實作」否決 Port。

實作量的節制仍然存在，但只針對**單一方法／類別內部**的複雜度，不用來質疑分層。

### 模組切分尚未定案

plan 沒有定義模組邊界。`architecture.md` §3 依「不變量的歸屬」提出了 8 個模組的**提議**（`chain` / `scanning` / `attribution` / `event` / `delivery` / `tenant` / `reconciliation` / `admin`）——**S01 實作前必須列為 OQ 請你確認**。

### 邊界靠測試守，不靠自律

`ArchitectureTests`（`modules.verify()` + 兩條 ArchUnit 分層規則）**S01 就要進 CI**，並列入 DoD 第 5 條。架構測試不是後補項——沒有它，邊界撐不過三個月。

---

## B 軌：維運後台（crypto-node-web）

讓維運人員用網頁完成 crypto-node 的設定與事故處置 —— 開通租戶、匯入地址、發下游 API Key、必要時止血。**Email + 2FA、三級權限（Viewer / Operator / Admin）、僅限內網／VPN。**

### ⚠ 最高紅線：內網邊界會靜默失效（R13a）

crypto-node 服務端的「只允許內網網段呼叫 `/admin/**`」是**依連線來源位址判斷、完全忽略代理標頭**。決議 3 之後對外由 nginx 收口 —— 服務端看到的來源恆為 nginx 自己（落在內網網段）→ **對所有請求一律放行**。

**不會報錯、不會有 log、測試不會紅。**

三項缺一不可：① nginx 只允許內網／VPN 存取 `/admin/**`；② 不得有繞過 nginx 直達服務的路徑；③ **服務端網段過濾不可再計入防線**（必須明文記錄，否則有人以為還有兩道而各自放鬆）。

### 三個最容易犯的錯

| 錯誤 | 後果 | 出處 |
|---|---|---|
| **API 失敗被渲染成空清單** | 值班員誤讀為「沒有資料」 | E1 |
| **Operator 做出的半成品看起來像完成** | 下游收到的門鈴**沒有可驗證的簽章**，且全程沒被擋 | R1a② |
| **前端隱藏按鈕就當授權完成** | 直接打 API 即繞過 | R2 + web-integration §5 |

### 已決的技術決策（2026-08-26）

| 項目 | 決議 |
|---|---|
| 前端技術棧 | **Vue 3 + Element Plus + Pinia + Vite** |
| 前端落點 | **同 repo**：`crypto-node-web/`，與 `crypto-node-service`、`crypto-node-flyway` 同層 |
| 後台與服務的連接 | **內網 RESTful**（後台後端代為呼叫 Admin API） |
| 第二因素 | **TOTP**；種子加密存 DB、漂移 **±30 秒**、**不做備援碼**（牴觸 E5） |
| 工作階段 | **Spring Session + JDBC**（不引入 Redis）。⚠ **禁止 stateless JWT** |
| 快取 | **首期不做跨請求快取**；只允許單一請求內去重 |
| 逐台能力 | `application.yml` 設 `node-id`，衝突拒絕啟動。**定址手段待確認** |

> ⚠ **連接方式的後果**：內網 RESTful 就是企劃警告的「代為呼叫」—— **服務端的網段過濾對後台路徑永遠放行**。
> 於是 **nginx 三項成為唯一防線**，且**後台後端的授權判定不是「多一道」，它是那一道**。
> Admin API client 的實作要求（Port 隔離、逾時、禁 retry、錯誤分類）見 `rules/web-integration.md` §2.5。

### 前端技術棧細節

`Vue 3 + Element Plus + Pinia + Vite`。**Vue 2 → Vue 3 是升級不是換框架** —— 組織既有的 Vue 心智模型直接可用。

> ⚠ **隨之而來的最高風險：抄到 Vue 2 寫法。** 組織有兩個 Vue 2 專案在旁邊（cx-sports / crypto-payment），網路教學也大量是 Vue 2。這與 Boot 3.5 誤抄 Boot 4 是同一類錯誤 —— `web-reviewer` 的**第一個檢查項（A0）**就是掃這個。
> 對照表見 `rules/web-frontend.md` §1，實作模式見 `/vue3-console`。
> **不要去改 cx-sports / crypto-payment 的 vue2 skill** —— 那兩個專案仍在 Vue 2，那些 skill 對它們是正確的。

**仍待決（OQ-9）**：前端落點（同 repo 目錄 vs 獨立 repo）、後台與服務的連接方式、第二因素形式、工作階段管理、快取策略、逐台狀態能否純靠 nginx。**未決前禁止開始寫對應的業務程式碼。**

---

## ⚠ 三件開工前必知

### 1. 版本基準：Java 21 + Spring Boot 3.5（覆蓋 plan D18）

| 來源 | 版本 |
|------|------|
| **本範本（以此為準）** | **Java 21 + Spring Boot 3.5** |
| plan **D18** | Java 21 + Spring Boot **4.1** |

Java 21 兩邊一致，**只有 Boot 版本不同**。使用者於 2026-08-17 明確指定 3.5。

**實務影響**：依賴鎖 Boot 3.5.x BOM（對應 Spring Framework 6.2 / Jakarta EE 10）。**不要抄 plan D18 或網路上的 Boot 4 / Framework 7 寫法**——這是 `code-reviewer` 的第一個 CRITICAL 檢查項。

D18 記載的背景（3.5 OSS 支援已於 2026-06-25 隨 3.5.16 終止、無商業訂閱即無安全修補）仍然成立，只是使用者接受了這個取捨。

### 2. bigpicture 是陷阱，先讀它的「取代對照表」

`bigpicture` 描述了 **WebSocket 雙通道、Webhook Dispatcher、Reorg 引擎、`payment.reorged`、`confirmations` 欄位** —— 這些**全部已被 D2 / D16 / D17 / D4 取代**。

**文件優先序**：實作步驟企劃書（排程與步驟）→ 開發企劃書（技術決策，**衝突時以此為準**）→ bigpicture（願景範圍）。

bigpicture 仍完全有效的段落只有：§1.3 非目標、§2.3 假幣與零金額過濾、§4 支援鏈與規格、§6 維運與告警、§8 風險、§9.1 灰度上線策略。

### 3. 所有整合測試一律兩租戶

`tenant-a` / `tenant-b`，各含專屬地址與各自的訂閱者。

**理由**：租戶隔離的 bug 在單租戶環境下 **100% 測不出來**。少了 `WHERE tenant_id = ?`、拉取 API 忘記過濾、歸屬解析寫錯 —— 只有一個租戶時全部「正常」，第二個租戶上線就是**資料洩漏**。

不是「另外加幾個隔離測試」，而是**把兩租戶設為所有測試的預設 fixture**。

---

## 這套規範在防什麼

**① 10 條不變量是正確性的定義**
不是建議、不是最佳實務。每條都必須有自動化測試，Code Review 以此為檢查清單。`invariant-guard` 會**實際跑測試**驗證，不接受「應該有測試」。

**② I8（租戶隔離）是法遵風險，不是功能問題**
`tenant-isolation-reviewer` 專責這一條，偏誤方向是從嚴——判不準就 block。它會逐一檢查每個查詢的租戶過濾，並拒絕「呼叫端會傳對的 tenantId」這種辯護（授權範圍必須由伺服器端從認證推導）。

**③ 已鎖定的決策不得自行推翻**
D2/D3/D4/D9/D10/D11/D13/D16/D17 都有完整推導。最常見的誤觸是「加個 WebSocket 會更即時」「Reorg 總得處理吧」「用 web3j 比較省事」——`rules/locked-decisions.md` §4 有誤判對照表。

**④ 對外契約破了下游不會報錯**
下游各支付系統在**不同 repo**。改 `idempotency_key` 組成規則 = 下游去重表全失效 = 重複入帳。`contract-reviewer` 會擋下並要求你去協調，不代改下游。

**⑤ 一次一個步驟，且必須回填**
步驟的粒度就是驗收與回退的粒度。DoD 第 7 條是「實作步驟企劃書已回填完成紀錄」——沒回填 = 步驟未完成。

---

## Sub-agents

| Agent | 管什麼 | 何時派 |
|-------|--------|--------|
| `planner` | 步驟拆解 + 驗收計畫（含具體測試方法名） | 開始任一步驟前 |
| `code-reviewer` | Java 品質、**Boot 3.5 API 相容**、過度工程、事務與並發 | 一律 |
| `arch-guard` | **架構邊界**：Domain 純度、依賴方向、Modulith 模組、事件與 I1 衝突 | package 結構 / 新增類別 / 跨模組 / 相依 |
| `web-reviewer` | **B 軌守門**：UI 行為契約、租戶範圍、憑證處理、內網邊界、Admin API 串接 | 後台前端 / 後台後端 / Admin API 呼叫 |
| `invariant-guard` | I1~I10 + **實際跑測試驗證** | 掃描迴圈 / 事務 / 冪等 / 高度推進 |
| `tenant-isolation-reviewer` | **I8 / I9 專責** | 查詢 / 認證 / 歸屬解析 / 拉取 API |
| `contract-reviewer` | 對外契約與下游相容性 | `/v1/events` 或事件欄位 |
| `build-error-resolver` | Maven / Boot 3.5 編譯與啟動錯誤 | `mvnw` 失敗 |

五個領域 reviewer 可平行啟動。

---

## 已知的文件內部矛盾（實作到 S12/S19/S23 前必須釐清）

開發企劃書的 **I7** 描述提到「receipt 回 `null` 時正確轉為 `reorged`」，但：

- **D17** 明確取消 Reorg 回溯與確認數狀態機
- bigpicture 取代對照表寫明 **`payment.reorged` 已自契約移除**，狀態機簡化為 `detected`（選用）→ `confirmed`

**這是不變量表未跟上 D17 的殘留。** 本範本的處置：**以 D17 為準**，Receipt 重查回 `null` 或 `blockNumber` 不符 → **不發事件並告警**，而非轉 `reorged`。

實作到相關步驟前，把此矛盾列為 OQ 請使用者確認，並在確認後**回頭修正開發企劃書的 I7 文字**——不要讓下一個 session 再撞一次。

---

## 檔案結構

```
.claude/
├── CLAUDE.md            ← 部署後搬到 repo 根目錄（入口 + 路由 + 版本覆寫聲明）
├── README.md            ← 本檔
├── settings.json        ← 權限 + 開工提醒 + autoMode 邊界
├── rules/               ← 每次 session 自動注入
│   ├── invariants.md          I1~I10（最高紅線）+ I7/D17 矛盾處置
│   ├── architecture.md        六角分層、Ports、Modulith 模組、事件 vs I1、兩個 Outbox
│   ├── locked-decisions.md    D2/D3/D4/D9/D10/D11/D13/D16/D17 + 版本覆寫 + 誤判對照
│   ├── event-contract.md      拉取 API 契約、五條鐵律、變更規則、Admin API、對帳
│   ├── development-workflow.md 文件優先序、38 步驟流程、OQ 規則
│   ├── testing.md             兩租戶硬規則、三層測試、Mock RPC、DoD
│   ├── web-frontend.md        （B 軌）技術棧基準 + UI 行為契約：危險操作、三種狀態、憑證只顯示一次、半成品明示
│   ├── web-integration.md     （B 軌）兩層串接、nginx 內網邊界靜默失效、資料唯一來源、OQ-9
│   ├── coding-style.md        Java 21 / Boot 3.5、相依紀律、大檔讀取、結構性設計 vs 投機性複雜度
│   └── git-workflow.md        分支、commit、MR、AIDD 指標
├── agents/              ← 8 個角色（含 arch-guard、web-reviewer）
└── skills/              ← step-run / arch-check / invariant-check / mock-rpc / vue3-console / strategic-compact
```

---

## 常見問題

**Q：為什麼不用既有的 `專案開發 java`（SDRP）範本？兩邊都用 Modulith 啊。**
Modulith 只是共用的工具，軸線完全不同。SDRP 那套繞著 AI 煞車 Confidence Score、alignment-evaluator、eval-m1 golden set 打轉；crypto-node 的正確性軸線是 **10 條不變量、多租戶隔離（I8 是法遵風險）、跨系統事件契約**，而且有本專案獨有的坑（`@ApplicationModuleListener` 撞 I1、兩個 Outbox 的分辨、Boot 3.5 覆寫 D18）。共用只會讓兩邊都不準。

**Q：下游 `crypto-payment` 出問題也找這套嗎？**
不。本專案只負責「照契約提供正確事件」。下游怎麼入帳、怎麼比對訂單、怎麼實作冪等是它自己的事，**不得代改、不得臆測**。切 `prompt-setup 專案維護 crypto-payment`。

**Q：Domain 只是想 import 一個 Spring 的小工具，不行嗎？**
不行。例外一開就回不去——後續每個新類別都會照抄，三個月後 Domain 就跟框架綁死了，這套架構的價值歸零。需要外部能力就宣告 Port。

**Q：想加 WebSocket / Webhook / Reorg 處理？**
停手。D2 / D16 / D17 都有完整推導。要翻案 → 整理證據成 OQ 回報使用者，決策變更後**回頭更新開發企劃書**再實作。文件不更新的翻案不算數。

**Q：plan 太長讀不完？**
三份共 3935 行，**禁止 full read**。用 `grep -nE "^#{1,3} "` 建標題索引，再 `Read(offset, limit)` 讀需要的段落。`rules/coding-style.md` §7 有指令範例。
