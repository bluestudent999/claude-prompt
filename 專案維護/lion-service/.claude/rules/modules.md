# 業務 Domain 索引

> **用途：** 收到需求時，Claude 先比對「業務關鍵字」到下表，**只 grep 對應目錄**，
> 不要全 repo 掃。完整業務規則 → 讀業務知識正本（見 §6 業務知識正本；「業務知識」欄有 domain 名的才有）。
>
> **本檔是輕量索引，不是完整業務知識。** domain 名與目錄是 `ls` 實際列出的事實；業務關鍵字取自團隊既有索引。
>
> **風險等級說明：**
> - **L1** — 金額 / 結算 / 狀態機 / 併發 / 冪等 / 第三方對接 / 包網商隔離 / filter 放行 / 賠率、限額、開獎（reviewer 全套派）
> - **L2** — 一般 service / controller / 業務邏輯但非金流（reviewer 擇一）
> - **L3** — config / DTO / i18n / 純 wiring（code-reviewer 輕掃）
> - **?** — 未填 / 未確認，收到需求時**預設升級不降級**（當 L2 處理）
>
> **不論哪一列**：改動若涉及「查詢 / 匯出 / 快取 key / ES / 排程批次帶不帶 platformId」或「`*Filter` / 放行清單」→ 直接升 **L1**（`rules/platform-isolation.md`、`rules/security.md` §filter 防線）。

---

## 使用方式（主 agent 參考）

1. 收需求 → 看使用者寫的「業務關鍵字」欄位
2. 對照本檔 §2 / §3 / §4 表格，找到**最窄的 domain 列**（不是第一個 match 就停）
3. 該列的「對應目錄」= grep / Read 的範圍上限，**禁止擴大**
4. 若表中找不到對應 domain → 先用 Explore agent quick 搜全 repo 抓關鍵字，再回來補 index
5. 該列「業務知識」欄有 domain 名 → 依 §6 讀業務知識正本
6. 跨模組需求 → 參照「常連帶」欄追加 grep 範圍；碰到新舊版並存（§5）先分清楚是哪一版
7. 關鍵字不在表內 → Grep `../lion-common/src/main/java/com/lc/common/bean/` 縮小範圍

---

## 1. 模組總覽

**本 repo（根 pom `<modules>` 只有 4 個）：**

| 模組 | base package | 本質 |
|------|------------|------|
| `cp-service` | `com.lc.cp` | 最大最核心：主業務、活動、報表、遊戲、代理、彩票計畫；`controller/` 依角色分子目錄；`job/` 100+ 排程 |
| `single-wallet-service` | `com.lc.single.wallet` | 單一錢包，**金額敏感度最高**；`@SingleWalletType` + `SingleWalletContext` 自動註冊交易類型 |
| `collector-service` | `com.cx.collector`（前綴不同是歷史沿革，不是 typo） | 開獎資料爬蟲聚合；無金額但**資料品質 = 金錢**（錯開獎 → 錯結算） |
| `upload-service` | `com.lc.upload` | 上傳；與獨立 repo `lion-upload-service` 同 package 前綴、不同部署單位，**新上傳邏輯放哪要先問** |
| `cp-flyway`（**不在 reactor**） | — | Flyway migration，見 `rules/flyway-migration.md` |

> 團隊根 `CLAUDE.md` 列的 `crypto-collector`、`websocket-service` **在 repo 裡不存在**（過期記載）。

**sibling repo（跨 repo，與 lion-service 同層 clone；本機未必每個都有，找不到就告知使用者，不要憑印象寫跨 repo 的行為）：**

| repo | 角色 | package |
|---|---|---|
| `framework_v3` | 底層：Exception、DAO 抽象（`MysqlBaseDaoImpl` / `SqlUtil` / ES 基類）、utils | `com.cx.framework.*` |
| `lion-common` | 共享層：model、VO/SO/BO/Query/Event、共用 DAO、Cache、常數列舉（含 `EnumClass.TranType`）、`UserMoneyService.changeMoney*` | `com.lc.common.*` |
| `lion-core` | 結算 / 派彩（`settle-service`） | `com.lc.lion.settle.*` |
| `lion-frontend` / `lion-manage` | 前端總倉 / 總控制中心（含前端） | — |

