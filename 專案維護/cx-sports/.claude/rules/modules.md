# 業務 Domain 索引

> **用途：** 收到需求時，Claude 先比對「業務關鍵字」到下表，**只 grep 對應目錄**，
> 不要全 repo 掃。完整業務規則 → 去載 `<domain>-business-knowledge` skill（若「完整 skill」欄 ✅）。
>
> **本檔是輕量索引，不是完整業務知識。**
>
> **風險等級說明：**
> - **L1** — 金額 / 結算 / 狀態機 / 併發 / 冪等 / 第三方對接（reviewer 全套派）
> - **L2** — 一般 service / controller / 業務邏輯但非金流（reviewer 擇一）
> - **L3** — config / DTO / i18n / 純 wiring（code-reviewer 輕掃）
> - **?** — 未填 / 未確認，收到需求時**預設升級不降級**（當 L2 處理）

---

## 使用方式（主 agent 參考）

1. 收需求 → 看使用者寫的「業務關鍵字」欄位（6 欄位模板）
2. 對照本檔第 2 / 3 節表格，找到**最窄的 domain 列**（不是第一個 match 就停）
3. 該列的「對應目錄」= grep / Read 的範圍上限，**禁止擴大**
4. 若表中找不到對應 domain → 先用 Explore agent quick 搜全 repo 抓關鍵字，再回來補 index
5. 若該 domain「完整 skill」欄 ✅ → 同時載入對應 skill
6. 跨模組需求 → 參照「常連帶模組」欄追加 grep 範圍
7. 關鍵字不在表內 → Grep `lib/cx-sport-common/bean/` 縮小範圍

---

## 1. Service 模組總覽

| 模組 | base package | 主要 service/ 子目錄 |
|------|------------|---------------------|
| `cx-sport-app-service` | `com.lc.sports` | betrank, chat, collector, common, credit, currency, cxgame, freespin, front, internal, livechat, match, mts, quest, rebate, report, settle, simulation, singlewallet, specialmarket, user |
| `cx-sport-single-wallet-service` | `com.lc.single.wallet` | money/, singlewallet/ |
| `cx-sport-mq-collector-service` | — | — |
| `cx-sport-memdb-service` | — | — |
| `cx-sport-websocket-service` | — | — |
| `manage-center/manage-service` | — | 商戶 / 活動 / 後台管理 |
| `lib/cx-sport-settle-rule` | — | 結算 / 派彩 / 反水規則 |
| `lib/cx-sport-common` | `com.lc.sports.bean.*` | SO / VO / BO / Event / Query |
| `lib/sport-framework` | — | 共用工具 / DAO 基類 / 例外類 |

---

## 2. cx-sport-app-service domain 索引

> 所有 domain 均連帶 `lib/cx-sport-common`（bean 定義），「常連帶模組」欄只列**額外**連帶模組。

