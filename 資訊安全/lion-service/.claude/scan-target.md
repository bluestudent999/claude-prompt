# 掃描標的宣告

> **開工前先確認這份填對了。** 掃錯 repo、掃到線上環境都是事故。

## 標的

| 項目 | 值 |
|---|---|
| **專案** | `lion-service` |
| **本機路徑** | `~/java/lion-service`（填你本機的 clone 路徑） |
| **業務型態** | 包網（白標）博弈平台後端 —— 一套系統服務多家包網商 |
| **技術棧** | Java 8 ／ Spring Boot 2.0.2.RELEASE ／ Spring Cloud Finchley ／ MySQL + ShardingSphere 4.0.1 ／ MyBatis ／ Redis ／ Elasticsearch 6.8 + 7.17 |
| **模組** | `cp-service`（CP 主業務）、`single-wallet-service`（單一錢包）、`collector-service`（資料收集）、`upload-service`（上傳）、`cp-flyway`（DB 遷移） |
| **規模** | 約 1,610 個 Java 檔、392 個 Controller、21 個第三方回調入口 |
| **租戶鍵** | `platformId`（約 5,800 處引用）—— **包網商隔離的軸心** |

## 相關倉庫（跨 repo 追查時會用到，但不在本次掃描範圍內，除非另行宣告）

| 倉庫 | 角色 |
|---|---|
| `framework_v3` | 底層框架（Exception、DAO 抽象類、utils） |
| `lion-common` | 共享領域模型、共用 DAO / Cache |
| `lion-core` | 結算服務（訂單結算、派彩） |
| `lion-manage` | 總控 / 管理後台（含 boss、manage、bet-order 後台） |
| `lion-frontend` | 前端總倉（admin / agent / third / bet-station） |
| `activity-service`、`lion-captcha`、`lion-upload-service` | 活動、驗證碼、獨立上傳服務 |

> 追到跨 repo 的呼叫時：**可以讀**（確認防線是否在上游），**但 finding 要標明它落在別的 repo**，
> 且不得把該 repo 的問題當成本次標的的 finding 交付。

## 掃描模式

| 項目 | 值 |
|---|---|
| **模式** | **靜態稽核（原始碼與設定）** |
| **是否允許動態測試** | ❌ **否** |
| **是否允許碰任何執行中環境** | ❌ **否** |

> 要改成允許動態測試，必須先取得**書面授權**與**專用測試環境**，並更新本檔與 `rules/scope-safety.md` 的授權欄。
> 未更新前，任何對執行中系統的請求都是越界（見 `rules/scope-safety.md` 紅線 1）。

## 既有資安資產（避免重工，也拿來當判準來源）

| 資產 | 在哪 | 本範本怎麼用 |
|---|---|---|
| 開發期撰碼規範 | `lion-service/.claude/rules/security.md` | **當判準來源**：違反它的地方就是 finding 的依據，不要另立一套標準 |
| 開發期 diff 審查 | `lion-service/.claude/agents/security-reviewer.md` | 那是審**變更**；本範本審**現況全貌**，兩者不重疊 |
| SonarQube | `lion-service/sonar-project.properties` | Sonar 抓得到的**規則型**缺陷不是本範本重點（見 `rules/false-positive.md` §4） |
| 嚴重度定義 | `lion-service/.claude/rules/severity-rubric.md` | 對照參考；本範本另有**包網情境**的加權（見 `references/severity-rubric.md`） |

## 產出位置

```
<標的 repo>/sec-reports/<YYYY-MM-DD>/
├── report.md          主報告
├── findings/          逐條 finding
└── recon.md           攻擊面盤點
```

> 這是**唯一**允許寫入標的 repo 的位置。其餘一律唯讀（`rules/scope-safety.md` 紅線 2）。
