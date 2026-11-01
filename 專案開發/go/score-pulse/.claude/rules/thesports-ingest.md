# TheSports 接入（D15、D16 的執行版）

> 本文只管 `internal/collector` 包：怎麼連、怎麼補、怎麼判停更、怎麼發 Kafka。資料套用（compare-and-set）在 `api` 的 `realtime-core`，見 `realtime-contract.md` §1.2；封包欄位見 `realtime-contract.md` §1.1。
> 來源：可行性報告（2026-10-29）、官方文件、`tech-decisions.md` D15／D16、Spec-2a R61–R63、Spec-2b R11–R13。
> **開發與測試一律先打 `cmd/thesports-sim`**（D13）。真實憑證只在測試環境的 collector 實例上，且只有 E1 開通後才有。

---

## 1. 兩條資料通道

| 通道 | 用途 | 連線 | 頻率／規則 |
|------|------|------|-----------|
| **MQTT over WebSocket** | 即時：比分、狀態、事件、文字直播 | `wss://mq.thesports.com:443`，topic：`score`、`stats`、`incidents`、`tlive` | 持久連線；`paho.mqtt.golang` QoS 1、`CleanSession=false`、`AutoReconnect=true`、`ConnectRetry=true`；重連退避 1s→30s 加 jitter |
| **HTTP** | 全量與增量同步、補齊 | `https://api.thesports.com/v1/{sport}/...`，`user` + `secret` query | 見 §2 的頻率表 |

**MQTT 是主通道，HTTP 是基準與補償。** 兩者都會產生同一場的更新，重複與亂序由 `realtime-core` 的 compare-and-set 吸收（I3）；collector **不做去重**，只保證每則都帶 `pv`（供應商版本或更新時間）。

---

## 2. HTTP 同步頻率（來自可行性報告，實測後可調，調了回填本表）

| 資料項 | 端點 | 頻率 | 說明 |
|--------|------|------|------|
| 賽程與賽果 | `/v1/{sport}/match/diary` | 今日每 10 分鐘；未來 7 天每 30 分鐘 | 新比賽首次出現即觸發 §4 的賠率補齊 |
| 比賽即時明細（MQTT 備援） | `/v1/{sport}/match/detail_live` | 足球、籃球約 2 秒一次；網球、棒球約 5 秒 | **只在 MQTT 斷線或單場停更時啟用**，正常時不輪詢（成本） |
| 賠率即時 | `/v1/football/odds/live` | 每 3 秒 | **每次只回最近 60 秒的變動**，間隔超過 60 秒就會漏；斷線後走 §4 補齊 |
| 賠率歷史 | `/v1/football/odds/history` | 按需 | 只保留 30 天 |
| 球員／球隊／聯賽／賽季 | `/v1/{sport}/{entity}/list` + 增量（time 參數） | 全量每日一次；增量每分鐘 | 名稱多語欄位見 §7 |
| 教練／裁判／場地 | 同上 | 增量每分鐘 | — |
| 陣容 | `/v1/{sport}/match/lineup/detail` | 開賽前 1 小時起每 5 分鐘；開賽後每 10 分鐘 | — |
| 統計 | `/v1/{sport}/match/trend/live`、`/stats` | MQTT `stats` 為主；HTTP 每 60 秒校正 | Spec-2a R13 的 60 秒目標 |
| 事件 GIF | `/v1/{sport}/match/highlight/detail` | 完場後一次；進行中每 2 分鐘 | 加購項，有才顯示 |
| FIFA 排名 | `/v1/football/ranking/fifa/{men\|women}` | 每日一次 | — |
| 榮譽 | `/v1/{sport}/{team\|player}/honor/list` | 每日一次 | 混有參賽紀錄，見 §8 |
| 影片 | `/v1/video/push/stream/list` | 每分鐘 | **先驗證新套餐是否含此端點**（tech-decisions §6 第 4 項）；cx-sports-v2 的 `specs/2026-06-17_match-live-stream_spec.md` 有可參考的既有用法 |

所有 HTTP 呼叫走 `resty`（框架依賴），逾時 10 秒、429 退避、5xx 重試 3 次後記 `source.health`。

