# 程式碼風格（通用）

> 跨語言、單行程式碼層級的通用規範：格式、命名、語法偏好、Log、重構安全。
> 應用分層與設計模式見 [patterns.md](./patterns.md)。
> Java/Spring Boot 專屬細節（Lombok @Data、Optional、Java 8 Streams、套件命名、類別後綴）見 `skills/springboot-patterns/` §Java 8 編碼重點。

---

## 1. 格式化

- 使用語言官方 / 主流 formatter，並透過 `PostToolUse` hook 自動觸發
  - Java → 4 spaces 縮排（依專案 `.editorconfig` 或 IDE 設定）— hook 設定見 [`java-hooks.md`](./java-hooks.md)
- formatter 設定統一放 repo 根目錄（如 `.editorconfig`），不依賴個人 IDE

---

## 2. 命名

### 通用大小寫慣例

| 種類 | 大小寫 | 範例 |
|------|--------|------|
| 類別 / 型別 | PascalCase | `OrderService` |
| 方法 / 函式 / 變數 | camelCase | `fetchOrder` |
| 常數 | UPPER_SNAKE | `MAX_RETRY` |
| 套件 / 模組目錄 | 小寫 / kebab-case | `order-service` |

### 命名原則

- 名稱要說明「做什麼」而非「怎麼做」
- 布林變數用 `is*` / `has*` / `can*` 開頭
- 避免縮寫（除非為公認術語：URL、ID、HTTP）
- 一致使用單複數（集合用複數、單體用單數）

> 各語言/框架的後綴慣例（`Controller`、`Service`、`Impl`、`Dao`…）見對應 tech skill。

---

## 3. 語法偏好（語言中立）

- **不可變性優先**：能 `final` / `const` / `readonly` 就用，避免共享可變狀態
- **空值處理**：用語言提供的明確機制（`Optional` / `Option` / 非空型別），避免 `null` 散播
- **流程簡短**：高階函式 / Stream / pipeline 串接超過 3 步驟，改寫成迴圈或抽方法
- **例外不吞**：`catch` 至少要記錄上下文，重新拋出或明確降級
- **Magic number / string** 抽常數
- **短名規則**：新程式碼禁止 inline FQCN（`com.cx.framework.utils.CollectionUtils.isEmpty(...)`），先 `import` 再用短名；遇同名 class 衝突時，較少用的那個才用 FQCN 並加一行註解說明。既有 inline FQCN 不強制重構

---

## 4. 語言規範

### 程式碼註解 / Javadoc

lion 既有註解**簡體為主但混用繁體**（抽樣簡體專用字約 1412、繁體專用字約 774），沒有單一字體可統一。規則：

| 情境 | 用什麼字體 |
|------|-----------|
| 改既有檔案、新增註解 | 跟**所在檔案**既有註解的字體一致 |
| 新檔案 | 依同 package 多數檔案的字體 |
| 同一個檔案內 | **不混用**簡繁 |
| 既有註解 | **不為統一字體而改**（只改字體會製造無意義 diff 與 review 噪音） |

- 範圍含 `//`、`/* */`、`/** */` Javadoc、`@param`、`@return`
- 公認技術術語（API、HTTP、UUID）可保留英文

### Log 訊息語言

- 一律英文（多語環境下唯一可保證可讀的通用語）

### 等級使用

| 等級 | 用途 | 是否常用 |
|------|------|----------|
| `info` | 一般操作、業務里程碑 | ✅ 主流 |
| `error` | 錯誤、需追查的失敗 | ✅ 主流 |
| `warn` | 系統級告警（熔斷、降級、資源不足） | ⚠️ 限定使用 |
| `debug` / `trace` | 開發期診斷 | ❌ 上線禁用 |

> 各語言取得 logger 的方式（Lombok `@Slf4j`、`logging.getLogger`、`zerolog` 等）見對應 tech skill。

---

## 5. 移除 / 重構安全

移除變數、欄位、方法或修改簽名時，**必須搜尋所有引用點並一併修改**：

