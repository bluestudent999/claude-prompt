# 升級工作流程（直接跳躍策略）

> 本文規範版本升級的生命週期。**升級 ≠ 開發**：成功定義是「版本到位 + 行為不變」，不是新增功能。
> 策略為**直接跳躍**——一次拉到目標版本，靠自動遷移 + 編譯收斂 + 回歸測試三道網收斂。

---

## 升級工單格式（使用者端）

下達升級需求時建議提供（缺欄位 Claude 補問）：
```
工單：UPGRADE-xxx
升級範圍：（哪個模組 / 整個 reactor）
來源版本：（Java? / Spring Boot?；不確定 Claude 會用 effective-pom 確認）
目標版本：（Java 21 / Spring Boot 3.x）
時程限制：（影響是否拆多個 MR）
特殊約束：（不可動的第三方對接 / 必須保留的行為）
```

---

## 升級生命週期（6 步）

### Step -1：Preflight — 雙 JDK 對齊 + 來源 baseline 綠燈

升級的「行為等價」需要一個**乾淨的對照基準**。動工前必須：

```bash
# 1. 來源 JDK 對齊，確認現況可編譯可測（升級前最後一次全綠）
export JAVA_HOME="$JAVA_HOME_SOURCE"   # 見 settings.local.json
java -version 2>&1 | grep "1\.8\." || { echo "[Preflight] 來源 JDK 未對齊"; exit 1; }
mvn -q clean test-compile                # 來源版本必須先綠

# 2. 確認目標 JDK 已安裝（升級時切換）
"$JAVA_HOME_TARGET/bin/java" -version

# 3. 記錄 baseline：跑一次來源版本的回歸測試套件，存基準結果
mvn -q test > upgrade/baseline-test-result.txt 2>&1 || echo "baseline 有紅燈，先確認是否升級前既有問題"
```

**硬規則：**
- 來源 baseline **必須先綠**——帶病升級，後面分不清紅燈是升級造成還是原本就壞。
- baseline 測試結果存檔，作為 Step 4 行為等價的對照。
- 若來源 baseline 本就有紅燈 → 列 OQ 問使用者「是否升級前先修 / 視為已知並排除」。

---

### Step 0：盤點升級面（`/upgrade-inventory`）

直接跳躍前必須知道「會炸哪裡」。用 `upgrade-inventory` skill 產出 `upgrade/inventory.md`，至少涵蓋：

1. **javax 使用面**：`grep -rn "import javax\." --include=*.java`，分類「Jakarta EE（需遷移）」vs「Java SE 保留（不動）」——白名單見 `jakarta-migration.md`。
2. **棄用 / 移除 API**：`@Deprecated(forRemoval=true)`、`WebSecurityConfigurerAdapter`、`javax.persistence` 等。
3. **依賴版本現況**：`mvn dependency:tree`，標出 §version-matrix 第 3 表的高風險依賴現況版本。
4. **設定屬性面**：`application*.yml` / `bootstrap.yml` / `.properties` 中 Boot 3 已改名/移除的屬性。
5. **springfox / 不相容庫**：標出需「換庫」而非「升版」的項目。
6. **JVM 參數 / GC 設定**：啟動腳本、Dockerfile 的 `-XX` 參數（CMS 等已移除項）。

> 盤點走 `upgrade-sweep` workflow（多模組平行掃描）效率更高，見 `.claude/workflows/upgrade-sweep.js`。

---

### Step 1：升級計畫（`upgrade-planner`）

`upgrade-planner` agent 依盤點結果產出 `upgrade/task-xxx-plan.md`。**plan 必含章節：**

| 章節 | 內容 |
|------|------|
| § 0 Meta | 升級範圍、來源/目標版本、風險層（見 `agents.md`） |
| § 1 版本鎖定確認表 | 見 `version-matrix.md §5`（現況證據 + 目標查證來源） |
| § 2 階段拆分 | 見下方「直接跳躍的階段順序」 |
| § 3 自動遷移計畫 | 要跑哪些 OpenRewrite recipe、預期覆蓋哪些盤點項 |
| § 4 編譯收斂預估 | recipe 不覆蓋、需人工修的清單（springfox 換 springdoc 等） |
| § 5 回歸驗證計畫 | 對照 baseline、哪些行為等價點要重點驗（見 `verification.md`） |
| § 6 風險點 | 已知行為差異（Hibernate 6 HQL、Security 6 預設變更…） |
| § 7 Open Questions | 留給使用者決議（目標版本、不相容庫的替代選型） |
| § 8 Success Criteria | 合入前自檢清單 |

**直接跳躍的階段順序（§2 模板）：**

