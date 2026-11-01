# 即時資料契約：Kafka topics 與 WebSocket（D4、D5、D17）

> 兩個受眾：本 repo 的 `collector` → `api` → `realtime` 三個角色之間（內部契約），以及 H5／App 部門的 WebSocket client（對外契約）。
> 對外部分與 `api-contract.md` 同級：**不可片面變更**。內部部分改了要同時改 `platform/envelope` 與本文。

---

## 1. Kafka topics

| Topic | Key | 分區 | 保留 | 生產者 | 消費者（group） | 內容 |
|---|---|---|---|---|---|---|
| `match.live` | `match_id` | **24** | 7 天 | collector | api `realtime-core`、api `persist` | 一個 topic 承載 `score`、`status`、`event`、`stat`、`lineup` 五種 kind；同場同分區，順序有保證（I2） |
| `odds.change` | `match_id` | 24 | 7 天 | collector | api `realtime-core`、api `persist` | 每一筆變盤；`persist` 是 `odds_history` 的唯一寫入者（I5） |
| `source.health` | 資料項名 | 3 | 1 天 | collector | api `monitor` | 各資料項狀態、延遲、每場最後收到時間（Spec-4 R49–R52） |
| `notify.trigger` | `operator_id` | 6 | 1 天 | api `realtime-core` | api `notify` | 「比分變動／狀態變動／事件新增取消」三種觸發（Spec-2a R64） |
| `websocket` | destination | 12 | **10 分鐘** | api `realtime-core` | realtime（每實例獨立 group，`latest-offset: true`） | 框架 `WebsocketMessage{destinations, data}`；data 已合流 |
| `cache-refresh` | — | 1 | 10 分鐘 | api | api | 框架本地快取失效廣播 |

**分區數建立後不改**（改了會破壞單場順序）。topic 由框架依 YAML 自動建立；YAML 裡要寫 `partitions` 與 `retention-ms`。

### 1.1 `match.live` 封包（`platform/envelope.MatchLive`）

```json
{
  "v": 1,                      // 封包版本
  "k": "score",                // kind: score | status | event | stat | lineup
  "m": "1234567890123",        // match_id（字串）
  "sp": "football",            // sport
  "pv": "1730000000123",       // 供應商版本或更新時間（毫秒）；compare-and-set 用（I3）
  "tp": 1730000000123,         // 供應商時間戳（毫秒，沒有就等於 tc）
  "tc": 1730000000456,         // collector 收到時間（毫秒）
  "src": "mqtt",               // mqtt | http-reconcile | override | sim
  "d": { ... }                 // 依 kind 的 payload，欄位短名見 §1.3
}
```

`odds.change` 同結構，`k` 固定 `odds`，`d` 含 `co`（公司）、`mk`（玩法：`eu`、`ah`、`ou`、`cr`…）、`st`（階段：`pre`、`live`）、`o`（三個值，decimal 字串）、`sc`（當時比分）。

### 1.2 消費規則

| group | 規則 |
|-------|------|
| `realtime-core` | 依 `pv` compare-and-set 套用到 Redis 快照（I3）；覆寫中的場次只存不套用（I4）；套用成功才產生推送；每場 `seq` 從 Redis `INCR`（I2）；資料錯誤 log + metric + 回 nil，不卡分區 |
| `persist` | 緩衝 500 筆或 1 秒 flush；`odds.change` 比對上一筆相同鍵（`m`,`co`,`mk`,`st`）的值，**無變動不寫**（I5）；flush 成功才回 nil（I9） |
| 兩者共同 | 不得假設同一場的 `score` 一定在 `event` 之前；以收到順序為準 |

### 1.3 `d` 的欄位短名（對外推送也用同一套）

| kind | 欄位 |
|------|------|
| `score` | `h` 主、`a` 客、`ht` 半場（有才）、`ck` 角球、`rc`／`yc` 牌數、`per` 節／盤／局細項（陣列） |
| `status` | `s` 狀態碼（Spec-2a R4 表）、`ks` 開球時間（毫秒）、`min` 平台推算分鐘的基準（`{"base":63,"at":1730000000000}`，client 自己走秒）、`stall` 停更旗標 |
| `event` | `id`、`t` 類型、`min`、`ext` 補時、`side`、`pl` 球員、`pl2` 助攻或換下、`sc` 進球後比分、`cx` 取消旗標、`rs` 原因 |
| `stat` | `items`：`[{ "c": "possession", "h": 55, "a": 45 }]` |
| `lineup` | `h`／`a`：陣型與球員陣列 |

---

## 2. WebSocket（對外）

### 2.1 連線與握手

- URL：`wss://<業主域名>/api/ws`。Host 決定業主；業主不存在或已停用 → HTTP 403，不升級。
- Origin：必須在該業主域名白名單（App 的 WebView 無 Origin 時放行，但要帶 `x-client`）。
- 匿名可連；會員相關 destination 訂閱時帶 token（見 2.3）。
- 每 IP 最多 20 條連線；每連線最多 50 個訂閱；超過回 `e` frame 並斷線。
- 心跳：client 每 25 秒送 `0`，server 回 `1`；30 秒沒收到 → server 斷線。

