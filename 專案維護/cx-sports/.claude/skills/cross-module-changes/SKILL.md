---
name: cross-module-changes
description: 跨模組連動修改 checklist。需求動到 ≥ 2 個模組、修改共享層、變更 enum、修改 VO/SO/BO 欄位、跨 backend/frontend i18n、DB schema 變更時使用。
origin: template
---

# 跨模組連動修改 checklist

> **啟用時機：** 同一 repo 內需求動到放射狀依賴點。不符合觸發條件不要啟用。
> **不重複：** 跨 repo → `skills/cross-repo-commit`；單模組 JSON 反序列化 → `rules/development-workflow.md` §Step 0。

## 觸發條件（符合任一）

- 變更動到 ≥ 2 個 Maven module
- 修改共享層（cx-sport-common / sport-framework）對外 API
- 新增 / 修改 / 移除 enum 值
- 修改 VO / SO / BO 欄位（命名 / 型別 / 註解）
- 新增 / 修改 i18n key（後端 + 前端）
- 修改 DB schema（Flyway migration）

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
grep -rn "switch.*XxxEnum\|XxxEnum\.\(VAL1\|VAL2\)" cx-sport-app-service/src/main/
grep -rn "XxxEnum\.valueOf\|XxxEnum\.fromCode" cx-sport-app-service/src/main/
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

### 1.4 i18n key

一律走 script，**禁止手動 Edit i18n 檔**（見 `rules/i18n.md`）。

- 後端新增 errorCode → 前端錯誤提示是否需同步
- 前端新增 key → 所有 locale 同時補

### 1.5 共享層（cx-sport-common / sport-framework）變更

```bash
grep -rln "<artifactId>cx-sport-common</artifactId>" */pom.xml
```

- 改 public API → spec §6 回答版本 bump 策略
- 下游 smoke test：依賴 module 跑 `mvn -pl <module> compile -o -q`

### 1.6 DB schema 變更

```bash
grep -rn "from <table>\|join <table>\|update <table>" cx-sport-app-service/src/main/resources/
```

- 新增欄位 → DAO / Mapper XML 同步補
- 改型別 → ShardingSphere 下隱式轉換是否正確
- 移除欄位 → 確認沒有 SELECT * + BeanUtils 反射的 silent dependency

### 1.7 共用組件 caller chain audit

**觸發條件**（符合任一）：
- 被 ≥ 2 個 caller 引用（Vue 子組件、Java service interface、common class）
- 改動可能改變 caller 契約：新增欄位、改 enum case、改 props、改 method 簽名

```bash
# Vue 共用子組件
grep -rln "<MyDetailComponent\|import.*MyDetailComponent" <frontend>/src/

# Java service interface / common class
grep -rln "MyService\b\|MyVO\b" cx-sport-app-service/ lib/cx-sport-common/

# 反射映射
grep -rln "MapUtils.mapToObject.*MyClass\|BeanUtils.copyProperties.*MyClass" --include="*.java"
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

- 跨 repo → `skills/cross-repo-commit`
- 單模組 JSON 反序列化 → `rules/development-workflow.md` §Step 0
- i18n → `rules/i18n.md`
- domain 索引 → `rules/modules.md`
