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

---

## 4. 語言規範

### 程式碼註解 / Javadoc / 說明文字

- **一律使用简体中文**（包含 `//`、`/* */`、`/** */` Javadoc、`@param`、`@return`、`@see`）
- 禁止繁體中文、英文（除非是公認技術術語如 API、HTTP、UUID）

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
     PlatformSettleReportV2Service.java 索引：
       calThirdOrderFee       L245-L310
       calculateTotal         L380-L420
       handleThirdFeeDetail   L510-L560
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

# 找 Vue 檔案的 data / methods 區塊
grep -n "^\s*\(data\|methods\|computed\|watch\)" <file.vue>

# 找段落的結束括號（配合 offset 讀完整函數）
awk '/calThirdOrderFee/{s=NR} s && /^    \}/{print s"-"NR; s=0}' <file.java>
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
    ErrorCodesEnum.Quest.INVALID_MATCH.code,
    ErrorCodesEnum.Quest.INVALID_MATCH.desc
);
```

`BusinessException` 只有兩個有效 constructor：
- `BusinessException(String msg)` — 單一 message 字串（無 code）
- `BusinessException(int code, String msg, Object... args)` — 數字 code + message

**禁止：**
- `new BusinessException("STRING_CODE", "message")` → `(String, String)` 不存在，**編譯錯誤**
- Magic number：`new BusinessException(9101, "赛事不在活动范围内")` → 不可維護

### 新增 error code 標準流程

1. **登記 `ErrorCodesEnum`**（`cx-sport-app-service/.../constants/enums/ErrorCodesEnum.java`）

   在對應 inner enum（或新增一個）加常數：

   ```java
   @Getter
   @AllArgsConstructor
   public enum Quest implements BusinessError {
       INVALID_MATCH(9101, "赛事不在活动范围内"),
       ;
       public final Integer code;
       public final String desc;
   }
   ```

   code 編號規則：接既有最大值往後取（現況末段 Tournament 用到 9023，Quest 從 9101 起）。

2. **補 i18n — 所有語系必填**

   後端 i18n 走 `cx-sport-app-service/src/main/resources/i18n/messages*.properties`，key 慣例 `errorCode.<code>`。**禁止 Edit 工具直接改 `.properties`（Unicode escape 會壞），用 python3 安全追加**。

   **格式規則：** 緊接在前一個 `errorCode` 後面，不加空行，code 數字由小到大排列。

   ```bash
   python3 - <<'EOF'
   import os, re

   key = "errorCode.9101"
   values = {
       "messages.properties":        "赛事不在活动范围内",
       "messages_zh.properties":     "赛事不在活动范围内",
       "messages_zh-HK.properties":  "賽事不在活動範圍內",
       "messages_en.properties":     "Match is not in the event range",
       "messages_br.properties":     "Match is not in the event range",
       "messages_vi.properties":     "Trận đấu không nằm trong phạm vi sự kiện",
       "messages_ko.properties":     "경기가 이벤트 범위 내에 없습니다",
       "messages_ja.properties":     "試合はイベント範囲内にありません",
       "messages_th.properties":     "การแข่งขันไม่อยู่ในช่วงกิจกรรม",
       "messages_ms.properties":     "Perlawanan tidak dalam julat acara",
       "messages_id.properties":     "Pertandingan tidak dalam rentang acara",
       "messages_bn.properties":     "ম্যাচটি ইভেন্টের পরিসীমার মধ্যে নেই",
       "messages_tl.properties":     "Ang laro ay wala sa saklaw ng kaganapan",
   }
   base = "cx-sport-app-service/src/main/resources/i18n"
   line = f"{key}={values['messages.properties'].encode('unicode_escape').decode('ascii')}"

   for fname, val in values.items():
       path = os.path.join(base, fname)
       escaped = val.encode("unicode_escape").decode("ascii")
       new_line = f"{key}={escaped}"
       # binary 讀取避免 codec 問題
       with open(path, "rb") as f:
           content = f.read()
       if key.encode() in content:
           print(f"[skip] {fname}")
           continue
       # 緊接在最後一個 errorCode 行後插入（不加空行）
       lines = content.decode("latin-1").splitlines(keepends=True)
       insert_at = len(lines)
       for i, l in enumerate(lines):
           if re.match(r"errorCode\.\d+\s*=", l):
               insert_at = i + 1  # 持續往後推，最終停在最後一個 errorCode 之後
       lines.insert(insert_at, new_line + "\n")
       with open(path, "wb") as f:
           f.write("".join(lines).encode("latin-1"))
       print(f"[ok]   {fname}  →  {new_line}")
   EOF
   ```

   > 非 ASCII 字元（中文、韓文、泰文…）必須 encode 成 `\uXXXX` Unicode escape，`encode("unicode_escape").decode("ascii")` 已處理；英文 / 拉丁字母不需要。
   > 部分 `.properties` 檔案非 UTF-8，腳本統一用 `latin-1` 讀寫（properties 格式規範允許）。

3. **驗收**：`grep "errorCode.9101" cx-sport-app-service/src/main/resources/i18n/messages*.properties`，確認所有語系都有。

---

## 8. 最小可行實作（反過度設計）

> 前面幾節管「**怎麼寫**」，這節管「**寫多少**」。`code-reviewer` 的「過度工程 — 是否加了不必要的抽象層、設計模式或額外功能？」就是在驗這條——不要等到 review 才被打回。
> **維護專案尤其重要**：這是一個 Java 8 / Boot 2 的既有 monorepo，每多一層自創抽象，下一個人（和下一個 session 的 Claude）就多一段要理解的東西。

**原則：能解決問題的最少程式碼，不做任何投機性設計。**

- **不做 spec / plan 沒要求的功能**。plan §2 的檔案清單就是範圍上限。
- **只用一次的程式碼不要抽象**。介面、策略模式、抽象基類等到**第二個實作出現**時再抽。
- **不做沒人要求的「彈性」與「可設定化」**。要加開關前先問：這個開關現在有人要切嗎？
- **不為不可能發生的情境寫防禦**。金額 / 狀態機 / 併發等 L1 場景的**可預期**失敗仍要處理，兩者不衝突：本節管的是**不必處理的**。
- **對齊既有寫法優先於引入更好的寫法**。庫內已有 `connector/impl/` 模式就照抄，不要在這次 MR 順手引入新架構（要改 → 另開重構 MR）。

**寫完自問兩題（過不了就重寫）：**

1. 「這 200 行能不能是 50 行？」——能 → 重寫。
2. 「資深工程師會不會說這寫得太複雜？」——會 → 簡化。

> **與 §5 移除 / 重構安全的關係：** §5 管「**要動的時候怎麼安全地動**」，本節管「**該不該動**」。順序是先問本節再走 §5。