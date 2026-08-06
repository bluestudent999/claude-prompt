# 測試規範與政策

> 本文規範 SDRP 專案的測試標準，包含 JUnit 5 測試架構、Spring Modulith 的邊界測試、以及針對不同風險層級的測試覆蓋要求。

---

## 1. 測試技術棧與命名

- **測試框架**：使用 **JUnit 5 (Jupiter)**（`org.junit.jupiter.api.*`）。
  - **禁忌**：嚴禁混用 JUnit 4（`org.junit.Test` 或 `@RunWith`）。
- **斷言庫**：統一使用 **AssertJ**（`assertThat(...)`）。
- **Mock 庫**：使用 **Mockito**（`org.mockito.*`）。
- **測試命名**：採用 `should_ExpectedBehavior_When_Scenario` 或 `method_scenario_expected` 格式。
  - 範例：`should_alignEntities_when_confidenceIsAboveThreshold`。

---

## 2. 風險層級測試政策 (L1 - L3)

為了兼顧開發效率與品質，SDRP 採用風險分級測試：

| 風險級別 | 典型場景 | 測試覆蓋要求 |
| :--- | :--- | :--- |
| **L1 (高風險)** | 核心對齊演算法（Golden Set 驗證）、悲觀鎖/事務控制、結算邏輯 | **強制撰寫整合測試**。需使用 `@SpringBootTest` 或 `@ApplicationModuleTest` 執行真實場景模擬。 |
| **L2 (中風險)** | 一般業務 Service、異步事件監聽器、Controller API 入口 | **可選擇性覆蓋**。優先使用單元測試（Mockito）或輕量級 `@WebMvcTest`，必要時撰寫模組整合測試。 |
| **L3 (低風險)** | 配置檔異動、DTO 定義、語系修改、拼字修正、純重構 | **不強制要求測試**，直接通過代碼審查與 Preflight 編譯即可。 |

---

## 3. Spring Modulith 邊界測試

- **模組架構驗證**：專案引入了 Spring Modulith，每次跑測試時都應驗證模組邊界是否完整。
- **自動驗證**：`settings.json` 的 `Stop` hook 會在每次修改代碼後自動運行：
  ```bash
  ./mvnw -q test -Dgroups=architecture
  ```
  該命令專門運行驗證模組內部封裝（非公開 package 不得跨模組 import）與依賴循環的 ArchUnit 測試。
- **異步事件測試**：
  - 模組間領域事件通訊應使用 `Scenario` 或 `PublishedEvents` 進行斷言驗證。

---

## 4. 資料庫與外部依賴隔離

- **Testcontainers 優先**：
  - 對於包含 Repository / SQL / PGVector 的 L1 整合測試，必須使用 **Testcontainers** 啟動 PostgreSQL 實例，禁止連線至真實開發/生產資料庫。
  - 禁止使用內存 H2 資料庫來測試 PGVector 專屬語法（如向量相似度計算），這會掩蓋語意相容性錯誤。
- **外部 HTTP 依賴**：
  - 使用 `@MockBean` Mock 掉 Outbound Port，或使用 WireMock 模擬第三方 RESTful API。
