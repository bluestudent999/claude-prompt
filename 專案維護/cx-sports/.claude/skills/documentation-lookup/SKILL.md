---
name: documentation-lookup
description: 透過 Context7 MCP 查詢最新的函式庫與框架文件，取代訓練資料。適用於設定問題、API 參考、程式碼範例，或使用者提及特定框架時。
origin: ECC
---

# 文件查詢（Context7）

當使用者詢問函式庫、框架或 API 時，透過 Context7 MCP（工具 `resolve-library-id` 與 `query-docs`）取得最新文件，而非依賴訓練資料。

## 核心概念

- **Context7**：提供即時文件的 MCP 伺服器，用它取代訓練資料來查詢函式庫與 API。
- **resolve-library-id**：從函式庫名稱與查詢內容回傳 Context7 相容的 library ID（例如 `/vercel/next.js`）。
- **query-docs**：根據 library ID 與問題取得文件與程式碼片段。務必先呼叫 resolve-library-id 取得有效的 library ID。

## 啟用時機

當使用者：

- 詢問設定或配置問題（例如「Spring Boot 的 ShardingSphere 怎麼設定？」）
- 要求撰寫依賴特定函式庫的程式碼（「寫一個 Jedis 的快取操作...」）
- 需要 API 或參考資訊（「Flyway 的遷移 API 有哪些？」）
- 提及特定框架或函式庫（Spring Boot、ShardingSphere、Jedis、Sentinel、Elasticsearch 等）

只要請求取決於函式庫、框架或 API 的準確且最新行為，就應使用此 skill。

## 使用流程

### 步驟 1：解析 Library ID

呼叫 **resolve-library-id** MCP 工具：

- **libraryName**：從使用者問題中提取的函式庫或產品名稱（例如 `Spring Boot`、`ShardingSphere`、`Elasticsearch`）。
- **query**：使用者的完整問題，用以提升結果的相關性排序。

必須先取得 Context7 相容的 library ID（格式 `/org/project` 或 `/org/project/version`）才能查詢文件。不要在沒有此步驟的有效 library ID 下呼叫 query-docs。

### 步驟 2：選擇最佳匹配

從解析結果中，依以下條件選擇一個結果：

- **名稱匹配**：優先選擇與使用者詢問最接近的結果。
- **Benchmark 分數**：分數越高代表文件品質越好（100 為最高）。
- **來源信譽**：可用時優先選擇 High 或 Medium 信譽。
- **版本**：若使用者指定版本（例如「Spring Boot 2.7.11」），優先選擇版本特定的 library ID。

### 步驟 3：取得文件

呼叫 **query-docs** MCP 工具：

- **libraryId**：步驟 2 選擇的 Context7 library ID（例如 `/spring-projects/spring-boot`）。
- **query**：使用者的具體問題或任務。越具體越能取得相關片段。

限制：每個問題最多呼叫 query-docs（或 resolve-library-id）3 次。若 3 次後答案仍不明確，說明不確定性並使用已有的最佳資訊，而非猜測。

### 步驟 4：使用文件

- 以取得的最新資訊回答使用者的問題。
- 適時附上文件中的相關程式碼範例。
- 在重要時標註函式庫或版本（例如「在 Spring Boot 2.7.11 中...」）。

## 最佳實踐

- **越具體越好**：盡可能使用使用者的完整問題作為查詢，以獲得更好的相關性。
- **版本意識**：當使用者提及版本時，優先使用解析步驟中的版本特定 library ID。
- **優先官方來源**：存在多個匹配時，優先選擇官方或主要套件，而非社群分支。
- **不傳送敏感資料**：在傳送到 Context7 之前，從查詢中移除 API 金鑰、密碼、token 及其他機密。
