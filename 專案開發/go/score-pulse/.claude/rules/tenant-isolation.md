---
paths:
  - "internal/**/dao/**"
  - "internal/**/controller/**"
  - "internal/**/service/**"
  - "internal/core/tenant/**"
  - "internal/core/auth/**"
  - "internal/realtime/**"
  - "migrations/**"
  - "test/**"
---

# 多業主隔離（I1，D7）

> 一位業主 = 一個站點 = 一個專屬域名。業主只看得到自己的會員、收藏、通知、導流記錄與設定；總控看全部業主（D24）。
> **隔離 bug 的共同特徵：在單租戶環境 100% 測不出來。** 少一個 `platform_code = ?`，第二位業主上線那天就是資料洩漏。
> 本文是機制與檢查清單；決策推導在 `tech-decisions.md` D7、§4。

---

## 1. 誰是租戶、怎麼解析

| 入口 | 租戶來源 | 解析位置 |
|------|---------|---------|
| H5／App 前台 API | **HTTP Host**（業主專屬域名）→ `platform_domain` 表（Redis 快取 `sp:pf:domain:`）→ 業主代碼 | `core/tenant` middleware（Sort 100） |
| 業主後台 API | 登入 session 綁定的 `platform_code`（**不是** Host、不是網址） | `core/auth` session middleware（Sort 200）載入身分，`PrincipalBridge`（Sort 250）放進 context；唯一讀取點 `auth.MustPlatform(ctx)`（ctx 的業主必須等於 session 身分的業主，否則 403；`MustBackOffice` 業主後台分支走它）；啟動檢查要求有業主後台路由時 bridge 必須在、且排在 session 之後（P-28） |
| 總控後台 API | 無租戶；總控身分對全部業主（D24），人員之間的差別只在角色的選單代碼。針對單一業主的總控端點由總控明示業主代碼（路徑 `{code}` 為主，查詢型可用 query），伺服器以 `auth.ManageTarget(ctx, code)` 驗證（身分是總控、ctx 無業主、`tenant.ValidCode`）後放進 ctx，並以 platform 包 `GetBrief`（`SelfScope`）確認存在（查無 → 404／10001） | `core/auth`（`ManageTarget`）；全部業主的列表／匯總只在白名單 dao 函式用 `tenant.AllPlatforms` |
| 後台 IP 白名單（Sort 150，P-29） | 總控路徑用總控那一份；業主後台登入用網址代碼、其餘用 session 的代碼（唯讀）。代碼**只用於挑白名單**，不寫回請求 ctx | `core/auth` 的 `IPAllowMiddleware` |
| WebSocket 握手 | Host → 業主代碼；業主停用 → 拒絕升級 | `realtime` 包 `HandshakeHandler` |
| Kafka consumer | 訊息內的 `platform_code`（`notify.trigger`，Kafka key 同為 `platform_code`）；比賽資料無租戶 | consumer 經 `core/tenant` 受控的設定函式放進 ctx（S3 通知 ticket 新增：先 `tenant.ValidCode`、拒絕已帶業主或 `AllPlatforms` 的 ctx，並加進 arch-check 第 15 項檔案白名單）；**不得**在 consumer 直接呼叫 `tenant.WithPlatform`，也不得把整個功能包目錄加進白名單 |

**鐵律：租戶（業主代碼）絕不接受由呼叫端指定。** 任何 `?platform_code=`、body 裡的 `platformCode`、header `x-session-platform-code` 都是越權入口（業主後台登入網址的代碼只決定「在哪一套後台驗證帳密」，不授予任何範圍）。總控指定單一業主只經 `auth.ManageTarget`（伺服器驗證身分、格式與存在）；業主後台與前台永遠不接受呼叫端指定（請求帶的業主代碼一律忽略，不回錯）。**唯一的請求結構例外**（P-29）：總控 IP 白名單 API 的 `internal/manage/dto/ip_allow.go` `IPAllowListSO.PlatformCode`（form）、`IPAllowAddSO.PlatformCode`（json）、`IPAllowDeleteSO.PlatformCode`（json）——只掛 `/api/manage`、一律經 `auth.ManageTarget` 驗證並查業主存在、三個結構只准在 `internal/manage/controller/ip_allow.go` 使用；與 `scripts/tenant-check.sh` 的 `MANAGE_TARGET_SO_ALLOW`（檔案:結構:欄位:標籤種類）、`MANAGE_TARGET_SO_USE_ALLOW` 一起改。

