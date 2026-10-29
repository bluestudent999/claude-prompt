---
name: cross-module-changes
description: 跨模組連動修改 checklist。需求動到 ≥ 2 個模組、修改共享層、變更 enum、修改 VO/SO/BO 欄位、跨 backend/frontend i18n、DB schema 變更時使用。
origin: template
---

# 跨模組連動修改 checklist

> **啟用時機：** 需求動到放射狀依賴點。不符合觸發條件不要啟用。
> **不重複：** 提交 / MR / 發版順序 → `skills/cross-repo-commit/SKILL.md`；單模組 JSON 反序列化 → `rules/development-workflow.md` §Step 0。
> **lion 特性：** 共享層 `lion-common` / `framework_v3` 是**另外的 repo**（sibling，與 lion-service 的 clone 放在同一層目錄），多數 SO / VO / BO / DAO / Cache / 列舉都在 lion-common —— 「跨模組」在 lion 常常同時是「跨 repo」。grep 時本 repo 與 sibling 都要查。

## 觸發條件（符合任一）

- 變更動到 ≥ 2 個 Maven module（`cp-service` / `single-wallet-service` / `collector-service` / `upload-service`）
- 修改共享層（lion-common / framework_v3）對外 API
- 新增 / 修改 / 移除 enum 值
- 修改 VO / SO / BO 欄位（命名 / 型別 / 註解）
- 新增 / 修改 i18n key（後端 + 前端）
- 修改 DB schema（cp-flyway migration / changelog SQL）
- 修改 Kafka Event（Spring Cloud Stream，cp-service `event/`）或 `controller/internal/` 介面（其他服務直接呼叫）

---

## 1. 連動類別 + grep pattern

### 1.1 JSON 欄位（DB text / json 欄位）

跨模組時寫入端與讀取端的 BO **常不是同一個類別**，必須兩端同步。

```bash
# 本 repo 與 lion-common 都要查（在 lion-service 根目錄執行；lion-common 為 sibling repo）
grep -rn "JsonUtil.toList.*XxxBO.class\|JsonUtil.toObject.*XxxBO.class" --include="*.java" . ../lion-common
grep -rn "TypeReference<.*XxxBO\|TypeReference<.*XxxVO" --include="*.java" . ../lion-common
grep -rn "parseObject(.*XxxBO\|parseArray(.*XxxBO" --include="*.java" . ../lion-common
```

### 1.2 enum 值變動

```bash
grep -rn "switch.*XxxEnum\|XxxEnum\.\(VAL1\|VAL2\)" --include="*.java" */src/main/ ../lion-common/src/main/
grep -rn "XxxEnum\.valueOf\|XxxEnum\.fromCode" --include="*.java" */src/main/ ../lion-common/src/main/
```

- 列出每個分派點，新值是否需對應分支
- `default` fallback 對新值是否合理
- 移除 enum：DB 歷史資料如何處理
- **`EnumClass.TranType`（lion-common）新增值**：single-wallet 用 `@SingleWalletType` 註冊到 `EnumMap`，新值要有對應 service；流水 / 報表依 TranType 分類的地方逐一確認（`single-wallet-service/CLAUDE.md`）
- 列舉值也可能被前端或 lion-manage 寫死 → 列跨 repo 影響清單

### 1.3 VO / SO / BO 欄位變更

```bash
grep -rn "new XxxVO\|XxxVO\.builder" --include="*.java" . ../lion-common
grep -rn "BeanUtils.copyProperties.*XxxVO\|MapUtils.mapToObject.*XxxVO" --include="*.java" . ../lion-common
```

- 改欄位名 → 同名 VO / SO / BO 必須一起改
- 改型別 → BeanUtils 反射複製可能 silent fail
- 加 `@JsonInclude(NON_NULL)` → 影響輸入輸出兩端
- SO 新增 `platformId` 欄位 → 只能拿來比對或被覆寫，不得當授權依據（`rules/platform-isolation.md`）
- VO 在 lion-common → 回應結構改變影響前端 / lion-manage，列跨 repo 影響清單