---

## 2. cp-service domain 索引

> 路徑前綴：`cp-service/src/main/java/com/lc/cp/service/<domain>/`（下表「對應目錄」只寫 `<domain>/`）。
> 所有 domain 均可能連帶 `lion-common`（bean / DAO / Cache 定義），「常連帶」欄只列**額外**連帶。

| 業務關鍵字 | domain | 對應目錄 | 風險 | 業務知識 | 常連帶 |
|-----------|--------|---------|------|---------|--------|
| 活動 | activity | `activity/` | ? | — | `activity2`（新舊版並存，§5） |
| 活動（新版） | activity2 | `activity2/` | ? | — | `activity` |
| 代理 | agent | `agent/` | L1 | — | `agentline`、`rebate`、`controller/agentline/`（改一處必查三處） |
| 代理佣金結算 / 負盈利 / 流水佣金 / 充值返利 / 代理線報表 / 結算週期 / 總代 / 代理線 | agentline | `agentline/` | L1 | agentline | `agent*`、`rebate`、`controller/agentline/` |
| 廣告分析傳送 | appsFlyer | `appsFlyer/` | ? | — | — |
| 對賭系統 | arbitrage | `arbitrage/` | ? | — | — |
| bigo | bigo | `bigo/` | ? | — | — |
| 真人視訊遊戲 | cglive | `cglive/` | ? | — | — |
| 彩票風控、盈利 | cgmanage | `cgmanage/` | ? | — | — |
| 聊天室 | chat | `chat/` | ? | — | `controller/internal/ChatController` |
| 商務後台對接 / 商務報表 / 充值推送 Commerce | commerce | `commerce/` | ? | commerce | `controller/commerce/` |
| 幣種 / 幣別 / 匯率 | currency | `currency/` | ? | — | — |
| 會員資料導入 | cvs | `cvs/` | ? | — | — |
| demo 平台 | demo | `demo/` | ? | — | — |
| 飛單 | fly | `fly/` | ? | — | — |
| 免費旋轉 / 免費投注 / SpinBonus / 三方憑證 | freespin | `freespin/` | L1 | freespin | `job/scheduler/freespin/` |
| 資金報表（充值、提現） | funds | `funds/` | L1 | — | `recharge`、`pay` |
| 彩票遊戲、遊戲機器人、賠率、彩種時間、遊戲報表、jackpot | game | `game/` | ? | — | `playcom`、`lottery` |
| 彩票遊戲水位 | gamingpoolalarm | `gamingpoolalarm/` | ? | — | — |
| httputil | http | `http/` | ? | — | — |
| 國際化字典（DB 動態多語翻譯）/ InternationalCache | international | `international/` | ? | international | `rules/i18n.md`（properties 之外的 DB 翻譯） |
| 直播 | live | `live/` | ? | — | — |
| 直播遊戲 | livegame | `livegame/` | ? | — | — |
| 彩票遊戲 / 投注 / 注單 / 派彩 / 開獎 | lottery | `lottery/` | L1 | lottery | `lion-core`（派彩）、`collector-service`（官方開獎來源）、`validation/` |
| 彩票推送計畫 | lotteryplan | `lotteryplan/` | ? | — | `lotteryplanV2`（部分重複但不等價，§5） |
| 推送計畫新版 | lotteryplanV2 | `lotteryplanV2/` | ? | — | `lotteryplan` |
| 推送計劃設定 | lotteryplanproject | `lotteryplanproject/` | ? | — | `lotteryplan*` |
| 彩票單錢包 | lotterysinglewallet | `lotterysinglewallet/` | L1 | — | `single-wallet-service` |
| 全民代理 | memberline | `memberline/` | ? | — | `recharge` |
| 國家 | nation | `nation/` | ? | — | — |
| 站內信 / 消息中心 / 推送公告 / JPush | notice | `notice/` | ? | notice | — |
| 追號、收藏 | offical | `offical/` | ? | — | `lottery` |
| 首頁彩票遊戲導航 | openlottery | `openlottery/` | ? | — | — |
| 轉化率分析 | operationData | `operationData/` | ? | — | — |
| 充值 / 提現 / 第三方支付 / 鏈上 | pay | `pay/` | L1 | pay | `recharge`、`funds`、`lion-common`（`UserMoneyService`） |
| pixel | pixel | `pixel/` | ? | — | — |
| 平台設定 / 平台費 / 第三方成本分攤 / 結算報表 | platform | `platform/` | L1 | platform | `report` |
| 彩票玩法、賠率 / 下注上限 / 浮動賠率 / 球號賠率 | playcom | `playcom/` | L1 | playcom | `randomodds`、`game`、`lion-core` |
| 任務 / 任務系統 | quest | `quest/` | ? | — | `controller/quest/` |
| 隨機賠率 | randomodds | `randomodds/` | L1 | — | `playcom` |
| 反水 / 返水 / 流水累積 / 防洗碼 | rebate | `rebate/` | L1 | rebate | `agentline`、`agent*` |
| 充值 / 充值活動 / 鏈上支付 / 自動拒絕 / 人工提現審核 | recharge | `recharge/` | L1 | — | `pay`、`funds`、`withdrawcheck` |
| 紅包雨 | redenp | `redenp/` | ? | — | — |
| 報表 / 日報 / 統計 / 財務統計 | report | `report/` | ? | — | `export/`（匯出也要帶 platformId） |
| 風控對外 / 彩票投注風控通知 | risk | `risk/` | ? | — | — |
| 風控設定 | risksetting | `risksetting/` | ? | — | — |
| 彩票路單 / 路圖 | roadmap | `roadmap/` | ? | — | — |
| 角色權限 / 選單 | roleauth | `roleauth/` | ? | — | cp-flyway / changelog（選單常以 SQL 上版） |
| 系統設定 / 系統參數 / 廣告 / 銀行卡黑名單 / 域名 | setting | `setting/` | ? | — | `lion-common`（`FrontConfigVO`，`rules/patterns.md` §8.5） |
| 系統初始化 / API 告警 | system | `system/` | ? | — | — |
| 標籤 / 會員標籤 | tag | `tag/` | ? | — | `controller/tag/` |
| Telegram 設定 / 推播 | telegram | `telegram/` | ? | — | — |
| 三方平台 / 三方遊戲 / 三方場館 | third | `third/` | L1 | — | `controller/third/`、`single-wallet-service` |
| 三方票券 | thirdVoucher | `thirdVoucher/` | ? | — | — |
| 三方管理（登入 / 轉帳 / 統計） | thirdmanage | `thirdmanage/` | L1 | — | `controller/thirdmanage/`（跨包網商，權限要求更高） |
| 會員 / 登入 / Token / 裝置 | user | `user/` | ? | — | `rules/stability.md`（Token 相容） |
| 虛擬投注 | virtualbet | `virtualbet/` | ? | — | — |
| 打碼流水稽核 / 反洗碼 / 提現前置稽核（**非**人工提現審核，那在 `recharge`） | withdrawcheck | `withdrawcheck/` | L1 | withdrawcheck | `recharge` |
| 無交易通知（活動 / 投注 / 飛單 / 反流水重置） | withouttx | `withouttx/` | ? | — | — |
| 世界盃活動 / 競猜 | worldcup | `worldcup/` | ? | — | — |

