# CLAUDE.md — crypto-node 開發專案（實作期 AI Agent 規範）

> **專案定位：** 自研的**鏈下索引與事件中繼服務**，介於 RPC 節點商與**多個支付系統（多租戶）**之間。只回答「鏈上發生了什麼」，不判斷「這筆錢屬於哪張訂單」。
> **支援鏈：** Ethereum、BSC、TRON ｜ **執行環境：** Java 21 + Spring Boot 3.5 + PostgreSQL
> **部署位置：** 隨整個 `.claude/` 部署到 crypto-node repo 根目錄。

---

## 0. 運作模式：雙軌驅動（最高優先）

本 repo 有**兩條交付線**，工單來源不同、流程相同：

| 軌 | 交付物 | 工單來源 | 編號 |
|---|-------|---------|------|
| **A · 服務端** | `crypto-node-service`（鏈下索引與事件中繼） | [`plan/2026-08-17-crypto-node-implementation-steps.md`](plan/2026-08-17-crypto-node-implementation-steps.md) 實作步驟企劃書 | **S01 ~ S38** |
| **B · 維運後台** | `crypto-node-web`（前端 + 後台後端） | [`plan/crypto-node-web/backlog.md`](plan/crypto-node-web/backlog.md) 企劃 Task Backlog | **T1a ~ T13c-ii**（19 顆） |

> **兩軌的工單格式不同**：A 軌的 S 步驟已含技術驗收測試；**B 軌的 T 任務是企劃層產出（業務語言），需要開發 planner 先補技術設計（How）** —— 見 §0.1。

接到「執行 S12」或「執行 T7」這類指令時：

1. **讀步驟**：到實作步驟企劃書找該步驟的範圍、驗收測試與涉及的不變量。
2. **planner 拆解**：產出 `plan/task-Sxx-plan.md`，管理 `⏳ 待決 OQ`。
3. **遵守 Rules**：`.claude/rules/` 全部適用，尤其[不變量](.claude/rules/invariants.md)與[已鎖定決策](.claude/rules/locked-decisions.md)。
4. **自我驗收**：依該步驟的驗收測試逐項檢查，全通過才回報。
5. **回填進度**：把完成紀錄寫回實作步驟企劃書（§0.2 範本），並更新 §2 進度總表。

> **回填不是可選的。** 那份文件是活的，`Definition of Done` 第 5 條明訂「本文件已回填完成紀錄」。沒回填 = 步驟未完成。

### 0.1 B 軌（後台）的差異

| 項目 | A 軌（S 步驟） | B 軌（T 任務） |
|------|--------------|--------------|
| 工單內容 | 已含技術範圍與驗收測試 | **只有業務語言**：目標、`Required Spec Sections`、Scope 邊界、對應 AC |
| planner 的工作 | 落到具體檔案與測試 | **先補技術設計（How）**，再落到檔案與測試 |
| 讀規格 | 讀該步驟即可 | **只讀 `Required Spec Sections` 指定的那幾節**，不通讀 60KB 的 spec |
| 驗收依據 | 步驟列出的驗收測試 | **對映的 AC 編號**（spec §1.6） |
| 回填 | 實作步驟企劃書 | `backlog.md` 的任務清單狀態 |

> **B 軌的 `Required Spec Sections` 是上下文預算的核心** —— 企劃已經切好了，**照著讀就不會爆**。看到自己在通讀整份 spec，就是沒照做。

---

## 跨 prompt-setup 職責路由（越界即提示切換）

本範本（`.claude/`）只負責軟體生命週期的**單一階段**。若接到的工作**不屬於本階段職責**——包含 planner 分流出的 OQ 被判定為「其實是他階段的事」——**不要硬接、不要在本階段臆測代答**，而是明確**提示使用者切換到對應的 prompt-setup 範本**，並附一句「為什麼這屬於他階段」。

