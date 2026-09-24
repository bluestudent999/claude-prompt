# Strategic Compact Skill

> **指令呼叫：** `/strategic-compact`
> **目的：** 在合適時機壓縮 Context，防止長對話造成推導精度下降或幻覺。**UX 稽核特別容易爆 context**——`take_snapshot` 的輸出、整份 network 清單、多張截圖描述都很肥。

## 觸發時機

符合任一即應壓縮：

- **深度走查每完成 2~3 條 Journey**（這是最主要的時機）。
- 已執行 `take_snapshot` **≥ 5 次**（snapshot 輸出極大，是本流程最大的 context 消耗源）。
- 工具調用次數達 50 次或其倍數。
- 已跑完守門並開始修正 Finding（守門的判定表通常很長）。
- 感覺到自己開始「記不清哪張截圖是哪一頁」時——這就是該壓縮的信號。

## 操作方式

於 chat 執行：

```
/compact
```

## 壓縮時的保留 / 清除原則

**必須保留**（否則稽核會斷線）：
- 本次產出資料夾路徑、環境模式、稽核模式
- `audit-plan.md` 的 Persona × Journey 清單與**進度**（哪幾條走完了、哪幾條還沒）
- 目前的瀏覽器狀態（在哪一頁、登入狀態、購物車／待處理狀態）
- 已產出的 Finding id 清單與各角色的 id 號段分配
- 守門判定中**尚未處理**的 `FIX` / `REJECT` 項目
- 各角色回報的「未覆蓋維度」與「補證需求」（報告限制章節要用）

**可放心清除**（已落地成檔案，需要時再讀）：
- `take_snapshot` 的完整輸出
- 完整的 network request 清單、console log 全文
- 已寫入 `journeys/*.md` 的逐步敘述細節
- 已寫入 `findings/*.md` 的 Finding 全文
- 已處理完的守門判定表

> **關鍵心法：** 證據都在磁碟上。context 裡只需要留「索引」與「進度」，不需要留「內容」。
