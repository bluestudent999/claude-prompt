---
name: cross-module-changes
description: 跨模組連動修改 checklist。需求動到 ≥ 2 個模組（service / flyway / frontend）、修改跨模組共享程式碼、變更 enum、修改共享資料物件（VO/SO/BO）欄位、變更前端 i18n、DB schema（Flyway migration）變更時使用。
origin: template
---

# 跨模組連動修改 checklist

> **啟用時機：** crypto-payment 為 Maven 多模組**單一 repo**（`crypto-payment-service` / `crypto-payment-flyway` / `front/crypto-payment-admin-frontend`），需求動到放射狀依賴點時使用。不符合觸發條件不要啟用。
> **不重複：** 單模組 JSON 反序列化 → `rules/development-workflow.md` §Step 0。

## 觸發條件（符合任一）

- 變更同時動到 ≥ 2 個模組（例：`crypto-payment-flyway` migration + `crypto-payment-service` repository/service + `front/crypto-payment-admin-frontend`）
- 修改跨模組共享程式碼（多個 service 子模組共用的 utils / event / cache）對外 API
- 新增 / 修改 / 移除 enum 值
- 修改共享資料物件（VO / SO / BO）欄位（命名 / 型別 / 註解）
- 新增 / 修改前端 i18n key
- 修改 DB schema（走 `crypto-payment-flyway` 新增版號 migration）

---

## 1. 連動類別 + grep pattern

### 1.1 JSON 欄位（DB text / json 欄位）

跨模組時寫入端與讀取端的 BO **常不是同一個類別**，必須兩端同步。

```bash
grep -rn "JsonUtil.toList.*XxxBO.class\|JsonUtil.toObject.*XxxBO.class" .
grep -rn "TypeReference<.*XxxBO\|TypeReference<.*XxxVO" .
grep -rn "parseObject(.*XxxBO\|parseArray(.*XxxBO" .
```

### 1.2 enum 值變動

```bash
grep -rn "switch.*XxxEnum\|XxxEnum\.\(VAL1\|VAL2\)" crypto-payment-service/src/main/
grep -rn "XxxEnum\.valueOf\|XxxEnum\.fromCode" crypto-payment-service/src/main/
```

- 列出每個分派點，新值是否需對應分支
- `default` fallback 對新值是否合理
- 移除 enum：DB 歷史資料如何處理

### 1.3 VO / SO / BO 欄位變更

```bash
grep -rn "new XxxVO\|XxxVO\.builder" .
grep -rn "BeanUtils.copyProperties.*XxxVO\|MapStruct.*XxxVO" .
```

- 改欄位名 → 同名 VO / SO / BO 必須一起改
- 改型別 → BeanUtils 反射複製可能 silent fail
- 加 `@JsonInclude(NON_NULL)` → 影響輸入輸出兩端

### 1.4 前端 i18n key

- 新增 key → 所有 locale 同時補（依 `front/crypto-payment-admin-frontend/src/i18n/` 實際語系）
- 後端錯誤訊息（英文）與前端提示分離：後端 log 用英文，使用者可見文字走前端 i18n

### 1.5 跨模組共享程式碼變更

多個 service 子模組共用的 utils / event / cache 若改對外 API，須找出所有呼叫端：

```bash
grep -rln "SharedUtil\b\|SharedEvent\b\|SharedCache\b" crypto-payment-service/src/main/
```

- 改 public API → spec §6 列出受影響的 service / controller / job，逐一確認契約相容
- smoke test：`mvn -pl crypto-payment-service compile -o -q`

### 1.6 DB schema 變更（走 crypto-payment-flyway）

```bash
grep -rn "from <table>\|join <table>\|update <table>" crypto-payment-service/src/main/
```

- 新增欄位 → repository / POJO 同步補；migration 一律**新增版號檔**（例 `V1_0_3__xxx.sql`），**禁改既有 migration**
- 改型別 → ShardingSphere 5.4 下隱式轉換是否正確
- 移除欄位 → 確認沒有 SELECT * + BeanUtils 反射的 silent dependency
- 多租戶：新查詢是否都以 `platform_id` 過濾（跨平台存取 = critical bug）

### 1.7 共用組件 caller chain audit

**觸發條件**（符合任一）：
- 被 ≥ 2 個 caller 引用（Vue 子組件、Java service interface、common class）
- 改動可能改變 caller 契約：新增欄位、改 enum case、改 props、改 method 簽名

```bash
# Vue 共用子組件
grep -rln "<MyDetailComponent\|import.*MyDetailComponent" front/crypto-payment-admin-frontend/src/

# Java service interface / 共用 class
grep -rln "MyService\b\|MyVO\b" crypto-payment-service/

# 反射映射
grep -rln "BeanUtils.copyProperties.*MyClass\|ObjectMapper.*MyClass" --include="*.java"
```

caller ≥ 3 → 高耦合，必執行：
1. 列所有 caller 路徑
2. 每個 caller 傳什麼 props / data、預期什麼行為
3. 不同 caller 行為不同 → 改動必須 **cover 並集**
4. 記錄於 plan §1 Investigation

---

## 2. planner 使用方式

plan §1 Investigation 加「連動點清單」：每列填類別 / 連動點 / 動作 / 已驗證（grep 結論一句話）。

連動點 ≥ 3 → §6 Sequencing 拆 commit。

---

## 3. reviewer 對照

| 對照項 | 處置 |
|--------|------|
| plan 列 N 個連動點，diff 只動 < N 個 | **block** — 連動點漏改 |
| plan 沒列連動點，diff 有跨模組改動 | **block** — plan 遺漏分析 |
| 連動點完整、diff 對應 | approve |

---

## 4. 相關

- 單模組 JSON 反序列化 → `rules/development-workflow.md` §Step 0
- domain 索引 → `rules/modules.md`
