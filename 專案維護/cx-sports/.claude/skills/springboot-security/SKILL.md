---
name: springboot-security
description: 安全性最佳實踐，涵蓋輸入驗證、SQL 注入防護、機密管理、日誌脫敏，以及後端服務常見安全需求（第三方驗簽、API Key、金額安全）。
origin: ECC
---

# Spring Boot 安全性審查

處理輸入、建立端點或管理機密時使用。

## 啟用時機

- 驗證使用者輸入（Bean Validation、自訂驗證器）
- 處理第三方服務商回調或 API 端點
- 管理機密（環境變數、provider_config）
- 處理金額運算或金額異動流程

## 輸入驗證

- Controller 使用 `@Valid` 的 Bean Validation
- DTO 套用約束：`@NotBlank`、`@Email`、`@Size`、自訂驗證器

```java
@Data
public class CreateUserDto {
  @NotBlank @Size(max = 100) private String name;
  @NotBlank @Email private String email;
  @NotNull @Min(0) @Max(150) private Integer age;
}

@PostMapping("/users")
public ResponseEntity<UserDto> createUser(@Valid @RequestBody CreateUserDto dto) {
  return ResponseEntity.status(HttpStatus.CREATED).body(userService.create(dto));
}
```

## SQL Injection 防護

- 使用 Spring Data Repository 或參數化查詢
- Native query 使用 `:param` 綁定；絕不拼接字串

```java
// 錯誤：字串拼接
@Query(value = "SELECT * FROM users WHERE name = '" + name + "'", nativeQuery = true)

// 正確：參數化
@Query(value = "SELECT * FROM users WHERE name = :name", nativeQuery = true)
List<User> findByName(@Param("name") String name);
```

## 機密管理

- 機密不進原始碼；從環境變數載入
- 保持 `application.yml` 無憑證；使用 `${DB_PASSWORD}` 佔位符
- 定期輪換 Token 與 DB 憑證

## 日誌記錄與脫敏

- 絕不記錄機密、Token、密碼或完整卡號
- 遮蔽敏感欄位；使用結構化 JSON 日誌

## 依賴安全性

- 在 CI 中執行 OWASP Dependency Check
- 保持 Spring Boot 在支援版本
- 發現已知 CVE 時建置失敗

## 檔案上傳

- 驗證大小、Content-Type 與副檔名
- 儲存於 Web root 之外

---

## 【本專案】後端服務安全需求

以下為本專案最重要的安全議題。

### 第三方服務商回調驗簽

- 每個第三方服務商的驗簽方式不同（MD5、HMAC-SHA256、RSA 等）
- 回調 URL（`/third/*`）必須驗證簽名或 IP 白名單
- 回調處理必須冪等（相同請求重複處理不會重複加扣款）
- 驗簽失敗必須記錄完整請求（遮蔽敏感欄位）並回傳適當錯誤碼

### API Key 管理

- 第三方服務商 API 金鑰、Secret 存放於 `provider_config` 表的 JSON 欄位
- 絕不在原始碼中硬編碼任何金鑰
- `.claude/settings.local.json` 的 `env` 區段存放本地開發憑證
- 新增第三方服務商時，金鑰欄位命名需與現有 Provider 一致

### 金額安全

- 所有金額運算使用 `BigDecimal`，禁止 `double`/`float`
- 幣種 rate 換算使用 `RoundingMode.DOWN`（無條件捨去，避免多給錢）
- 金額異動操作必須有 Redis 分散式鎖防重複
- 訂單去重依靠 `orderNo` 唯一約束

### platformId 驗證

- 所有 API 請求需驗證 platformId 的合法性
- 防止跨平台資料存取

### 熔斷限流

- 本 repo（sport）目前**無**全域熔斷 / 限流框架（無 Alibaba Sentinel / Resilience4j / Bucket4j）；application.yml 的 `spring.redis.mode: sentinel` 指 Redis 哨兵，與限流無關
- 高成本端點若需限流，目前僅能個別自寫（Filter / 切面 / Redis 計數）— **新增前先開架構討論**
- 若全站性導入限流，應由 architect agent 評估方案後統一

## 發布前檢查清單

- [ ] 所有輸入均已驗證並清理
- [ ] SQL 無字串拼接
- [ ] 機密已外部化；無機密提交
- [ ] 第三方服務商回調有驗簽/IP 白名單
- [ ] 金額計算用 BigDecimal + RoundingMode.DOWN
- [ ] 金額異動有 Redis 鎖防重複
- [ ] 日誌不含敏感資料（密碼、Token、完整 API Key）
- [ ] 依賴已掃描且為最新

**牢記**：預設拒絕、驗證輸入、最小權限，並以設定為安全第一。
