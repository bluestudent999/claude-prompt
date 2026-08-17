# Strategic Compact Skill

> **指令呼叫：** `/strategic-compact`
> **目的：** 在邏輯間隔點壓縮 context，防止長對話造成推導精度下降或幻覺。

## 觸發時機

符合任一即應壓縮：

- **一個步驟（Sxx）完成後**（最主要的時機）
- plan 三份文件已讀過 **≥ 3 個大段落**（三份共 3935 行，很吃 context）
- 已整讀實作檔案 **≥ 3 個**（含 > 300 行者）
- Reviewer 輸出 **≥ 2 個**（各含 Artifacts / Next actions）
- 已做過 **≥ 1 輪**修復又重跑測試
- 已跑過 **≥ 5 次**跨檔 grep
- 貼過長篇的 `mvnw test` 輸出或 stack trace
- 工具調用次數達 50 次或其倍數

## 操作方式

```
/compact
```

## 保留 / 清除原則

**必須保留**（否則工作會斷線）：

- **目前步驟編號與進度**（`Sxx`、`n / 38`）
- plan `task-Sxx-plan.md` 的路徑、**§0 元資料**（涉及哪些不變量、是否涉及契約）、**§2 變更檔案清單**
- **§4 驗收計畫**與哪幾項已通過
- 尚未回寫 plan 的 **OQ 決議**
- 已建立的**行號索引**（例：「S12 在 implementation-steps 第 615 行；I7 在 development-plan 第 630 行」）
- Reviewer 的 **Final Status** 與未處理的 CRITICAL / HIGH
- 已確認的**現況事實**（例：「兩租戶 fixture 已於 S04 建立於 TestFixtures.java」）
- **版本基準**：Java 21 + Spring Boot 3.5（覆蓋 plan D18 的 4.1）——這條若丟失，下半場會開始抄 Boot 4 寫法
- **架構基準**：六角架構 + Spring Modulith；**Domain 零框架**；I1 範圍內不得用 `@ApplicationModuleListener`

**可放心清除**（需要時再讀）：

- plan 文件已讀過的段落全文
- 已讀過的實作程式碼全文
- `grep` / `ls` 的原始輸出
- Reviewer 的長文說明（只留 Status 與待辦）
- 完整的 `mvnw test` 輸出（只留結果與失敗項）
- 已完成步驟的中間過程

> **關鍵心法：** 事實都在磁碟上（plan、程式碼、測試）。context 只需要留「**索引 + 進度 + 已驗證的現況結論 + 版本基準**」，不需要留內容。
>
> **最容易丟失而出事的三項**：版本基準（Boot 3.5 而非 4.1）、架構基準（Domain 零框架）、以及「涉及哪些不變量」。壓縮前確認這三項有被寫進摘要。