```go
// core/tenant
func WithPlatform(ctx context.Context, p Platform) context.Context  // 唯一設定入口；ctx key 不匯出（ctxKey），呼叫位置只准 arch-check 第 15 項檔案白名單
func FromCtx(ctx context.Context) (Platform, bool)    // Platform{Code, Name, Status, Domain}
func MustFromCtx(ctx context.Context) Platform   // 沒有就 panic(runtime.UnauthorizedError())
func Scope(ctx context.Context) func(*gorm.DB) *gorm.DB   // db.Scopes(tenant.Scope(ctx)) → WHERE platform_code = ?
func SelfScope(ctx context.Context) func(*gorm.DB) *gorm.DB   // platform 表本身：WHERE code = ?（只准 internal/platform/dao）
func ManageRows() func(*gorm.DB) *gorm.DB  // 總控自身的列：WHERE platform_code = '0'（只准 internal/manage/dao）
```

---

## 2. 哪些表是租戶表（必帶 `platform_code`）

| 租戶表（必帶） | 全平台共用（不帶） |
|---|---|
| `platform`（租戶鍵是自己的 `code`）、`platform_domain`、`platform_brand`、`redirect_setting`、`ad_slot`、`ad_material`、`redirect_click`、`redirect_impression`、`visit_log` | `sport`、`league`、`team`、`player`、`season`、`match`、`match_event`、`match_stat`、`match_lineup`、`match_override`、`match_media` |
| `member`、`member_device`、`member_login`、`sms_record`、`favorite`、`member_setting`、`search_log` | `odds_company`、`odds_live`、`odds_history`、`honor_map`、`ranking_*` |
| `notice_setting`、`notice`、`push_token`、`push_record` | `hot_content`（平台預設份）、`featured_match`、`source_monitor`、`app_version`、`category_i18n` |
| `admin_info`／`admin_role`／`admin_ip_allow`／`login_log`／`operate_log` 的 **業主後台** 列（`scope = platform`，`platform_code` = 業主代碼） | `admin_info`／`admin_role`／`admin_ip_allow`／`login_log`／`operate_log` 的 **總控** 列（`scope = manage`，`platform_code = '0'`） |
| `hot_content_override`（業主自加與排序） | |

新增表時**先決定它屬哪一欄**，寫進 `architecture.md` §4 與本表。判不出來 → 問「同一列資料會不會屬於不同業主」，會就是租戶表。

---

### 2.1 業主代碼與系統保留代碼（2026-11-02 使用者決定，D20）

租戶鍵是字串型的**業主代碼** `platform_code VARCHAR(20) utf8mb4_bin`（= `platform.code`）。`platform` 表本身以自己的 `code` 為租戶鍵（`id` 只是自增主鍵）。

| 值 | 意義 | 規則 |
|----|------|------|
| `'0'` | **系統層級**：總控（可跨平台的維護人員）自身的資料列，即 `admin_info`／`admin_role`／`admin_ip_allow`／`login_log`／`operate_log` 中 `scope = manage` 的列（`tenant.SystemCode`） | 只允許出現在後台表：`admin_info`、`admin_role`、`admin_ip_allow`、`login_log`、`operate_log`（D27）；以 `tenant.ManageRows()` 查（只准 `internal/manage/dao`）。資料庫以 CHECK 約束 `scope` 與 `platform_code` 對應（`ck_admin_*_scope_code`、`ck_login_log_scope_code`、`ck_operate_log_scope_code`） |
| 業主代碼 | 一般業主 | 建立業主時由總控輸入、**不自動產生**：小寫英數與連字號、3～20 字、不得以連字號開頭或結尾，且**不得是保留字** `login`、`logout`、`auth`、`admin`、`api`、`manage`（會撞後台網址固定段 `/platform/login`、`/api/platform/auth/…`；`tenant.ReservedCodes`，資料庫 `ck_platform_code_reserved`、`ck_platform_domain_code_reserved`）（`tenant.ValidCode`，大小寫敏感、不轉小寫）；**全平台唯一**（`uk_platform_code`）；**建立後不可改**（不提供修改端點；保險絲對 UPDATE 租戶鍵 panic） |