---

## 3. 主備選主（D16）

| 項目 | 規則 |
|------|------|
| 實例數 | 兩台，IP 都進 TheSports 白名單（tech-decisions §6 第 8 項） |
| 選主 | Redis `SET collector:leader <instance> NX PX 15000`；主每 5 秒續約；備每 5 秒嘗試取鎖 |
| 主做什麼 | MQTT 連線、所有 HTTP 排程、發 Kafka |
| 備做什麼 | 不連 MQTT、不發 Kafka、只跑選主迴圈與 `/ping`；**取得鎖後 2 秒內接手** |
| 切換後 | 新主先跑一次 §4 的斷線補齊（以舊主最後心跳時間為起點），再開 MQTT |
| 指標 | `sp_collector_leader{instance}`、`sp_collector_leader_switch_total` |

**不得**兩台同時發 Kafka。測試：`test/scenario/collector_failover_test.go` 殺主 → 備 2 秒內接手且 Kafka 無重複實例來源。

---

## 4. 斷線補齊與賠率歷史補齊

### 4.1 MQTT 斷線（Spec-2a R63）

1. 偵測：paho `OnConnectionLost` 或 60 秒無任何訊息（含 `tlive` 心跳）。
2. 立即：發 `source.health{item=mqtt, status=down}`；啟用 §2 的 `detail_live` 輪詢（只對進行中場次）。
3. 重連成功：以斷線時間為起點，對每場進行中比賽拉一次 `detail_live` + 事件列表，以 `src=http-reconcile` 發 `match.live`；`realtime-core` 靠 `pv` 判斷哪些是新的。
4. 補齊完成：發 `source.health{item=mqtt, status=up}`；前台橫幅由 `api` 依此消失。

### 4.2 賠率補齊（Spec-2b R11、R13；OQ-8）

| 時機 | 做什麼 |
|------|--------|
| 新比賽首次出現（diary） | 拉 `odds/history` 取 30 天內每公司每玩法的全部變盤，依時間順序以 `src=http-reconcile` 發 `odds.change`；`persist` 寫入即為歷史，最早一筆即初盤 |
| 平台接收中斷 | 恢復後對中斷期間有變盤的場次拉 `odds/history`，補中斷區間 |
| 補不到真正第一筆 | 不特別處理；`odds` 包依「最早一筆落在 30 天邊界」判「初盤資料不完整」（E3） |
| 超過 30 天的缺口 | 無法補；`odds` 包標「此區間無資料」 |

賠率補齊的筆數可能很大（一場 × 20 公司 × 3 玩法 × 數百筆），**分批發、每批 500 筆**，不要一次塞進記憶體。

---

## 5. 停更與中斷判定（I8）

| 判定 | 規則 | 輸出 |
|------|------|------|
| 單場停更（R62） | 每場維護 `last_recv_at`（Redis `match:{id}:lastrecv`）；進行中比賽超過 **停更門檻** 無任何資料（含內容無變化的） → 停更 | `match.live{k=status, d.stall=true}`；恢復時 `stall=false` |
| 停更門檻 | 預設 **60 秒**，設定鍵 `thesports.stall-threshold`，**上限 120 秒**；實際值定案後**回填 Spec-2a R62** | — |
| 全站中斷（R63） | MQTT 斷線（§4.1）或 `tlive` 心跳超過 120 秒 | `source.health{item=mqtt}` |
| 資料項延遲（Spec-4 R50） | 每資料項最後成功同步時間與目前延遲秒數 | `source.health{item=<名>, lag_ms}`，每 30 秒一則 |

**停更不改比賽狀態、不標完場**（I8）。狀態永遠跟供應商；長時間中斷的「標示」由 `match` 包依 24 小時規則加，不在 collector。

---

## 6. 發 Kafka

```go
// 一律帶 key，否則同場會散到不同分區（I2）
emitter.EmitWithKey(strconv.FormatInt(matchID, 10), &envelope.MatchLive{
    V: 1, K: "score", M: matchIDStr, Sp: sport,
    Pv: providerVersion,        // 供應商 update_time 或 version；沒有就用 tc
    Tp: providerTs, Tc: now,    // 毫秒
    Src: "mqtt",                // mqtt | http-reconcile | sim
    D:  payload,
})
```