1. 移除欄位 → 搜尋 `getter` / `setter` / 屬性名所有引用
2. 修改方法簽名 → 搜尋所有呼叫處
3. 移除變數 → 確認 log、賦值、傳參都已清理
4. **每次修改後確認無編譯 / 型別錯誤**（IDE 診斷或 build 指令）

```text
# 錯誤情境（任何語言通用）
removed_var = ...           # 變數已刪除
log.info("value: " + removed_var)   # 仍引用 → 編譯錯誤

# 正確流程
1. Grep / Find Usages 找出所有引用
2. 逐一移除或替換
3. 跑 build / type-check 確認通過
```


---

## 6. 大檔案讀取策略（Token 預算硬規則）

單檔 > 500 行一次 full read 吃 ~3-5k token，sub-agent 重讀時 N 倍消耗。下列策略是合入前必查。

### 6.1 300 行門檻

- 檔案 **> 300 行禁用 full read**（`Read(file_path)` 不帶 `offset` / `limit`）
- 第一次接觸大檔案時：
  1. `grep -n "public \|private \|protected " <file>` 取得方法行號索引
  2. 在對話中保留「關鍵行號索引」摘要，例：
     ```
     XxxService.java 索引：
       methodA                L245-L310
       methodB                L380-L420
     ```
  3. 後續修改只讀需要的段落：`Read(file, offset=245, limit=66)`

### 6.2 為什麼重要

- Sub-agent 不繼承父 context，每次派 reviewer 同一個檔案被父/子 agent 各讀一次 → N 倍消耗
- 多 session 場景下（context 滿壓縮、後續 session 重啟），大檔案會被再讀一次
- 單檔超過 500 行時，full read 單次可吃掉 ~3-5k token，累積 5 次就是 15-25k token

### 6.3 配套工具

```bash
# 找方法索引
grep -n "^\s*\(public\|private\|protected\)\s" <file.java>

# 找段落的結束括號（配合 offset 讀完整函數）
awk '/methodA/{s=NR} s && /^    \}/{print s"-"NR; s=0}' <file.java>
```

### 6.4 例外

- 一律允許 full read 的檔案類型：
  - `pom.xml`、`application.yml`、`.properties`（結構性檔）
  - 測試 fixtures（為了對照預期）
  - 檔案本身 ≤ 300 行


---

## 7 BusinessException 拋錯規範（Java）

### 正確寫法

```java
throw new BusinessException(
    ErrorCodesEnum.UserService.MUST_AN_AGENT.code,
    ErrorCodesEnum.UserService.MUST_AN_AGENT.desc
);
```

`BusinessException` 只有兩個有效 constructor：
- `BusinessException(String msg)` — 單一 message 字串（無 code）
- `BusinessException(int code, String msg, Object... args)` — 數字 code + message

**禁止：**
- `new BusinessException("STRING_CODE", "message")` → `(String, String)` 不存在，**編譯錯誤**
- Magic number：`new BusinessException(1020, "该IP被限制注册")` → 不可維護，且 i18n 對不到 enum

### 新增 error code 標準流程

1. **登記 `ErrorCodesEnum`**（`lion-common` 的 `com.lc.common.constants.enums.ErrorCodesEnum`，跨 repo；見 `rules/patterns.md` §8 新開流程）

   在對應 inner enum（或新增一個）加常數，寫法對齊同 enum 既有常數（`code` / `desc` 欄位）。
   **code 編號**：先 grep 該 inner enum 與 `messages.properties` 既有 `errorCode.*`，取該 domain 號段內未使用的號碼；**撞號不會編譯錯，只會讓兩個錯誤共用同一則訊息**。

2. **補 i18n — 走 `scripts/i18n.py`**（禁止 Edit `.properties`；locale 與參數見 `rules/i18n.md`）：

   ```bash
   python3 scripts/i18n.py add backend errorCode.<code> --zh-CN "<訊息>" --zh-TW "..." --en "..." ...
   ```

