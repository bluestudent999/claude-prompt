# 程式碼風格與規範（Python）

> 本文規範 AI UX Audit Platform 的 Python 代碼風格、命名、型別、註解語言、Log 等級，以及 Context 節省硬性規則。

---

## 1. 格式與工具鏈

- **格式化 / Lint**：使用 **ruff**（format + lint）；縮排 4 空白，遵循專案 `pyproject.toml` 設定。
- **型別檢查**：公開函式與 Port 介面**必須**有型別註解（type hints）；建議 `mypy` 綠燈。
- **Python 版本**：以 **3.12+** 語法為基準（善用 `match` 結構化模式、`|` 型別聯集、`dataclass` / `Enum`）。

---

## 2. 命名規範

- 類別 / Protocol / Enum：`PascalCase`（如 `Observation`、`InferencePort`、`Severity`）。
- 函式 / 變數 / 參數：`snake_case`（如 `collect_dom`、`issue_count`）。
- 常數：`UPPER_SNAKE_CASE`（如 `MAX_RETRY`、`DEFAULT_REPORT_DIR`）。
- 模組 / package：小寫 `snake_case`，不帶連字號。
- **角色後綴一致**：Port 以 `XxxPort`、Adapter 以 `XxxAdapter`、Stub 以 `XxxStub` 命名（對映 architecture §2）。

---

## 3. 不可變性與資料模型

- 值物件 / DTO（`Observation`、`Issue`、`Report`、`Persona`、`Task`）優先使用 `@dataclass(frozen=True)` 或 `pydantic` model，避免意外副作用。
- `Severity` 等固定集合一律用 `Enum`（`Blocker / Major / Minor / Suggestion`），**禁止**裸字串魔術值。
- Core / Domain 模型**禁止**攜帶框架物件（Playwright Page、HTTP client、LLM client）。

---

## 4. 語言與註解規範

- **Docstring 與代碼註解**：一律使用**繁體中文**（專有名詞如 DOM、LLM、API、URL 保留原文）。
- **Log 訊息**：一律使用**英文**，便於蒐集與解析（如 `Observation captured: screenshot+dom`）。
- **Log 等級**：
  - `info`：關鍵管線節點與狀態轉換（如 `Login succeeded, entering member area`）。
  - `warning`：非預期但可自我修復 / 降級 / 容錯（如雲端 API 逾時後改備援）。
  - `error`：阻礙當前 Task 的錯誤，必須帶 traceback 與 context。
  - `debug`：開發調試用，正式環境不輸出冗餘。
- **Log 脫敏（硬規則）**：帳密、Token、Cookie、session 值**嚴禁**明文輸出（見 security-audit §4）。

---

## 5. 例外處理規範（呼應「失敗不靜默」紅線）

- 專案統一以 `UXAuditError` 或其子類拋出領域錯誤；**禁止**裸 `except:` 或吞掉例外（`except Exception: pass`）。
- 管線各階段的可預期失敗（登入失敗、Session 逾時、憑證缺失、API 逾時、目標站不可達）**必須**轉為結構化結果並在報告留痕（dev-plan §2.6），不得靜默中止。
- 重試次數 / 逾時秒數等實作參數為 `defer-to-dev`，但**必須可設定、不可寫死**。

---

## 6. 大檔案讀取策略（Context 節省硬規則）

當單一代碼檔超過 300 行，一次性 Full Read 會耗費大量 Token。

- **硬規則**：檔案 **> 300 行禁止 Full Read**（不帶 offset/limit 的整檔讀取）。
- **流程**：先 `grep -n` 定位關鍵函式行號 → 記錄簡短行號索引 → 用 `Read(offset, limit)` 只讀目標區段。
- **例外**：`pyproject.toml`、設定檔、測試資料 / fixtures、報告樣板不受此限。

---

## 7. 最小可行實作（反過度設計）

> 前面幾節管「**怎麼寫**」，這節管「**寫多少**」。`code-reviewer` 的「過度工程 / 越權」檢查項就是在驗這條——不要等到 review 才被打回。

**原則：能解決問題的最少程式碼，不做任何投機性設計。**

- **不做計畫沒要求的功能**（呼應 `development-workflow.md` Step 3 Golden Rule 與「禁止越權決策」）。
- **只用一次的程式碼不要抽象**。第二個實作出現時再抽。
- **不做沒人要求的「彈性」與「可設定化」**。
- **不為不可能發生的情境寫防禦**。可預期的管線失敗（登入失敗、API 逾時、目標站不可達）仍須依 §5 結構化留痕，兩者不衝突：§5 管**該處理的**，本節管**不必處理的**。
- **不預先為後續 E-Phase 鋪路**。E2/E3 的能力在 E1 連骨架都不要留（違反 `architecture.md` §5 階段範圍紅線）。

**寫完自問兩題（過不了就重寫）：**

1. 「這 200 行能不能是 50 行？」——能 → 重寫。
2. 「資深工程師會不會說這寫得太複雜？」——會 → 簡化。

> **與 `defer-to-dev` 的界線：** §5 說重試次數 / 逾時秒數「必須可設定、不可寫死」，指的是**不要散落魔術數字**——提成模組常數或建構子參數即可，**不等於**要做設定檔載入器、環境覆寫層或 schema 驗證。
>
> **與 Port/Adapter 的界線：** Core-Port-Adapter 分層是**架構規定**（`architecture.md` §2），不算投機抽象，照做。本節針對的是分層**之內**自行增生的抽象。