| 撞到的工作性質（非本職） | 應切換到 | 指令 |
|---|---|---|
| 需求收斂 / 商業價值 / 範圍界定 / Persona / 驗收標準 / 規格 / 任務拆解 | 企劃 | `prompt-setup 專案企劃` |
| 新功能開發（Python / AI UX 稽核平台） | 開發 | `prompt-setup 專案開發 ai-ux-agent` |
| 新功能開發（Java 21 / Spring Modulith） | 開發 | `prompt-setup 專案開發 java` |
| 既有主業務維護 / 修 bug（cx-sports-v2，Java 8 / Boot 2） | 維護 | `prompt-setup 專案維護 cx-sports` |
| 既有加密支付維護 / 修 bug（crypto-payment，Java 21 / Boot 3） | 維護 | `prompt-setup 專案維護 crypto-payment` |
| Java 8→21 / Boot 2→3 版本升級遷移 | 版本管理 | `prompt-setup 版本管理` |
| 已完成網站的 UX 體驗稽核（實際開瀏覽器體驗、產 UX 修改建議報告） | 網站體驗稽核 | `prompt-setup 網站體驗稽核` |
| 既有骰寶辨識維護 / 修 bug（sicbo，Python / YOLO 影像辨識） | 維護 | `prompt-setup 專案維護 sicbo` |
| crypto-node 鏈下索引服務開發（Java 21 / Boot 3.5 / 多租戶） | 開發 | `prompt-setup 專案開發 java crypto-node` |

> **你在這裡：開發 · crypto-node（Java 21 / Boot 3.5）**（表格第 9 列為本職，不適用切換）。
> **跨系統邊界（極重要）：**
> - **下游 `crypto-payment` 不在本專案職責內。** 本服務只負責「照契約提供正確事件」。下游怎麼入帳、怎麼比對訂單、怎麼實作冪等，是它自己的事——**不得代改、不得臆測其行為**。要改契約 → 見 `rules/event-contract.md`，那是雙邊變更。
> - **不做出金／簽章／私鑰**、**不做訂單匹配與帳務**、**不做自建全節點**、**不做歷史全鏈索引**（bigpicture §1.3 非目標，仍完全有效）。
> - 需求若是「幫我改 crypto-payment 的入帳邏輯」→ 切 `prompt-setup 專案維護 crypto-payment`。

---

## 1. 指路（每次開工先看）

### 文件優先序（衝突時的裁決順序）

```
實作步驟企劃書（怎麼做、驗收什麼）  ← 排程與步驟以此為準
        ↑ 承接
開發企劃書（技術取捨 D1~D18、不變量、資料模型、對外契約）  ← 技術決策以此為準
        ↑ 承接
bigpicture（願景與範圍）  ← 多處已被取代，讀前必看其「取代對照表」
```

- **實作步驟：** `plan/2026-08-17-crypto-node-implementation-steps.md`（38 步、驗收測試、進度回填）
- **技術決策：** `plan/2026-08-14-crypto-node-development-plan.md`（**衝突時以此為準**）
- **願景範圍：** `plan/2026-08-14-crypto-node-bigpicture.md`（**§「取代對照表」務必先讀**）
- **多租戶評估：** `plan/2026-08-14-crypto-node-multi-tenant-evaluation.md`
- **RPC 成本分析：** `plan/2026-08-14-crypto-node-rpc-cost-analysis.md`

**B 軌（維運後台）** —— 企劃三件套，衝突時以 `spec.md` 為準：

- **任務清單：** `plan/crypto-node-web/backlog.md`（19 顆 T 任務、DAG、估算、三個跨系統依賴）
- **業務規格：** `plan/crypto-node-web/spec.md`（**R# 業務規則 / E# 邊界情境 / AC 驗收條件** —— 依 `Required Spec Sections` 分節讀，禁 full read）
- **範圍與決議：** `plan/crypto-node-web/brief.md`（In/Out Scope、成功指標 M1~M6、OQ 決議）

### 規範

