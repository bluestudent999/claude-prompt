---
name: springboot-tdd
description: sport 測試基礎設施備忘 — JUnit 4 + SpringRunner + Mockito 慣例、Testcontainers 導入路徑、本專案測試覆蓋率現況與優先補測場景。
origin: template
---

# sport 測試基礎設施備忘

> 現況快照：
> - **`spring-boot-starter-test` 已加在** `cx-sports-v2`（`cx-sport-single-wallet-service` 沒有，需要時要先加）
> - **既有測試類別 10+ 個**（`cx-sports-v2/src/test/java/`），全部用 **JUnit 4 + SpringRunner**（`@RunWith(SpringRunner.class)` + `@SpringBootTest(classes = CPServiceApplication.class)` + `@Resource`）
> - 既有「測試」**多為手動跑的整合驗證 harness**（如 `InternationalAuto.java` / `RegularTest.java`），非典型 unit test；不要當成範本套用所有新測試
> - **無 Testcontainers / 無 JaCoCo / 無 CI 跑 mvn test**

## 使用時機

- 使用者明確要求「補測試」/「導入 Testcontainers」/「升級 JUnit 5」
- 規劃新功能時，PO 要求附帶測試
- 寫 `business-reviewer` 提的「金額 / 狀態機 / 冪等」類測試

**非使用時機：** 例行 feature 開發無強制測試（目前團隊測試文化偏弱）。

## 測試框架版本（重要 — 不要混用）

| 元件 | 本專案版本 | 說明 |
|------|-----------|------|
| JUnit | **4.x**（隨 Spring Boot 2.7.11 預設） | `import org.junit.Test`；不要 `import org.junit.jupiter.api.Test` |
| Spring Test Runner | `SpringRunner.class` | 不要 `@ExtendWith(SpringExtension.class)` |
| Mockito Runner | `MockitoJUnitRunner.class` | 不要 `@ExtendWith(MockitoExtension.class)` |
| AssertJ | 隨 spring-boot-starter-test | OK |
| Mockito | 隨 spring-boot-starter-test | OK |
| MockMvc | 隨 spring-boot-starter-test | 用 `@AutoConfigureMockMvc` |

> 若要升 JUnit 5，需所有模組同步：加 `junit-jupiter`、`junit-vintage-engine`（過渡）、所有既有 `@RunWith` 改 `@ExtendWith`。**不在單一 PR 範圍內**。

## 既有測試的標準骨架

```java
package com.lc.cp.xxx;

import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.junit4.SpringRunner;
import javax.annotation.Resource;
import com.lc.cp.CPServiceApplication;  // 對應模組的 Application 類

@SpringBootTest(classes = CPServiceApplication.class)
@RunWith(SpringRunner.class)
public class XxxServiceTest {

    @Resource
    private XxxService xxxService;

    @Before
    public void setUp() { /* ... */ }

    @Test
    public void should_return_X_when_Y() {
        // given / when / then
    }
}
```

## 純單元測試（不啟動 Spring，較少見但更快）

```java
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnitRunner;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

@RunWith(MockitoJUnitRunner.class)
public class OrderServiceTest {
    @Mock private OrderDao orderDao;
    @InjectMocks private OrderServiceImpl orderService;

    @Test
    public void should_return_order_when_exists() {
        Order o = new Order(); o.setId(1L);
        when(orderDao.selectById(1L)).thenReturn(o);
        assertThat(orderService.findById(1L)).isNotNull();
    }
}
```

## 本專案應優先補測的場景

依 `CLAUDE.md` 與 `business-reviewer` 檢查清單，本專案測試**必須優先覆蓋**：

| 場景 | 測什麼 | 為什麼 |
|------|-------|--------|
| **狀態機** | 訂單 / 金額異動 `State` / `UserStatus` 合法/非法轉換 | AI 常在這裡犯錯 |
| **金額計算** | `BigDecimal` + `RoundingMode.DOWN`、多幣別換算方向 | 涉及真錢 |
| **冪等** | `orderNo` 重送同訂單回傳一致；流水不重複寫入 | 第三方廠商重送頻繁 |
| **single-wallet 7 步流程** | 鎖 → 事務 → SELECT FOR UPDATE → 驗 → 扣 → 寫流水 → commit | 跳步即金錢損失 |
| **第三方異常** | API 逾時 / 錯誤碼 / 廠商回 200 + HTML | 多個第三方整合點 |

純 CRUD / 純查詢端點優先級較低。

## 進階：Testcontainers（若要導入真 DB 測試）

目前**無人用**；要導入需先：
1. 加依賴（每個要測的模組）：
   ```xml
   <dependency><groupId>org.testcontainers</groupId><artifactId>testcontainers</artifactId><version>1.15.3</version><scope>test</scope></dependency>
   <dependency><groupId>org.testcontainers</groupId><artifactId>mysql</artifactId><version>1.15.3</version><scope>test</scope></dependency>
   ```
   > ⚠️ Testcontainers 1.16+ 需要 JUnit 5；本專案是 JUnit 4，鎖在 1.15.x（最後支援 JUnit 4 的版本系列）。
2. JUnit 4 用法（不用 `@Testcontainers`，改 `@ClassRule`）：
   ```java
   @ClassRule
   public static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:5.7")
       .withDatabaseName("gamedbn");
   ```
3. `application-test.yml` 用 `${mysql.getJdbcUrl}` 注入

## 與其他 skill / rule 的關係

| 項目 | 位置 |
|------|------|
| 測試命名 / 框架慣例 / 覆蓋率目標 | `rules/testing.md`（已存在） |
| 狀態機 / 金額 / 訂單業務規則 | `business-reviewer` agent 內含清單，或自建 `<domain>-business-knowledge` skill（複製 `business-template`） |
| 命名 / Log / 語法偏好 | `rules/coding-style.md` |
| 金額 / RoundingMode | `rules/security.md` |

## 常見坑

| 坑 | 症狀 | 防範 |
|----|------|------|
| 在 JUnit 4 專案寫 `@ExtendWith(MockitoExtension.class)` | 測試完全不跑（runner 不認） | 統一用 `@RunWith(MockitoJUnitRunner.class)` |
| `@SpringBootTest` 沒寫 `classes = XxxApplication.class` | Context 啟動失敗或載入錯模組 | 對照同模組既有 test class |
| 把 `cx-sports-v2/src/test/java/RegularTest.java` 當範本 | 那是手動 harness，不是 unit test | 範本看 `LotteryPlanTest.java` / `UserMoneyServiceTest.java` |
| 在 `cx-sport-single-wallet-service` 寫測試 | pom 沒加 `spring-boot-starter-test` 會編譯失敗 | 先加依賴 |