### 1.4 i18n key

後端（cp-service `messages*.properties`）一律走 `scripts/i18n.py`，**禁止手動 Edit i18n 檔**（見 `rules/i18n.md`）。

- 後端新增 errorCode → `ErrorCodesEnum` 在 lion-common（跨 repo），前端錯誤提示是否需同步
- 前端 key 在 lion-frontend / lion-manage（跨 repo）→ 只列清單，本範本不改前端

### 1.5 共享層（lion-common / framework_v3）變更

```bash
# 哪些模組引用（本 repo）
grep -rln "<artifactId>common</artifactId>\|<artifactId>framework</artifactId>" */pom.xml pom.xml
# 改動的類在本 repo 的使用點
grep -rln "XxxClass\b" --include="*.java" */src/main/
```

- 改 public API → spec §6 回答版本策略（lion 既有做法是同版號覆蓋，見 `skills/spec-review/SKILL.md`）
- 下游 compile：lion-common 本機 install 後，依賴 module 跑 `mvn -pl <module> compile -o -q`
- lion-common 也被其他 repo 引用（例：lion-core、lion-manage）→ 實際清單問使用者（`skills/cross-repo-commit/SKILL.md` Phase 4）

### 1.6 DB schema 變更

lion **沒有 mapper XML**：SQL 寫在 Java（framework_v3 `SqlUtil` / 字串），欄位對應在 model 類（多在 lion-common）。

```bash
grep -rni "from <table>\|join <table>\|update <table>\|into <table>" --include="*.java" */src/main/ ../lion-common/src/main/
grep -rn "<column_name>" --include="*.java" */src/main/ ../lion-common/src/main/
# 兩條 SQL 軌都查
grep -rln "<table>" cp-flyway/src/main/resources/db/migrations/general/ zz_document/script/changelog/
```

- 新增欄位 → model（lion-common）與用到的 DAO 查詢同步補
- 改型別 → ShardingSphere 下隱式轉換是否正確；`user_money` 是分庫表（`skills/mysql-patterns/SKILL.md` §2）
- 移除欄位 → 確認沒有 `buildSelect()` 全欄位 + 反射映射的 silent dependency
- migration 寫哪一軌依 `rules/flyway-migration.md`，**不得自行判定**

### 1.7 共用組件 caller chain audit

**觸發條件**（符合任一）：
- 被 ≥ 2 個 caller 引用（Java service interface、lion-common class、`controller/internal/` 介面、Kafka Event）
- 改動可能改變 caller 契約：新增欄位、改 enum case、改 props、改 method 簽名

```bash
# Java service interface / common class（本 repo + lion-common）
grep -rln "MyService\b\|MyVO\b" --include="*.java" */src/main/ ../lion-common/src/main/

# controller/internal/ 介面：被其他服務直接 HTTP 呼叫
grep -rn "RestTemplate\|@FeignClient" --include="*.java" */src/main/ | grep -i "<path 片段>"

# 反射映射
grep -rln "MapUtils.mapToObject.*MyClass\|BeanUtils.copyProperties.*MyClass" --include="*.java"
```

caller ≥ 3 → 高耦合，必執行：
1. 列所有 caller 路徑
2. 每個 caller 傳什麼 props / data、預期什麼行為
3. 不同 caller 行為不同 → 改動必須 **cover 並集**
4. 記錄於 plan §1 Investigation
5. caller 在前端 / 其他 repo（看不到原始碼）→ 列跨 repo 影響清單，標「未驗證」，不宣稱已涵蓋

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

- 跨 repo 提交 / 發版順序 → `skills/cross-repo-commit/SKILL.md`
- 單模組 JSON 反序列化 → `rules/development-workflow.md` §Step 0
- i18n → `rules/i18n.md`
- domain 索引 → `rules/modules.md`