業務租戶表（會員、通知、導流記錄等）**永遠沒有** `platform_code = '0'` 的合法列；出現即為誤用（保險絲與資料庫 CHECK 都會擋）。
**型別紅線**：租戶鍵是字串，條件不得以數字比較（MySQL 的 `'op-a' = 0` 為真，等於全表）；保險絲對數字參數或字面值 panic。

## 3. 資料層強制（gorm）

| 層 | 規則 |
|----|------|
| dao | 租戶表的**每一個**查詢、更新、刪除都 `db.Scopes(tenant.Scope(ctx))`（`platform` 表本身用 `tenant.SelfScope(ctx)`，只准 `internal/platform/dao`）；INSERT 由 create callback 從 ctx 填 `platform_code`，**不接受 DTO 帶入** |
| 保險絲 | `core/tenant` 註冊 gorm callback：對 §2 租戶表清單，查詢 SQL 若無租戶鍵條件（`platform` 表是 `code`，其他是 `platform_code`，字邊界比對）→ **panic**（prod 也開，寧可 500 不洩漏）；租戶鍵以數字比較 → panic；UPDATE 的目標欄含租戶鍵 → panic（業主代碼不可改）；ctx 同時帶業主與 `AllPlatforms` 標記 → panic（不論是不是租戶表；P-28）。`auth.ManageTarget` 也拒絕帶 `AllPlatforms` 的 ctx |
| 總控跨租戶 | 總控沒有範圍子集（D24）。單一業主：`auth.ManageTarget` 把業主放進 ctx 後照常 `tenant.Scope`（保險絲照常檢查；同一 handler 寫總控自己的列用原本的 ctx）；全部業主 → 不加條件，但**必須明寫** `tenant.AllPlatforms(ctx)` 讓 callback 放行，且只允許在白名單位置使用：`manage` 包；`internal/platform/dao/platform.go` 的 `ExistsByName`、`ExistsByCode`、`ListForManage`（總控建立業主的唯一檢查與列表；`ListForManage` 對帶業主的 ctx 拒絕）、`SummaryForManage`（總控工作台彙總，P-24）；`internal/core/tenant/resolver.go`（Host → 業主）。後台登入網址的代碼本身就是租戶鍵：先過 `tenant.ValidCode`，再把 ctx 設成該代碼經 `SelfScope` 讀，**不需要**跨租戶出口。白名單與 `scripts/arch-check.sh` 第 8 項一致，新增位置要兩邊一起改。彙總（計數）查詢在範圍判不出時**回錯而不是回 0**（身分不是總控、ctx 帶業主、ctx 與身分不符；0 也是會被看見的數字。P-24：service 先回 403，platform dao 的 `SummaryForManage` 與 manage dao 的 `CountActive`／`ListRecent` 在 ctx 與後台不符時也回錯、不查） |
| 誰能設定業主與身分 ctx | `tenant`、`auth` 兩包的 ctx key 型別**不匯出**（`ctxKey`），其他包無法以 `context.WithValue` 偽造；唯一入口 `tenant.WithPlatform`、`auth.WithPrincipal`，呼叫位置是 arch-check 第 15 項的**檔案層級**白名單（掃 `internal` 與 `cmd` 的非測試檔）：`WithPlatform` 只准 `internal/core/tenant/context.go`（定義）、`internal/core/tenant/middleware.go`（前台 Host）、`internal/core/auth/session_middleware.go`、`internal/core/auth/bridge.go`、`internal/core/auth/manage_target.go`、`internal/manage/service/login.go`（登入網址的代碼）、`internal/manage/dao/role.go`（建業主同一事務的第一批角色列）、`internal/core/auth/ipallow_middleware.go`（P-29：**只用於挑白名單時的區域 ctx**，不寫回請求 ctx，之後的 handler 看到的請求 ctx 沒有業主）；`WithPrincipal` 只准 `internal/core/auth/principal.go`（定義）與 `internal/core/auth/session_middleware.go`；`auth.WithSession`（登入中途的 session）只准 `internal/core/auth/session.go`（定義）與 `session_middleware.go`；白名單檔案內三者只准直接呼叫 `Name(`（方法值、賦值轉手、`go:linkname` 一律 FAIL）；`ctxKey` 在兩包內只准各自定義檔，且只准 `type ctxKey struct{}` 與 `context.WithValue(ctx, ctxKey{}, …)`、`.Value(ctxKey{})` 的引數（別名、以它建的匯出型別或變數一律 FAIL）；舊匯出名 `CtxKey`／`CtxPrincipal` 不得再出現；15e：`internal` 與 `cmd` 不得宣告任何 `Value` 方法（內嵌 `context.Context` 覆寫 `Value` 就能讓 `FromCtx` 讀到偽造的業主與身分；放行清單 `VALUE_METHOD_ALLOW` 為空，新增要經 review）。新增位置要與 `scripts/arch-check.sh` 一起改，不得放寬成目錄 |
| WHERE 寫法（白名單） | 保險絲把 WHERE 實際組成 SQL 後逐字檢查，**只認得**：租戶鍵以 `<鍵> = ?` 或 `<鍵> IN (?, …)`（`IN ?` 帶 `[]string`）出現，綁定值是 Go `string`／`[]string`（或引號字串字面值），且只和其他條件以 AND 相連（可在只含 AND 的括號裡）。其他一律 panic：數字／布林／十六進位、運算式、函式、CAST、CONCAT、欄名或 `clause.Column`、反向 `? = 鍵`、`NOT`／`!`、`IS`、`!=`、`<>`、`LIKE`、`NOT IN`、包在 OR 分組或函式裡、頂層 `OR`／`\|\|`／`XOR`、括號不平衡、SQL 註解、手寫字串子查詢（`*gorm.DB` 子查詢由它自己執行時的保險絲檢查）。有 JOIN 時，帶表名的租戶鍵必須是主表或主表別名。**ctx 有業主時，每一個租戶鍵的值都必須等於 ctx 的業主代碼**（`IN (NULL)` 除外；範圍外的代碼請在 dao 直接回查無，不要拿去查）。`between … and` 的 and 不算條件邊界；`Table("?", clause.Table{…})` 先組成 SQL 再判斷主表。明寫 `AllPlatforms` 時不要求有租戶鍵、不比對 ctx，但只要出現租戶鍵就照樣檢查寫法與 OR |
| 共用主表 | 主表不是租戶表（且沒有 `AllPlatforms`）時，`Joins`、FROM 子句的 joins、`Table()` 字串（逗號 join、衍生表）、`Select` 字串、WHERE 的手寫字串（含 `gorm.Expr` 參數）**都不得帶進任何租戶表** → panic；要用租戶表的資料，請以 `*gorm.DB` 子查詢（它自己過保險絲、要有 `tenant.Scope`）或直接查租戶表 |
| 寫入 | 租戶表禁 `ON CONFLICT`（`Save(切片)`、`OnConflict{UpdateAll}`／`DoUpdates`／`DoNothing`）；`Create` 的 struct（含批次、他型別 struct）／`map`／`*map`／`[]map` 都由 ctx 覆寫 `platform_code`（map 直接寫入並讀回），`*[]map` 與其他 map 型別、ctx 有業主卻無法保證寫入 → panic。**ctx 沒有業主的 INSERT 必須明寫 `tenant.SystemWrite(ctx)`**（總控自身的列、建立業主、建業主同一事務內的第一批列；只准 `internal/manage/dao`、`internal/platform/dao`，arch-check 第 12 項）或 `AllPlatforms`（測試 seed），否則 panic；`platform` 表不得在業主 ctx 下建立。UPDATE 目標欄（經 schema 解析：欄位名、column tag、內嵌 struct，以及 `db.Clauses(clause.Set{…})`）含租戶鍵 → panic |
| 手寫 SQL | 保險絲不涵蓋 `Raw`／`Exec`：`internal/` 非測試程式的 `.Raw(`／`.Exec(` 第一個引數必須是字串字面值，且（去掉 `'…'` 字串值後）**不得提到任何租戶表**；`database/sql` 直連只准在 `internal/core`（`scripts/arch-check.sh` 第 11 項；非 SQL 的 `.Exec(`，例如 go-redis pipeline，逐檔列在 `RAW_EXEC_ALLOW` 並寫原因） |
| 保險絲的限制 | 它是**縱深防禦，不取代 dao 的 code review**：以組出的 SQL 字元判斷、不是完整 SQL 解析器（不認得的寫法一律拒絕）；經變數傳遞的 append-only 刪改（`.Delete(&rows)`）arch-check 抓不到；Raw／Exec 與 database/sql 只靠 arch-check；跨租戶出口（`AllPlatforms`）的正確使用靠白名單與 review；主表是租戶表時 JOIN 進來的其他租戶表只檢查主表的租戶鍵（被 JOIN 表的範圍靠 review）；`SystemWrite` 寫入的租戶鍵值由 dao 自己決定（資料庫 CHECK 擋格式與保留代碼） |
| 唯一鍵 | 租戶內唯一的欄位（帳號、手機號）唯一鍵是 `(platform_code, xxx)`；全平台唯一的（專屬域名）才是單欄唯一 |
| 會員歸屬 | `member.platform_code` 註冊時寫入、**終身不變**（Spec-1 R32）；沒有「轉移會員」的 API |

