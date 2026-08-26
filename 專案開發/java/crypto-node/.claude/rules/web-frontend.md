# 後台前端規範（crypto-node-web）

> **本文管的是「怎麼工作」**：技術棧基準、去哪裡讀行為契約、agent 在這個專案容易犯的錯。
> **UI 行為的權威來源是 `plan/crypto-node-web/spec.md`（R# / E# / AC）** —— 本文**不複述它**。看到需要知道某個畫面該長怎樣，去讀 spec 對映的那幾節。

---

## 1. 技術棧基準（已決，2026-08-26）

| 項目 | 基準 |
|------|------|
| 框架 | **Vue 3**（Composition API + `<script setup>`） |
| 元件庫 | **Element Plus** |
| 狀態管理 | **Pinia**（**不是** Vuex） |
| 建置 | Vite |

決議理由與落點見 [`locked-decisions.md`](./locked-decisions.md)。

### ⚠ 本專案最高的 agent 失誤風險：抄到 Vue 2 寫法

**這與 Boot 3.5 誤抄 Boot 4 是同一類錯誤，而且更容易發生** —— 組織有**兩個 Vue 2 專案在旁邊**（`cx-sports`、`crypto-payment`），網路上的 Vue 教學也大量是 Vue 2。

**開工前先驗，不要憑印象：**

```bash
grep -n '"vue"\|element-plus\|element-ui\|pinia\|vuex' package.json
```

看到 `element-ui` 或 `vuex` → **停手回報**，那是 Vue 2 的東西混進來了。

| Vue 2（❌ 不可用） | Vue 3（✅） |
|---|---|
| Options API（`data()` / `methods` / `computed` 物件） | `<script setup>` + Composition API |
| `new Vue({...})` | `createApp(App)` |
| `Vue.component()` 全域註冊 | `app.component()` 或直接 import |
| `this.$refs.x` / `this.$emit()` | `ref()` / `defineEmits()` |
| `filters`（**Vue 3 已移除**） | computed 或一般函式 |
| `$listeners`（**Vue 3 已移除**） | 併入 `$attrs` |
| `.sync` 修飾詞 | `v-model:xxx` |
| `Vuex` | Pinia |
| `:visible.sync` | `v-model` |
| `element-ui` 套件 | `element-plus` 套件 |

**判不準某個寫法在 Vue 3 是否可用 → 查官方文件或直接跑起來驗證。**

> **不要去改 `cx-sports` / `crypto-payment` 的 `vue2-patterns` 與 `vue2-coding-standards` skill** —— 那兩個專案仍在 Vue 2，那些 skill 對它們是正確的。

---

## 2. 落點與隨之而來的工程事項

`crypto-node-web` 在 crypto-node repo 內，與 `crypto-node-service`、`crypto-node-flyway` 同層。

**動工前要處理（這些 spec 不會寫，是工程設定）：**

| 項目 | 要做什麼 |
|------|---------|
| **`.gitignore`** | 加 `node_modules/`、`dist/` —— **不加就會有人把 node_modules commit 進去** |
| **建置鏈** | Vite 產物要不要進 Maven reactor / 打進 image？決定 `Dockerfile` 與 `deploy/` 怎麼改 |
| **CI** | 前端 lint / build 要進 pipeline，與後端同一個 stage 或獨立 |
| **commit scope** | 見 [`git-workflow.md`](./git-workflow.md) —— 已新增 `web` / `web-api` |
| **跨模組變更** | 一個需求同時動 service + web 時，**兩邊同一個 MR**，不需要跨 repo 交叉引用 |

---

## 3. 行為契約去哪裡讀

**不要通讀 spec。** `backlog.md` 的每顆 T 任務都列了 `Required Spec Sections`，**照著讀就不會爆上下文**（`CLAUDE.md` §0.1）。

| 要知道什麼 | 讀哪裡 |
|---|---|
| 這個畫面該做什麼、驗收條件 | 該 T 任務的 `Required Spec Sections` + 對映的 **AC 編號** |
| 業務規則、邊界情境 | spec 的 **R#** / **E#**（由 AC 反查） |
| 範圍邊界（什麼明確不做） | `brief.md` 的 Out of Scope |

**看到自己在通讀整份 spec，就是沒照做。**

---

## 4. agent 在這個專案容易犯的錯（只列失敗模式，做法去讀 spec）

這些是**讀了 spec 仍然會寫錯**的地方 —— 因為錯的寫法在功能測試下全綠。

| # | 失敗模式 | 條號 |
|---|---------|------|
| 1 | 把「**取得失敗**」和「**確實沒有**」都渲染成空清單 —— 多數 HTTP client 的錯誤處理會回空集合，UI 照樣顯示「目前沒有資料」 | **E1／E10** |
| 2 | 憑證明文進了 store／storage／網址／log —— **自檢：重新整理後還拿得到嗎？拿得到就是違規** | **R9／R10** |
| 3 | 取全部再前端 `filter` 租戶 —— 範圍外的資料**已經到了瀏覽器** | **R2** |
| 4 | 以為 `v-if` 藏掉按鈕就是授權完成 —— 那是 UX，**後端必須重新判定**（[`web-integration.md`](./web-integration.md) §3） | **R2** |
| 5 | 把「看起來完成、實際不能用」的半成品渲染成完成 —— 這條**全程不會撞牆** | **R1a** |
| 6 | 把**單台狀態**呈現成全體狀態 —— 值班員會以為節點已全數切換 | **R16／R17** |
| 7 | 對「結果未知」的操作自動重送（例如裝 axios 全域 retry 攔截器） | **E2** |
| 8 | 危險操作的**後果文案寫反** —— 會誤導值班員做出反向處置。**這類文案一律人審** | **R6** |
| 9 | 為 Out of Scope 的功能預留路由或入口 —— 留了就會有人來填（[`coding-style.md`](./coding-style.md) §8） | brief |
| 10 | 自建業務資料的持久化快取 —— 違反「不得成為第二個真實來源」 | **R11** |

> **第 1、5、7 條的共同特徵：不會報錯、不會有 log、功能測試全綠。** 只能靠開工前知道它們存在。

---

## 5. 驗收

依該 T 任務**對映的 AC 逐條驗**，不是依本文。`web-reviewer` 的檢查依據同此。