- **10 條核心不變量（最高紅線）：** [`.claude/rules/invariants.md`](.claude/rules/invariants.md)
- **架構：六角 + Spring Modulith：** [`.claude/rules/architecture.md`](.claude/rules/architecture.md)
- **已鎖定決策（不得自行推翻）：** [`.claude/rules/locked-decisions.md`](.claude/rules/locked-decisions.md)
- **對外事件契約（跨系統）：** [`.claude/rules/event-contract.md`](.claude/rules/event-contract.md)
- **開發流程與步驟回填：** [`.claude/rules/development-workflow.md`](.claude/rules/development-workflow.md)
- **測試政策（兩租戶硬規則）：** [`.claude/rules/testing.md`](.claude/rules/testing.md)
- **後台前端規範（B 軌）：** [`.claude/rules/web-frontend.md`](.claude/rules/web-frontend.md)
- **後台串接規範（B 軌）：** [`.claude/rules/web-integration.md`](.claude/rules/web-integration.md)
- **Flyway migration 版本號（時間戳）：** [`.claude/rules/flyway-migration.md`](.claude/rules/flyway-migration.md)
- **Java 21 / Boot 3.5 風格：** [`.claude/rules/coding-style.md`](.claude/rules/coding-style.md)
- **分支與提交：** [`.claude/rules/git-workflow.md`](.claude/rules/git-workflow.md)

---

## 2. 不可妥協紅線

1. **10 條不變量是正確性的定義**（`rules/invariants.md`）。每一條都必須有自動化測試，Code Review 以此為檢查清單。**違反不變量 = block，沒有例外。**
2. **租戶隔離（I8）是正確性問題，不是功能問題。** 違反即租戶資料洩漏，可能構成法遵事故，且**在單租戶測試環境下 100% 測不出來**。所有整合測試一律以 `tenant-a` / `tenant-b` 兩租戶為基準環境（`rules/testing.md`）。
3. **對外契約不可片面變更**（`rules/event-contract.md`）。`sequence` 語意、`idempotency_key`、`tenant_id` 不接受呼叫端指定——這些改了會讓下游靜默出錯，而下游在**不同 repo**。
4. **架構分層不可破**（`rules/architecture.md`）：**Domain 零框架依賴**——不得 import `org.springframework.*`（含 Modulith 註解）、`jakarta.persistence.*`、Jackson、Lombok。依賴只能由外往內。模組間禁止直接注入彼此的 Service，走事件。
   > **但 I1 優先於架構通則**：`@ApplicationModuleListener` 是 `AFTER_COMMIT` + `REQUIRES_NEW`，**區塊四項寫入不得用它跨模組拆開**（`architecture.md` §4）。
5. **已鎖定的架構決策不得自行推翻**（`rules/locked-decisions.md`）：不做 WebSocket、不做 Webhook 推送、不做 Reorg 回溯、不引入 web3j / MQ / Quartz、單一部署產出物。要翻案 → 停手，回報使用者走決策流程。
6. **範圍紀律**：只做實作步驟企劃書列出的內容，不做「順便加的」功能、不為已移除的範圍（WebSocket / Webhook / `reorged`）留接縫。
   > **判準是「這個抽象隔離的是哪一個已知的變動源」**（`rules/coding-style.md` §8）。Ports、分層、模組邊界隔離的是**已知會發生**的框架與技術變動 → **必做，缺了才是缺陷**；為不存在的變動源而建 → 不做。**結構性設計不足與投機性複雜度都是缺陷。**
7. **後台的內網邊界會靜默失效**（B 軌，`web-integration.md` §2）：nginx 之後，crypto-node 服務端的「只允許內網網段呼叫 `/admin/**`」對所有請求一律放行。**邊界必須由 nginx 執行，且服務端網段過濾不可再計入防線**。後台後端**不得成為 Admin API 的公開代理**，且必須自行完成權限與租戶範圍判定。
8. **後台不得成為業務資料的第二個真實來源**（B 軌，R11）：租戶／地址／訂閱者／交易／事件一律以 crypto-node 為唯一來源。後台自有資料**只有四類**（使用者帳號、權限指派、操作紀錄、開通檢核狀態）。
9. **步驟完成必須回填**實作步驟企劃書（A 軌）或 `backlog.md` 任務狀態（B 軌），且既有測試不得有任何一個變紅。

