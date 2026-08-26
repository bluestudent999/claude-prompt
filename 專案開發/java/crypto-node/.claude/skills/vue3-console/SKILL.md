---
name: vue3-console
description: crypto-node-web 後台前端的開工程序——確認技術棧、抓 Vue 2 混入、取得該 TASK 的驗收依據、自檢容易靜默出錯的幾處。寫後台前端前載入。
---

# vue3-console — 後台前端開工程序

> **這個 skill 不是 Vue 教學，也不複述 spec。** 它回答的是「動手前該先做哪幾件事」。
> 畫面該長什麼樣 → 讀該 TASK 的 `Required Spec Sections`。技術棧基準與 Vue 2 對照表 → [`rules/web-frontend.md`](../../rules/web-frontend.md)。

---

## Step 1：確認技術棧沒被污染

```bash
grep -n '"vue"\|element-plus\|element-ui\|pinia\|vuex' crypto-node-web/package.json
grep -rn "element-ui\|vuex\|new Vue(\|\$listeners\|filters:" --include=*.vue --include=*.js --include=*.ts crypto-node-web/
```

- `vue` 應為 **3.x**、元件庫 **`element-plus`**、狀態管理 **`pinia`**
- 命中 `element-ui` / `vuex` / Vue 3 已移除的特性 → **停手回報**

> 組織有兩個 Vue 2 專案在旁邊，網路教學也大量是 Vue 2。**這是本專案最高頻的錯誤**，`web-reviewer` 的第一個 CRITICAL 就是它。

---

## Step 2：取得驗收依據（不要通讀 spec）

```bash
grep -n "^| \*\*T7\*\*" -A 2 plan/crypto-node-web/backlog.md    # 換成實際 TASK 編號
```

拿到兩樣東西：

| 拿到什麼 | 怎麼用 |
|---|---|
| **`Required Spec Sections`** | **只讀這幾節** spec |
| **對映的 AC 編號** | 這就是完成的定義，也是 `web-reviewer` 的依據 |

**看到自己在 full read 60KB 的 spec，就是沒照做。**

---

## Step 3：查有沒有已決的決策（不要重新選）

技術棧、落點、連接方式、第二因素、工作階段、快取**都已決**，見 [`rules/locked-decisions.md`](../../rules/locked-decisions.md) 三之二。

**照決議做，不要在 plan 裡重新開一次 OQ。**

---

## Step 4：實作中的四個自檢問句

寫的時候拿這四題問自己。它們對應的都是**功能測試會全綠**的錯誤：

| 問句 | 抓的是 |
|------|--------|
| 「**取得失敗**」和「**確實沒有**」在畫面上分得出來嗎？ | 用陣列長度 0 表達兩件事（E1／E10） |
| 這個憑證**重新整理後還拿得到嗎**？ | 明文落到 store／storage／網址／log（R9／R10） |
| 這份清單是**後端已依租戶範圍過濾**的，還是取全部再前端 filter？ | 範圍外資料已經到了瀏覽器（R2） |
| 這個操作**送出後結果未知**時，會不會自動重送？ | 危險操作重複執行（E2） |

> 前三題有個共同點：**寫錯的版本在單租戶、連線正常的開發環境下完全正常。**

---

## Step 5：完成前

- **逐條對映 AC 自檢**（不是對映本 skill）
- 動到後台前端／後台後端／Admin API 呼叫 → 派 `web-reviewer`
- 危險操作的**後果文案**（R6）標注「需人審」—— 寫反會誤導值班員做出反向處置

---

## 不要做的事

| ❌ | 為什麼 |
|---|--------|
| 抄 `cx-sports` / `crypto-payment` 的 Vue 元件 | 那兩個是 **Vue 2**。觀念可參考，**程式碼不可直接抄** |
| 去改那兩個專案的 `vue2-patterns` skill | 它們仍在 Vue 2，那些 skill 對它們是正確的 |
| 為 Out of Scope 的功能留路由或入口 | 留了就會有人來填（`coding-style.md` §8） |
| 自己算「全叢集是否切完」 | 服務端尚未提供逐台能力，猜就是編造（`web-integration.md` §5） |
| 在 plan 裡重新決議已鎖定的事項 | 見 Step 3 |
