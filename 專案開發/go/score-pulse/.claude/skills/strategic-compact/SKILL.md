# Strategic Compact Skill

> **指令呼叫：** `/strategic-compact`
> **自動觸發：** `settings.json` 的 `PreToolUse` (Edit / Write)
> **目的：** 提醒 AI 與開發者在合適時機進行 Context 壓縮，防範對話 Token 過長導致推導精度下降或產生幻覺。

## 觸發時機

當符合以下任一代理指標時，應啟動壓縮：
- 當前 Session 中工具調用次數（Tool Calls）已達 50 次或其倍數。
- 當前已整讀實作檔案 $\ge 3$ 個（含 $\gt 300$ 行的檔案）。
- 經歷了 $\ge 2$ 輪的代碼審查與修復反覆。

## 操作方式

手動於 chat 中執行：
```
/compact
```
在壓縮時，必須**保留**當前 Task 相關的 Spec/Plan 結論、受影響檔案清單、當前實作進度，並**清除**中途已讀取的實作細節與長文 Review 輸出。
