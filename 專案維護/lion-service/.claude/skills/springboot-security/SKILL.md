---
name: springboot-security
description: 安全性最佳實踐，涵蓋輸入驗證、SQL 注入防護、機密管理、日誌脫敏，以及後端服務常見安全需求（第三方驗簽、API Key、金額安全）。
origin: ECC
---

# Spring Boot 安全性審查

處理輸入、建立端點或管理機密時使用。

> **lion 先讀這兩份（本 skill 是通用補充，衝突時以它們為準）：**
> - `rules/security.md` §filter 防線 —— 認證 filter 曾因 `.do` 副檔名放行被實際入侵；改任何 `*Filter` / 放行清單 = L1，禁止新增副檔名 / 子字串 / `contains` 型放行（`checks/filter-bypass.md`）；同檔另有 §彩票（賠率、限額、封盤、開獎）
> - `rules/platform-isolation.md` —— platformId 只取自登入 token（resolver），不得取自請求 SO；查詢 / 快取 / ES / 匯出 / 排程都要帶 platformId

## 啟用時機

- 驗證使用者輸入（Bean Validation、自訂驗證器）
- 處理第三方服務商回調或 API 端點
- 管理機密（環境變數、第三方 config 表 + `*ConfigCache`）
- 處理金額運算或金額異動流程

## 輸入驗證

- Controller 使用 `@Valid` 的 Bean Validation
- SO（請求物件，lion 禁用 `DTO` 命名，見 `rules/patterns.md` §8）套用約束：`@NotBlank`、`@Email`、`@Size`、自訂驗證器
- 回應格式對齊同 controller 既有寫法（`rules/patterns.md` §4），不要自創 `ResponseEntity` 包法

```java
@Data
public class CreateUserSO {
  @NotBlank @Size(max = 100) private String name;
  @NotBlank @Email private String email;
  @NotNull @Min(0) @Max(150) private Integer age;
  // 不放 platformId：platformId 由 resolver 從登入 token 取得（rules/platform-isolation.md）
}
```

## SQL Injection 防護

lion 的 SQL 由 framework_v3 `SqlUtil` 組裝（**沒有 MyBatis / Spring Data**），注入面是**把請求參數拼進 SQL 字串**：

```java
// 錯誤：請求參數拼接進 SQL
buildSelect().where().addSql(" user_name = '" + so.getUserName() + "'").queryList();
buildSQL("select * from " + getTableName() + " order by " + so.getSortField());

// 正確：值走參數綁定
buildSelectWhere().andEqual("user_name", so.getUserName()).queryList();
buildSelectWhere().addSqlAndArgs(" and money >= ?", so.getMinMoney()).queryList();

// 正確：欄位名 / 排序方向來自請求 → 白名單映射後才拼
String col = SORT_COLUMNS.get(so.getSortField());   // 不在白名單 → 用預設或拒絕
```

- cp-service 的 `SqlInjectAndXssFilter` 是額外一層，**不能當成 DAO 可以拼接的理由**（`skills/mysql-patterns/SKILL.md` §1）

## 機密管理

- 機密不進原始碼；從環境變數載入
- 保持 `application.yml` 無憑證；用佔位符由部署時注入（對齊既有 yml 的佔位寫法）
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

- 第三方 API 金鑰、Secret 存放於對應的 config 資料表，執行期由 `*ConfigCache`（例：`PayConfigCache`、`TelegramConfigCache`，繼承 lion-common `CacheService<V>`）載入（`rules/security.md` §第三方 API 金鑰管理）
- 絕不在原始碼中硬編碼任何金鑰；金鑰不進 log
- `.claude/settings.local.json` 的 `env` 區段存放本地開發憑證（不進版控）
- 新增第三方時，設定欄位命名對齊同類既有對接

### 金額安全

- 所有金額運算使用 `BigDecimal`，禁止 `double`/`float`
- 幣種 rate 換算使用 `RoundingMode.DOWN`（無條件捨去，避免多給錢）
- 金額異動操作必須有分散式鎖防重複；一般會員餘額走 lion-common `UserMoneyService.changeMoney*`，不自己寫 `UPDATE user_money`
- 訂單去重依靠 `orderNo` 唯一約束；冪等判定在寫流水**前**，同 `orderNo` 重送回傳與首次相同結果

### platformId 驗證（包網商隔離，lion 最高風險之一）

- platformId 只取自 resolver（`UserIdWithPlatformId` / `PlatformId` / `TokenInfo` 參數），**不得取自請求 body / query 的 SO 欄位**；SO 帶了 platformId 必須與登入者比對或覆寫
- `controller/boss/`、`manage/`、`thirdmanage/` 依設計跨包網商，不算隔離問題，但權限要求更高
- 完整規則與檢查：`rules/platform-isolation.md`、`checks/platform-isolation.md`

### 熔斷限流

- 本 repo（lion-service）目前**無**全域熔斷 / 限流框架（pom 查無 Sentinel / Resilience4j / Bucket4j / Hystrix）
- 高成本端點若需限流，目前僅能個別自寫（Filter / 切面 / Redis 計數）— **新增前先開架構討論**
- 若全站性導入限流，應由 architect agent 評估方案後統一

## 發布前檢查清單

- [ ] 所有輸入均已驗證並清理
- [ ] 沒有新增副檔名 / 子字串 / `contains` 型放行；放行用精確路徑、檢查失敗必 `return`（`rules/security.md` §filter 防線）
- [ ] platformId 只取自 resolver；查詢 / 快取 / ES / 匯出帶 platformId（`rules/platform-isolation.md`）
- [ ] 賠率只取自伺服器設定、限額檢查與扣額同鎖同事務、封盤以伺服器時間判定（`rules/security.md` §彩票）
- [ ] SQL 無請求參數拼接（`SqlUtil` 綁定參數；欄位名白名單）
- [ ] 機密已外部化；無機密提交
- [ ] 第三方服務商回調有驗簽/IP 白名單
- [ ] 金額計算用 BigDecimal + RoundingMode.DOWN
- [ ] 金額異動有分散式鎖防重複
- [ ] 日誌不含敏感資料（密碼、Token、完整 API Key）
- [ ] 依賴已掃描且為最新

**牢記**：預設拒絕、驗證輸入、最小權限，並以設定為安全第一。