**cp-service 非 service/ 的關鍵位置：**

| 位置 | 風險 | 注意 |
|---|---|---|
| `controller/internal/` | L1 | 被其他服務直接 HTTP 呼叫；改簽名前 grep 所有 `RestTemplate` / Feign caller；絕不掛前端可達路由 |
| `controller/third/` | L1 | 必驗簽 / IP 白名單 |
| `filter/`（`MyFilter`、`SignFilter`、`PlatformSignFilter`、`SqlInjectAndXssFilter`…） | L1 | 曾被繞過入侵；`checks/filter-bypass.md` |
| `config/CustomWebMvcConfig` 與 `*MethodArgumentResolver` | L1 | platformId / 登入者的唯一來源 |
| `job/`（`quartz/`、`scheduler/`、`service/`） | 依業務 | 冪等；`scheduler/` 只寫觸發；金額排程不得吞例外 |
| `analysis/` | ? | 遺漏分析；新地區繼承 `AbstractMissAnalysis` |
| `sms/impl/` | ? | 13 個 provider，`New*Service` 是新版、舊版不動 |
| `export/` | L1（若含他家資料風險） | 匯出必帶 platformId |

---

## 3. single-wallet-service domain 索引

> 路徑前綴：`single-wallet-service/src/main/java/com/lc/single/wallet/service/<domain>/`。
> 本模組**全部視為 L1**（每筆呼叫直接影響玩家餘額）。金額 8 步順序見 `rules/security.md`。

