# 對外事件契約（跨系統，不可片面變更）

> 採 **D16** 後，**事件拉取 API 是唯一的對外事件介面**。不再有 Webhook 推送端點。
> 下游（各支付系統）在**不同 repo**。契約破了，下游不會報錯——它會**靜默漏單或重複入帳**。

---

## 1. 唯一路徑：事件拉取 API

```http
GET /v1/events?after_sequence=88123456&limit=100&chain=BSC
Authorization: Bearer <subscriber-api-key>
```

```json
{
  "events": [
    {
      "sequence": 88123457,
      "event_id": "01J9Z8K3M4N5P6Q7R8S9T0V1W2",
      "event_type": "payment.confirmed",
      "idempotency_key": "BSC_0xabc...def_12_payment.confirmed",
      "tenant_id": "main",
      "occurred_at": "2026-08-14T10:35:22Z",
      "schema_version": "1.0",
      "data": { }
    }
  ],
  "has_more": true,
  "latest_sequence": 88125000
}
```

| 欄位 | 語意 |
|------|------|
| `sequence` | 全域單調遞增序號（`events.id`）。**下游據此保存游標** |
| `event_id` | 事件唯一識別（ULID） |
| `event_type` | `payment.confirmed`；`payment.detected` 為**選用**（D6，快鏈預設關閉）。**`payment.reorged` 不存在**（D17 已自契約移除） |
| `idempotency_key` | 下游去重用。**即使有游標仍必須去重** |
| `tenant_id` | 事件所屬租戶。跨租戶訂閱者（如稽核系統）靠它分流 |
| `occurred_at` | 事件發生時間（UTC） |
| `schema_version` | 契約版本。擴充欄位遞增 minor，破壞性變更遞增 major 並協調過渡期 |
| `has_more` | 尚有更多事件，下游應立即再拉一次（補齊時的連續分頁） |
| `latest_sequence` | **該訂閱者可見範圍內**的最大序號，供下游計算落後量 |

---

## 2. 五條契約鐵律

### ① 認證即授權範圍

由 API Key 解析出 `subscriber_id` 與其訂閱的租戶集合，**只回傳該範圍內的事件**（不變量 **I8**）。

> **`tenant_id` 絕不接受由呼叫端指定。** 那會成為越權查詢的入口。任何形式的 `?tenant_id=` 參數都是安全漏洞。

### ② `latest_sequence` 是訂閱者視角，不是全域值

回傳全域最大序號會**洩漏其他租戶的事件量資訊**。必須以該訂閱者可見範圍計算。

### ③ `sequence` 單調但**不連續**

跳號是其他租戶的事件。因此：

- **下游不可用「連號檢查」偵測遺漏** —— 會誤報。
- 完整性由 `id > cursor` 的查詢條件保證，不依賴連號。
- **這一點必須寫進交付給下游的契約文件**，否則下游一定會實作出錯誤的缺口偵測。

### ④ 游標是效率機制，冪等鍵才是正確性機制

下游的標準處理流程（`§6.2`，兩者缺一不可）：

```text
 1. cursor = load_persisted_cursor()
 2. loop:
 3.     resp = GET /v1/events?after_sequence=cursor&limit=100
 4.     for event in resp.events:
 5.         if already_processed(event.idempotency_key): continue   ← 不可省
 6.         process(event)
 7.         mark_processed(event.idempotency_key)                    ← 與 6 同一本地事務
 8.     cursor = max(e.sequence for e in resp.events)
 9.     persist_cursor(cursor)
10.     if not resp.has_more: sleep(10s)
```

下游若在步驟 6 成功、步驟 9 之前崩潰，重啟後會重複拉到同一批事件 —— **這是設計上允許的**，正確性靠步驟 5/7 的冪等鍵保證。

### ⑤ 落後時不要沿用 10 秒節奏

建議輪詢週期 10 秒（與掃鏈同步）。但落後時應**持續拉取直到 `has_more = false`**，與 D13 的補塊邏輯同理。

