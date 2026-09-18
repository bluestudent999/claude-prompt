# 程式碼風格（crypto-payment）

> 跨語言、單行程式碼層級的通用規範：格式、命名、語法偏好、Log、重構安全、大檔讀取。
> 應用分層與設計模式見 [patterns.md](./patterns.md)；金額 / 私鑰 / 驗簽見 [security.md](./security.md)。

---

## 1. 格式化

- Java → 4 spaces 縮排；統一放 repo 根 `.editorconfig`，不依賴個人 IDE
- hook 設定見 [`java-hooks.md`](./java-hooks.md)

## 2. 命名

| 種類 | 大小寫 | 範例 |
|------|--------|------|
| 類別 / 型別 | PascalCase | `DepositService` |
| 方法 / 變數 | camelCase | `verifyHmac` |
| 常數 | UPPER_SNAKE | `REPLAY_WINDOW_SECONDS` |
| 套件 | 小寫 | `com.lion.crypto.service.platform` |

- 名稱說明「做什麼」而非「怎麼做」；布林用 `is*`/`has*`/`can*`
- 避免縮寫（公認術語除外：URL、ID、HTTP、HMAC、AES、TRON、BSC、ETH）
- 後綴慣例（`Controller`/`Service`/`Repository`/`Filter`/`Job`/`Listener`）沿用既有

## 3. 語法偏好

- **不可變性優先**：能 `final` 就 `final`
- **空值**：用 `Optional` / 非空約束，避免 `null` 散播
- **流程簡短**：Stream / pipeline 串接超過 3 步改抽方法
- **例外不吞**：`catch` 至少記錄上下文並重拋 / 明確降級（見 [patterns.md](./patterns.md) §3）
- Magic number / string 抽常數

## 4. 語言

### 註解 / Javadoc / 說明文字

- **一律使用繁體中文**（`//`、`/* */`、`/** */`、`@param`、`@return`）
- 技術術語（API、HTTP、UUID、HMAC、AES-GCM、txHash…）保留英文

### Log 訊息語言

- 一律英文（多語環境下唯一可保證可讀的通用語）
- 取得 logger：Lombok `@Slf4j`；**禁 `System.out.println`**

### 等級

| 等級 | 用途 | 常用 |
|------|------|------|
| `info` | 一般操作、業務里程碑 | ✅ |
| `error` | 錯誤、需追查的失敗 | ✅ |
| `warn` | 系統級告警（重試、降級、reorg、資源不足） | ⚠️ 限定 |
| `debug`/`trace` | 開發期診斷 | ❌ 上線禁用 |

> **Log 脫敏**：禁記私鑰 / 助記詞 / Token / 完整 API Key（見 [security.md](./security.md) §7）。

---

## 5. 移除 / 重構安全

移除變數、欄位、方法或改簽名時，**必須搜尋所有引用點並一併修改**：

1. 移除欄位 → 搜 getter/setter/屬性名所有引用
2. 改方法簽名 → 搜所有呼叫處
3. 移除變數 → 確認 log、賦值、傳參都清理
4. **每次修改後確認無編譯 / 型別錯誤**（IDE 診斷或 `mvn compile`）

---

## 6. 大檔案讀取策略（Token 預算硬規則）

單檔 > 500 行一次 full read 吃 ~3-5k token，sub-agent 重讀時 N 倍消耗。合入前必查。

### 6.1 300 行門檻

- 檔案 **> 300 行禁用 full read**（不帶 `offset`/`limit` 的 `Read`）
- 第一次接觸大檔案：
  1. `grep -n "public \|private \|protected " <file>` 取方法行號索引
  2. 對話中保留「關鍵行號索引」摘要
  3. 後續只讀需要的段落：`Read(file, offset=N, limit=M)`

### 6.2 為什麼重要

- Sub-agent 不繼承父 context，每次派 reviewer 同檔被父/子各讀一次 → N 倍消耗
- 多 session（壓縮後、重啟）會再讀一次

### 6.3 配套

```bash
grep -n "^\s*\(public\|private\|protected\)\s" <file.java>   # 方法索引
grep -n "^\s*\(data\|methods\|computed\|watch\)" <file.vue>   # Vue 區塊
```

### 6.4 例外（允許 full read）

- 結構性檔：`pom.xml`、`application.yml`、`.properties`
- 測試 fixtures、Flyway migration 檔（對照 schema）
- 檔案本身 ≤ 300 行

---

## 7. 最小可行實作（反過度設計）

> 前面幾節管「**怎麼寫**」，這節管「**寫多少**」。`code-reviewer` 的「過度工程 — 是否加了不必要的抽象層、設計模式或額外功能？」就是在驗這條——不要等到 review 才被打回。

**原則：能解決問題的最少程式碼，不做任何投機性設計。**

- **不做 spec / plan 沒要求的功能**。plan §2 Architecture Changes 的檔案清單就是範圍上限。
- **只用一次的程式碼不要抽象**。介面、策略模式、抽象基類等到**第二個實作出現**時再抽。
  - **反例（本專案特別容易犯）**：只接一條鏈就先造一整套 chain provider 抽象層。Web3j / Trident / BitcoinJ 的既有分法已經是抽象，照用即可。
- **不做沒人要求的「彈性」與「可設定化」**。要加 `setting/` 組態前先問：這個值現在有人要按平台切換嗎？沒有就寫常數。
- **先查 `utils/`（25 類）再自建**（呼應 `development-workflow.md` Step 0）。重造一個工具類就是最常見的過度工程。
- **不為不可能發生的情境寫防禦**。私鑰 / 金額 / 入帳 / 冪等等 L1 場景的**可預期**失敗仍要處理（見 `patterns.md` §3「例外不吞」），兩者不衝突：本節管的是**不必處理的**。

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