| 業務關鍵字 | domain / 子目錄 | 對應目錄 | 風險 | 完整 skill | 常連帶模組 |
|-----------|--------------|---------|------|-----------|----------|
| 投注 / 下注 / 注單 / bet | betrank | `cx-sport-app-service/.../service/betrank/` | L1 | ❌ | `lib/cx-sport-settle-rule` |
| 賠率 / 盤口 / 特殊盤 | specialmarket | `cx-sport-app-service/.../service/specialmarket/` | L1 | ❌ | — |
| 賽事 / 比賽 / 聯賽 / match | match | `cx-sport-app-service/.../service/match/` | L2 | ❌ | — |
| 結算 / 派彩 / 開獎 / settle | settle | `cx-sport-app-service/.../service/settle/` + `lib/cx-sport-settle-rule/` | L1 | ❌ | `lib/cx-sport-settle-rule` |
| 反水 / 佣金 / rebate | rebate | `cx-sport-app-service/.../service/rebate/` | L1 | ❌ | `lib/cx-sport-settle-rule` |
| 積分 / credit | credit | `cx-sport-app-service/.../service/credit/` | L1 | ❌ | — |
| 會員 / 用戶 / 登入 / 註冊 / user | user | `cx-sport-app-service/.../service/user/` | L1 | ❌ | — |
| 前台 / 使用者端 / front | front | `cx-sport-app-service/.../service/front/` | L2 | ❌ | — |
| 幣別 / 匯率 / currency | currency | `cx-sport-app-service/.../service/currency/` | L2 | ❌ | — |
| 任務 / quest | quest | `cx-sport-app-service/.../service/quest/` | L2 | ❌ | — |
| 免費旋轉 / freespin | freespin | `cx-sport-app-service/.../service/freespin/` | L1 | ❌ | — |
| 第三方遊戲 / 外接遊戲 / cxgame | cxgame | `cx-sport-app-service/.../service/cxgame/` | L1 | ❌ | `cx-sport-single-wallet-service` |
| 報表 / 日結 / report | report | `cx-sport-app-service/.../service/report/` | L2 | ❌ | — |
| 模擬 / simulation | simulation | `cx-sport-app-service/.../service/simulation/` | L3 | ❌ | — |
| MTS | mts | `cx-sport-app-service/.../service/mts/` | L1 | ❌ | — |
| 聊天室 / chat | chat | `cx-sport-app-service/.../service/chat/` | L2 | ❌ | — |
| livechat | livechat | `cx-sport-app-service/.../service/livechat/` | L2 | ❌ | — |
| 內部 / internal API | internal | `cx-sport-app-service/.../service/internal/` | L2 | ❌ | — |
| 採集 / collector | collector | `cx-sport-app-service/.../service/collector/` | L2 | ❌ | — |
| 共用 / common service | common | `cx-sport-app-service/.../service/common/` | ? | ❌ | — |
| 單一錢包（app 側） | singlewallet | `cx-sport-app-service/.../service/singlewallet/` | L1 | ❌ | `cx-sport-single-wallet-service` |
| 站內信 / 通知 / 系統公告 / 消息中心 / notice | notice | `cx-sport-app-service/.../service/notice/` | L2 | ✅ `.claude/skills/business/notice/` | `cx-sport-websocket-service` |
| 全民代理 / 會員代理 / 會員佣金 / 流水佣金 / 充值返佣 / memberline | memberline | `cx-sport-app-service/.../service/memberline/` | L1 | ✅ `.claude/skills/business/memberline/` | `recharge`、`usermoney`、`withdraw` |
| 代理 / 佣金 / 分紅 / 代理結算 / 代理提款 / agent | agent | `cx-sport-app-service/.../service/agent/` | L1 | ✅ `.claude/skills/business/agent/` | `lib/cx-sport-common`（Enum） |

---

## 3. cx-sport-single-wallet-service domain 索引

| 業務關鍵字 | domain / 子目錄 | 對應目錄 | 風險 | 完整 skill | 常連帶模組 |
|-----------|--------------|---------|------|-----------|----------|
| 單一錢包 / 第三方錢包 / 錢包對接 | singlewallet | `cx-sport-single-wallet-service/.../service/singlewallet/` | L1 | ❌ | `cx-sport-app-service`（app 側） |
| 餘額 / 轉入 / 轉出 / 扣款 | money | `cx-sport-single-wallet-service/.../service/money/` | L1 | ❌ | `cx-sport-common` |
| 錢包設定 / 幣別 | config/currency | `cx-sport-single-wallet-service/.../service/` | L2 | ❌ | `cx-sport-common` |

---

## 4. 其他後端模組

