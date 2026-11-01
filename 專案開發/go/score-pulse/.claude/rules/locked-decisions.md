# 已鎖定的架構決策（不得自行推翻）

> 來源：`plan/on-sports-lite/tech-decisions.md`（v1.1，2026-11-01，使用者逐條拍板）。本檔是它的執行版：只列「做什麼、不做什麼」，推導與取捨請回去讀原檔。
> **AI 不得在實作中「順手改回原案」、引入被排除的東西，或因為「這樣比較完整」而加料。** 要翻案 → 停手，回報使用者走決策流程，並在 `tech-decisions.md` 留紀錄。
> **常見誤觸來源：** 外部提出的「方案 A」四服務圖、sp-config 的分層分包、sp-common 的現成程式碼、網路上的 Go 微服務教學、投注平台的概念（結算、盤口）。

---

## 一、範圍被**移除**或**不在本 repo** 的（做了就是越界）

| # | 決策 | 不要做什麼 |
|---|------|-----------|
| **D9** | H5 與 App 畫面由另一部門負責 | 不寫 H5 頁面、不寫 App；不替他們回答 OQ-63／OQ-62／OQ-32a；API 設計對「App 沿用 H5 或另做」保持中立 |
| **D3** | 單一部署單元 | 不拆微服務、不拆多個 binary、不拆多個後端 repo；**不做「結算」**（投注概念，比分網沒有） |
| **D2** | 不依賴 sp-common | 不 `import "sp-common/..."`；不引入 Ignite、不引入 Elasticsearch；可以**抄概念**（platform、domain_config、international、sms_message_record、push_message、app_device 的表設計），不能抄 import |
| **D4** | 不用 Redis Pub/Sub 當廣播總線 | 扇出走框架的 Kafka `websocket` topic；Redis 只做快照、熱狀態、鎖 |
| **D5** | 第一期不用 protobuf、不做按場動態訂閱 | 訊息一律 JSON；看到 `.proto`、`protobuf.js`、「gateway 依本機訂閱數向 Redis 訂閱／退訂」= 越界。升級觸發點：單連線平均下行 > 20 KB/s；realtime 單實例每秒收訊 > 5000 或 CPU > 60% |
| **D7** | 不用 JWT 擋匿名的比賽訂閱 | 規格允許未登入看比分；只有會員通知 destination 驗 token |
| **D12** | 不接 sp-config、不用 go.work 指向同層 checkout | 設定走 YAML + 環境變數；框架依賴走 tag |
| **D16** | 不以「比分只能變大」過濾更新 | 比分回退是合法事件（VAR 取消），套用規則是 compare-and-set（`invariants.md` I3） |
| Brief Out | 不做與業主站點帳號互通、不做域名自動部署 | 導流只做跳轉加記錄；域名第一期人工部署，但憑證自動化（Nginx + ACME）要做 |

---

## 二、架構形態被**鎖定**的

