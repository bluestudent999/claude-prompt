---
paths:
  - "**/*.java"
---
# Java 測試

> 測試規範：通用原則 + 本專案特有要求。
>
> **撰寫政策**（是否必寫、何時可緩）見 [`development-workflow.md`](./development-workflow.md) §Step 3。本專案屬 **Mode B（整合為主 legacy adaptation）**，只保 L1 關鍵路徑；L2/L3 不強制。

## 通用測試規範

- 框架：**JUnit 4**（`org.junit.Test` + `@RunWith(SpringRunner.class)` 或 `@RunWith(MockitoJUnitRunner.class)`）+ Mockito + AssertJ
  - Spring Boot 2.7.11 預設綁 JUnit 4；新類別請對齊既有寫法（`@RunWith(SpringRunner.class)` + `@SpringBootTest(classes = XxxApplication.class)`）
  - **不要混用 JUnit 5 的 `@ExtendWith(MockitoExtension.class)` / `@WebMvcTest`**（除非整個測試模組已升級，目前未升）
- 測試命名：`method_scenario_expected`（例如 `transfer_insufficientBalance_throwsException`）
- 覆蓋率目標：**Mode B — 只保 L1 關鍵路徑有測試**（見 development-workflow.md §Step 3b），不追 80%
- 測試結構：Arrange → Act → Assert，每個測試只驗證一件事

## 測試組織結構

```
src/test/java/com/lc/cp/
├── service/      # L2 可選
├── controller/   # L2 可選
├── dao/          # L2 可選
├── integration/  # Mode B 主力，L1 落在這
└── support/      # 共用基類 AbstractIntegrationTest
```

## Mode B 共用測試基座

L1 整合測試繼承共用基類，避免重造輪子：

```
src/test/java/com/lc/cp/support/
├── AbstractIntegrationTest.java          ← @RunWith(SpringRunner.class) + @SpringBootTest + @ActiveProfiles("test") + H2
├── AbstractMoneyIntegrationTest.java     ← 金錢 fixtures（UserMoney / YebConfig）
└── Abstract<Domain>IntegrationTest.java  ← 各業務域 fixtures
```

**建基座時機**：第一個 L1 feature 寫整合測試時，**獨立任務** 1-2 天投入，不跟功能測試混寫。若 L1 尚無基座 → 走 `development-workflow.md` §Step 3d 技術債流程。

## 專案特有

- **現況**：既有測試多手動驗證型（`cx-sports-v2/src/test/java/bet/BetTest.java`），L1 基座尚未建立 → 第一個 L1 走 §3d 過渡期
- **關鍵 L1 場景**：金額（`BigDecimal` + `DOWN`）/ 狀態機（訂單/提款/充值）/ 併發（`FOR UPDATE` + 事務）/ 冪等（排程 / Spring Event / Stream 重送）
- **整合測試 DB**：目前無 Testcontainers，第一次建基座引入 H2 或 Testcontainers，細節見 `springboot-tdd` skill
- **CI 現況**：Jenkins `-Dmaven.test.skip=true` → 測試僅 local 跑，**不要把 CI 綠當測試通過證據**
- **禁忌**：測試寫正式/測試 MySQL（用 `@MockBean` / H2 / Testcontainers）；L1 落 Mockito 單元測試（靜態工具 + `@Transactional` 會迫使上 PowerMock）
