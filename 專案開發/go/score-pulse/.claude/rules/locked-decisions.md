# 已鎖定的架構決策（不得自行推翻）

> 來源：`plan/on-sports-lite/tech-decisions.md`（v1.16，2026-11-01 使用者逐條拍板，2026-11-02～06 修訂至 D28）。本檔是常駐的**索引**；每條 D 的完整規格、P-20／24／26／27 規則與長條停手徵兆在 `locked-decisions-detail.md`（碰到程式碼時自動載入）。
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
| **D12** | 不接 sp-config | 設定走 YAML + 環境變數（框架依賴方式見 D2a） |
| **D16** | 不以「比分只能變大」過濾更新 | 比分回退是合法事件（VAR 取消），套用規則是 compare-and-set（`invariants.md` I3） |
| Brief Out | 不做與業主站點帳號互通、不做域名自動部署 | 導流只做跳轉加記錄；域名第一期人工部署，但憑證自動化（Nginx + ACME）要做 |

---

## 二、架構形態被鎖定的（一行索引，細節見 `locked-decisions-detail.md` §二）

| # | 一句話 |
|---|------|
| D1 | Go 1.27.3（跟 go-framework 一致），不自行升 |
| D2／D2a | go-framework（2026-11-05 取代 sp-framework；缺的機制只增不改移植進 go-framework）。2026-11-06 起go-framework 由不進版控的 go.work 接入（`bash scripts/setup-go-work.sh`；做法同 lion-quest），go.mod 不寫 framework，版本記在 `deploy/go-framework.ref`；升級框架是一張明確的 ticket（改 ref 檔） |
| D3／D3a | 單 binary 三角色 `api`／`collector`／`realtime`；依功能分包 `internal/{platform,match,odds,member,notify,manage,collector,realtime}` + `internal/core` |
| D4 | Kafka；業務 topic 以 `match_id` 當 key；`match.live` 24 分區 |
| D5 | JSON、delta、每場 `seq` 單調；快照只讀 Redis；慢連線經 P-17 有界佇列斷線 |
| D6／D6a | MySQL 8 唯一主庫 + Redis；賠率歷史 append-only；golang-migrate 時間戳 SQL |
| D7／D20 | 單庫多業主；租戶鍵是字串 `platform_code`，建立後不可改；gorm 強制過濾；測試一律雙租戶 |
| D8 | 後台 Vue 3 + Element Plus + Pinia + Vite（`web/admin`） |
| D10～D15 | Firebase 推播、簡訊 mock、TOTP、SMTP；媒體回 iframe URL；YAML + 環境變數、docker compose、不用 k8s；`cmd/thesports-sim`；新第三方相依要在 plan §2 說明理由；TheSports MQTT over WS + HTTP |
| D16 | collector 主備；套用一律 compare-and-set |
| D17 | 每則訊息三個時間戳，p95 指標 |
| D18 | 後台密碼前端算 MD5，後端存 bcrypt(MD5)，MD5 不進日誌 |
| D21 | 驗證器密鑰在新增帳號時產生、只顯示一次；登入一律要驗證碼 |
| D22 | migration 已整併成基準；已套用的 migration 不可改 |
| D23 | 後台權限 = 頁面 × 動作的 8 位數選單代碼；每支後台 API 經 `auth.RouteTable` 宣告，fail-closed |
| D24 | 總控可操作所有業主；指定業主只經 `auth.ManageTarget`；業主後台的業主代碼只來自 session |
| D25 | 後台所有 API 先過 IP 白名單，沒設定 = 全拒；IP 只信可信代理的 `X-Real-IP` |
| D26 | 總控命名 `admin` → `manage`（`internal/manage`、`/api/manage/**`、`admin_info`） |
| D27 | 後台記錄拆 `login_log`／`operate_log`，皆 append-only 租戶表 |
| D28 | 總控可替任何業主填寫、更換、撤回專屬域名，與業主後台共用同一 service 與規則；指定業主只經 `auth.ManageTarget` |

---

## 四、看到這些就停手（短條；長條在 `locked-decisions-detail.md` §四）

| 徵兆 | 它違反了 |
|------|---------|
| `go.work`／`go.work.sum` 進了版控；go.mod 出現 `framework` 的 require 或 replace；改了 `deploy/go-framework.ref` 卻沒跑完整驗收 | D2a |
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
| `internal/realtime` 之外對 client 寫 socket，或直接呼叫框架 `Client.SendData` 繞過有界佇列 | D5、P-17 |
| 舊後台記錄表 `admin_audit`／`AdminAudit` 重新出現；登入（含失敗）寫進 `operate_log`；`login_log` 加密碼、MD5、驗證碼、token、User-Agent 欄 | D27、I10 |
| 在 `main`／`developing` 上 commit，在 `main` 上 merge，在 `developing` 上做 `--no-ff` 合併 feature／hotfix 以外的 merge、rebase、reset、強制推送，或從 `main` 切 feature | git-workflow §1（使用者 2026-11-02 指定；2026-11-05 開放本機 `--no-ff` 合併回 `developing`，§1.2） |
| 租戶鍵寫法、後台路由註冊、IP 判定、P-19／P-30 舊命名 | 見 `locked-decisions-detail.md` §四 |