| # | 決策 | 規格 |
|---|------|------|
| **D1** | 語言 | **Go**，版本與 sp-framework 一致（`go 1.23`），不自行升。本機 1.26 可編，CI 以 1.23 為準 |
| **D2** | 框架 | **sp-framework**：gin + fx + gorm + go-redis v9 + sarama + gorilla websocket + cron + go-i18n + viper + prometheus + otp。慣例見 `framework-conventions.md` |
| **D2a** | 框架依賴 | **git tag 鎖版本**，`go.mod` 以 `replace` 或私有模組指向固定 tag；升級是一顆明確的 ticket |
| **D3** | 單 binary 多角色 | `cmd/score-pulse` 一個 binary，`--active=<profile>` 選角色：`api`、`collector`、`realtime`。`api` 內兩個 consumer group：`realtime-core`、`persist`；流量上來時 `persist` 可成第四個 profile，零程式碼改動 |
| **D3a** | 包結構 | **依業務功能分包**：`internal/{operator,match,odds,member,notify,admin,collector,realtime}`，包內 `controller/ service/ dao/ model/ dto/ inject.go`；共用放 `internal/platform`。規則見 `architecture.md` |
| **D4** | 訊息 | **Kafka**。業務 topic 以 **`match_id` 當 partition key**；`match.live` **24 個分區**（建立後不改）；業務 topic 保留 **7 天**；`websocket` topic 保留 **10 分鐘**、consumer **`latest-offset: true`**。topic 表見 `realtime-contract.md` |
| **D5** | 即時推送 | 框架 WebSocket 協定；JSON、短欄位名、delta；每場 `seq` 單調遞增；三個時間戳；合流在 `api` 的 `realtime-core` 做一次（離散事件零延遲、賠率與統計 1 秒 Last-Write-Wins）；首屏與重連快照只讀 Redis；心跳 30 秒；慢連線滿佇列即斷線；斷線退回 10 秒輪詢 |
| **D6** | 儲存 | **MySQL 8**（gorm + gorm/gen）唯一主庫；**Redis** 熱狀態、快照、鎖。賠率歷史 append-only、按月分區、只存變動、第一期不刪 |
| **D6a** | Migration | **golang-migrate**，SQL 檔，時間戳版本。規則見 `db-migration.md` |
| **D7** | 多業主 | 單庫，租戶表帶 `operator_id`；Host → operator 放 context；gorm callback 強制過濾；測試一律雙租戶。規則見 `tenant-isolation.md` |
| **D8** | 後台前端 | **Vue 3 + Element Plus + Pinia + Vite**，兩套後台在本 repo `web/admin/`，共用登入、權限、API client。規則見 `web-frontend.md` |
| **D10** | 外部服務 | 推播 Firebase Go SDK（一專案多 App）；簡訊 provider 介面先接 mock；後台驗證器 TOTP（框架內 otp）；告警郵件 SMTP |
| **D11** | 媒體 | 動畫與 GIF 回 iframe URL 與可播放狀態；影片先驗證 `GET /v1/video/push/stream/list` 在新套餐內可用 |
| **D12** | 設定與部署 | YAML + 環境變數，三角色各一份 profile；Docker、k8s；業主域名 Nginx + ACME |
| **D13** | 第一週工具 | `cmd/thesports-sim`：內嵌 MQTT broker 重放 fixture + HTTP stub。W1 交付，見 `skills/sim-scenario` |
| **D14** | 新增依賴 | MQTT：`github.com/eclipse/paho.mqtt.golang`；lint：golangci-lint；測試：testify + docker-compose；API 文件：swag。**其他第三方相依要在 plan §2 說明理由** |
| **D15** | TheSports 介接 | MQTT over WebSocket（`mq.thesports.com:443`）+ HTTP 全量／增量；賠率即時每 3 秒、60 秒窗口；歷史 30 天內單場補齊。規則見 `thesports-ingest.md` |
| **D16** | collector 高可用 | 主備兩實例、Redis 鎖選主、備機熱待命；套用一律 compare-and-set；每場維護最後收到時間；供應商心跳當全站中斷依據 |
| **D17** | 可觀測性 | 每則訊息三個時間戳，Prometheus 直方圖出 p95；gateway 連線數、每秒收訊、每秒推送、丟棄慢連線數都是指標；滾動更新走 k8s preStop 分批 drain |

---

## 三、看到這些就停手

| 徵兆 | 它違反了 |
|------|---------|
| `go.work` 裡出現 `../sp-framework` | D2a |
| `import "sp-common/` | D2 |
| 新的 `cmd/<service>` 目錄（`thesports-sim`、`gen` 除外） | D3 |
| `redis.Subscribe(` 用在推送路徑 | D4 |
| `.proto` 檔、`proto.Marshal` 用在對前端訊息 | D5 |
| 查詢租戶表卻沒經過 `tenant.Scope` | D7、I1 |
| `if newScore < oldScore { return }` | D16、I3 |
| `DELETE FROM odds_history`、`UPDATE odds_history` | D6、I5 |
| 首屏 REST 讀 MySQL 取即時比分 | D5、I9 |
| `websocket.allow-cross-origin: true` 留在 prod profile | D7 |
| `settle`、`settlement`、`bet`、`stake` 等字眼出現在程式碼 | D3 |
