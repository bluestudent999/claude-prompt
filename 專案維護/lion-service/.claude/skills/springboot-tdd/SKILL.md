---
name: springboot-tdd
description: lion-service 測試基礎設施備忘 — JUnit 4 + SpringRunner + Mockito 慣例、Testcontainers 導入路徑、本專案測試覆蓋率現況與優先補測場景。
origin: template
---

# lion-service 測試基礎設施備忘

> 現況快照：
> - **`spring-boot-starter-test` 已加在** `cp-service` / `collector-service` / `upload-service`；**`single-wallet-service` 沒有，也沒有任何測試檔**，要寫測試前先加依賴
> - **既有測試檔約 110 個**（`cp-service/src/test/java/` 約 94 個、`collector-service` 約 18 個），全部 **JUnit 4**（0 處 jupiter）；整合型用 `@RunWith(SpringRunner.class)` + `@SpringBootTest(classes = CPServiceApplication.class)` + `@Resource`，純單元型用 `MockitoJUnitRunner` 或不帶 runner
> - 既有「測試」**約一半是手動跑的整合驗證 harness**（如 `InternationalAuto.java` / `RegularTest.java` / `bet/BetTest.java` / `lotteryplan/LotteryPlanTest.java`，沒有任何 assert），非典型 unit test；**不要當成範本**
> - 有 assert 可參考的：純 JUnit golden test（`agentline/AgentSettleTemplateAGoldenTest.java`）、Mockito 單元測試（`com/lc/cp/service/user/*Test.java`）
> - L1 整合測試基座 `AbstractIntegrationTest` **尚未建立**（`rules/testing.md`）
> - **無 Testcontainers / 無 JaCoCo；Jenkins 用 `-Dmaven.test.skip=true`，CI 不編譯也不跑測試** → 測試只能本地跑，CI 綠不是證據

## 使用時機

- 使用者明確要求「補測試」/「導入 Testcontainers」（「升級 JUnit 5」不在維護範圍，見下方「禁用 JUnit 5」）
- 規劃新功能時，PO 要求附帶測試
- 寫 `business-reviewer` 提的「金額 / 狀態機 / 冪等」類測試

**非使用時機：** L2 / L3 例行開發無強制測試（L1 強制整合測試，見 `rules/testing.md`）。

## 測試框架版本（重要 — 不要混用）

| 元件 | 本專案版本 | 說明 |
|------|-----------|------|
| JUnit | **4.x**（隨 Spring Boot 2.0.2 的 `spring-boot-starter-test`） | `import org.junit.Test`；不要 `import org.junit.jupiter.api.Test` |
| Spring Test Runner | `SpringRunner.class` | 不要 `@ExtendWith(SpringExtension.class)` |
| Mockito Runner | `MockitoJUnitRunner.class` | 不要 `@ExtendWith(MockitoExtension.class)` |
| AssertJ | 隨 spring-boot-starter-test | OK |
| Mockito | 隨 spring-boot-starter-test | OK |
| MockMvc | 隨 spring-boot-starter-test | 用 `@AutoConfigureMockMvc` |

> **禁用 JUnit 5**（`@ExtendWith`、`org.junit.jupiter.*`）。團隊根 CLAUDE.md 寫 JUnit 5 是過期記載，程式碼實際 0 處 jupiter。升級牽涉所有模組與 Boot 版本，**不在維護範圍**（要升 → `prompt-setup 版本管理`）。

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
        when(orderDao.get(1L)).thenReturn(o);   // MysqlBaseDao.get(PK)
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
| **single-wallet 金額 8 步** | 鎖 → 事務 → 鎖定行 → 驗 → 扣 / 加 → 寫流水 → commit → 釋放鎖；同 `orderNo` 重送回傳與首次相同 | 跳步即金錢損失 |
| **包網商隔離** | 至少兩個 `platformId` 的資料，A 家的請求讀 / 改不到 B 家 | 單平台測試 100% 測不出（`rules/platform-isolation.md`） |
| **filter 放行** | 帶 `.do` / 子字串 / 編碼變體的路徑不得繞過認證 | 已發生過實際入侵（`rules/security.md` §filter 防線） |
| **彩票賠率 / 限額 / 封盤** | 請求端帶的賠率不生效；併發下注不突破限額；封盤後下注被拒 | 不需入侵就能穩定獲利（`rules/security.md` §彩票） |
| **第三方異常** | API 逾時 / 錯誤碼 / 廠商回 200 + HTML | 多個第三方整合點 |

純 CRUD / 純查詢端點優先級較低。

## 進階：Testcontainers（若要導入真 DB 測試）

目前**無人用**，導入屬於建 L1 基座的獨立任務（`rules/testing.md`），不跟功能測試混寫。導入前要先決定的事（**判不出就問使用者**，不要自選）：
1. **版本**：要同時相容 Java 8、JUnit 4（用 `@ClassRule`，不用 `@Testcontainers` 註解）與本機 Docker 版本 —— 用 `documentation-lookup` 查，不憑印象鎖版號
2. **MySQL image 版本**：對齊線上版本（先問使用者 / DBA）
3. **ShardingSphere**：`datasource-gamedbn.yml` 是主從 + `user_money` 10 分庫 + 欄位加密；測試要不要繞過 ShardingSphere 直連單庫，會影響能測到什麼 → 列 OQ
4. **schema 來源**：`cp-flyway` migration 與 `zz_document/script/changelog/` 雙軌，單跑 flyway 不一定得到完整 schema → 列 OQ

## 與其他 skill / rule 的關係

| 項目 | 位置 |
|------|------|
| 測試命名 / 框架慣例 / 覆蓋率目標 | `rules/testing.md`（已存在） |
| 狀態機 / 金額 / 訂單業務規則 | `business-reviewer` agent 內含清單；業務語意讀業務知識正本（見 `rules/modules.md` §業務知識正本） |
| 命名 / Log / 語法偏好 | `rules/coding-style.md` |
| 金額 / RoundingMode | `rules/security.md` |

## 常見坑

| 坑 | 症狀 | 防範 |
|----|------|------|
| 在 JUnit 4 專案寫 `@ExtendWith(MockitoExtension.class)` | 測試完全不跑（runner 不認） | 統一用 `@RunWith(MockitoJUnitRunner.class)` |
| `@SpringBootTest` 沒寫 `classes = XxxApplication.class` | Context 啟動失敗或載入錯模組 | 對照同模組既有 test class |
| 把 `RegularTest.java` / `LotteryPlanTest.java` / `UserMoneyServiceTest.java` 當範本 | 那是手動 harness，沒有 assert，不是 unit test | 骨架照本檔；有 assert 的參考 `agentline/*GoldenTest.java` |
| 在 `single-wallet-service` 寫測試 | pom 沒加 `spring-boot-starter-test` 會編譯失敗 | 先加依賴（改 pom → 告知使用者） |
| 照團隊舊文件寫 JUnit 5 | 測試不跑或編譯失敗 | 一律 JUnit 4 |
| 只用一個 `platformId` 造資料 | 隔離漏洞測不出 | 至少兩個 `platformId` |
| 以為 CI 會跑測試 | Jenkins `-Dmaven.test.skip=true`，連編譯都跳過 | 本地 `mvn -pl <module> test -Dtest=XxxTest` 並把結果貼進 MR |