| 業務關鍵字 | domain | 對應目錄 | 風險 | 常連帶 |
|-----------|--------|---------|------|--------|
| 餘額查詢 / 扣減 / 加款（所有金額異動必走） | balance | `balance/` | L1 | `transaction` |
| 金額工具（格式化、換算） | money | `money/` | L1 | — |
| 單一錢包對接 / 交易類型（`@SingleWalletType`） | singlewallet | `singlewallet/` | L1 | `lion-common`（`EnumClass.TranType`）、`context/SingleWalletContext` |
| 對第三方廠商反向呼叫 | third | `third/` | L1 | — |
| 交易流水（`TransactionV2Service`） | transaction | `transaction/` | L1 | `balance` |
| 驗簽入口 | — | `filter/SingleWalletSignFilter.java` | L1 | 改了等於改所有廠商的對接合約；`checks/filter-bypass.md` |
| 回廠商狀態碼 | — | `constants/RespStateEnum.java` | L1 | 對接合約，回歸所有廠商 |

---

## 4. 其他模組與跨 repo

| 業務關鍵字 | 位置 | 風險 | 常連帶 / 注意 |
|-----------|------|------|--------------|
| 開獎資料 / 爬蟲 / 彩種代碼 / 資料來源 | `collector-service/` | L1 | `GameCodeDictionary` 必登記；`/getAllLotterys.do` 拼字與 `.do` 不可改（cp-service 寫死）；`${vienam.api-key}` 拼字是 legacy 別糾正；走 `SourceProxyService`；時區 GMT+8 |
| 上傳 | `upload-service/` | ? | 與 `lion-upload-service`（獨立 repo）同前綴，新邏輯放哪先問 |
| DB schema / Flyway / DDL / 手動上版 SQL | `cp-flyway/`、`zz_document/script/changelog/` | L1 | 兩條 SQL 軌，`rules/flyway-migration.md` |
| SO / VO / BO / Query / Event / model / 共用 DAO / Cache | `lion-common`（跨 repo） | L2 | 改 enum / DAO / `UserMoneyService` → L1；多 repo 同步見 `cross-repo-commit` skill |
| 底層框架 / DAO 基類 / 例外 | `framework_v3`（跨 repo） | L2 | 影響所有下游 |
| 結算規則 / 派彩計算 | `lion-core`（跨 repo） | L1 | 本 repo 不改；列跨 repo 影響清單 |
| 後台 / 代理端 / 前台 UI、前端 i18n | `lion-frontend` / `lion-manage`（跨 repo） | — | 本 repo 不改前端；列跨 repo 影響清單 |

---

## 5. 新舊版並存（線上都在跑，不是死碼）