```
Phase A  依賴/BOM 對齊   — 升 parent、Spring Cloud train、第三方相容版本（先動 pom，必然編譯紅）
Phase B  自動遷移        — OpenRewrite：java.migrate + spring.boot3 + jakarta recipe（Step 2）
Phase C  設定遷移        — config-migrator：yml/properties Boot 3 屬性（Step 2 並行）
Phase D  編譯收斂        — build-error-resolver 修 recipe 未覆蓋的編譯錯誤（Step 3）
Phase E  回歸驗證        — 跑測試對照 baseline，regression-reviewer 審行為等價（Step 4）
```

**OQ 硬規則：** 目標版本、不相容庫替代選型（springfox→springdoc）、不可動的第三方對接行為——這些**必列 OQ**，未決議禁止進 Phase A。

---

### Step 2：自動遷移優先（`/rewrite-run`）

**升級期最重要的效率與正確性槓桿。** 詳見 `openrewrite.md`。

- 切換到**目標 JDK**：`export JAVA_HOME="$JAVA_HOME_TARGET"`。
- 先升 pom（Phase A），再跑 recipe：`org.openrewrite.java.spring.boot3.UpgradeSpringBoot_3_x` + `org.openrewrite.java.migrate.UpgradeToJava21`。
- **硬規則：先 `dryRun` 審 diff，再 `run`。** recipe 改動量大，盲跑會把行為改動和機械遷移混在一起，難以審查。
- recipe 跑完先 commit（`chore: openrewrite 自動遷移`），與後續人工修復分開——出問題可二分。

---

### Step 3：編譯收斂（`build-error-resolver`）

直接跳躍 + recipe 後仍會有大量編譯錯誤（recipe 覆蓋不到的、需換庫的、簽名變更的）。

- `mvn -pl <module> -am clean compile 2>&1` 收集全部錯誤，交 `build-error-resolver` **分類**（namespace / 移除 API / 簽名變更 / 換庫）後最小修復。
- **硬規則：** 只做「讓它編得過且行為相同」的最小改動，**禁止**夾帶重構（見 `CLAUDE.md §2`）。
- 收斂順序：先 `dependency-analyzer` 解依賴缺失/衝突 → 再修 source 編譯錯誤（依賴沒對齊時 IDE/編譯訊號會誤導）。

---

### Step 4：回歸驗證（行為等價）

升級沒有「新功能測試」，只有「行為等價驗證」。詳見 `verification.md`。

- 切目標 JDK，跑該模組回歸測試套件，**對照 Step -1 的 baseline**：理想是「baseline 綠的，升級後仍綠」。
- 新紅燈逐一判定：是**升級造成的行為差異**（必修或記錄）還是**測試本身依賴舊版行為**（改測試，但要說明為何安全）。
- `regression-reviewer` 審 diff 的行為等價性，重點看 `breaking-changes.md` 列的高風險點（Security 6 預設、Hibernate 6 HQL、時間/序列化行為）。
- CI 若 `-Dmaven.test.skip=true`（如部分 Jenkins pipeline）→ **本地手動跑回歸**，不能把測試 skip 當綠燈。

---

### Step 5：提交與 MR

- 詳見 `git-workflow.md`。
- **commit 粒度：一個 Phase 一個 commit**（依賴對齊 / recipe 自動遷移 / 編譯收斂 / 設定遷移分開），方便 review 與二分回溯。
- MR 描述必含：**版本前後對照表**、**行為差異記錄**（哪些行為變了、為何可接受）、**回歸測試證據**（對照 baseline）。
- commit 前確認 `upgrade/*-plan.md` 無「⏳ 待決」OQ（hook 攔截）。

---

## 操作原則（升級期硬規則）

### JDK 切換
- 來源 baseline 用 `JAVA_HOME_SOURCE`；升級動工後用 `JAVA_HOME_TARGET`。每個 session 開工先確認 `java -version` 指向預期版本。

### 工具失敗重試上限
- 同一工具同參數失敗 ≥ 2 次 → 換工具。典型：`Edit` 改大批量 namespace 失敗 → 改用 OpenRewrite recipe（這正是 recipe 的用途，不要手刻硬幹）。

### 大檔案讀取策略
- 檔案 > 300 行禁 full read（`pom.xml` / `application.yml` 例外）。先 grep 定位再分段讀。詳見 `coding-style.md`。

### 平行化與子 Agent
- 獨立 tool call 同一則訊息平行啟動。多模組盤點用 `upgrade-sweep` workflow。子 Agent briefing 必須自包含（plan 路徑 + diff 片段 + 規範摘要），詳見 `agents.md`。