### 2.2 frame 格式（框架協定）

```
client → server
  [0x30 '0']                                   ping
  [0x53 'S'][len][destination][payload?]       subscribe；payload 可為空或 JSON（含 token）
  [0x55 'U'][len][destination]                 unsubscribe
server → client
  [0x31 '1']                                   pong
  [0x70 'p'][len][destination][json]           push
  [0x65 'e'][utf8 text]                        error（subscribe error / destination 404 / frame format error …）
```

subscribe 成功後 server **立即推一則該 destination 的快照**（`"snap": true`），之後才是 delta。

### 2.3 destinations

| destination | 認證 | 推什麼 | 快照來源 |
|---|---|---|---|
| `/match/list/{sport}/{date}` | 匿名 | 該日列表級 delta：`score`、`status`（含分鐘基準、停更旗標） | Redis `match:list:{sport}:{date}` |
| `/match/{matchId}` | 匿名 | 詳情級：`score`、`status`、`event`、`stat`、`lineup`、媒體可播放狀態 | Redis `match:{id}:snapshot` |
| `/match/{matchId}/odds` | 匿名 | 合流後的賠率（每公司每玩法 1 秒一筆） | Redis `match:{id}:odds` |
| `/site/notice` | 匿名 | 全站中斷橫幅、恢復（Spec-2a R63） | Redis `site:{op}:notice` |
| `/operator/{op}/member/{memberId}/notice` | payload `{"token": "..."}`；`{op}` 必須等於握手業主、`memberId` 必須等於 token 主體 | 站內通知、未讀數 | Redis `member:{op}:{id}:notice` |

### 2.4 推送訊息

```json
{ "v": 1, "k": "score", "m": "1234567890123", "seq": 418, "snap": false,
  "tp": 1730000000123, "tc": 1730000000456, "tg": 1730000000789,
  "d": { "h": 1, "a": 0 } }
```

| 欄位 | 語意 |
|------|------|
| `seq` | **每場**單調遞增（列表 destination 內每場各自的 seq）。client 若收到 `seq` 不等於上次 + 1 → **重新訂閱取快照**，不要自己補 |
| `snap` | true = 全量快照，client 以它取代本地狀態 |
| `tp`／`tc`／`tg` | 供應商、collector、gateway 三個時間戳；client 可算端到端延遲上報（選用） |
| `d` | delta，只含變動欄位；快照含全部欄位 |

### 2.5 合流（server 端，client 不需處理）

| kind | 策略 |
|------|------|
| `score`、`status`、`event`（含取消） | 零延遲，逐筆推 |
| `odds` | 每（場、公司、玩法）1 秒窗口 Last-Write-Wins |
| `stat`、`lineup` | 每場 1 秒窗口，合併成一則 |

### 2.6 client 行為（寫進交付文件）

- 重連：指數退避 `base=1s, max=30s`，每次加隨機 `0–1s` jitter；重連後**重新訂閱**所有 destination（會拿到快照）。
- 斷線超過 10 秒 → 改走 REST 輪詢（10 秒一次）直到重連成功。
- 收到 `e` frame → 記 log，不要立刻重試同一個 subscribe（避免風暴）。
- 不要依賴推送順序跨場；同場以 `seq` 為準。

---

## 3. 版本與相容

- 封包 `v` 是對外訊息版本。新增可選欄位 → 不升版，CHANGELOG 記一行。改語意、改短名、刪欄位 → `v` +1，**舊版並行至少一個 App 發版週期**（App 不能強迫更新）。
- destination 新增 → 相容；改路徑 → 破壞性，走 `api-contract.md` §3。
- 內部 Kafka 封包的 `v` 與對外獨立；內部改版要同時改 `collector` 與兩個 consumer，**同一個 commit**。

---

## 4. SLO 與量測（D17）

| 指標 | 定義 | 目標 |
|------|------|------|
| `sp_e2e_latency_seconds{kind}` | `tg - tp`，直方圖 | `score`／`status` p95 ≤ 5s（AC-40）；`stat` p95 ≤ 60s（R13） |
| `sp_ws_connections` | 每實例連線數 | 告警 > 2000 |
| `sp_ws_inbound_per_sec` | 每實例每秒從 Kafka 收到的訊息 | > 5000 觸發 D5 動態訂閱評估 |
| `sp_ws_dropped_slow_clients_total` | 因佇列滿被斷的連線 | 觀察 |
| `sp_ingest_stall{match}` | 單場停更旗標 | 對應 R62 |

AC-40 的驗收方式：模擬器以 `tp` 打時間戳送 1000 筆比分變化，從 `sp_e2e_latency_seconds` 取 p95。
