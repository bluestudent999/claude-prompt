# 升級期程式碼風格

> 升級期的風格規範與一般開發不同：**行為等價優先，最小改動**。本檔規範升級時可改/不可改的範圍、新特性採用界線、大檔讀取策略。

---

## 1. 升級期的最小改動原則

- 升級 commit 只做「讓它在新版本以**相同行為**運作」的改動：namespace 遷移、API 改名、設定遷移、依賴對齊、編譯修復。
- **禁止夾帶**：邏輯重構、命名美化、抽方法、效能調優、補註解、格式化整檔。要做 → 另開非升級 MR。
- 理由：升級 MR 一旦混入重構，review 無法區分「機械遷移」與「行為改動」，回歸出問題也無法二分。

---

## 2. 新特性採用界線（Java 17/21）

升級到新 JDK **不代表**要立刻改寫成新語法。

| 情境 | 是否採用新特性 |
|------|--------------|
| 為修 breaking change 必須改（如 `finalize` → `Cleaner`） | ✅ 用必要的最小新寫法 |
| OpenRewrite recipe 順帶現代化（如 `var`、diamond） | ✅ 接受 recipe 的一致改動，審 diff 確認無行為差異 |
| 既有可運作的程式碼，純為「用上 record/sealed/switch pattern」 | ❌ 升級期不主動改寫（另開重構 MR） |
| 新寫的修復程式碼 | 可用目標版本特性，但以可讀、與周邊一致為準 |

> 原則：**升級讓你「能用」新特性，但升級本身不是「改用」新特性的時機。**

---

## 3. 命名與格式

- 沿用專案既有 `.editorconfig` / formatter，**不在升級 commit 重新格式化未動到的程式碼**（formatter 全檔重排會淹沒真正的遷移 diff）。
- 命名、縮排等沿用原專案慣例——升級不是統一風格的時機。

---

## 4. Log 與註解

- **不為升級新增大量註解或 log**。遷移點若需說明，用一行精簡註解標明「升級遷移：javax→jakarta」即可。
- 既有 log 訊息不動（除非 API 簽名變更被迫改）。

---

## 5. 大檔案讀取策略（Token 預算硬規則）

升級會碰大量檔案，token 控制尤其重要。

- **檔案 > 300 行禁 full read**（不帶 offset/limit 的 Read）。
  1. 先 `grep -n "import javax\.\|@Deprecated\|WebSecurityConfigurerAdapter" <file>` 定位升級相關行。
  2. 對話保留簡短行號索引。
  3. `Read(offset, limit)` 只讀需要的段落。
- **例外**（允許 full read）：`pom.xml`、`application*.yml`、`.properties`、`*.factories`、測試 fixtures、≤ 300 行的檔。
- **批量遷移不用逐檔 Read**：jakarta / 屬性遷移走 OpenRewrite recipe + diff 審查，不要為了改 import 把整個檔案讀進 context（這正是 recipe 存在的理由）。

---

## 6. 升級遷移點的標註慣例（可選）

若某處遷移有非顯而易見的決策（例如保留某個 `javax.*` 是因為它是 Java SE 白名單），加一行註解避免後續誤改：

```java
// 升級保留：javax.crypto 屬 Java SE，非 Jakarta EE，不遷 jakarta（見 .claude/rules/jakarta-migration.md）
import javax.crypto.Cipher;
```

> 一般機械遷移點**不需**註解（diff 自明）。只在「容易被後人誤判而改錯」處標註。
