# 掃描標的宣告

> **開工前先確認這份填對了。** 掃錯 repo、掃到線上環境都是事故。

## 標的

| 項目 | 值 |
|---|---|
| **專案** | `cx-sports-v2` |
| **本機路徑** | `~/java/cx-sports-v2`（填你本機的 clone 路徑） |
| **業務型態** | **體育投注主業務** monorepo；多平台（包網）架構，一套系統服務多個平台 |
| **技術棧** | Java 8 ／ Spring Boot **2.7.11** ／ Spring Cloud 2021.0.5 ／ MySQL 5.7 + ShardingSphere 4.0.0-RC2 ／ MyBatis ／ Redis + Zookeeper ／ Elasticsearch 6.8 + 7.17 並用 ／ **Kafka 走 Spring Cloud Stream**（非 spring-kafka） |
| **後端模組** | `cx-sport-app-service`（主業務）、`cx-sport-single-wallet-service`（單一錢包）、`cx-sport-memdb-service`、`cx-sport-mq-collector-service`、`cx-sport-websocket-service`、`manage-center/manage-service`（總控制中心） |
| **前端（同 repo）** | `lion-frontend/`：admin-frontend、agent-front、ctrl-center-frontend、boss-crtl-center、chatroom、mq-frontend ／ `manage-center/`：manage-frontend、boss-frontend、mts-frontend |
| **共用框架（同 repo）** | `lib/sport-framework`（含 `XssFilter`、`CheckSQLInjectionFilter`、`RequestLogInterceptor`） |
| **規模** | 約 **7,808** 個 Java 檔、**595** 個 Controller、20+ 個 filter／攔截器 |
| **租戶鍵** | `platformId`（約 8,700 處引用）—— **平台隔離的軸心**；另有 `agentId` 代理層級 |

> **注意大小寫與拼寫不一致**：程式碼中出現 `platformId` / `platFormId` / `platform_Id` / `platformid` 等多種寫法。
> 掃描時 grep 要不分大小寫，否則會漏。

## 這個 repo 的三個結構特點（影響掃描方式）

| 特點 | 對掃描的影響 |
|---|---|
| **monorepo，前端在同一個 repo** | 前後端可一起追，不必跨 repo；但也代表前端原始碼會被一起掃到（機密、硬編 URL） |
| **控制中心 vs 總控制中心** | 控制中心（單一平台）＝ `lion-frontend/ctrl-center-frontend`；**總控制中心（跨平台）** ＝ `manage-center/manage-frontend`。**跨平台的那個權限最大，越權影響最嚴重** |
| **CI 不跑測試** | `Jenkinsfile` 用 `-Dmaven.test.skip=true`。代表任何「靠測試攔下來」的假設都不成立，防線只剩 review 與執行期 |

## 相關倉庫

| 倉庫 | 角色 |
|---|---|
| `lion-service` | 姊妹系統（同 `com.lc.lion` groupId），有另一套資安掃描範本：`prompt-setup 資訊安全 lion-service` |
| `Flyway`（獨立 repo） | 資料庫遷移 |

> 追到跨 repo 時：**可以讀**（確認防線是否在上游），但 finding 要標明落在別的 repo，
> 且不得把該 repo 的問題當成本次標的的 finding 交付。

## 掃描模式

| 項目 | 值 |
|---|---|
| **模式** | **靜態稽核（原始碼與設定）** |
| **是否允許動態測試** | ❌ **否** |
| **是否允許碰任何執行中環境** | ❌ **否** |

> 要改成允許動態測試，必須先取得**書面授權**與**專用測試環境**，並更新本檔與 `rules/scope-safety.md` 的授權欄。

## 既有資安資產（避免重工，也拿來當判準來源）

| 資產 | 在哪 | 本範本怎麼用 |
|---|---|---|
| 開發期撰碼規範 | `cx-sports-v2/.claude/rules/security.md`（BigDecimal / RoundingMode.DOWN / **7 步餘額異動**） | **當判準來源**：違反它的地方就是 finding 的依據 |
| 分層與資料物件規範 | `cx-sports-v2/.claude/rules/patterns.md` | 同上 |
| 開發期 diff 審查 | `cx-sports-v2/.claude/agents/` 的 reviewer 群 | 那是審**變更**；本範本審**現況全貌** |
| 測試政策 | `cx-sports-v2/.claude/rules/testing.md`（L1 強制整合測試） | 注意：**CI 不跑測試**，所以這條政策在 CI 層沒有強制力 |

## 產出位置

```
cx-sports-v2/sec-reports/<YYYY-MM-DD>/
├── report.md
├── recon.md
└── findings/
```

> 這是**唯一**允許寫入標的 repo 的位置。其餘一律唯讀（`rules/scope-safety.md` 紅線 2）。
