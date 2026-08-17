# Strategic Compact Skill

> **指令呼叫：** `/strategic-compact`
> **目的：** 在邏輯間隔點壓縮 context，避免長對話造成推導精度下降或幻覺。

## 觸發時機

符合任一即應壓縮：

- 已整讀實作檔案 **≥ 3 個**（尤其 `recognize_sicbo_stream.py` 584 行 / `local_train.py` 441 行的多個區段）
- Reviewer 已完成輸出 **≥ 2 個**（各含 Artifacts / Next actions）
- 已做過 **≥ 1 輪**修復又重跑 reviewer
- 已跑過 **≥ 5 次**跨檔 grep
- 貼過大量 log、YOLO 輸出或影像清單進對話
- 工具調用次數達 50 次或其倍數

## 操作方式

```
/compact
```

## 保留 / 清除原則

**必須保留**（否則工作會斷線）：
- spec / plan 路徑與 §0 元資料（段別、l_tier、是否涉及 Go 契約與部署介面）
- plan §2 的**變更檔案清單**與目前進度
- plan §4 的**驗證計畫與改前基準數字**
- 已建立的**行號索引**（例：「開盅判定在 512、常數區在 59-66、槽位分配在 435」）
- Reviewer 的 **Final Status** 與尚未處理的 CRITICAL / HIGH 清單
- 尚未回寫 plan 的 OQ 決議
- 已確認的**現況事實**（例：「主程式未接 TCPBroadcaster，grep 零命中」）

**可放心清除**（需要時再讀）：
- 已讀過的實作程式碼全文
- grep / ls 的原始輸出
- Reviewer 的長文說明（只留 Status 與待辦）
- 已完成步驟的中間過程
- 貼進來的 log 與影像清單

> **關鍵心法：** 這個專案的事實都在磁碟上（程式碼、`data/verified_rounds_sicbo/`、`.plan/`）。context 只需要留「**索引 + 進度 + 已驗證的現況結論**」，不需要留內容。
