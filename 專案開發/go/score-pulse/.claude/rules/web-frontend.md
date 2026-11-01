# 後台前端規範（`web/admin`：總控後台 + 業主後台）

> **本文管的是「怎麼工作」**：技術棧基準、兩套後台怎麼共存、去哪裡讀行為契約、agent 在這個專案容易犯的錯。
> **畫面行為的權威來源是 Spec-4（總控）與 Spec-5（業主後台）的 R# / E# / AC** —— 本文**不複述它**。要知道某個畫面該長怎樣，去讀 ticket 的 Required Spec Sections。
> 後端 API 的規則在 `api-contract.md`；權限的伺服器端判定在 `tenant-isolation.md` §1。

---

## 1. 技術棧基準（D8，已決 2026-11-01）

| 項目 | 基準 |
|------|------|
| 框架 | **Vue 3**（Composition API + `<script setup>` + TypeScript） |
| 元件庫 | **Element Plus** |
| 狀態管理 | **Pinia**（**不是** Vuex） |
| 建置 | Vite |
| 路由 | vue-router 4 |
| HTTP | axios，單一 `src/api/client.ts`；型別由 `openapi-typescript` 從 `docs/contract/openapi-admin.yaml` 產生到 `src/api/types.gen.ts`（不手改） |
| 測試 | Vitest + Vue Test Utils |
| 位置 | `web/admin/`（本 repo，與後端同一個 MR） |

### ⚠ 本專案最高的 agent 失誤風險：抄到 Vue 2 寫法

**公司所有既有後台都是 Vue 2 + Element UI + Vuex**（cx-sports-v2、crypto-payment、lion-frontend、casino），網路教學也大量是 Vue 2。這是本專案最高頻的錯誤，與「憑印象寫 sp-framework」同級。

**開工前先驗，不要憑印象：**

```bash
grep -n '"vue"\|element-plus\|element-ui\|pinia\|vuex' web/admin/package.json
grep -rn "element-ui\|vuex\|new Vue(\|\$listeners\|filters:\|\.sync" --include=*.vue --include=*.ts web/admin/src/
```

看到 `element-ui`、`vuex` 或任何命中 → **停手回報**。

| Vue 2（不可用） | Vue 3 |
|---|---|
| Options API（`data()` / `methods` / `computed` 物件） | `<script setup>` + Composition API |
| `new Vue({...})` | `createApp(App)` |
| `Vue.component()` 全域註冊 | `app.component()` 或直接 import |
| `this.$refs.x` / `this.$emit()` | `ref()` / `defineEmits()` |
| `filters`（已移除） | computed 或一般函式 |
| `$listeners`（已移除） | 併入 `$attrs` |
| `.sync` 修飾詞 | `v-model:xxx` |
| `Vuex` | Pinia |
| `:visible.sync` | `v-model` |
| `element-ui` | `element-plus` |
| `this.$message` | `ElMessage` import |

**不要去改 cx-sports / crypto-payment / lion 範本的 Vue 2 規則**，那些對它們是正確的。

---

## 2. 兩套後台同一個 app

| 項目 | 規則 |
|------|------|
| 路由前綴 | 總控 `/admin/**`，業主後台 `/operator/**`；登入頁各一（`/admin/login`、`/operator/login`） |
| 登入 scope | 登入回應含 `scope: platform \| operator`；Pinia `useSession()` 依 scope 載入選單樹與權限表；**scope 錯的路由直接導回對應登入頁** |
| API 前綴 | `/api/admin/**`、`/api/operator/**`；client 依 scope 選前綴，頁面程式碼不寫死 |
| 共用 | 登入與驗證器綁定、角色權限、帳號管理、操作記錄的頁面元件**共用**（Spec-4 R1–R8 兩套後台規則相同），以 scope 參數化 |
| 不共用 | 業務頁面各自獨立目錄：`src/views/admin/**`、`src/views/operator/**` |
| 語言 | **只中文**（dept-assignment 預設 1）；不裝 i18n 套件；不送 `x-lang` |
| 業主識別 | 業主後台**不帶** operator id 到任何請求（伺服器從 session 推導，`tenant-isolation.md` §1）；總控選單站時帶 `operatorId` 由後端驗證在指派範圍內 |

---

## 3. 權限：前端隱藏 + 後端判定（Spec-4 R1–R8）

| 規則 | 前端做什麼 | 後端做什麼 |
|------|-----------|-----------|
| 查看／管理兩級 | 無「查看」→ 選單不顯示該模組；有「查看」無「管理」→ 頁面唯讀、可操作欄位（含匯出）顯示鎖頭 | 每個端點標 `Permissions`，無權限回 403 |
| 直接開網址 | 路由守衛檢查權限表 → 顯示「你沒有這個模組的權限」頁（不是 404、不是空白） | 403 |
| 權限變更生效 | **每次路由切換重新拉權限表**（R8：下次載頁即生效，不需重登）；不快取超過一次導航 | 以 DB 為準 |
| 下級角色 | 只能管自己的下級；同級／上級唯讀並顯示提示文案（AC-13） | 後端判定 |
| 匯出 | 管理權限才可點；按鈕鎖頭是 UX，**後端 403 是授權** | 403 |

**`v-if` 藏掉按鈕不是授權。** 每個會改資料的操作，後端都會重新判定權限與租戶範圍；前端的工作是不讓使用者看到做不到的事。

