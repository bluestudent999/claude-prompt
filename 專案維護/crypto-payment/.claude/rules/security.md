---
paths:
  - "**/*.java"
---
# 安全性（crypto-payment）

> 加密支付平台安全紅線。**凡涉及私鑰、金額、驗簽、多租戶、對外 API 的變更必須嚴格遵守。**
> 錢包 / 私鑰處理錯誤會造成**不可逆的資金損失**——有疑問一律停手問人。

---

## 1. 私鑰與加密（最高紅線）

- **私鑰儲存前必須以 AES-GCM 加密**，**禁明文**落庫、落 log、落設定檔
- 加解密邏輯集中在既有 `Aes`/`Gcm`/`Encrypt`/`Decrypt`/`Key` 相關類別；**修改這些類別須明確確認**，不可自動改
- **禁止**在任何 log、異常訊息、API 回應中輸出私鑰、助記詞、完整金鑰或解密後明文
- 金鑰 / secret 來源：對應 config 資料表 + `*ConfigCache` 預載，**非硬編碼**
- 本地開發憑證放 `.claude/settings.local.json` 的 `env`（不進版控）

## 2. 多租戶隔離（platform_id）

- **所有查詢、更新、刪除都必須以 `platform_id`（或等價 platform 範圍）過濾**
- **跨平台資料存取 = critical bug**——reviewer 發現即 `block`
- 後台用戶、錢包、設定（IP 白名單 / chain / token）全部 platform-bound
- 新 DAO / service 方法審查時，逐一確認 WHERE 條件含 platform 範圍；經 resolver 注入的 platform 上下文不可被繞過

## 3. HMAC 驗簽與防重放（`/api/pay/*`）

- `/api/pay/*` 一律走既有 **`SignFilter`（HMAC-SHA256）**，**不可繞過 filter chain**、不可為新 endpoint 另開後門
- 簽章組成：`timestamp + nonce + 排序後參數`；**replay window 5 分鐘**，逾時或 nonce 重複必須拒絕
- **修改 `filter/SignFilter.java` 須明確確認**——改壞會讓所有支付整合失效
- webhook（`/api/thirdparty/*`，QuickNode/Tatum）入站需驗簽或來源校驗後才解析

## 4. 存取控制

- **IP 白名單**：平台範圍的 IP/CIDR，設定在 setting/ + config 表
- **Google 2FA（TOTP）**：後台登入
- **RBAC**：角色 / 選單權限；新 `/api/manage/*` endpoint 須掛對應權限碼
- Controller 邊界輸入用 `@Valid` + Bean Validation
- API 錯誤回應**不暴露** stack trace、SQL、內部路徑

## 5. 金額安全

- **所有金額運算用 `BigDecimal`**，**禁 `double` / `float`**
  - 例外：純統計（筆數、耗時）、隨機數、限流速率可用 `double`
- **金額異動在 DB 事務中使用悲觀鎖**（`SELECT ... FOR UPDATE`）
- **餘額 / 入帳異動步驟（不可跳步）：** 分散式鎖（Redis）→ `@Transactional` 開事務 → `SELECT … FOR UPDATE` → 驗餘額 → 異動 → 寫流水 → commit
- **禁用 `synchronized` 做跨節點業務鎖**（多節點無效）

### RoundingMode（依場景）

| 場景 | RoundingMode | 原因 |
|------|--------------|------|
| 入帳 / 出款 / 退款 / 歸集金額 | **`DOWN`** | 避免多給錢 |
| 幣種 / rate 換算 | **`DOWN`** | 避免多給錢 |
| 一般業務中間值 | `HALF_UP` 可接受 | 常規四捨五入 |
| 報表 / 顯示用聚合 | `HALF_UP` 可接受 | 僅顯示 |

> **判定原則：** 值會變成**實際入帳/出帳**用 `DOWN`；僅**中間值或顯示**用 `HALF_UP`。不確定預設 `DOWN`。

## 6. SQL 安全

- MyBatis 一律 `#{param}` 參數化，**禁 `${param}`**（動態表名 / 排序欄位需白名單校驗）
- ShardingSphere 5.4 自動讀寫分離，**不要手動路由**
- schema 變更走 Flyway（見 `patterns.md`）

## 7. Log 脫敏

- 禁止記錄密碼、Token、完整 API Key、私鑰、助記詞
- webhook 原始 body 可記錄，但需遮蔽敏感欄位（地址可留、金鑰類必遮）

---

## 8. 檔案存取紅線（與 reviewer / 主 agent 共用）

- **禁讀**：`.env`、`application-prod.yml`、`application-staging.yml`、`*.key`/`*.pem`/`*.p12`/`*.jks`、`logs/`
  - 需要其中某個值 → 停手，請使用者只提供該值，勿直接讀檔
- **可讀不可自動改（需確認）**：flyway migration 目錄、`filter/SignFilter.java`、任何 `Aes`/`Gcm`/`Encrypt`/`Decrypt`/`Key` 加密類、`application-dev.yml`/`application.yml`、`pom.xml`
- **可自由讀寫**：`service/` `controller/` `repository/` `job/` `event/` `cache/` `src/test/`、前端 `src/`、`.claude/commands/`；`utils/` 新增可自由、改既有需確認

---

## 9. 安全審查清單（每次功能結束前必做）

- [ ] 所有新查詢是否都有 `platform_id` 過濾？
- [ ] 新 `/api/pay/*` endpoint 是否走 `SignFilter`（未繞過）？
- [ ] 有無明文私鑰 / 金鑰出現在程式碼、log 或回應中？
- [ ] 改狀態的方法是否有 `@Transactional` + 金額用 `BigDecimal` + `DOWN`？
- [ ] 使用者輸入是否都有驗證（`@Valid`）？
- [ ] webhook / 回調是否驗簽並防重放（nonce + 5 分鐘窗）？
