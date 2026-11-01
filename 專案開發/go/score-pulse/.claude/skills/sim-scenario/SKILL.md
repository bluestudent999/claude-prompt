---
name: sim-scenario
description: cmd/thesports-sim 的設計要求與必備情境腳本——同場交錯、重複與較舊更新、比分回退、狀態回退、停更與中斷補齊、賠率高頻與歷史補齊、p95 量測、故障注入。要驗證不變量 I2/I3/I5/I8、AC-40，或任何「真實供應商無法按需觸發」的情境時使用。
---

# sim-scenario — TheSports 模擬器情境腳本

**VAR 取消、狀態回退、全站中斷、跨日在真實環境無法按需觸發。** `cmd/thesports-sim` 是基礎設施（D13），W1 交付（`/bootstrap` B-10），它是 I2／I3／I8 與 AC-40 唯一可靠的驗證手段，也解掉 E1 憑證未到時的開工問題。

---

## 設計要求

| 要求 | 說明 |
|------|------|
| **可腳本化** | `--scenario test/scenario/<name>.yaml`；一個測試能宣告「第 1～3 次回 A，第 4 次起回 B」，不改模擬器程式碼 |
| **可重放** | fixture 是**錄製**的真實回傳（`test/fixtures/thesports/*.json`，含 MQTT 訊息與 HTTP 回應），**不手編**——手編的資料會剛好符合自己的實作 |
| **雙通道** | 內嵌 MQTT broker（`mochi-mqtt`，topic：score、stats、incidents、tlive）+ HTTP stub（diary、detail_live、odds/live、odds/history、lineup、highlight） |
| **可注入故障** | 逾時、連線拒絕、HTTP 429、5xx、格式異常（缺欄位、型別錯、空陣列 vs null）、MQTT 斷線 N 秒 |
| **確定性** | 同一腳本跑兩次結果相同；時間用腳本內的虛擬時鐘（`platform/clock`），不用真實 sleep |
| **可斷言** | 能列出收到的訂閱與 HTTP 呼叫次數（驗證補齊只打必要的 API） |
| **可打時間戳** | 每則送出帶 `tp`，供 `sp_e2e_latency_seconds` 計算 |

腳本格式（YAML）：`steps: [{at: 0ms, mqtt: {topic, fixture, override: {...}}}, {at: 500ms, http: {path, status, fixture}}, {at: 1s, fault: {type: disconnect, duration: 70s}}]`。

---

## 必備情境腳本（`test/scenario/<group>_<name>_test.go` 各對一支）

### A. 順序與冪等（I2、I3）

| 腳本 | 驗證 |
|------|------|
| `order_interleaved_100` 同場 100 筆 score/event/status 交錯 | 推送 `seq` 連續且與送入順序一致；兩場分在不同分區互不影響 |
| `order_duplicate` 同一筆送 3 次 | 套用 1 次、推送 1 次 |
| `order_stale` 較舊 `pv` 後送 | 被丟棄、不推送、metric +1 |
| `order_rollback_1_0_to_0_0` 進球後 VAR 取消 | 比分回到 0-0；原事件 `cx=true` 仍在；新增「進球取消」事件（I6）；**沒有被「分數只能變大」擋掉** |

### B. 狀態

| 腳本 | 驗證 |
|------|------|
| `status_finished_then_live` 2-1 78' 標完場後 1 分鐘改回進行中（AC-46） | 列表歸類兩次變動；分鐘自 79' 續推；比分續更新 |
| `status_interrupt_resume` 1-0 63' 中斷 → 恢復 | 歸進行中標中斷、分鐘停；恢復後續推（AC-8） |
| `status_long_interrupt_24h` 中斷超過 24 小時無更新 | 標「長時間中斷」，仍進行中，比分保留（AC-10） |
| `status_cross_day` 23:59 → 00:01 | 列表日期歸屬正確；訂閱 `/match/list/{sport}/{date}` 的 client 收到移出與移入 |

### C. 停更與中斷（I8）

| 腳本 | 驗證 |
|------|------|
| `stall_single_70s` 單場 70 秒無資料 | `stall=true` 推送；狀態不變、**未標完場**；恢復後 `stall=false` |
| `outage_site_3min` MQTT 斷 3 分鐘後恢復 | `source.health` 標中斷；恢復後以 HTTP 補齊期間的比分與事件；補齊只打受影響的場次 |
| `outage_reconcile_duplicates` 補齊回傳含已收過的事件 | 不重複套用、不重複推送（I3） |

### D. 賠率（I5）

| 腳本 | 驗證 |
|------|------|
| `odds_burst_30_per_sec` 同公司同玩法 1 秒 30 筆 | `odds_history` 30 列（只要值有變）；推送合流為 1 筆 |
| `odds_no_change` 30 筆中 10 筆值相同 | 只寫 20 列 |
| `odds_backfill_30d` 首次接到比賽時補 30 天歷史 | 初盤 = 補齊後最早一筆；走勢連續 |
| `odds_backfill_incomplete` 開盤早於 30 天 | 初盤標「不完整」；更早區間標「無資料」 |

### E. 負載與 SLO（AC-40、D17）

| 腳本 | 驗證 |
|------|------|
| `slo_score_1000` 1000 筆比分變化打 `tp` | `sp_e2e_latency_seconds{kind="score"}` p95 ≤ 5s |
| `slo_stat_200` 200 筆統計 | p95 ≤ 60s；合流後推送數 ≤ 場數 × 秒數 |
| `load_500_matches` 500 場同時進行 | realtime 每秒收訊、CPU；對照 D5 升級觸發點 |

### F. 故障

| 腳本 | 驗證 |
|------|------|
| `fault_http_timeout`、`fault_http_429`、`fault_http_5xx` | 退避重試、不打爆、不漏場；metric |
| `fault_bad_payload` 缺欄位／型別錯 | log + metric + 跳過該筆，**不卡分區**、不寫半筆 |
| `fault_big_id` id 超過 2^53 | 對外 JSON 是字串、無精度損失 |
| `fault_missing_lang` 名稱缺某語系 | 回退順序正確（`i18n.md`） |

---

## 使用

```bash
go run ./cmd/thesports-sim --scenario test/scenario/order_rollback_1_0_to_0_0.yaml --mqtt :1883 --http :8099
go test -tags=scenario ./test/scenario/ -run TestOrderRollback -v
```

新增情境時：先錄 fixture（`--record` 對真實 API 或從 cx-sports 既有錄製檔轉換），再寫腳本，再寫測試。測試名 `Test<Group><Name>`，斷言指回不變量或 AC 編號。