| 規則 | 說明 |
|------|------|
| `pv` 必填 | 沒有版本的資料項（如 lineup）用供應商回傳的 `updated_at`；再沒有就用 `tc`，並在 §8 記一筆 |
| 一則一事 | 一筆 MQTT 訊息含多場 → 拆成多則，各自帶自己的 key |
| 不轉換業務語意 | collector 只做 raw parsing 與欄位短名對映；「進球取消」「長時間中斷」等判定在 `match` 包 |
| 解析失敗 | log + `sp_ingest_parse_error_total{topic}` + 丟棄，**不中斷連線**、不 panic |
| 憑證 | `thesports.user`、`thesports.secret` 只在 `application_collector.yaml`，值走環境變數；不進 log、不進封包（I7）。`/arch-check` 會掃 |

---

## 7. 資料名稱與媒體設定

| 項目 | 規則 |
|------|------|
| 名稱多語欄位 | 供應商回 `name_zh`（簡中）、`name_zht`（繁中）、`name_en`、`name_vi`；菲律賓文未確認。**原樣存進 `league/team/player` 的各語欄位**，不在 collector 回退（回退在 `i18n.md` §2） |
| 缺語系 | 空字串存 NULL，不填英文（否則 `i18n.md` 的回退會以為有翻譯） |
| 動畫 iframe URL | 按球種設定：`thesports.animation-url.football` 等（沿用 cx-sports-v2 的 `theSportsFtUrl` 概念）；`match` 包組 URL，collector 只標「有動畫」 |
| GIF | 封面圖 URL 與片段 URL 原樣存 `match_media` |
| 影片 | 有訊號的場次 `match_id → stream` 存 Redis，TTL 2 分鐘；`match` 包回 `playable` |

---

## 8. 常見坑（可行性報告實測）

| 坑 | 處置 |
|----|------|
| id 超過 2^53 | Go 用 int64 沒問題；**對外 JSON 一律字串化**（`api-contract.md` §2 第 5 條） |
| 網球 H2H 30 筆樣本全空 | 空就回空狀態，不報錯；不要假設一定有 |
| 傷停原因截斷 20 字 | 原樣存，前端自行處理；不要補字 |
| 球隊榮譽混「參賽」紀錄、賽季 id 常為 null | 依平台對照表 `honor_map` 的「顯示清單」制過濾（Spec-2b R24 承接），collector 原樣存 |
| 籃球沒有身價欄位 | 用 salary 當替代，`odds` 包標明 |
| 賠率 60 秒窗口 | 輪詢間隔絕不可超過 60 秒；排程卡住超過 60 秒要告警並走 §4.2 補齊 |
| 動畫 widget 要用實際回傳測 | 不要憑文件寫；bootstrap 時錄一份真實回傳進 fixture |
| MQTT 訊息一包多場 | 拆則、各帶 key（§6） |
| 時區 | 供應商時間戳是 Unix 秒；統一轉毫秒 UTC |

---

## 9. 測試

| 測試 | 位置 |
|------|------|
| MQTT 解析：每個 topic 用錄製 fixture 各一組 table test | `internal/collector/mqtt/*_test.go` |
| HTTP 同步：各端點的 stub 回傳 → 發出的封包欄位齊全、`pv` 非空 | `internal/collector/sync/*_test.go` |
| 選主：兩實例、殺主 2 秒接手 | `test/scenario/collector_failover_test.go` |
| 斷線補齊：模擬器斷 3 分鐘 → 恢復後進行中場次全部補到 | `test/scenario/reconcile_test.go` |
| 停更：停送 70 秒 → `stall=true`、狀態不變；恢復 → `stall=false` | `test/scenario/stall_test.go` |
| 賠率補齊：30 天歷史 → 筆數與順序正確、分批 | `test/scenario/odds_backfill_test.go` |
| 憑證隔離：`api` profile 啟動後設定樹無 `thesports.secret` | `internal/collector/conf_test.go` |

情境腳本見 `skills/sim-scenario`。
