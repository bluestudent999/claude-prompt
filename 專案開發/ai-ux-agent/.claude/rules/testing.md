# 測試規範與政策（pytest）

> 本文規範 AI UX Audit Platform 的測試標準：pytest 架構、確定性測試（LLM/瀏覽器需可重現）、風險分級覆蓋，以及證據契約驗證。

---

## 1. 測試技術棧與命名

- **框架**：**pytest**（`test_*.py` / `*_test.py`）。
- **斷言**：優先使用 pytest 原生 `assert` + 明確訊息；複雜結構可用輔助斷言工具。
- **Mock**：`pytest` fixtures + `unittest.mock` / `monkeypatch`。
- **命名**：`test_<行為>_when_<情境>`（如 `test_issue_rejected_when_evidence_missing`）。
- **標記（markers）**：
  - `@pytest.mark.architecture` — 分層 / 管線邊界驗證（供 Stop hook 與 `/arch-check`）。
  - `@pytest.mark.integration` — 需真實瀏覽器 / 網路的整合測試。
  - `@pytest.mark.slow` — 長時測試。

---

## 2. 確定性紀律（LLM / 瀏覽器不可直連真實服務）

> 這是本專案測試的核心難點：LLM 與網站皆為非確定來源。

- **推理（InferencePort）**：單元測試一律注入 **`InferenceStub`** 回傳**確定性**結果，**禁止**在單元測試呼叫真實雲端 / 本地模型。
- **瀏覽器（BrowserPort）**：單元測試用 **`BrowserStub`** 或**已錄製的 DOM / Screenshot fixture**；禁止在單元測試連真實目標站。
- **真實連線**：只在 `@pytest.mark.integration` 測試中，對**測試專用**目標執行，且憑證由環境變數注入（見 security-audit §1）。CI 預設不跑 integration。

---

## 3. 風險分級測試政策（L1–L3）

| 風險級別 | 典型場景 | 測試覆蓋要求 |
| :--- | :--- | :--- |
| **L1（高風險）** | 登入 / Session / 憑證處理；`Issue↔Evidence` 連結；例外留痕（失敗不靜默）；報告要件完整性 | **強制**撰寫測試：登入態流程、證據缺失時 Issue 被拒、每類例外都在報告留痕 |
| **L2（中風險）** | Observation 收集器、Persona / Task 引擎、Reasoning 編排、報告格式化 | **優先**單元測試（Stub 注入），必要時整合測試 |
| **L3（低風險）** | 設定檔、prompt 文案微調、docstring、純重構 | **不強制**測試，通過 review + `ruff` 即可 |

---

## 4. 證據契約測試（本專案專屬，必測）

對映 architecture §4 契約鐵律與產品紅線：

- **每個 Issue 必有可解析的 Evidence**：斷言 `Issue.Evidence` 指向真實存在的 `Observation`（截圖檔存在 / DOM 片段非空）。
- **四欄位齊全**：斷言 `Severity / Category / Evidence / Recommendation` 皆非空，且 `Severity` 為合法 Enum。
- **失敗留痕**：模擬登入失敗 / API 逾時 / 目標站不可達，斷言報告出現對應留痕與失敗證據，且**不產出無證據 Issue**。
- **報告快照（golden report）**：以固定的 Stub 輸入產生報告，做快照比對，防止格式回歸。

---

## 5. E-Phase 測試邊界

- **E1**：只需覆蓋 Screenshot+DOM 觀察、登入 Task、Issue 四欄位、5 要件 Markdown 報告、5 類例外留痕、一鍵可重跑。
- **不得**在 E1 為尚未實作的 E2/E3 能力（A11y/Network/Perf、HTML、排程、多 Agent）撰寫測試（越界，違反範圍紀律）。