| 業務關鍵字 | 模組 | 對應目錄 | 風險 | 常連帶模組 |
|-----------|------|---------|------|----------|
| MQ / Kafka 消費 / 事件消費 | `cx-sport-mq-collector-service` | `cx-sport-mq-collector-service/` | L2 | `cx-sport-common`（Event 物件） |
| WebSocket / 即時推送 / 協議 | `cx-sport-websocket-service` | `cx-sport-websocket-service/` | L2 | `lib/cx-sport-ws-protocol-base`、`cx-sport-common` |
| 記憶體快取 / memdb | `cx-sport-memdb-service` | `cx-sport-memdb-service/` | L2 | `cx-sport-common` |
| 商戶 / 活動 / 後台管理 | `manage-center/manage-service` | `manage-center/manage-service/` | L2 | `cx-sport-common`、`manage-center/manage-frontend` |
| SO / VO / BO / Event / Query / 領域模型 | `lib/cx-sport-common` | `lib/cx-sport-common/bean/` | L3 | — |
| 結算規則 / 派彩規則 | `lib/cx-sport-settle-rule` | `lib/cx-sport-settle-rule/` | L1 | `cx-sport-app-service`、`cx-sport-common` |
| ES 索引 / 查詢 / 主從切換 | 依業務模組（多數在 app-service） | `cx-sport-app-service/.../dao/es/` | L2 | `lib/sport-framework`（DAO 基類） |
| 共用工具 / DAO 基類 / 例外類 / 抽象 | `lib/sport-framework` | `lib/sport-framework/` | L3 | — |
| DB schema / Flyway 遷移 / DDL | Flyway（獨立 repo） | — | L1 | — |
| 系統參數 / FrontConfigVO / 平台設定 | `lib/cx-sport-common` + `admin-frontend/SystemParam.vue` | `lib/cx-sport-common/` | L3 | 後端 `ConfigService` 反射映射，不需改 |
| 入款 / 出款 / 餘額 / 流水 / 錢包 | `cx-sport-app-service` 或 `cx-sport-single-wallet-service` | — | L1 | 🚧 `.claude/skills/business/pay/` | 視內部錢包 or 第三方錢包，**不確定先問** |

---

## 5. 前端子專案路由

> Vue 2，build 獨立於後端 Maven reactor。
> **控制中心 vs 總控制中心（常混淆）**：控制中心（單一平台）→ `lion-frontend/ctrl-center-frontend`；總控制中心（跨平台）→ `manage-center/manage-frontend`。不同 build，不可混。

| 業務關鍵字 | 子專案 | 常見子目錄 |
|-----------|--------|-----------|
| 系統參數 / 商戶 / 會員 / 活動 UI | `lion-frontend/admin-frontend` | `src/components/platformsettle/`、`src/components/member/` |
| 代理後台 UI | `lion-frontend/agent-front` | — |
| Boss 控制台 UI（平台運營端） | `lion-frontend/boss-crtl-center` 或 `manage-center/boss-frontend` | — |
| **控制中心 UI**（平台費用 / 抽成方案 / 第三方對接） | `lion-frontend/ctrl-center-frontend` | `src/components/platform/scheme/`、`src/components/platform/report/` |
| MQ 監控 UI | `lion-frontend/mq-frontend` | — |
| **總控制中心 UI**（manage 側後台、跨平台總覽） | `manage-center/manage-frontend` | — |
| MTS UI | `manage-center/mts-frontend` | — |
| 聊天室（靜態頁，原生 HTML/JS） | `lion-frontend/chatroom` | — |

---

## 6. 如何新增 domain 列

當 Explore agent 幫你找到新 domain 後，補一行到對應表格：

```
| <業務關鍵字> | <domain 名> | `<模組>/.../service/<domain>/` | L? | ❌ | <常連帶模組> |
```

建立完整 business skill 後：

1. 複製 `.claude/skills/business/_template/` 為 `.claude/skills/business/<domain>/`（例：`.claude/skills/business/settle/`）
2. 填完內容後回本檔把「完整 skill」欄改為：
   - `🚧 .claude/skills/business/<domain>/` — 草稿中
   - `✅ .claude/skills/business/<domain>/` — 完成可載入

> **注意**：Claude Code 的 skill loader 不遞迴掃描子目錄，`business/<domain>/SKILL.md` **不會**自動出現在 `/skills` 清單，這是有意設計（避免 60+ skill description 吃 prompt token）。主 agent 透過本檔索引找到路徑後直接 Read 即可，子 agent 由 briefing 指路。