---

## 3. 變更契約的規則

| 變更類型 | 處置 |
|---------|------|
| **新增可選欄位** | `schema_version` minor +1。可單邊上線，但要通知下游 |
| **改欄位語意 / 改名 / 移除 / 改型別** | **破壞性變更**：major +1，**必須與所有下游協調過渡期**。停手回報使用者，不得自行實施 |
| **新增 `event_type`** | 需確認下游對未知 type 的處置（忽略 or 報錯）。列 OQ |
| **改 `idempotency_key` 組成規則** | **等同資損風險** —— 下游既有去重表會失效，同一筆交易會被重複入帳。**絕對禁止**未經協調的變更 |
| **改 `sequence` 語意（例如改成每租戶獨立編號）** | 破壞下游游標。禁止 |

> **本專案不得修改下游 `crypto-payment` 的任何程式碼。** 需要下游配合時，產出「給下游的變更說明」交由使用者協調。

---

## 4. Admin API（維運介面）

| API | 方法 | 說明 |
|-----|------|------|
| `/admin/reconcile/run` | POST | 手動觸發對帳，需指定 `tenant_id`、日期與鏈 |
| `/admin/scanner/pause` | POST | 暫停指定鏈掃描（維護、緊急止血），**恢復後自動補塊** |
| `/admin/tenants` | GET／POST | 租戶查詢與開通（含確認數覆寫） |
| `/admin/subscribers` | GET／POST／PATCH | 訂閱者開通、API Key 輪替、限流調整、停用 |

**租戶範圍限定（硬規則）：** Admin 操作者需具備租戶範圍屬性。針對租戶 A 的補塊**不應影響租戶 B**，操作稽核日誌必須記錄 `tenant_id`。全域操作（如 Scanner pause）需獨立的全域管理員角色。

> **`pause` 在事故處理時非常重要**：發現解析邏輯有誤時，第一步應該是**停止繼續產生錯誤事件**，而不是一邊修一邊繼續發。
> **採 D16 後不再需要「手動重發」API** —— 事件持久保存於 `events`，下游把游標往回調就能重放。這是 Pull 模型的附帶收益：少一支會製造資損風險的維運 API。

---

## 5. 租戶開通 Runbook（本期不做自助）

1. 建立租戶（`POST /admin/tenants`），設定確認數政策。
2. 於 Secret Manager 產生訂閱者 API Key，**僅將雜湊寫入** `subscribers.api_key_hash`。
3. 建立訂閱者與訂閱關係（`subscriptions`）。
4. 匯入該租戶收款地址，**系統須拒絕已屬於其他租戶的地址**（I9）。
5. 端到端驗證：小額入金 → 下游拉取到該事件 → **以該租戶憑證確認取不到其他租戶的任何事件**。
6. 納入每日對帳範圍與游標落後監控。

> **步驟 5 的最後一項不可省略** —— 這是 I8 在正式環境的唯一驗證機會。

---

## 6. 對帳（獨立於事件流的核對路徑）

任何支付系統都不能只靠「事件應該有送到」運作。每日對帳任務（凌晨低峰）：

1. 統計前一日各鏈 `confirmed` 交易，產出 `idempotency_key` 集合。
2. 呼叫下游對帳介面取得其同期已入帳集合。
3. 比對差集：
   - **node 有、下游沒有** → 漏單，告警（Pull 模型下由下游拉回即可）。
   - **下游有、node 沒有** → **嚴重異常**（下游憑空入帳或我方資料遺失）。**僅告警，絕不自動處理。**
4. 結果寫入 `reconciliation_runs`，差異數 > 0 發 P1 告警。

**額外防線：** 每週抽樣，從區塊鏈瀏覽器或**第二家 RPC provider** 獨立驗證若干筆已確認交易。單靠自己跟自己對帳，無法發現**自己一開始就解析錯了**。
