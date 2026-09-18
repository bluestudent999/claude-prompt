---
name: arch-check
description: 檢查架構邊界有沒有被破 —— 前端有沒有算錢、後端有沒有信任前端結果、有沒有自建餘額、派彩模組能不能獨立測試。動到結構、新增類別、前後端介面時跑。
---

# arch-check — 架構邊界檢查

**用法：** `/arch-check`

這個 skill 回答一個問題：**把前端整包換成一個亂寫的程式，後端的帳還是完全正確嗎？**

---

## Step 1 · 前端有沒有算錢（最重要）

```bash
echo "=== 前端出現金額或勝負計算 ==="
grep -rniE "paytable|payline|multiplier|calcWin|winAmount|odds|prize" \
  --include="*.ts" --include="*.js" --include="*.vue" web/ src/ 2>/dev/null

echo "=== 前端出現隨機開獎 ==="
grep -rniE "Math\.random|randomSymbol|spin.*random" --include="*.ts" --include="*.vue" web/ 2>/dev/null
```

任一命中 → **破了不變量 I1**。

---

## Step 2 · 後端有沒有信任前端送來的結果

```bash
grep -rn "resultMatrix\|winAmount\|winLines\|symbols" --include="*.java" src/main/ \
  | grep -i "request\|dto\|param\|payload"
```

請求物件裡只能有**意圖**（下注額、線數、快速模式），不能有**結果**（盤面、中獎線、金額）。

---

## Step 3 · 有沒有自建餘額

```bash
grep -rn "balance" --include="*.sql" src/main/resources/db/
grep -rn "class.*Balance\|balanceRepository" --include="*.java" src/main/
```

> 錢包是外部系統（`business-logic.md` §2），遊戲不得自建餘額（不變量 I2）。
> 最早那份 `Yummy_Slot_Development_Plan.md` §2.3 的說法已被取代，照它做就是破線。

---

## Step 4 · 判定引擎能不能獨立測試

```bash
echo "=== 判定引擎的相依（A 群 T-05~T-09 的產物）==="
grep -rn "^import" --include="*.java" src/main/java/**/payline/ src/main/java/**/engine/ 2>/dev/null \
  | grep -iE "springframework|jakarta\.persistence|repository"
```

命中 → 判定引擎綁死框架，**M-2 實測回歸與 RTP 模擬都無法自動化**（`architecture.md` §4）。
backlog 的 A 群標明「純規則，不依賴任何外部系統」，就是為了這件事。

---

## Step 5 · 單一結算路徑

```bash
grep -rln "settle\|payout\|結算" --include="*.java" src/main/ | sort
```

REST 與 WebSocket 兩條進來的請求，**必須共用同一條結算程式碼**。兩份 = 兩個會漂移的真實來源。

---

## Step 6 · 獎勵事件有沒有被硬編

```bash
grep -rniE "freeSpin|FREE_SPIN|rewardType|RewardEvent" --include="*.java" src/main/ | grep -iE "enum|type|class"
```

`spec.md` R-15 要求獎勵事件做成泛化模型，**要有型別欄位**。v1 只有一種是正常的，但型別欄位不能省。

---

## 判定

| 情況 | 處置 |
|---|---|
| 前端有任何算錢的實作 | **block**（I1） |
| 後端請求物件含結果類欄位 | **block**（I1） |
| 遊戲側有餘額表 | **block**（I2） |
| 判定引擎綁死 Spring／資料庫 | **block**，M-2 與 RTP 模擬都無法自動化 |
| 兩條協定各自結算 | **block** |
| 獎勵事件硬編成只有免費旋轉 | **block**（`spec.md` R-15） |
| 本次只動設定或文件 | 直接通過 |
