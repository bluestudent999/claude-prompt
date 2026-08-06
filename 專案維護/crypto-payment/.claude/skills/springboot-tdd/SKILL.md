---
name: springboot-tdd
description: crypto-payment 測試基礎設施備忘 — JUnit 5（Jupiter）+ Mockito + @SpringBootTest 慣例、Testcontainers 導入路徑、既有 5 個測試現況與優先補測場景（私鑰/入款冪等/HMAC/platform_id）。
origin: template
---

# crypto-payment 測試基礎設施備忘

> 現況快照：
> - `crypto-payment-service`（Spring Boot **3.1.2** / **Java 21**）已含 `spring-boot-starter-test`
> - 測試框架為 **JUnit 5（Jupiter）+ Mockito**，**不是** JUnit 4 / SpringRunner
> - **既有 5 個測試**：錢包產生、QuickNode webhook、chain log service、HMAC 驗簽、collector listener（見下方場景表）
> - CI 若 `skip tests` → 本地 `mvn test` 是防線

## 使用時機

- 使用者明確要求「補測試」
- 規劃新功能時附帶測試（尤其 L1：金額 / 私鑰 / HMAC / 入帳 / 歸集）
- 寫 `business-reviewer` 提的「金額 / 狀態機 / 冪等 / 私鑰 / 驗簽」類測試

**非使用時機：** 純 config / VO / wiring（L3）不強制。

## 測試框架版本（重要 — 不要混用 JUnit 4 慣例）

| 元件 | 本專案版本 | 說明 |
|------|-----------|------|
| JUnit | **5（Jupiter）**（隨 Spring Boot 3.1.2） | `import org.junit.jupiter.api.Test`；**不要** `import org.junit.Test` |
| Spring Test | `@SpringBootTest`（含 `SpringExtension`，自動註冊） | **不要** `@RunWith(SpringRunner.class)` |
| Mockito | `@ExtendWith(MockitoExtension.class)` | **不要** `@RunWith(MockitoJUnitRunner.class)` |
| 生命週期註解 | `@BeforeEach` / `@AfterEach` | **不要** `@Before` / `@After` |
| 注入 | 建構子注入或 `@Autowired`（測試類可用） | 生產程式碼一律建構子注入 |
| AssertJ / Mockito | 隨 spring-boot-starter-test | OK |
| MockMvc | 隨 spring-boot-starter-test | 用 `@AutoConfigureMockMvc` |

> JUnit 4 的 `@RunWith` / `org.junit.Test` / `@Before` 在本專案**會讓測試不執行或編譯錯**，一律用 Jupiter。

## 整合測試骨架（啟動 Spring Context）

```java
package com.lion.crypto.service.user;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
class DepositServiceTest {

    @Autowired
    private DepositService depositService;

    @BeforeEach
    void setUp() { /* 準備測試資料，帶 platformId */ }

    @Test
    void should_credit_user_when_deposit_matched() {
        // given / when / then
    }
}
```

## 純單元測試（不啟動 Spring，較快，優先用於邏輯驗證）

```java
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ChainLogServiceTest {
    @Mock private WalletRepository walletRepository;
    @InjectMocks private ChainLogServiceImpl chainLogService;

    @Test
    void should_match_wallet_by_platform_and_address() {
        when(walletRepository.findByPlatformIdAndAddress(1L, "0xabc"))
            .thenReturn(new WalletBO());
        assertThat(chainLogService.matchWallet(1L, "0xabc")).isNotNull();
    }
}
```

## 既有 5 個測試（範本參考）

| 測試 | 對應層 | 測什麼 | 風險 |
|------|--------|-------|------|
| **錢包產生** | `service/platform/` | 每鏈地址產生正確、私鑰 AES-GCM 加密後儲存、不重複 | L1（私鑰） |
| **QuickNode webhook** | `controller/thirdparty/` | webhook payload 解析、驗簽、入款事件觸發 | L1（第三方對接） |
| **chain log service** | `service/system/` | 鏈上 log 解析 → 匹配錢包（帶 platform_id）→ 入帳 | L1（入帳） |
| **HMAC 驗簽** | `filter/SignFilter` | HMAC-SHA256（timestamp+nonce+排序參數）、5 分鐘 replay window、nonce 去重 | L1（驗簽） |
| **collector listener** | `event/` | 歸集(sweep)事件消費、最小歸集門檻、金額 BigDecimal 正確 | L1（歸集/金額） |

## 本專案應優先補測的場景

| 場景 | 測什麼 | 為什麼 |
|------|-------|--------|
| **私鑰加解密** | AES-GCM encrypt/decrypt 往返一致；DB 無明文 | 私鑰洩漏 = 資金全失 |
| **金額計算** | `BigDecimal` + `RoundingMode.DOWN`、歸集門檻、rate 換算方向 | 涉及真錢 |
| **入款冪等** | 同一 tx hash / (txHash, logIndex) 重送不重複入帳 | webhook / 鏈重組會重送 |
| **HMAC 驗簽** | 簽章正確 / 過期 timestamp / 重複 nonce → 拒絕 | 支付 API 唯一門禁 |
| **platform_id 隔離** | 跨平台查詢應查不到 / 拒絕 | 跨租戶洩漏 = critical |
| **狀態機** | 入款 / 歸集 / 出款狀態合法/非法轉換 | AI 常在此犯錯 |

純 CRUD / 純查詢端點優先級較低。

## 進階：Testcontainers（若要導入真 DB 測試）

Boot 3.1.2 / JUnit 5 可直接用新版 Testcontainers（`@Testcontainers` + `@Container`）：

```java
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.containers.MySQLContainer;

@Testcontainers
@SpringBootTest
class DepositRepositoryIT {
    @Container
    static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8");
    // 用 @DynamicPropertySource 注入 mysql.getJdbcUrl() 等
}
```

> 需在 `pom.xml` 加 `org.testcontainers:junit-jupiter` + `:mysql`（`<scope>test</scope>`）。Boot 3 有 `@ServiceConnection` 可簡化連線設定。

## 常見坑

| 坑 | 症狀 | 防範 |
|----|------|------|
| 沿用 JUnit 4 的 `@RunWith` / `org.junit.Test` | 測試不跑或編譯錯 | 一律 Jupiter：`@ExtendWith` + `org.junit.jupiter.api.Test` |
| 用 `@Before` / `@After` | Jupiter 不認 | 改 `@BeforeEach` / `@AfterEach` |
| 整合測試漏帶 `platform_id` | 查不到資料 / 誤判 | 測試資料一律綁 platformId |
| 測私鑰卻斷言明文 | 洩漏測試意圖、且不符實作 | 斷言「解密後 == 原值」，不比對 DB 明文 |
| `mvn test` 被 CI skip 就不跑 | 缺陷溜進 developing | 本地 commit 前必跑 `mvn test` |

## 與其他 skill / rule 的關係

| 項目 | 位置 |
|------|------|
| 金額 / RoundingMode / 私鑰 / 驗簽安全 | `skills/springboot-security/` |
| 第三方 / webhook 對接模式 | `skills/api-connector-builder/` |
| 命名 / Log / 語法偏好 | `rules/coding-style.md` |