3. **驗收**：`python3 scripts/i18n.py audit --scope backend` 無新增不對齊；`grep -c "errorCode.<code>=" cp-service/src/main/resources/i18n/messages*.properties` 每個 locale 檔都有。

---

## 8. 最小可行實作（反過度設計）

> 前面幾節管「**怎麼寫**」，這節管「**寫多少**」。`code-reviewer` 的「過度工程 — 是否加了不必要的抽象層、設計模式或額外功能？」就是在驗這條——不要等到 review 才被打回。
> **維護專案尤其重要**：這是一個 Java 8 / Boot 2.0 的既有多模組 repo，每多一層自創抽象，下一個人（和下一個 session 的 Claude）就多一段要理解的東西。

**原則：能解決問題的最少程式碼，不做任何投機性設計。**

- **不做 spec / plan 沒要求的功能**。plan §2 的檔案清單就是範圍上限。
- **只用一次的程式碼不要抽象**。介面、策略模式、抽象基類等到**第二個實作出現**時再抽。
- **不做沒人要求的「彈性」與「可設定化」**。要加開關前先問：這個開關現在有人要切嗎？
- **不為不可能發生的情境寫防禦**。金額 / 狀態機 / 併發等 L1 場景的**可預期**失敗仍要處理，兩者不衝突：本節管的是**不必處理的**。
- **對齊既有寫法優先於引入更好的寫法**。同模組已有同類寫法（`service/third*/`、`sms/impl/`、`@SingleWalletType`）就照抄，不要在這次 MR 順手引入新架構（要改 → 另開重構 MR）。

**寫完自問兩題（過不了就重寫）：**

1. 「這 200 行能不能是 50 行？」——能 → 重寫。
2. 「資深工程師會不會說這寫得太複雜？」——會 → 簡化。

> **與 §5 移除 / 重構安全的關係：** §5 管「**要動的時候怎麼安全地動**」，本節管「**該不該動**」。順序是先問本節再走 §5。

---

<!-- shared:no-emoji-in-code -->
## 程式碼與設定檔禁止 emoji

| 位置 | 可以用 emoji？ |
|---|---|
| 說明文件（`.md`、`.html`）、企劃書、規格、報告 | ✅ 可以 |
| 前端程式碼 | ✅ 可以 |
| **後端程式碼、腳本** | ❌ **禁止** |
| **程式註解**（任何語言） | ❌ **禁止** |
| **設定檔**（`.yml` / `.yaml` / `.json` / `.properties` / `.xml` / `.sql` / `.env` / `.toml` / `.ini`） | ❌ **禁止** |
| **Log 訊息、例外訊息、CLI 輸出**（寫在程式碼裡的字串） | ❌ **禁止** |

**為什麼：**

| 理由 | 具體會發生什麼 |
|---|---|
| **grep 找不到** | 用 emoji 當標記，別人不知道要搜什麼，鍵盤也打不出來 |
| **編碼會炸** | emoji 是 4 bytes 的 UTF-8。資料庫欄位定序、舊終端機、部分 log 收集器與建置工具會吐錯或顯示成亂碼 |
| **diff 噪音** | 不同編輯器與字型對 emoji 的寬度處理不一致，會產生看不出原因的行變更 |
| **機器要讀** | log 與設定檔是給程式解析的，不是給人看的裝飾 |

**替代寫法**：用文字前綴。`// TODO:`、`// WARNING:`、`// NOTE:`、`[ERROR]`、`[WARN]`、`log.warn("...")` —— 搜得到、打得出來、不會壞。

### 一個例外：emoji 是「資料」的時候

emoji 若是**要比對或要產生的文件內容**，那不是裝飾，是資料，**照留**：

```bash
grep -rl '⏳ 待決' "$PLAN_DIR"          # 對，這在比對 .md 裡的標記
echo "  ✗ $file"                        # 錯，這只是裝飾 → 改成 "  - $file"
```

判準：**把這個 emoji 換成文字，功能會不會壞？** 會壞 → 是資料，留著；不會壞 → 是裝飾，拿掉。
<!-- /shared -->
