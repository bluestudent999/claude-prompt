# 升級驗證政策（行為等價）

> 升級沒有「新功能要測」，只有「**行為等價要證**」。本檔規範升級期測試的意義、分層與如何對照 baseline。
> 核心觀念：升級的測試目標不是「測新功能對不對」，而是「升級前後行為一不一樣」。

---

## 1. baseline 對照法（升級驗證的骨架）

```
Step -1：來源 JDK + 來源版本跑全套測試 → 存 upgrade/baseline-test-result.txt（綠燈基準）
   ↓ 升級
Step 4：目標 JDK + 目標版本跑同一套測試 → 與 baseline 逐項對照
```

| 對照結果 | 判定 | 處置 |
|---------|------|------|
| baseline 綠 → 升級後綠 | ✅ 行為等價 | 通過 |
| baseline 綠 → 升級後紅 | ⚠️ **升級造成的行為差異** | 逐一判定：修 code（行為要等價）或修測試（測試依賴舊版實作細節，須說明為何安全） |
| baseline 紅 → 升級後紅 | 既有問題 | 不在升級範圍（Step -1 已標記） |
| baseline 紅 → 升級後綠 | 順帶修好 | 記錄，但不主動追求 |

> **硬規則：** 升級後新增的紅燈**逐一判定來源**，禁止用「改測試讓它過」草草收尾——那等於放棄行為等價的證明。

---

## 2. 測試技術棧（升級期注意）

- **JUnit**：來源若為 JUnit 4，升級期**可保留 JUnit 4**（Boot 3 仍可跑 vintage engine）或用 OpenRewrite `JUnit4to5Migration` 一併遷移——**遷移與否列 OQ**（遷 JUnit 是額外變更面，直接跳躍時可選擇延後）。
- **Spring 測試**：`@SpringBootTest` / `@WebMvcTest` 在 Boot 3 下 context 載入是最強的 jakarta/設定遷移驗證——namespace 漏遷、設定屬性錯誤，多在 context 啟動時才爆。
- **斷言 / Mock**：AssertJ / Mockito 跨版本穩定，但 Mockito 需確認版本支援 JDK 21（舊版在新 JDK 對 inline mock 可能失敗）。

---

## 3. 升級期測試分層（驗證強度）

| 層級 | 範圍 | 升級期驗證要求 |
|------|------|--------------|
| **V1 啟動驗證** | 應用能否在目標版本啟動（context 載入、bean 裝配、auto-config） | **強制**：跑 `@SpringBootTest` context loads；這是 jakarta + 設定遷移正確性的第一道證明 |
| **V2 行為等價** | 對外 API 回傳、鑑權行為、序列化格式、查詢結果 | **強制對照 baseline**：重點打 `breaking-changes.md §F` 的高風險點（Security 路徑、編碼、trailing slash、主鍵生成） |
| **V3 整合** | DB / Redis / Kafka / 第三方對接在新版下的連線與序列化 | **依命中情況**：用到的中介層 client 有升版就必驗（如 Lettuce、Kafka client、ShardingSphere DSL） |

> 沒有任何測試基座的模組 → 至少手動驗 V1（啟動）+ 關鍵 API 手測，MR 附手動 QA 步驟與技術債追蹤。

---

## 4. 必跑的升級專屬驗證點

升級 diff 不論測試覆蓋多少，下列**必須驗**（對應 `breaking-changes.md §F`）：

1. **應用啟動**：目標 JDK 下 `mvn spring-boot:run` 或 context-load 測試能起來（最基本，namespace/設定錯這裡先爆）。
2. **鑑權路徑**（若用 Spring Security）：打受保護端點，確認該擋的擋、該放的放（C4 易誤判）。
3. **對外 API 契約**：抽幾個關鍵端點，比對升級前後的 response（含 trailing slash B5、JSON 格式）。
4. **資料寫入正確性**（若用 JPA/Hibernate）：主鍵生成、欄位映射（D4）。
5. **字元編碼**：含中文/多語的輸入輸出，確認 UTF-8 行為未變（A8）。

---

## 5. CI 與本地的分工

- **CI 若 skip test**（例如 Jenkins 用 `-Dmaven.test.skip=true` 只驗編譯）→ **回歸測試必須本地手動跑**，把測試 skip 當綠燈是升級期紅線（見 `CLAUDE.md §2`）。
- 升級 MR 描述必附：
  - baseline vs 升級後的測試結果對照（pass/fail 數、新紅燈的判定）。
  - 手動 QA 清單（§4 必跑點的執行證據）。
  - 已知行為差異記錄（哪些行為變了、為何可接受 / 已同步調整 client）。

---

## 6. 不做的事

- 不為升級**補大量新測試**（升級期目標是等價，不是提升覆蓋率——補測試另開 MR）。
- 不為了讓紅燈變綠而**放寬斷言**（除非確認是測試依賴舊版實作細節，且記錄原因）。
- 不在沒有 baseline 對照下宣稱「行為等價」。
