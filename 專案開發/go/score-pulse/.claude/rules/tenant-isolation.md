# 多業主隔離（I1，D7）

> 一位業主 = 一個站點 = 一個專屬域名。業主只看得到自己的會員、收藏、通知、導流記錄與設定；總控看全部或被指派的業主。
> **隔離 bug 的共同特徵：在單租戶環境 100% 測不出來。** 少一個 `operator_id = ?`，第二位業主上線那天就是資料洩漏。
> 本文是機制與檢查清單；決策推導在 `tech-decisions.md` D7、§4。

---

## 1. 誰是租戶、怎麼解析

| 入口 | 租戶來源 | 解析位置 |
|------|---------|---------|
| H5／App 前台 API | **HTTP Host**（業主專屬域名）→ `operator_domain` 表（Redis 快取）→ `operator` | `platform/tenant` middleware（Sort 100） |
| 業主後台 API | 登入 session 綁定的 `operator_id`（**不是** Host） | `platform/auth` middleware（Sort 200）寫入 context |
| 總控後台 API | 無租戶；查詢範圍 = 「管理全部」或「被指派的業主集合」 | `platform/auth`，`admin` 包的 `AssignedScope(ctx)` |
| WebSocket 握手 | Host → operator；業主停用 → 拒絕升級 | `realtime` 包 `HandshakeHandler` |
| Kafka consumer | 訊息內的 `op`（`notify.trigger`）；比賽資料無租戶 | consumer 自己把 `op` 放進 ctx |

**鐵律：租戶 id 絕不接受由呼叫端指定。** 任何 `?operator_id=`、body 裡的 `operatorId`、header 裡的 platform code 都是越權入口。總控選單站看單一業主，也是**在伺服器端驗證該業主在被指派集合內**之後才放行。

```go
// platform/tenant
type CtxKey struct{}
func FromCtx(ctx context.Context) (Operator, bool)
func MustFromCtx(ctx context.Context) Operator   // 沒有就 panic(runtime.UnauthorizedError())
func Scope(ctx context.Context) func(*gorm.DB) *gorm.DB   // db.Scopes(tenant.Scope(ctx)) → WHERE operator_id = ?
```

---

## 2. 哪些表是租戶表（必帶 `operator_id`）

| 租戶表（必帶） | 全平台共用（不帶） |
|---|---|
| `operator`、`operator_domain`、`operator_brand`、`redirect_setting`、`ad_slot`、`ad_material`、`redirect_click`、`redirect_impression`、`visit_log` | `sport`、`league`、`team`、`player`、`season`、`match`、`match_event`、`match_stat`、`match_lineup`、`match_override`、`match_media` |
| `member`、`member_device`、`member_login`、`sms_record`、`favorite`、`member_setting`、`search_log` | `odds_company`、`odds_live`、`odds_history`、`honor_map`、`ranking_*` |
| `notice_setting`、`notice`、`push_token`、`push_record` | `hot_content`（平台預設份）、`featured_match`、`source_monitor`、`app_version`、`category_i18n` |
| `admin_user`／`admin_role`／`admin_audit` 的 **業主後台** 列（`scope = operator`） | `admin_user`／`admin_role`／`admin_audit` 的 **總控** 列（`scope = platform`） |
| `hot_content_override`（業主自加與排序） | |

新增表時**先決定它屬哪一欄**，寫進 `architecture.md` §4 與本表。判不出來 → 問「同一列資料會不會屬於不同業主」，會就是租戶表。

---

## 3. 資料層強制（gorm）

| 層 | 規則 |
|----|------|
| dao | 租戶表的**每一個**查詢、更新、刪除都 `db.Scopes(tenant.Scope(ctx))`；INSERT 由 `BeforeCreate` hook 從 ctx 填 `operator_id`，**不接受 DTO 帶入** |
| 保險絲 | `platform/tenant` 註冊 gorm callback：對 §2 租戶表清單，查詢 SQL 若無 `operator_id` 條件 → **panic**（prod 也開，寧可 500 不洩漏） |
| 總控跨租戶 | 用 `tenant.AdminScope(ctx)`：被指派集合 → `operator_id IN (?)`；管理全部 → 不加條件，但**必須明寫** `tenant.AllOperators(ctx)` 讓 callback 放行，且只允許在 `admin` 包使用 |
| 唯一鍵 | 租戶內唯一的欄位（帳號、手機號）唯一鍵是 `(operator_id, xxx)`；全平台唯一的（專屬域名）才是單欄唯一 |
| 會員歸屬 | `member.operator_id` 註冊時寫入、**終身不變**（Spec-1 R32）；沒有「轉移會員」的 API |

---

## 4. 查詢結果與錯誤訊息

- 取不到他人資料時回 **404 或空清單**，不回 403（403 會洩漏「那筆存在」）。
- 計數、分頁、匯出的分母都是租戶範圍內的；總控匯總另算。
- Log 帶 `operator_id`（有的話），不帶 session token。

---

## 5. 測試：雙租戶是預設 fixture（硬規則）

`test/fixtures/tenants.go` 提供 `op-a`（`a.example.test`）與 `op-b`（`b.example.test`）各一位業主、各一位會員、各一位業主後台管理員、一位總控「只指派 A」的人員。

**每一個**租戶端點的單元測試與整合測試至少含：

| 情境 | 斷言 |
|------|------|
| 以 A 的 Host／登入呼叫，帶入 B 的資源 id | **取不到**（404／空），不是「筆數對」 |
| 以 A 的業主後台帳號呼叫 B 的設定 | 404 |
| 以「只指派 A」的總控人員看全部業主匯總 | 只有 A；選 B 的單站 → 拒絕 |
| A 的會員收藏數 | 不受 B 的會員影響 |
| 停用 B | A 的前台與 WebSocket 不受影響；B 的 WebSocket 被拒 |

命名：`Test<Handler>_OtherTenant_NotFound`、`Test<Handler>_AssignedScope_ExcludesUnassigned`。

> **Review 檢查點：** 看到新查詢的第一個問題永遠是「它經過 `tenant.Scope` 了嗎？沒有的話，為什麼這張表不是租戶表？」答不出來 → block。

---

## 6. 本專案容易漏的地方

| 地方 | 為什麼容易漏 |
|------|-------------|
| 搜尋（S3-T7）| 搜的是全平台共用的聯賽／球隊，但「最近搜尋」是會員的 → 兩種表混在同一個 service |
| 熱門內容（S4-T8、S5-T6）| 平台預設份是共用表，業主覆蓋是租戶表；回應要合併 |
| 通知觸發（S3-T12～T15）| 一場比賽的事件要扇出到**每位業主**各自的會員；比對時 ctx 沒有租戶，要逐業主迭代並各自 Scope |
| 導流數據匯出（S1-T10、S4-T13）| 匯出檔的檔名與內容都不得含其他業主 |
| WebSocket 通知 destination | `/operator/{op}/member/{id}/notice` 的 `{op}` 必須等於握手時解析的業主，否則拒絕訂閱 |
| 操作記錄 | 業主後台的操作記錄只給該業主看；總控看全部 |
