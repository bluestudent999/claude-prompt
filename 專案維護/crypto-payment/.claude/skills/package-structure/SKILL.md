---
name: package-structure
description: Spring Boot 後端專案的標準 package 結構模板。用於新專案初始化或重構時，對齊團隊約定的分層與命名。
---

# Spring Boot Package 結構模板

> 以 crypto-payment 主後端 `crypto-payment-service` 的分層約定為基準（base package `com.lion.crypto`）。
> 新模組 / 重構請依此建立 `src/main/java/com/lion/crypto/` 下的骨架。

## 頂層結構

```
src/main/java/com/lion/crypto/
├── controller/                            # REST API 入口（manage / center / system / thirdparty 分區）
├── service/                               # 業務邏輯層（依領域分包，見下）
│   ├── platform/                          # 平台 & 錢包管理、錢包產生
│   ├── user/                              # 用戶錢包 & 入款
│   ├── system/                            # 歸集(sweep)、入款重試、HMAC 驗證
│   └── setting/                           # token / chain / IP / vendor 設定
├── job/                                   # 排程任務（Quartz & @Scheduled）
├── event/                                 # Kafka & Spring event listeners
├── cache/                                 # Redis-backed 快取（依領域分包）
├── repository/                            # DAO
├── filter/                                # security / signature(SignFilter) / webhook filters
├── resolver/                              # method argument resolvers（platform / auth / locale）
└── utils/                                 # 工具類（新增前先查是否已有，現況約 25 類）
```

> 依實際需要可補上 Spring Boot 常見的 `config/`（DataSource / Redis / WebMvc 設定類）與 `constants/`（常數、列舉）；不要為了湊模板憑空建立空目錄。

## 資料物件慣例

> 資料物件的實際放置位置以 repo 現況為準（新增前先 grep 既有同類物件擺哪，不要另起一套目錄）。
> 對外回應**一律用既有 `BaseResponse<T>` 包裝**，禁回傳裸物件。

依資料用途區分（依專案慣例分層 / 分包）：

| 類型 | 用途 | 範例 |
|------|------|------|
| Model / Entity | 對應 DB Table | `WalletModel` |
| VO（View Object） | Response 回前端（外層再包 `BaseResponse<T>`） | `WalletDetailVO` |
| SO（Service Object） | Service 層內部傳遞 | `DepositCreateSO` |
| Query | 查詢參數 | `DepositSearchQuery` |
| BO（Business Object） | 彙總運算結果 | `SweepSummaryBO` |

## cache/ 分包

Redis-backed 快取，依業務領域分包，每個領域內自行組織 `*Cache.java` 與 key 常數：

```
cache/
├── platform/
├── user/
├── system/
└── setting/
```

> 快取失效原則：DB 寫入的同事務內或緊接其後更新 Redis（見 `rules/patterns.md`）。

## config/ 慣例（依實際需要）

```
config/
├── DataSourceConfig.java   # ShardingSphere 5.4 讀寫分離資料源
├── RedisConfig.java        # Jedis
├── KafkaConfig.java        # 原生 Apache Kafka
├── WebMvcConfig.java
└── convert/                # 型別轉換器
```

## 建議分層依賴方向

```
controller ──► service ──► repository
     │            │             │
     └────────────┴──► 資料物件 ◄┘
                      ▲
                 cache / event
```

- `controller` 不直接呼叫 `repository`
- 改狀態的 service 方法必須 `@Transactional`
- `service` 之間可互相依賴，但避免循環
- 依賴注入一律**建構子注入**，禁 `@Autowired` 欄位注入
- Model / Entity 不應反向依賴 `service`

## 套用步驟

1. base package 固定為 `com.lion.crypto`
2. 依實際領域在 `service/`、`cache/` 下建立子包（platform / user / system / setting）
3. 新增 `utils/` 工具類前，先確認既有約 25 個工具類是否已涵蓋
4. 移除不需要的頂層目錄（例如無新排程任務可略過 `job/`）

## 檢查清單

- [ ] 所有 controller 只依賴 service，不直接呼叫 repository
- [ ] service 依領域分包（platform / user / system / setting），不混雜
- [ ] 改狀態的 service 方法標註 `@Transactional`
- [ ] 依賴注入用建構子注入，無 `@Autowired` 欄位注入
- [ ] 對外回應用 `BaseResponse<T>` 包裝
- [ ] 新增工具前已查 `utils/` 是否已有同功能
