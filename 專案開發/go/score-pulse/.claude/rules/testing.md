# 測試政策

> 本專案的測試不是覆蓋率遊戲，它是三件事的驗證機制：**每個 API 的行為**、**10 條不變量**、**ticket 對映的 AC**。
> 工具：Go 內建 `testing` + `testify`（assert/require/mock）、`httptest`、docker-compose（MySQL／Redis／Kafka）、`cmd/thesports-sim`。

---

## 1. 每個 API 都要有單元測試（硬規則，使用者指定）

**「API」的定義：**

| 類型 | 範圍 |
|------|------|
| REST handler | `internal/*/controller/` 下每一個被 `RegisterRouter` 掛上的 handler（前台、業主後台、總控） |
| WebSocket 訂閱 action | `internal/realtime/` 下每一個 `WebSocketSubscriptionAction` 與 `HandshakeHandler` |
| Kafka consumer | 每一個 `MessageHandler.AcceptMessage` |

**每一個都必須有同包 `_test.go`，且至少涵蓋：**

| 案例 | REST | WS action | consumer |
|------|------|-----------|----------|
| 正常路徑（200 / 快照 / 套用成功） | 必 | 必 | 必 |
| 參數錯誤（400，含每個必填欄位缺一） | 必 | 必（destination 參數錯） | 必（封包壞 → 回 nil + metric） |
| 未登入 / 無權限（401 / 403） | 需登入的必 | 會員 destination 必 | — |
| **他租戶資源 → 404 或空**（I1） | 租戶表相關的必 | `{op}` 不符必 | — |
| 業務錯誤碼（每個 handler 會 panic 的每一個 `apierr`） | 必 | — | — |
| 重複／較舊更新被丟棄（I3） | — | — | `realtime-core` 必 |

**作法：** gin `TestMode` + `httptest`，service 用 testify mock 或介面替身；**controller 測試不連 DB**。斷言 HTTP 狀態、`code`、`data` 的關鍵欄位，以及 mock 被呼叫的參數（租戶 id 是否來自 ctx 而非請求）。

命名：`Test<Handler>_<Case>`，例：`TestGetMatchDetail_OK`、`TestGetMatchDetail_OtherTenant_NotFound`、`TestSubscribeMemberNotice_TokenMismatch_Rejected`。

**檢查：** `/arch-check` 會列出沒有 `_test.go` 的 handler；`code-reviewer` 看到新增或修改 handler 卻沒有對應測試 → **block**。planner 的 §4 必須逐一列出每個端點的測試名。

---

## 2. 測試分層

| 層 | 位置 | 用途 | 需要什麼 | 進 CI |
|----|------|------|---------|------|
| 單元 | `internal/**/ *_test.go` | §1 的 API 測試；service 規則；envelope 編解碼；合流；compare-and-set | 無外部依賴 | ✅ `go test ./internal/...` |
| 整合 | `test/integration/*_test.go` | dao 對真實 MySQL；Kafka 兩 group 消費；Redis 快照；雙租戶越權 | `docker compose -f deploy/docker-compose.yml up -d mysql redis kafka` | ✅ `go test -tags=integration ./test/...` |
| 情境 | `test/scenario/*_test.go` | 模擬器腳本：同時進球、回退、跨日、停更、中斷補齊、p95 量測 | 上述 + `cmd/thesports-sim` | ✅（夜間或 PR label） |
| 架構 | `skills/arch-check` 腳本 | import 方向、禁用依賴、handler 有測試、租戶 dao 經 Scope | 無 | ✅ |

整合與情境測試用 build tag 分開，預設 `go test ./...` 只跑單元。

---

## 3. 雙租戶是預設 fixture（硬規則）

`test/fixtures/tenants.go`：`op-a` / `op-b` 各一位業主、域名、會員、業主後台管理員；一位只指派 A 的總控人員。**所有**整合測試用這組；租戶端點的單元測試也用它的 id 與 Host。

必測越權情境與命名見 `tenant-isolation.md` §5。斷言的是「**取不到**」，不是「筆數對」。

---

## 4. 各不變量的測試

對照 `invariants.md` 的「驗證方式」表；planner §4 必須把涉及的不變量對應到**具體測試函式名**，不是「補測試」。

---

## 5. 模擬器是基礎設施（D13）

TheSports 的 VAR 取消、狀態回退、中斷、跨日在真實環境**無法按需觸發**。`cmd/thesports-sim` 在 W1 交付：

- 錄製真實回傳當 fixture（`test/fixtures/thesports/*.json`），**不要手編資料**（手編的資料會剛好符合自己的實作）。
- 情境腳本見 `skills/sim-scenario`：同場 100 筆交錯、1-0 → 0-0、完場 → 進行中、停送 70 秒、全站斷 3 分鐘後補齊、跨日 23:59 → 00:01、賠率 1 秒 30 筆。
- 可宣告「第 1～3 次回 A、第 4 次起回 B」；可注入逾時、429、格式異常。
- 整合測試與 AC-40 的 p95 量測都靠它。

---

## 6. AC 對映（ticket 驗收）

- planner §4 把 ticket 的每一條 AC 對到至少一個測試（單元或整合或情境）。
- AC 含「95 百分位」「5 秒內」這類量測字眼 → 情境測試 + `sp_e2e_latency_seconds` 直方圖。
- AC 含畫面（B 類）→ `web/admin` 的 Vitest 元件測試 + 後端 API 測試各一；畫面三態（載入／空／錯誤）必測（`web-frontend.md`）。
- 「人介入」欄寫驗收的 AC（例如 AC-40 需量測）→ 仍要有自動化測試，人只是確認數字。

---

## 7. 風險分級與最低要求

| 級別 | 範圍 | 最低測試 |
|------|------|---------|
| L1 | 不變量相關、租戶隔離、賠率歷史、套用邏輯、合流、collector 補齊 | 單元 + 整合 + 情境 |
| L2 | 一般 service、handler、consumer、後台 CRUD | 單元（§1）+ 必要整合 |
| L3 | DTO、設定、純重構 | 單元（§1 仍適用於 handler） |

---

## 8. DoD（七條全滿足才算完成）

1. `go build ./... && go vet ./...` 通過；`golangci-lint run` 無新問題。
2. **每個新增或修改的 API 有 §1 要求的單元測試且全綠。**
3. 涉及的不變量有對應測試且全綠。
4. ticket 的每條 AC 對到測試或情境腳本。
5. 整合測試（有動 dao／consumer 時）全綠；`/arch-check` 通過。
6. 涉及契約：`/contract-export` 產出已更新、CHANGELOG 有紀錄。
7. ticket 狀態與 `plan/task-<ticket>-plan.md` §8 完成紀錄已回填。

---

## 9. 命名與慣例

- `Test<Subject>_<Case>`；table-driven 時 `t.Run(name, ...)`，name 用英文句子。
- 不用 `time.Now()` 直接比較；注入 `platform/clock`。
- 不用 `sleep` 等非同步結果；用 channel 或 `require.Eventually`。
- 測試資料的 id、域名用 fixture 常數，不寫魔術數字。
- 一個測試只驗一件事；失敗訊息要能看出哪個 AC 掛了。
