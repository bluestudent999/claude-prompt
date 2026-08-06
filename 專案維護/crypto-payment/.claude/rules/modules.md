# 業務 Domain 索引（crypto-payment）

> **用途：** 收到需求時，Claude 先比對「業務關鍵字」到下表，**只 grep 對應目錄**，不要全 repo 掃。
>
> **本檔是輕量索引，不是完整業務知識。** 深入業務規則見 `blockchain-wallet` skill。
>
> **風險等級：**
> - **L1** — 金額 / 入帳 / 歸集 / 狀態機 / 併發 / 冪等 / **私鑰** / **AES-GCM** / **HMAC 驗簽** / **platform_id 隔離** / webhook / 鏈對接
> - **L2** — 一般 service / controller / 業務邏輯但非金流
> - **L3** — config / VO / 純 wiring / typo
> - **?** — 未確認，**預設升級不降級**（當 L2 處理）

---

## 使用方式（主 agent 參考）

1. 收需求 → 看使用者寫的「業務關鍵字」欄位
2. 對照下表，找到**最窄的 domain 列**（不是第一個 match 就停）
3. 該列的「對應目錄」= grep / Read 的範圍上限，**禁止擴大**
4. 表中找不到 → 先用 Explore agent quick 搜 `crypto-payment-service/src/main/java/com/lion/crypto/` 抓關鍵字，再回來補 index
5. 立即預判 L 層並輸出給使用者確認（例：`預判 L 層：L1（私鑰/AES-GCM）`），寫入後續 spec §風險評估
6. **多租戶提醒：** 任何 domain 的查詢都要確認 `platform_id` 過濾（見 `security.md`）

---

## 1. 後端 service 模組（base package `com.lion.crypto`）

| 業務關鍵字 | domain / 子目錄 | 對應目錄 | 風險 | 說明 |
|-----------|--------------|---------|------|------|
| 平台 / 商戶 / 錢包產生 / 熱錢包 / 平台設定 | platform | `service/platform/` | L1 | 平台與錢包管理；**錢包產生邏輯只在這裡，禁他處重複** |
| 用戶錢包 / 入款 / 存款 / deposit / 入帳 | user | `service/user/` | L1 | 用戶錢包與入款處理（credit 用戶帳戶） |
| 歸集 / sweep / collector / 入款重試 / HMAC 驗證 | system | `service/system/` | L1 | collector 歸集、deposit retry、HMAC verifier |
| token 設定 / chain 設定 / IP 白名單 / vendor / provider 設定 | setting | `service/setting/` | L2 | token / chain / IP / vendor 組態 |
| 後台管理 / 角色 / 選單 / RBAC / 平台 config | controller/manage | `controller/manage/` + `service/` | L2 | `/api/manage/*`；權限相關升 L2+ |
| 支付 API / 對外下單 / 簽章請求 | controller + filter | `controller/` + `filter/SignFilter` | L1 | `/api/pay/*`，HMAC + IP 白名單，**不可繞過 SignFilter** |
| webhook / 回調 / QuickNode / Tatum / chain log | controller/thirdparty + event | `controller/thirdparty/` + `event/` | L1 | `/api/thirdparty/*`，驗簽後解析 chain log |
| 排程 / job / Quartz / 定時 | job | `job/` | L2 | Quartz & `@Scheduled`；需冪等 |
| Kafka / 事件 / event listener | event | `event/` | L2 | Kafka & Spring event listeners |
| 快取 / Redis / cache 失效 | cache | `cache/` | L2 | Redis-backed；寫 DB 後須失效 |
| DAO / repository / 查詢 | repository | `repository/` | L2 | ShardingSphere 5.4 自動讀寫分離 |
| filter / 簽章 / 驗簽 / IP / locale | filter / resolver | `filter/` `resolver/` | L1 | SignFilter / webhook filter；改 SignFilter 須確認 |
| 工具類 / util / 加解密工具 | utils | `utils/`（25 類） | L2 | **新增前先查是否已有**；含 Aes/Gcm/Encrypt 類改動須確認 |

## 2. DB / Migration

| 業務關鍵字 | 模組 | 對應目錄 | 風險 | 說明 |
|-----------|------|---------|------|------|
| DB schema / DDL / Flyway 遷移 | crypto-payment-flyway | `crypto-payment-flyway/src/main/resources/db/migration/` | L1 | **只增新版號檔（V1_0_x__desc.sql），禁改既有** |

## 3. 前端子專案

> Vue 2 + Element UI + Vuex + Webpack 3，build 獨立於後端 Maven。

| 業務關鍵字 | 對應目錄 | 常見子目錄 |
|-----------|---------|-----------|
| 後台 UI / 平台管理 / 錢包 / 交易列表 / 設定頁 | `front/crypto-payment-admin-frontend/src/` | `views/`、`components/`、`store/`（Vuex）、`utils/request.js`（Axios） |

---

## 4. 如何新增 domain 列

當 Explore agent 找到新 domain 後，補一行到對應表格：

```
| <業務關鍵字> | <domain 名> | `service/<domain>/` | L? | <說明> |
```

> 需要完整業務知識時載入 `blockchain-wallet` skill（入款流程、歸集門檻、鏈差異、webhook 驗簽細節）。
