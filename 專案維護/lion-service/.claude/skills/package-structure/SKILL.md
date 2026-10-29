---
name: package-structure
description: lion-service 各模組 package 結構與「新類別放哪」的判定（cp-service / single-wallet-service / collector-service / upload-service，共享層 lion-common / framework_v3）。新增類別決定目錄、或在既有結構找東西時使用。
---

# lion-service Package 結構

> **不是新專案模板** —— lion-service 是既有專案，本檔記**現存結構**與「新類別放哪」的決議。業務 domain 對照（`service/<domain>/`）見 `rules/modules.md`，不在此重複。
> 新類別一律**對齊同目錄既有寫法**；結構與本檔不符時以 `ls` 實際結果為準，並回報使用者。

## 模組與 base package

| 模組 | base package | 頂層目錄（實際） |
|------|------------|----------------|
| `cp-service` | `com.lc.cp` | `analysis/ aspect/ bean/ cache/ config/ controller/ dao/ event/ exception/ export/ filter/ job/ redis/ service/ sms/ util/ validation/` |
| `single-wallet-service` | `com.lc.single.wallet` | `annotation/ aspect/ cache/ config/ constants/ context/ controller/ filter/ handler/ runner/ schedule/ service/` |
| `collector-service` | `com.cx.collector`（前綴不同是歷史沿革，**不要改**） | `bean/ config/ constants/ controller/ handler/ http/ job/ service/ util/` |
| `upload-service` | `com.lc.upload` | `bean/ config/ constants/ controller/ service/ utils/`；與獨立 repo `lion-upload-service` 同前綴、不同部署單位 → **新上傳邏輯放哪先問** |
| `cp-flyway` | — | migration，見 `rules/flyway-migration.md` |

**共享層（跨 repo）：**

| repo | package | 放什麼 |
|------|---------|--------|
| `lion-common` | `com.lc.common.*` | `bean/`（`model/ vo/ so/ query/ bo/ event/ es/ …`）、`dao/`（共用 DAO）、`cache/`（共用 Cache）、`constants/`（含 `EnumClass`）、`service/`（如 `UserMoneyService`） |
| `framework_v3` | `com.cx.framework.*` | Exception、DAO 抽象（`MysqlBaseDaoImpl` / `SqlUtil` / ES 基類）、utils（如 `ApachePoolingHttpClientUtil`） |

## 新類別放哪（決議）

**團隊原則（2026-04-22）：SO / VO / BO / Query / Event / Model / DAO / Cache 一律放 `lion-common`；框架級放 `framework_v3`；本模組 `bean/*` 只留純模組內中介物件，PR 要說明為何不放 common。**（`rules/patterns.md` §8 共享物件放置原則）

| 要新增的東西 | 預設位置 | 例外 |
|-------------|---------|------|
| SO / VO / BO / Query / Event / Model | lion-common `bean/<用途>/<domain>/` | 純模組內中介物件 → 模組 `bean/`（cp-service 目前只有 `bean/query/`） |
| MySQL / ES DAO | lion-common `dao/<domain>/` | 模組私有才放模組 `dao/`（cp-service 目前只有極少數） |
| 共用快取 | lion-common `cache/<domain>/`，繼承 `CacheService<V>`（`skills/springboot-patterns/SKILL.md`） | 模組專屬設定快取 → 模組 `cache/`（如 cp-service `PayConfigCache`） |
| 列舉 / 常數（跨模組用到） | lion-common `constants/` | 模組內用 → 模組 `constants/` |
| 業務邏輯 | 模組 `service/<domain>/` | — |
| 排程 | cp-service：`job/quartz/`（單節點）、`job/scheduler/`（只寫觸發）、`job/service/`（業務） | single-wallet：`schedule/` |
| 單一錢包交易類型 | single-wallet `service/singlewallet/impl/` + `@SingleWalletType` | — |
| 開獎來源 | collector `service/<country>/<source>/` | — |
| Kafka（Spring Cloud Stream） | cp-service `event/`（`input/ output/ emitter/ listener/`） | 不用 `@KafkaListener` / `KafkaTemplate` |
| Filter | 模組 `filter/` | 改 / 新增 = L1（`rules/security.md` §filter 防線） |

放進 lion-common = 跨 repo：lion-common 先發版，lion-service 才能引用（`skills/cross-repo-commit/SKILL.md`）。

## cp-service controller 子目錄（依角色）

| 子目錄 | 角色 | 注意 |
|------|------|------|
| `front/` `center/` | 會員前台 / 個人中心 | platformId 取自 resolver |
| `admin/` | 包網商後台 | 只能操作自家資料 |
| `agent/` `agentline/` | 代理 / 代理線 | 改一處查 `service/agent*`、`service/rebate` |
| `boss/` `manage/` `thirdmanage/` | 跨包網商管理 | 依設計跨包網商，權限要求更高 |
| `commerce/` `quest/` `tag/` | 商務 / 任務 / 標籤 | — |
| `third/` | 第三方回調 | 必驗簽 / IP 白名單 |
| `internal/` | 被其他服務直接 HTTP 呼叫 | 改簽名前 grep 所有 caller；不得掛前端可達路由 |

## 分層依賴方向

```
controller ──► service ──► dao（lion-common / 模組 dao）
     │            │          │
     └────────────┴──► bean（多在 lion-common）◄┘
                      ▲
              cache / redis / http
```

- `controller` 不直接呼叫 `dao`
- `service` 之間可互相依賴，但避免循環
- `bean/model` 不應反向依賴 `service`
- **lion 沒有 MyBatis**：沒有 `mapper/` 目錄，不要新建

## 檢查清單

- [ ] 新類別位置符合上方「新類別放哪」；放模組內的共享型物件，PR 有說明理由
- [ ] controller 只依賴 service，不直接呼叫 dao
- [ ] bean 命名遵循 VO / SO / BO / Query / Record / Event（禁 DTO / Request / Entity，`rules/patterns.md` §8）
- [ ] collector-service 新類別用 `com.cx.collector` 前綴（不是 `com.lc`）
- [ ] 新舊版並存的目錄（`lotteryplan` / `lotteryplanV2`、`activity` / `activity2`）新功能放新版
