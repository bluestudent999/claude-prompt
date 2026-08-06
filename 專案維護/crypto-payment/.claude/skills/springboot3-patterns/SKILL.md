---
name: springboot3-patterns
description: Spring Boot 3.1.2 / Java 21 架構模式 — 分層 Service、建構子注入、BaseResponse 信封、自訂例外、原生 Kafka、Redis/Jedis 快取失效、Quartz/@Scheduled 排程、Jakarta 命名空間。crypto-payment 後端開發時載入。
---

# Spring Boot 3 架構模式（crypto-payment）

> Java 21 / Spring Boot 3.1.2。新程式碼對齊；既有違反不強制重構。動手前先 grep 同目錄既有類別對齊寫法。

## Boot 3 / Java 21 遷移重點

- **命名空間 `jakarta.*`**（非 `javax.*`）：`jakarta.servlet`、`jakarta.validation`、`jakarta.annotation`
- **Spring Security 6**：`SecurityFilterChain` bean（非 `WebSecurityConfigurerAdapter`）；本專案安全主力在自訂 `filter/`（SignFilter/webhook/IP）
- Java 21 可用 record、pattern matching、`switch` 表達式、virtual threads（導入前先確認團隊政策）

## 分層與 DI

- 建構子注入（`@RequiredArgsConstructor` + `private final`），**禁 `@Autowired` 欄位注入**
- 改狀態的 service 方法必須 `@Transactional`
- Controller 依 `manage`/`center`/`system`/`thirdparty` 分目錄

```java
@Slf4j
@Service
@RequiredArgsConstructor
public class DepositService {
    private final UserWalletRepository userWalletRepository;
    private final ChainLogService chainLogService;

    @Transactional
    public void creditDeposit(DepositEvent event) {
        // 冪等：先查 txHash 是否已處理
    }
}
```

## 回應信封與例外

- 一律 `BaseResponse<T>` 包裝，禁裸物件
- 自訂 exception + 既有 `@RestControllerAdvice` 全域處理；禁裸 `RuntimeException`；禁吞例外

## 原生 Apache Kafka（**非** Spring Cloud Stream）

- 本專案用**原生 Kafka**，**不要**用 `@EnableBinding`/`@StreamListener`/`@Input`/`@Output`
- 動 Kafka 前**先 grep 既有 producer/consumer**（`event/`）對齊寫法（listener 註解、序列化、group id、topic 命名）
- **消費者必須冪等**：txHash / orderNo / nonce 去重（重投必然發生，見 `rules/stability.md`）

## 快取（Redis / Jedis）

- 讀多寫少的 config / 字典用 `*ConfigCache` 預載
- **寫 DB 後同事務內或緊接失效 / 更新 Redis key**（漏失效讀 stale）
- 跨節點狀態（nonce、鎖、session）一律 Redis，禁單機記憶體

## 排程與非同步

- `@Scheduled` / Quartz（`job/`）；需單節點執行用 Quartz cluster 或 Redis SETNX
- `@Async` + `@EnableAsync`；Spring 內部事件 `ApplicationEventPublisher` + `@EventListener`
- 所有排程 handler 冪等

## 相關

- 金額 / 私鑰 / 驗簽 → `rules/security.md`
- DAO / ShardingSphere / Flyway → `mysql-shardingsphere5` skill
- 錢包 / 鏈 client → `blockchain-wallet` skill