---

## 3. ⚠ 執行環境版本：本範本以 Spring Boot 3.5 為準（覆蓋 plan D18）

**這是本範本與 plan 唯一的刻意分歧，讀 plan 時會撞到，先講清楚：**

| 來源 | 版本 | 說明 |
|------|------|------|
| **本範本（以此為準）** | **Java 21 + Spring Boot 3.5** | 使用者於 2026-08-17 明確指定 |
| plan D18 | Java 21 + Spring Boot 4.1 | 理由：3.5 OSS 支援已於 2026-06-25（3.5.16）終止，無商業訂閱即無安全修補 |

**Java 21 兩邊一致，只有 Boot 版本不同。**

依此分歧，以下事項需注意：
- **依賴版本一律鎖定** Boot 3.5.x BOM，不要抄 plan 或網路上 Boot 4 / Spring Framework 7 的寫法。
- Boot 3.5 對應 **Spring Framework 6.2**、Jakarta EE 10。Boot 4 移除／改名的 API 在 3.5 仍然存在——**反之亦然**，Boot 4 才有的 API 在這裡不可用。
- plan D18 提到的組織層影響（`crypto-payment`、Boot 2→3 遷移專案的安全支援問題）**不是本專案職責**，但若使用者問起，如實轉述 plan 的分析。
- 若日後決定改回 4.1，那是一次**獨立的升級 TASK**，不是順手改版本號。

---

## 4. 可用工具與 Sub-agents

- **自訂 Skills**：`/step-run`、`/arch-check`、`/invariant-check`、`/mock-rpc`、**`/vue3-console`（B 軌前端）**、`/strategic-compact`
- **Sub-agents**：

| Agent | 職責 |
|-------|------|
| `planner` | 步驟拆解、假設驗證、OQ 管理（含驗收測試計畫） |
| `code-reviewer` | 通用 Java Clean Code、投機性複雜度、資源與並發 |
| `arch-guard` | **架構邊界守門**：Domain 純度、依賴方向、Modulith 模組邊界、事件與 I1 的衝突 |
| `invariant-guard` | **I1~I10 守門**：改動是否破壞不變量、對應測試是否存在 |
| `tenant-isolation-reviewer` | **I8 / I9 專責**：租戶隔離與越權路徑（最關鍵） |
| `contract-reviewer` | 對外拉取 API 契約與下游相容性 |
| `web-reviewer` | **B 軌守門**：後台 UI 行為契約、租戶範圍、憑證處理、內網邊界、Admin API 串接 |
| `build-error-resolver` | Maven / Spring Boot 3.5 編譯與啟動錯誤診斷 |

**派工原則：** 動到 package 結構 / 新增類別 / 跨模組呼叫 / 引入相依 → `arch-guard`；動到掃描迴圈 / 事務 / 冪等 → `invariant-guard`；動到查詢 / 認證 / 歸屬解析 → `tenant-isolation-reviewer`；動到 `/v1/events` 或事件欄位 → `contract-reviewer`；**動到後台前端 / 後台後端 / Admin API 呼叫 → `web-reviewer`**。五者可平行。

---

## 5. 提交前固定動作

1. `./mvnw test` 綠燈（含 `*IT.java` 整合測試，兩租戶 fixture；含 `ArchitectureTests`）。
2. 靜態檢查通過（Checkstyle／SpotBugs）。
3. 動到類別 / package / 相依 → 跑 `/arch-check`；涉及不變量 → 跑 `/invariant-check`。
4. 涉及對外契約 → `contract-reviewer` 放行，並確認是否需通知下游。
5. 檢查 OQ：`plan/` 中無「⏳ 待決」（否則 git hook 攔截）。
6. **回填實作步驟企劃書**的完成紀錄與進度總表。
