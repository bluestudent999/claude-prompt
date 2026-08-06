---
name: package-structure
description: Spring Boot 後端專案的標準 package 結構模板。用於新專案初始化或重構時，對齊團隊約定的分層與命名。
---

# Spring Boot Package 結構模板

> 此結構為團隊慣用的分層約定。新專案請依此建立 `src/main/java/<base-package>/` 下的骨架。

## 頂層結構

```
src/main/java/{{base-package}}/
├── {{ApplicationName}}Application.java   # Spring Boot 啟動入口
├── annotation/                            # 自訂註解
├── aspect/                                # AOP 切面（日誌、權限、限流等）
├── bean/                                  # 資料模型（依用途分層，見下）
├── cache/                                 # 快取存取層（依領域分包）
├── config/                                # Spring 設定類（DataSource、ES、Convert…）
├── constants/                             # 常數、列舉
├── controller/                            # REST API 入口
├── dao/                                   # MyBatis/JPA Mapper/Repository
├── filter/                                # Servlet Filter
├── http/                                  # 對外 HTTP 客戶端封裝
├── job/                                   # 排程任務
├── redis/                                 # Redis 操作封裝（若 cache/ 無法涵蓋）
├── resolver/                              # ArgumentResolver、HandlerMethodResolver
├── service/                               # 業務邏輯層
└── util/                                  # 純工具類
```

## bean/ 分層

`bean/` 下**依資料用途**而非領域分層。每一子層再依業務領域分包（如 `user/`、`game/`、`platform/`）。

| 子層 | 用途 | 範例 |
|------|------|------|
| `model/` | 對應 DB Table 的 entity | `UserModel.java` |
| `vo/` | View Object — Response 回前端 | `UserDetailVO.java` |
| `so/` | Service Object — Service 層內部傳遞 | `UserCreateSO.java` |
| `query/` | Query Object — Request 查詢參數 | `UserSearchQuery.java` |
| `bo/` | Business Object — 彙總運算結果 | `ReportSummaryBO.java` |

### bean 範例結構

```
bean/
├── model/
│   ├── user/UserModel.java
│   ├── game/GameModel.java
│   └── platform/PlatformModel.java
├── vo/
│   ├── user/UserDetailVO.java
│   └── page/PageVO.java
├── so/
│   └── user/UserCreateSO.java
├── query/
│   └── user/UserSearchQuery.java
└── bo/
    └── report/ReportSummaryBO.java
```

## cache/ 分包

依業務領域分包，每個領域內自行組織 `*Cache.java` 與 key 常數：

```
cache/
├── auth/
├── user/
├── game/
├── platform/
├── system/
└── router/
```

## config/ 慣例

```
config/
├── DataSourceConfig.java
├── RedisConfig.java
├── WebMvcConfig.java
├── es/                  # Elasticsearch 相關
└── convert/             # 型別轉換器
```

## 建議分層依賴方向

```
controller ──► service ──► dao
     │            │          │
     └────────────┴──► bean ◄┘
                      ▲
              cache / redis / http
```

- `controller` 不直接呼叫 `dao`
- `service` 之間可互相依賴，但避免循環
- `bean/model` 不應反向依賴 `service`

## 套用步驟

1. 將 `{{base-package}}` 替換為實際 package（如 `com.company.project`）
2. 將 `{{ApplicationName}}` 替換為專案名（如 `OrderServiceApplication`）
3. 依實際領域在 `bean/*/`、`cache/`、`service/` 下建立子包
4. 移除不需要的頂層目錄（例如無排程任務可移除 `job/`）

## 檢查清單

- [ ] 所有 controller 只依賴 service，不直接呼叫 dao
- [ ] bean 分層遵循 model/vo/so/query/bo 用途區分
- [ ] 每個 bean 子層依業務領域分包
- [ ] config 類集中在 `config/`，不散落各處
- [ ] 常數集中在 `constants/`，不硬編碼