---

## 4. 畫面三態（硬規則）

每個列表與詳情頁必須區分三種狀態，**API 失敗不得渲染成空清單**：

| 狀態 | 呈現 | 來源 |
|------|------|------|
| 載入中 | Element Plus `v-loading` 或骨架 | 請求進行中 |
| 空 | 空狀態文案（依 spec 的文案，例「你目前沒有負責的業主」） | `code=0` 且 `data` 為空 |
| 錯誤 | 錯誤區塊 + 重試按鈕；顯示後端 `msg` | HTTP 非 2xx、`code≠0`、逾時、網路錯誤 |

axios client 的錯誤攔截器**不得回空集合**；它要 reject，由頁面渲染錯誤態。

---

## 5. 憑證與安全

| 規則 | 說明 |
|------|------|
| session cookie | 登入後由後端設 `HttpOnly; Secure; SameSite=Lax` cookie（框架 `x-session-token` 名稱）；**前端不接觸 token** |
| 不落地 | 不用 localStorage／sessionStorage 存 token、權限表、租戶 id；Pinia 狀態重新整理後重新拉 |
| 驗證器 | TOTP 綁定與驗證畫面只顯示 QR 與輸入框；secret 不寫 log、不進 URL |
| 操作記錄 | **由後端寫**（Spec-4 R15）；前端不送「我做了什麼」 |
| 匯出 | 後端產檔回下載 URL（短效）；前端不自己拼 CSV |
| 自動重送 | 對結果未知的變更操作（提交、採用、停用）**不加全域 retry** |

---

## 6. Element Plus 慣例

| 項目 | 規則 |
|------|------|
| 表格分頁 | `el-pagination` 後端分頁；`page` 從 1 起、`size` 預設 20、上限 100（`api-contract.md` §2 第 7 條）；排序與篩選都帶到後端 |
| 表單 | `el-form` + rules；提交前 `validate()`；錯誤碼對應文案由後端 `msg` 顯示 |
| 二次確認 | 停用、刪除、退回、標記上線一律 `ElMessageBox.confirm`，文案照 spec |
| 日期 | 顯示依平台時區（總控設定，預設 UTC+8）；送後端一律 ISO UTC |
| 數字 id | 從 API 來的 id 是字串，**不要 `Number()` 轉**（精度） |
| 圖示 | `@element-plus/icons-vue`；不用 iconfont |

---

## 7. 行為契約去哪裡讀

**不要通讀 spec。** 每張 ticket 都列了 `Required Spec Sections` 與對映的 AC，**照著讀**（`development-workflow.md` Step 0）。

| 要知道什麼 | 讀哪裡 |
|---|---|
| 畫面該做什麼、驗收條件 | ticket 的 Required Spec Sections + AC 編號 |
| 業務規則、邊界情境 | Spec-4／5 的 R# / E#（由 AC 反查） |
| 後端 API 的形狀 | `docs/contract/openapi-admin.yaml` 與 `src/api/types.gen.ts`；**API 還不存在 → 那是 A 類工作，先做後端** |

---

## 8. 測試（Vitest）

| 要求 | 說明 |
|------|------|
| 每個頁面至少三態測試 | mock API 回成功、空、失敗各一，斷言畫面 |
| 權限 | 無查看權限 → 選單無、路由到「沒有權限」頁；有查看無管理 → 按鈕鎖頭 |
| 表單 | 必填缺一不可送出；錯誤碼顯示後端 `msg` |
| 租戶 | 業主後台頁面的請求**不含** operator id 參數（斷言 axios mock 的 params） |
| 不測 | Element Plus 內部行為、樣式 |
| 命名 | `*.spec.ts` 與元件同目錄；`describe('<Page>')` + `it('shows error state when api fails')` |

後端對應的 API 測試另在 Go 側（`testing.md` §1）；B 類 ticket 的 DoD 兩邊都要。

---

## 9. agent 在這個專案容易犯的錯

| # | 失敗模式 | 條號 |
|---|---------|------|
| 1 | 把「取得失敗」和「確實沒有」都渲染成空清單 | §4 |
| 2 | token 或權限表進了 localStorage —— 自檢：重新整理後還拿得到嗎？拿得到就違規 | §5 |
| 3 | 業主後台請求帶 `operatorId` | §2、I1 |
| 4 | 以為 `v-if` 藏按鈕就是授權完成 | §3 |
| 5 | 權限表快取到下次登入才更新 | Spec-4 R8 |
| 6 | 抄了 cx-sports 的 Vue 2 元件 | §1 |
| 7 | 為 H5 前台頁面在 `web/admin` 開路由 | D9（不在本 repo） |
| 8 | 自己拼匯出 CSV、自己寫操作記錄 | §5 |
| 9 | 把 id `Number()` 後比對 | §6 |
| 10 | 後台頁面接 `x-lang` 做多語 | §2 |

---

## 10. 禁止事項

- 不用 Vue 2 任何寫法、不裝 `element-ui`、`vuex`。
- 不在前端做租戶過濾（取全部再 filter）。
- 不自建與後端平行的業務資料快取（Pinia 只存 session 與 UI 狀態）。
- 不為 Out of Scope（聊天、新聞、第二期語系）預留路由或入口。
- 不把 `openapi-typescript` 產物手改；API 變了重產。
- 不在 `web/admin` 放 H5／App 的任何程式碼。