| 舊版 | 新版 | 規則 |
|------|------|------|
| `service/lotteryplan*` | `service/lotteryplanV2` | 部分重複但**不等價**；改動先確認影響哪一版使用者 |
| `service/activity` | `service/activity2` | 新功能用新版 |
| `sms/impl/SmsbaoService` 等 | `sms/impl/NewSmsbaoService` 等 | 部分舊商戶設定仍走舊版 |
| collector `MacaumCollectService` | `NewMacaumCollectService`、`NewMacaumV2CollectService` | 同上 |

**共同規則：** 新功能用新版、**舊版不動**；要刪舊版前先查商戶設定是否仍在用，查不到就問使用者，**不自行判定為死碼**。

---

## 6. 業務知識正本

lion 的業務 domain 知識由**團隊維護在 git 版的 `.claude/skills/business/<domain>/SKILL.md`**。本範本**不複製**這些檔案；部署本範本後，工作目錄的 `.claude/` 會被取代，所以那些檔案在工作目錄裡**不存在**，要從 git 讀。

**有正本的 11 個 domain（用途取自團隊正本的 INDEX：`git show origin/developing:.claude/skills/business/INDEX.md`）：**

| domain | 用途 |
|---|---|
| `agentline` | 代理結算 / 流水佣金 / 充值返利 |
| `commerce` | commerce-management 三方對接資料流 |
| `freespin` | 免費旋轉 / 派發紀錄 / 不入打碼 |
| `international` | 後端 i18n 字典（messages.properties 之外的 DB 動態翻譯） |
| `lottery` | 彩期 / 開獎結果（lion-core settle 上游） |
| `notice` | 消息中心 / 推送公告 / JPush 三層架構 |
| `pay` | 充值 / 提現支付（含鏈上） |
| `platform` | 平台費結算 / 主報表 |
| `playcom` | 玩法 / 賠率 / 浮動賠率 / 下注上限 |
| `rebate` | 反水 / 流水累積 / 防洗碼 |
| `withdrawcheck` | 打碼稽核 / 14 天過期（非人工提現審核） |

**讀法：**

```bash
git show origin/developing:.claude/skills/business/<domain>/SKILL.md
# 讀不到（本機沒 fetch 過 / 遠端名不同）→ 退一步
git show HEAD:.claude/skills/business/<domain>/SKILL.md
```

- 兩個都讀不到 → **告知使用者**「業務知識正本讀不到」，**不要憑印象補業務規則**
- 正本內容是**業務事實來源**；與程式碼衝突時以程式碼為準，並在 spec 標 `⏳` 請使用者確認哪邊過期
- 派子 agent 時，briefing 給「domain 名 + 上述讀法」，不要把正本全文貼進 prompt

**為什麼不複製：** 團隊持續更新正本（狀態從 🚧 升 ✅、補新 domain），複本一旦落後就會給出過期的業務規則，而且沒人會發現兩份已經不一樣。

**新增 / 修改業務知識：** 團隊寫業務 skill 的規範在 `git show origin/developing:.claude/skills/business/CONTRIBUTING.md`（claim → 填模板 → PO 確認 → 標 ✅）。要新增或修改業務知識 → **回團隊 repo 走他們的流程**，不在本範本改，也不在工作目錄建 `skills/business/`。

---

## 7. 如何新增 domain 列

當 Explore agent 幫你找到新 domain（或 `ls` 發現本表漏列的目錄）後，補一行到對應表格：

```
| <業務關鍵字> | <domain 名> | `<domain>/` | L? | <有正本填 domain 名，否則 —> | <常連帶> |
```

- 業務關鍵字以需求實際會用的詞為主，多個用 `/` 分隔；兩列關鍵字重疊時要寫得**互斥**
- 風險依上方 L1/L2/L3 定義；有疑問升級不降級（不確定填 `?`）
- 「業務知識」欄只在 §6 正本清單內的 domain 才填；團隊新增正本後，同步把 domain 加進 §6 表與本欄