---

## 4. 查詢結果與錯誤訊息

- 取不到他人資料時回 **404 或空清單**，不回 403（403 會洩漏「那筆存在」）。
- 計數、分頁、匯出的分母都是租戶範圍內的；總控匯總另算。
- Log 帶 `platform`（業主代碼，有的話），不帶 session token。

---

## 5. 測試：雙租戶是預設 fixture（硬規則）

`test/fixtures/tenants.go` 提供 `op-a`（`a.example.test`）與 `op-b`（`b.example.test`）各一位業主、各一位會員、各一位業主後台管理員、兩位總控人員（root 第 0 級、一般人員 ops；D24 皆對全部業主）。

**每一個**租戶端點的單元測試與整合測試至少含：

| 情境 | 斷言 |
|------|------|
| 以 A 的 Host／登入呼叫，帶入 B 的資源 id | **取不到**（404／空），不是「筆數對」 |
| 以 A 的業主後台帳號呼叫 B 的設定 | 404 |
| 以一般總控人員（ops，持有代碼）看業主列表／匯總 | A、B 都在；沒有代碼 → 403／40100 |
| 以 A 的業主後台身分帶 B 的代碼（標頭 `x-session-platform-code`、query、body） | 只有 A（忽略，不回錯） |
| A 的會員收藏數 | 不受 B 的會員影響 |
| 停用 B | A 的前台與 WebSocket 不受影響；B 的 WebSocket 被拒 |

