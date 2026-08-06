---
paths:
  - "**/*.java"
---
# 測試（crypto-payment）

> 測試規範：通用原則 + 本專案特有要求。
> **撰寫政策**（是否必寫）見 [`development-workflow.md`](./development-workflow.md) §Step 3。本專案屬 **Mode B（整合為主）**，只保 L1 關鍵路徑；L2/L3 不強制。

## 通用規範

- 框架：**JUnit 5（Jupiter）** + Mockito + AssertJ
  - Spring Boot 3.1.2 綁 JUnit 5；用 `@ExtendWith(MockitoExtension.class)`（純單元）或 `@SpringBootTest`（整合）
  - `org.junit.jupiter.api.Test` / `@BeforeEach` / `@DisplayName`
  - **不要用 JUnit 4 的 `@RunWith(SpringRunner.class)` / `org.junit.Test`**
- 測試命名：`method_scenario_expected`（例 `verifyHmac_expiredTimestamp_throwsException`）
- 覆蓋率：**Mode B — 只保 L1 關鍵路徑**，不追 80%
- 結構：Arrange → Act → Assert，每個測試只驗一件事

## 既有測試（參考基準，共 5 個）

| 測試 | 覆蓋 |
|------|------|
| 錢包產生 | 私鑰產生 + AES-GCM 加密落庫 |
| QuickNode webhook | 入站 webhook 解析 |
| chain log service | chain log 解析與匹配 |
| HMAC 驗證 | SignFilter 簽章驗證邏輯 |
| collector listener | 歸集事件監聽 |

> 新測試對齊上述既有寫法（先讀對應既有測試檔再動手）。

## 測試組織結構

```
crypto-payment-service/src/test/java/com/lion/crypto/
├── service/       # L2 可選
├── controller/    # L2 可選
├── integration/   # Mode B 主力，L1 落在這
└── support/       # 共用基類 AbstractIntegrationTest
```

## 關鍵 L1 場景（必測）

- **私鑰 / 加密**：AES-GCM 加解密可逆、明文不外漏
- **金額**：`BigDecimal` + `RoundingMode.DOWN`，入帳 / 歸集金額正確
- **HMAC 驗簽**：正確簽章通過、過期 timestamp / 重複 nonce 拒絕（5 分鐘窗）
- **冪等**：webhook / Kafka 重送同一筆入款只入帳一次（txHash / nonce 去重）
- **platform_id 隔離**：跨平台查詢取不到別平台資料
- **狀態機**：deposit / withdraw / collection 狀態轉換合法性

## 專案特有

- **整合測試 DB**：優先 H2 或 Testcontainers（`@Testcontainers` / `@Container`；Boot 3 可用 `@ServiceConnection`），細節見 `springboot-tdd` skill
- **禁忌**：測試連正式 / 測試 MySQL（用 `@MockBean` / H2 / Testcontainers）；金額 / 私鑰 L1 場景避免只用 Mockito mock 掉核心邏輯
- **CI**：若 CI skip tests → 本地 `mvn test` 是唯一防線，**不要把 CI 綠當測試通過證據**
