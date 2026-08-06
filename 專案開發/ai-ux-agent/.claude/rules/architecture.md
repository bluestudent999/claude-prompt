# 架構規範 — 管線與分層（Pipeline & Layering）

> 本文規範 AI UX Audit Platform 的架構紀律。核心是一條**單向管線**與**可抽換的 Port/Adapter 接縫**，以及貫穿全專案的「非 RPA / 證據優先」紅線。

---

## 1. 核心管線（不可繞過的軸線）

```
Browser Control → Observation → Reasoning (LLM) → UX Evaluation → Reporting
```

- 資料只能**單向**沿管線流動：上游產出 → 下游消費。下游不得回頭改上游的原始證據。
- 每個階段的產出是下游的**唯一輸入契約**；不得跨階段偷讀彼此的內部狀態。
- **紅線：** 禁止「Click → Assert → Pass」式測試框架思維。Agent 的目的是**理解網站、完成任務、發現問題**，不是自動點擊（Spec §15）。

| 階段 | 職責 | 產出契約 |
|------|------|---------|
| Browser Control | 開站、等頁面穩定、導航、互動 | 穩定的頁面狀態 |
| Observation | 蒐集多模態證據（見 §3） | `Observation`（含證據引用 + 落地路徑） |
| Reasoning | LLM 站在 Persona 視角理解頁面、完成 Task | 推理結論（引用 Observation 證據） |
| UX Evaluation | 依 UX 規則產出 Issue | `Issue[]`（四欄位齊全） |
| Reporting | 彙整成報告並落地 | `Report`（Markdown / HTML） |

---

## 2. 分層與依賴方向（Ports & Adapters）

外部相依一律以 **Port（介面）+ Adapter（實作）** 隔離，讓推理後端、瀏覽器、報告輸出可抽換（對映 dev-plan 的 E1→E2→E3 演進：雲端 API → 本地 + API 備援 → 本地大模型）。

- **Domain / Core（純邏輯）**：Persona、Task、Observation、Issue、Report、UX Rule 的模型與規則。**禁止**依賴 Playwright、LLM SDK、HTTP、檔案系統等**外部資源型技術**（純運算函式庫如 `dataclasses`/`enum`/`pydantic` 不在此限；界線與判定三問見下方 §2 依賴紅線）。
- **Ports（介面，屬 Core）**：由 Core 宣告「需要什麼能力」。
  - `InferencePort` — LLM 推理（E1 雲端 / E2 本地 / 混合備援皆為其 Adapter）。
  - `BrowserPort` — 瀏覽器控制與觀察擷取（Playwright Adapter）。
  - `ReportSinkPort` — 報告落地（檔案系統資料夾，路徑可設定）。
- **Adapters（實作，屬 Infrastructure）**：實作 Port、呼叫具體技術。可有多個（Real / Stub / Cloud / Local）。
- **依賴反轉：** Infrastructure 依賴 Core 定義的 Port，**不得反向**讓 Core 依賴 Adapter。

### 依賴紅線（arch-guard 靜態守門）
1. Core / Domain 檔案**不得** `import playwright`、LLM SDK、`requests`/`httpx`、`os`/檔案 I/O 等**外部資源型技術**（碰 I/O、隨環境可替換、或非確定者），一律走 Port。
   - **此條不禁純運算函式庫**：`dataclasses`、`enum`、`typing`/`Protocol`、`re`、`pathlib`（僅路徑運算）、以及 **`pydantic`**（純建模/驗證，coding-style §3 明文允許）可留在 Core。
   - **判定三問**（任一「是」→ 須走 Port；三個都「否」→ 可留 Core）：① 做 I/O / 碰外部資源？② 會隨環境（雲端/本地/CI）換實作？③ 引入非確定性（網路/時間/亂數）？
2. 推理、瀏覽器、報告落地一律走 Port，**不得**在 Core 內直接 new 具體 Adapter 或呼叫 SDK。
3. 憑證只從設定/環境變數注入 Adapter，**不得**出現在 Core 或任何進版控檔案（見 security-audit §1）。

---

## 3. 觀察策略（Observation Strategy）

結論不可只靠 Screenshot，應綜合多模態證據（Spec §9）：Screenshot、DOM、Accessibility Tree、Network、Console、Performance Timing。

- **階段落點（dev-plan §6）：**
  - **E1**：僅落地 **Screenshot + DOM** 兩項（最小子集）。
  - **E2 起**：補齊 A11y / Network / Console / Performance 全集。
- 所有證據**落地到磁碟**（不常駐記憶體），並保留可被 Issue 引用的穩定路徑（對映 E2 M4/32GB 記憶體紀律，dev-plan §3.4）。

---

## 4. 資料契約（Core Domain 模型）

| 概念 | 必要欄位（Spec 對映） |
|------|---------------------|
| `Persona` | 身分類型（Visitor / New / Registered / VIP / Mobile…）；E1 = Visitor + 已登入使用者（§11） |
| `Task` | Goal / Preconditions / Steps / Success Criteria / Expected Result；**必須可重複執行**（§12） |
| `Observation` | 證據種類 + 內容/落地路徑 + 擷取當下頁面識別（§9） |
| `Issue` | **Severity / Category / Evidence / Recommendation**（四欄位齊全，§10）；`Severity ∈ {Blocker, Major, Minor, Suggestion}` |
| `Report` | Executive Summary / Overall Score / UX Issues / Recommendations / Screenshots（E1 五要件）；Completed/Failed Tasks / Timeline 為 E2（§13、dev-plan §5.5） |

> **契約鐵律：** `Issue.Evidence` 必須指向真實存在的 `Observation`。無法連結證據的 Issue 不得產生 —— 這是「AI Native 而非 RPA」的成敗點。

---

## 5. 階段能力邊界（E-Phase Scope，dev-plan §6）

| 能力 | E1 Demo | E2 本地 M4 | E3 DGX Spark |
|------|:------:|:---------:|:------------:|
| Observation:Screenshot+DOM | ✅ | ✅ | ✅ |
| Observation:A11y/Network/Console/Perf | — | ✅ | ✅ |
| Persona | 1（+登入） | 5 | 5+ 自訂 |
| Report:Markdown / HTML | MD | MD+HTML | +歷史比較 |
| 定時排程 | — | 本地（選配） | CI/CD |
| Multi-Agent | — | — | ✅ |
| 推理後端 | 雲端 API | 本地+API 備援 | 本地大模型平行 |

- **紅線：** 開發時**不得**在當前階段實作後續階段能力（越界 = arch-guard `VIOLATION`）。
- DGX Spark（E3）僅為**執行環境**，不在其上開發（dev-plan §4.5）。