命名：`Test<Handler>_OtherTenant_NotFound`、`Test<Handler>_OtherTenant_IgnoresClientPlatformCode`。

> **Review 檢查點：** 看到新查詢的第一個問題永遠是「它經過 `tenant.Scope` 了嗎？沒有的話，為什麼這張表不是租戶表？」答不出來 → block。

---

## 6. 本專案容易漏的地方

| 地方 | 為什麼容易漏 |
|------|-------------|
| 搜尋（S3-T7）| 搜的是全平台共用的聯賽／球隊，但「最近搜尋」是會員的 → 兩種表混在同一個 service |
| 熱門內容（S4-T8、S5-T6）| 平台預設份是共用表，業主覆蓋是租戶表；回應要合併 |
| 通知觸發（S3-T12～T15）| 一場比賽的事件要扇出到**每位業主**各自的會員；比對時 ctx 沒有租戶，要逐業主迭代並各自 Scope |
| 導流數據匯出（S1-T10、S4-T13）| 匯出檔的檔名與內容都不得含其他業主 |
| WebSocket 通知 destination | `/platform/{code}/member/{id}/notice` 的 `{code}` 必須等於握手時解析的業主代碼，否則拒絕訂閱 |
| 操作記錄 | 業主後台的操作記錄只給該業主看；總控看全部 |
