---
name: springboot-security
description: 安全性最佳實踐，涵蓋輸入驗證、SQL 注入防護、機密管理、日誌脫敏，以及後端服務常見安全需求（第三方驗簽、API Key、金額安全）。
origin: ECC
---

# Spring Boot 安全性審查（crypto-payment）

處理輸入、建立端點、對接鏈上 / webhook 或管理機密時使用。
本專案為多租戶加密貨幣支付平台（TRON / BSC / Ethereum），涉及私鑰、金額、HMAC 驗簽，安全紅線極高。

## 啟用時機

- 驗證使用者輸入（Bean Validation、自訂驗證器）
- 建立或修改 `/api/pay/*`、`/api/thirdparty/*` 端點（HMAC 驗簽 / webhook 接收）
- 管理機密（私鑰、API Key、vendor secret）
- 處理金額運算、入帳、歸集(sweep)等金流流程
- 涉及 `platform_id` 多租戶隔離

## 輸入驗證

- Controller 使用 `@Valid` 的 Bean Validation
- DTO 套用約束：`@NotBlank`、`@Size`、`@DecimalMin`、自訂驗證器
- 回應一律用既有 `BaseResponse<T>` 包裝，禁回傳裸物件

```java
@Data
public class CreateWalletQuery {
  @NotNull private Long platformId;            // 多租戶必帶
  @NotBlank @Size(max = 32) private String chain;   // TRON / BSC / ETH
  @NotBlank @Size(max = 64) private String userRef;
}

@PostMapping("/wallet")
public BaseResponse<WalletVO> createWallet(@Valid @RequestBody CreateWalletQuery query) {
  return BaseResponse.success(walletService.create(query));
}
```

## SQL Injection 防護（MyBatis）

- MyBatis mapper 一律用 `#{param}`（預編譯佔位符），**絕不用 `${param}`**（字串拼接 → 注入）
- `${}` 僅可用於無法參數化的動態表名 / 欄位名，且輸入必須來自白名單，不可來自使用者
- ShardingSphere 5.4 自動讀寫分離，**不要手動拼分片路由 SQL**

```xml
<!-- 錯誤：${} 直接拼接使用者輸入 -->
<select id="findByAddress">SELECT * FROM wallet WHERE address = '${address}'</select>

<!-- 正確：#{} 預編譯，並強制帶 platform_id 過濾 -->
<select id="findByAddress" resultType="WalletBO">
  SELECT * FROM wallet
  WHERE platform_id = #{platformId} AND address = #{address}
</select>
```

## 機密管理

- 機密**不進原始碼**：API Key / vendor secret / 簽章密鑰放 config 資料表，經 `*ConfigCache`（Redis 預載）取用
- `application.yml` 保持無憑證；連線密碼用 `${DB_PASSWORD}` 佔位符由環境變數注入
- **禁讀 / 禁提交**：`.env`、`application-prod.yml`、`application-staging.yml`、`*.key`/`*.pem`/`*.p12`/`*.jks`
- 定期輪換 API Key 與 DB 憑證

### 私鑰加密（AES-GCM，L1 紅線）

- 錢包私鑰**儲存前必須 AES-GCM 加密**，DB 絕不存明文
- 加解密走既有含 `Aes`/`Gcm`/`Encrypt`/`Decrypt`/`Key` 的工具類（Bouncy Castle 1.78）；**改這些類需人工確認，不可自動改**
- 私鑰明文只在記憶體內短暫存在（簽交易當下），用後即棄，**禁寫入日誌 / 快取 / 回應**

## HMAC-SHA256 SignFilter（`/api/pay/*`）

- `/api/pay/*` 全部經 **SignFilter** 驗簽，新 endpoint **不可繞過** filter chain
- HMAC-SHA256 簽章內容 = `timestamp + nonce + 排序後參數`
- **防重放**：nonce 去重 + **5 分鐘** replay window（逾時或 nonce 重複一律拒絕）
- 驗簽失敗須記錄完整請求（遮蔽敏感欄位）並回既有錯誤碼
- `filter/SignFilter.java` **可讀不可自動改，需確認**

## Webhook 驗簽（`/api/thirdparty/*`）

- QuickNode / Tatum 等鏈上 webhook 進 `/api/thirdparty/*`，必須驗簽名或 IP 白名單後才處理
- **入款處理必須冪等**：同一鏈上交易（tx hash + log index）重複收到不可重複入帳
- 詳細對接模式見 `api-connector-builder` skill

## IP 白名單

- 平台範圍（per `platform_id`）的 IP / CIDR 設定，套用於 `/api/pay/*` 與 webhook 入口
- 白名單設定來自 config 表，經 setting 層讀取，不硬編碼

## Google 2FA

- 後台（`/api/manage/*`）登入採 Google Authenticator TOTP 二次驗證
- TOTP secret 屬敏感資料，儲存前加密，禁明文 / 禁入日誌

## 金額安全（L1 紅線）

- 所有金額運算使用 `BigDecimal`，禁 `double`/`float`
- 幣種 rate 換算、歸集門檻計算一律 `RoundingMode.DOWN`（無條件捨去，避免多給錢）
- 金額異動 / 入帳 / 歸集操作須有 Redis 分散式鎖防重複
- 改狀態的 service 方法必須 `@Transactional`；DB 寫入後同事務內或緊接更新 Redis 快取
- 冪等去重依靠交易唯一鍵（tx hash / orderNo 唯一約束）

## platform_id 多租戶隔離（L1 紅線）

- 資料以 `platform_id` 分租；後台用戶、錢包、入款均綁 platform
- **所有查詢必須以 `platform_id` 過濾；跨平台存取 = critical bug**
- Controller 從 resolver 取得當前 platform，禁信任前端傳入的 platformId 未經驗證直接查詢

## 日誌記錄與脫敏

- 用 `@Slf4j` + SLF4J，禁 `System.out.println`；日誌訊息用英文
- **絕不記錄**：私鑰、AES 金鑰、API Key / secret、TOTP secret、HMAC 簽章原文、完整助記詞
- 錢包地址 / tx hash 可記錄；敏感欄位輸出前遮蔽

## 依賴安全性

- 在 CI 中執行 OWASP Dependency Check
- 保持 Spring Boot（3.1.2）、Web3j、Trident、Bouncy Castle 在支援版本
- 發現已知 CVE 時建置失敗

## 發布前檢查清單

- [ ] 所有輸入均已驗證（`@Valid`）並帶 `platform_id`
- [ ] MyBatis 用 `#{}`，無 `${}` 拼接使用者輸入
- [ ] 私鑰儲存前 AES-GCM 加密，無明文
- [ ] `/api/pay/*` 走 SignFilter（HMAC-SHA256 + nonce + 5 分鐘 replay window），未繞過
- [ ] webhook（`/api/thirdparty/*`）已驗簽 / IP 白名單，且入款冪等
- [ ] 機密外部化（config 表 + `*ConfigCache`），無硬編碼、無敏感檔提交
- [ ] 金額計算用 BigDecimal + RoundingMode.DOWN，金額異動有 Redis 鎖
- [ ] 所有查詢以 platform_id 過濾，無跨平台存取
- [ ] 日誌不含私鑰 / 金鑰 / API Key / 簽章原文
- [ ] 依賴已掃描且為最新

**牢記**：預設拒絕、驗證輸入、最小權限、私鑰永不落地明文，並以設定為安全第一。
