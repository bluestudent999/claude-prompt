# 程式碼風格與規範

> 本文規範 SDRP 專案的代碼風格、命名習慣、Java 21 編寫實踐、註解語言、Log 等級，以及 Context 節省硬性規則。

---

## 1. 格式與命名

- **縮排**：使用 4 個空白縮排，遵循專案 `.editorconfig` 規範。
- **命名規範**：
  - 類別、介面、Record：`PascalCase`（如 `ConfidenceEvaluator`、`EntityResolved`）。
  - 方法、變數、參數：`camelCase`（如 `calculateScore`、`matchCount`）。
  - 常數：`UPPER_SNAKE_CASE`（如 `MAX_MATCH_LIMIT`）。
  - 模組與 package 命名：小寫，不可帶底線或連字號（如 `com.sdrp.alignment.domain`）。

---

## 2. Java 21 & Spring Boot 3 特性實踐

- **不可變性優先**：
  - 值物件（Value Object）或 DTO 優先使用 Java **`record`**。
  - Domain Entity 成員變數優先使用 `final`，防範意外副作用。
- **Lombok 使用守則**：
  - 在 L2 Domain 層**禁用** `@Data`，避免破壞封裝與 Aggregate 一致性。
  - 優先使用 `@Value`（不可變物件）、`@Builder`、`@Getter` 與 `@RequiredArgsConstructor`。
- **Java 21 語法偏好**：
  - 善用 Switch 模式匹配 (Pattern Matching) 與 Record 模式 (Record Patterns)。
  - 對於多型與受限繼承，使用 `sealed class / interface` 明確限制其實作子類。
  - 優先使用 `var` 宣告局部變數（在型別顯而易見時）。

---

## 3. 語言與註解規範

- **Javadoc 與代碼註解**：一律使用**繁體中文**（除了專有名詞如 API, CPU, UUID 等外，說明與注釋均用繁中）。
- **Log 訊息**：一律使用**英文**，以便於日誌搜集與標準化解析。
- **Log 等級使用**：
  - `info`：用於關鍵業務節點與狀態轉換（如：`Entity alignment finished, confidence: {}`）。
  - `error`：用於系統異常、阻礙當前操作的錯誤，必須帶 stack trace。
  - `warn`：用於非預期但系統可自我修復、降級或容錯的警告。
  - `debug`：開發調試用，嚴禁在正式環境輸出過多冗餘。

---

## 4. 大檔案讀取策略（Context 節省硬規則）

當單個代碼檔超過 300 行時，一次性 Full Read 會耗費大量 Token。

- **硬規則**：檔案 **> 300 行禁止 Full Read**（不帶 parameters 的 view_file）。
- **流程**：
  1. 使用 `grep` 搜尋關鍵方法行號。
  2. 在對話中記錄簡短的行號索引。
  3. 使用 `view_file` 指定 `StartLine` 與 `EndLine` 只讀取特定方法區段。
- **例外**：`pom.xml`、`application.yml`、測試資料檔案不受 300 行 Full Read 限制。

---

## 5. 業務異常拋出規範

- 專案統一使用 `BusinessException` 或其子類別拋出業務錯誤。
- **禁止**拋出無意義的通用 `RuntimeException`。
- 所有的 BusinessException 拋出時必須帶有清晰的 Error Code 與英文描述，並在 L4 Interfaces 層被 `@ControllerAdvice` 統一捕獲與轉換，嚴禁向外暴露 stack trace。
- 新增 Error Code 時，必須同步在 `i18n/messages*.properties` 中添加對應的多語系（包含繁體中文、英文等）。

---

## 6. 最小可行實作（反過度設計）

> 前面幾節管「**怎麼寫**」，這節管「**寫多少**」。`code-reviewer` 的「過度工程」檢查項就是在驗這條——不要等到 review 才被打回。

**原則：能解決問題的最少程式碼，不做任何投機性設計。**

- **不做計畫沒要求的功能**（呼應 `development-workflow.md` Step 3 Golden Rule）。
- **只用一次的程式碼不要抽象**。介面、策略模式、抽象基類等到**第二個實作出現**時再抽。
- **不做沒人要求的「彈性」與「可設定化」**。把值提成常數 ≠ 要做一整套設定框架。
- **不為不可能發生的情境寫防禦**。可預期的業務失敗仍須依 §5 包裝為 `BusinessException`，兩者不衝突：§5 管**該處理的**，本節管**不必處理的**。
- **不預先為未來需求鋪路**。Plan 沒寫的擴充點就是不做。

**寫完自問兩題（過不了就重寫）：**

1. 「這 200 行能不能是 50 行？」——能 → 重寫。
2. 「資深工程師會不會說這寫得太複雜？」——會 → 簡化。

> **與 Modulith 分層的界線：** 分層（domain / application / infrastructure / interfaces）與 Port/Adapter 是**架構規定**，不算投機抽象，照做。本節針對的是**分層之內**自行增生的抽象。
