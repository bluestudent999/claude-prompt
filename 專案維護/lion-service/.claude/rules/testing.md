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
  - Spring Boot 2.0.2 的 `spring-boot-starter-test` 綁 JUnit 4；新類別對齊既有寫法（`@RunWith(SpringRunner.class)` + `@SpringBootTest(classes = CPServiceApplication.class)`）
  - **禁用 JUnit 5**（`org.junit.jupiter.*`、`@ExtendWith(MockitoExtension.class)`）—— repo 內 0 處 jupiter；團隊根 `CLAUDE.md` 寫的「JUnit 5」是過期記載，以程式碼為準
- 測試命名：`method_scenario_expected`（例如 `transfer_insufficientBalance_throwsException`）
- 覆蓋率目標：**Mode B — 只保 L1 關鍵路徑有測試**，不追 80%
- 測試結構：Arrange → Act → Assert，每個測試只驗證一件事

## 測試組織結構

依模組 package 對應：

```
cp-service/src/test/java/com/lc/cp/
single-wallet-service/src/test/java/com/lc/single/wallet/
collector-service/src/test/java/com/cx/collector/
upload-service/src/test/java/com/lc/upload/
```

子目錄建議：`service/`、`controller/`、`dao/`（L2 可選）；`integration/`（**Mode B 主力，L1 落在這**）；`support/`（共用基類）。

## Mode B 共用測試基座（尚未建立）

L1 整合測試應繼承共用基類，避免每個測試類別重造輪子：

```
cp-service/src/test/java/com/lc/cp/support/
├── AbstractIntegrationTest.java          ← @RunWith(SpringRunner.class) + @SpringBootTest + @ActiveProfiles("test")
├── AbstractMoneyIntegrationTest.java     ← 金錢場景共用 fixtures
└── Abstract<Domain>IntegrationTest.java  ← 各業務域 fixtures
```

**建基座時機**：第一個 L1 feature 要寫整合測試時，把基座當**獨立任務**一次性投入，不跟功能測試混寫。基座未建前 → 走 §3d 技術債追蹤段。

## 專案特有

- **現況**：既有測試多為手動驗證型（`cp-service/src/test/java/bet/BetTest.java` 等），L1 基座未建
- **single-wallet-service 沒有 `spring-boot-starter-test` 依賴、也沒有任何測試檔** → 要寫測試先在該模組 `pom.xml` 加 `spring-boot-starter-test`（`<scope>test</scope>`），這屬 plan §2 要列的檔案變更
- **關鍵測試場景（L1）**：
  - 金額運算（`BigDecimal` + `RoundingMode.DOWN`）— 結算、退款、反水、代理分潤
  - 狀態機（訂單、提款、充值、活動獎勵）
  - 併發（分散式鎖 + DB `FOR UPDATE` + 事務邊界；限額併發突破）
  - 冪等（排程重跑 / Spring Event / Spring Cloud Stream 重送；同 `orderNo` 重送回傳與首次相同結果）
  - **跨 platformId 隔離**：fixture **至少準備兩個 platformId** 的資料，驗「A 平台登入者查 / 改不到 B 平台資料」「SO 帶別家 platformId 會被拒或覆寫」。**單平台 fixture 測不出隔離問題**（見 `rules/platform-isolation.md`）
- **整合測試資料庫**：目前無 H2 / Testcontainers 設定，第一次建 L1 基座時引入，細節見 `springboot-tdd` skill
- **CI 現況**：Jenkins `-Dmaven.test.skip=true`，連測試編譯都跳過 → 測試只在本地跑，**CI 綠不是測試通過的證據**；MR 測試計畫要附本地執行結果
- **禁忌**：測試直連正式 / 共用測試 MySQL 做寫入（改用 `@MockBean` 或 H2 / Testcontainers）；L1 關鍵路徑落 Mockito 單元測試（靜態工具 + `@Transactional` + `SpringContext.getBean` 耦合會迫使上 PowerMock，收益低）

## 3d. L1 無基座時的技術債追蹤段

L1 改動但基座未建、無法寫整合測試時，**不得默默略過**。MR description 必附：

```markdown
### 測試技術債（L1 無整合測試）
- 未覆蓋的 L1 場景：<例：同 orderNo 重送、跨 platformId 查詢>
- 本次替代驗證：<手動 QA 步驟 / 本地執行紀錄>
- 追蹤工單：<Jira / GitLab issue 連結>
```

缺此段 → code-reviewer / java-reviewer 判 HIGH。
