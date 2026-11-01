# 10 條核心不變量（正確性的定義）

> 這 10 條是 score-pulse 後端「做對」的定義，來源是 Spec-1／2a／2b／3／4 的業務規則與 `tech-decisions.md` D5、D7、D16。
> **每一條都必須有自動化測試**；Code Review 以此為檢查清單；**違反不變量 = block，沒有例外。**
> 寫程式時的習慣：每寫一個查詢問 I1，每寫一個套用問 I2／I3，每寫一個 REST 讀即時資料的端點問 I9。

---

| # | 不變量 | 一句話 | 來源 |
|---|--------|--------|------|
| **I1** | 租戶隔離 | 業主 A 的任何請求取不到 B 的會員、收藏、通知、導流記錄、設定；範圍由 Host 與登入身分在伺服器端推導，**不接受呼叫端指定** | Spec-1 R28–R36；D7 |
| **I2** | 單場順序 | 同一場比賽的比分、狀態、事件變動以收到的順序套用與推送；`match_id` 是 partition key；每場推送 `seq` 單調遞增 | Spec-2a R58–R60、AC-46；D4 |
| **I3** | 套用冪等 | 每筆更新以供應商的版本或更新時間做 compare-and-set；重複與較舊的更新被丟棄；**比分變小是合法更新**，不得以分數大小過濾 | Spec-2a R59；D16 |
| **I4** | 校正覆寫優先 | 總控對比分、狀態、事件的手動覆寫在解除前**永遠**優先於供應商資料；覆寫期間供應商更新照收、不套用到對外狀態 | Spec-2a R14、E23；Spec-4 |
| **I5** | 賠率歷史只增不刪 | `odds_history` 只 INSERT；只存有變動的筆；補齊後最早一筆即初盤；第一期不刪除 | Spec-2b R11–R13；D6 |
| **I6** | 事件不刪只標取消 | 進球被取消時原事件標 `cancelled`，新增「進球取消」事件；任何事件不 DELETE | Spec-2a R59 |
| **I7** | 憑證只在 collector | TheSports 憑證只載入 `collector` 角色；不進 log、不進錯誤訊息、不進 Kafka 訊息、不進任何 API 回應 | D15 |
| **I8** | 停更與中斷不誤判 | 單場超過門檻無資料 → 標「資料暫停更新中」，**狀態不變、不標完場**；全站中斷 → 橫幅，恢復後補齊；比賽狀態只跟供應商（I4 覆寫除外） | Spec-2a R61–R63、E6、E21 |
| **I9** | 快照一致 | 即時比分、狀態、事件的首屏與重連快照**只從 Redis 讀**；DB 可落後；`persist` 只在批次 flush 成功後 commit offset | D5、D16 |
| **I10** | 記錄 append-only | 兩套後台的操作記錄、導流曝光與點擊記錄只 INSERT；每次點擊一筆（含未登入）；業主停用後入口不顯示、不記錄、不跳轉 | Spec-1 R24–R27、Spec-4 R15；Spec-1 R41 |

---

## 各不變量的驗證方式

| # | 測試手法 | 測試位置（命名） |
|---|---------|----------------|
| I1 | 雙租戶 fixture（`op-a` / `op-b`）；以 A 的 Host 與登入呼叫每一個租戶端點，帶入 B 的 id → **取不到**（404 或空），不是 403 洩漏存在性 | `internal/<feature>/controller/*_test.go`、`test/integration/tenant_*_test.go` |
| I2 | 模擬器送同場 100 筆交錯更新 → 推送 `seq` 連續且與送入順序一致；跨兩個分區的兩場互不影響 | `internal/realtime/.../order_test.go` |
| I3 | 同一筆送兩次、較舊版本後送、比分 1-0 → 0-0 → 比對狀態；重複不重複推送 | `internal/match/service/apply_test.go` |
| I4 | 覆寫 2-1 後供應商送 3-1 → 對外仍 2-1；解除後下一筆才生效 | `internal/match/service/override_test.go` |
| I5 | 送 50 筆變盤含 10 筆無變動 → 40 列；查無 UPDATE／DELETE 語句（靜態 grep + repo 測試） | `internal/odds/dao/history_test.go`、`/arch-check` |
| I6 | VAR 取消 → 原事件 `cancelled=true` 仍在；事件總數 +1 | `internal/match/service/event_test.go` |
| I7 | 以 `api` profile 啟動 → 憑證設定鍵不存在；log 掃描無 secret | `internal/collector/conf_test.go`、`/arch-check` |
| I8 | 模擬器停送 70 秒 → 狀態仍「進行中」、標停更；恢復 → 標示消失並補齊 | `internal/collector/.../stall_test.go` |
| I9 | 關掉 MySQL 寫入 → 首屏快照仍正確；`persist` flush 失敗 → offset 未前進 | `internal/match/controller/snapshot_test.go`、`internal/match/persist_test.go` |
| I10 | 同一會員連點 5 次 → 5 筆；停用業主 → 0 筆且不跳轉；操作記錄表無 UPDATE／DELETE | `internal/operator/.../click_test.go`、`internal/admin/.../audit_test.go` |

---

## 不變量之間的優先序

- **I4 高於 I3**：覆寫期間供應商的更新即使版本較新也不套用到對外狀態（但要存起來，解除時可用）。
- **I2 高於推送延遲**：寧可晚 1 秒也不能亂序；合流只對賠率與統計做，離散事件不合流。
- **I9 高於查詢便利**：REST 端點要即時比分就讀 Redis 快照，不要為了「順便 join」改讀 DB。
