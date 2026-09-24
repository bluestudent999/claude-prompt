# 證據紀律

> 一條沒有證據的 finding，對維護方而言等於零 —— 他無法確認、無法定位、無法修。
> **本範本的每一條 finding 都必須讓 lion-service 的工程師「只讀這一條就能動手」。**

---

## 1. 每條 finding 的必備欄位

缺任一欄，`finding-verifier` 直接退回，不得進報告。

| 欄位 | 要求 | 反例（會被退） |
|---|---|---|
| **位置** | `模組/路徑/檔名.java:行號`，可點擊、可跳轉 | 「錢包相關的 Service」 |
| **證據片段** | 直接貼出該處程式碼（3~15 行，含足夠上下文） | 只寫敘述，不貼 code |
| **攻擊路徑** | 從**對外入口**到這個點的完整鏈路 | 「這裡沒驗證 platformId」（但沒說怎麼打得到） |
| **前提條件** | 攻擊者需要什麼（已登入？某個角色？知道某個 ID？） | 省略不寫 |
| **影響** | 具體到業務：能看到什麼、能改什麼、能拿到多少錢 | 「可能造成安全風險」 |
| **嚴重度 + 信心** | 依 `references/severity-rubric.md`，兩者分開標 | 只給嚴重度不給信心 |
| **修復方向** | 具體改法，並盡量對應到 lion-service 既有規範條文 | 「建議加強驗證」 |

---

## 2. 攻擊路徑要從「對外入口」寫起

這是最常偷懶的一欄，也是維護方最需要的一欄。

**格式**：

```
POST /cp/order/query          ← 對外入口（OrderController.java:88）
  → 無 @PreAuthorize，僅 LoginFilter 檢查登入      （SecurityConfig.java:52）
  → OrderService.queryList(query)                  （OrderService.java:134）
  → query.platformId 直接取自 request body，未以 session 的 platformId 覆寫
  → OrderMapper.selectList                         （OrderMapper.xml:71）
  ⇒ 已登入的任一包網商使用者，改 body 的 platformId 即可讀取他家注單
```

**判準**：維護方照著這條路徑走一遍，能不能自己重現？不能 → 路徑沒寫完整。

---

## 3. 「可達性」是硬要求

程式碼裡寫得不安全，但**打不到**，那不是 finding（頂多是待查或程式碼品質問題）。

必須確認至少一項：

- 該路徑掛在對外可達的 Controller / 回調 / MQ consumer / 排程上
- 或：被某個對外可達的路徑呼叫到（要指出是哪一個）

追不到對外入口 → **降級為「待查」**，不給嚴重度（`rules/scope-safety.md` 紅線 4）。

> 追呼叫鏈時常會進到 `framework_v3` / `lion-common` / `lion-core`。**可以讀**，
> 但要確認防線是否已在上游做掉了 —— 很多「漏洞」其實被上游 filter 擋住了。

---

## 4. 證據要能被重現

每條 finding 附上**定位指令**，讓維護方自己能再找一次：

```bash
grep -rn "platformId" cp-service/src/main/java/.../OrderService.java
```

> 貼指令不是形式。維護方修完之後要能用同一條指令確認改掉了，回歸驗證（`/sec-verify`）也靠它。

---

## 5. 一條 finding 只講一件事

同一個檔案有三種問題 → 三條 finding。
同一種問題出現在二十個檔案 → **一條 finding**，位置欄列出全部二十處（或列前五處 + 總數 + 定位指令）。

判準：**修復動作是不是同一個？** 是 → 合併；否 → 拆開。

---

## 6. 不要把「沒看到」寫成「沒有」

| ❌ | ✅ |
|---|---|
| 「系統沒有防重放機制」 | 「在 `XxxController` 的 21 個回調入口中，未找到 timestamp/nonce 檢查；`SingleWalletSignFilter` 有驗簽但未見時間窗」 |
| 「密碼沒有加密」 | 「`UserService.java:88` 以 MD5 無 salt 雜湊；未在其他路徑找到補強」 |

沒掃到的範圍寫進「本次掃描限制」（`rules/scope-safety.md` 紅線 6），不要用推論填補。
