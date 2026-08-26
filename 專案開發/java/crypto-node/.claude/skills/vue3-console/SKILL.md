---
name: vue3-console
description: crypto-node-web 後台的 Vue 3 + Element Plus 實作模式——三種狀態、危險操作確認、憑證只顯示一次、表格分頁、租戶範圍。寫後台前端時載入。
---

# vue3-console — Vue 3 + Element Plus 實作模式

> **前提**：技術棧已決（`rules/web-frontend.md` §1）。本 skill 給的是**對映 spec 硬要求的具體實作模式**，不是 Vue 教學。
> 每一節都對映 spec 的 R# / E#；行為契約以 `web-frontend.md` 為準，本檔只回答「用 Vue 3 怎麼做」。

---

## 0. 開檔前先確認

```bash
grep -n "\"vue\"\|element-plus\|pinia\|vuex" package.json
```

- `vue` 應為 **3.x**、元件庫為 **`element-plus`**（不是 `element-ui`）、狀態管理為 **`pinia`**（不是 `vuex`）
- 看到 `element-ui` 或 `vuex` → **停手回報**，那是 Vue 2 的東西混進來了

---

## 1. 三種狀態必須是三個狀態（E1 / E10）—— 最容易犯的錯

**禁止用「陣列長度 0」表達兩件不同的事。**

```ts
// ❌ 錯：失敗與「確實沒有」都變成空陣列
const list = ref([])
try { list.value = await api.listTenants() } catch { /* list 仍是 [] */ }
// 畫面：v-if="list.length === 0" → 顯示「目前沒有租戶」← 但其實是連不上
```

```ts
// ✅ 對：明確的三態，一路貫穿到畫面
type LoadState<T> =
  | { status: 'loading' }
  | { status: 'failed'; reason: string }   // ← E1
  | { status: 'ready'; data: T[] }         // data 可能是空陣列 = 確實沒有

const state = ref<LoadState<Tenant>>({ status: 'loading' })

async function load() {
  state.value = { status: 'loading' }
  try {
    state.value = { status: 'ready', data: await api.listTenants() }
  } catch (e) {
    state.value = { status: 'failed', reason: toMessage(e) }
  }
}
```

```vue
<template>
  <!-- 失敗：絕不可渲染成空清單（E1） -->
  <el-alert v-if="state.status === 'failed'" type="error" :closable="false"
            title="無法連線到 crypto-node，以下資料無法取得" :description="state.reason" />

  <!-- 確實沒有：文案必須與上面明顯可區分（E10） -->
  <el-empty v-else-if="state.status === 'ready' && !state.data.length"
            description="目前沒有租戶">
    <el-button type="primary" @click="openCreate">建立第一個租戶</el-button>
  </el-empty>

  <el-table v-else-if="state.status === 'ready'" :data="state.data" />
  <el-skeleton v-else :rows="5" />
</template>
```

**失敗時變更類操作必須停用**（E1）：

```vue
<el-button :disabled="state.status !== 'ready'" @click="submit">送出</el-button>
```

---

## 2. 危險操作：二次確認 + 理由 ≥10 字（R5 / R6）

`ElMessageBox.confirm` **不夠** —— 規格要求理由必填且 ≥ 10 字。用 `prompt` 加驗證，或自訂 dialog。

```ts
import { ElMessageBox } from 'element-plus'

async function confirmDangerous(opts: {
  title: string
  consequence: string   // ⚠ 白話後果與可逆性；此文案必須人審（R6）
}) {
  const { value: reason } = await ElMessageBox.prompt(
    opts.consequence,
    opts.title,
    {
      confirmButtonText: '確認執行',
      cancelButtonText: '取消',
      inputPlaceholder: '請輸入操作理由（至少 10 字）',
      inputValidator: (v) => (v ?? '').trim().length >= 10 || '理由至少需 10 個字',
      type: 'warning',
    },
  )
  return reason.trim()   // ← 必須隨請求送出並寫入操作紀錄（R7）
}
```

**七項危險操作**（完整清單，不得增刪）：
`暫停掃描 · 恢復掃描 · 切換節點 · 重掃區間 · 地址移除 · 訂閱者停用 · 訂閱者恢復`

**三項明確不是危險操作**（**不要**加二次確認，會讓日常操作變吵）：
`拉取速率調整 · 通知網址登記 · 發測試通知`

> ⚠ **後果文案寫錯會誤導值班員做出反向處置。** 例：「暫停掃描期間鏈上入金不會被記錄，恢復後會自動補上，不會遺漏」——把「會自動補上」寫成「會遺漏」，值班員就不敢暫停了。**這類文案一律人審。**

### 地址移除的加強確認（E13，M5 風險最高）

除上述外，還要：顯示該地址的**入金筆數與最近一筆時間**、揭露**三項後果**、**已有入金者要求輸入該地址本身**：

```ts
inputValidator: (v) => v?.trim() === address || '請輸入完整地址以確認'
```

---

## 3. 憑證明文只顯示一次（R9 / R10）

```ts
// ✅ 只活在組件內，卸載即消失
const plaintextKey = ref<string | null>(null)   // 組件 local ref

async function issueApiKey(subscriberId: string) {
  plaintextKey.value = (await api.issueApiKey(subscriberId)).plaintext
}
```

**絕對禁止**：

| ❌ | 為什麼 |
|---|---|
| 放進 Pinia store | devtools 看得到；若裝了持久化外掛會直接落地 |
| `localStorage` / `sessionStorage` / cookie | 明文留在瀏覽器 |
| 放進 module scope 的 `ref`（模組級單例） | 跨組件存活，違反「只顯示一次」 |
| 進 route query / hash | 會進瀏覽器歷史與伺服器 log |
| `console.log` / 前端錯誤回報 | 會外流到 log 系統 |

**必須提供**：一鍵複製、「關閉後無法再取得」警語、**E4 的「立即輪替」入口**。

**節點供應商網址內含憑證** → 顯示前遮蔽（R10、AC-58）。

> **自檢：重新整理後還拿得到嗎？** 拿得到 → 違規。

---

## 4. 表格與分頁（E11）

**查詢結果過大必須分頁並顯示總筆數，不得一次載入全部。**

```vue
<el-table :data="state.data" v-loading="loading" />
<el-pagination
  v-model:current-page="page" v-model:page-size="size"
  :total="total" :page-sizes="[20, 50, 100]"
  layout="total, sizes, prev, pager, next"
  @change="load" />
```

- **分頁參數送給後端**，不要取回全部再前端切
- `layout` 含 `total` —— 規格要求顯示總筆數
- `v-model:current-page` 是 Vue 3 寫法（Vue 2 是 `:current-page.sync`）

---

## 5. 租戶範圍（R2）

**下拉選單的資料來源必須是後端已過濾的清單**，不要取全部再前端 `filter`。

```ts
// ✅ 後端依操作者的租戶範圍回傳（web-integration.md §5）
const tenants = await api.listMyTenants()
```

```ts
// ❌ 取全部再前端過濾 —— 範圍外的租戶已經到了瀏覽器
const all = await api.listAllTenants()
const mine = all.filter(t => myTenantIds.includes(t.id))
```

**權限不足的動作不顯示按鈕**（而非顯示後點擊報錯）：

```vue
<el-button v-if="can('ISSUE_CREDENTIAL')" @click="issue">發放 API Key</el-button>
```

> ⚠ **`v-if` 隱藏是 UX，不是安全邊界。** 後端必須重新判定（`web-integration.md` §5）。**兩者都要做。**

---

## 6. 半成品狀態必須明示（R1a）

Operator 會做出**看起來完成、實際不能用**的東西 —— 這是最危險的一條，因為**全程不會撞牆**。

```vue
<!-- 訂閱者開通後，當前操作者無發憑證權限 -->
<el-alert v-if="!subscriber.hasApiKey && !can('ISSUE_CREDENTIAL')"
          type="warning" :closable="false"
          title="尚待管理員發放憑證"
          description="在管理員發放 API Key 之前，此訂閱者無法使用。" />

<!-- 已登記通知網址但尚無簽章金鑰 -->
<el-alert v-if="subscriber.notifyUrl && !subscriber.hasSigningKey"
          type="warning" :closable="false"
          title="尚待管理員產生簽章金鑰"
          description="在此之前，下游無法驗證通知的真偽。" />
```

**測試通知的結果畫面必須同時明示此限制** —— 送達成功 ≠ 下游能驗簽：

```vue
<el-result v-if="testSent" icon="success" title="測試通知已送出">
  <template #sub-title>
    <el-alert v-if="!subscriber.hasSigningKey" type="warning" :closable="false"
              title="但下游目前無法驗證這則通知的真偽（尚無簽章金鑰）" />
  </template>
</el-result>
```

---

## 7. 其他對映 spec 的實作點

| 需求 | 做法 | 來源 |
|---|---|---|
| 兩個時間分別標示 | 欄位標題明寫「鏈上發生時間」／「我方記錄時間」；前者可能為空，顯示 `—`；**篩選不得只依前者** | R18 |
| 地址匯入 | 送出前確認「N 筆 → 租戶 X」；結果頁三類統計 + **被拒逐筆清單（含原因）** + 明告「已成功不回滾」 | R8、E3 |
| 全體 vs 單台狀態 | **分區呈現**；單台區塊加註「此為回應本次查詢的伺服器狀態」 | R16 |
| 非本後台的變更 | 操作者欄顯示 `sys`、理由「非本後台操作」，**不得留空** | E9、E17 |
| 訂閱者停用 | 狀態顯示「已停用」，**不得顯示「已刪除」** | E15 |
| 併發編輯 | 後送出者提示「此資料已被他人變更」並重新載入，**不得靜默覆蓋** | E7 |
| 結果未知 | 提示「結果未確認，請重新查詢確認後再重試」，**不得自動重送**（不要用 axios retry 攔截器蓋掉變更類請求） | E2 |
| 服務端回報的限制 | 確認數範圍、重掃區間上界一律顯示**服務端回傳值**，前端不自訂；越界**不提供強制選項** | E8、E14 |

---

## 8. 不要做的事

| ❌ | 為什麼 |
|---|---|
| 用 Pinia 快取業務資料當事實來源 | 違反 R11；快取屬 OQ-9 待決，未決前不要做 |
| 裝 axios 全域 retry 攔截器 | 會把變更類請求也重送，違反 E2 |
| 用 Options API 或任何 Vue 2 寫法 | `web-frontend.md` §1 —— `web-reviewer` 的第一個 CRITICAL |
| 抄 `cx-sports` / `crypto-payment` 的 Vue 2 元件 | 那兩個專案是 Vue 2；觀念可參考，**程式碼不可直接抄** |
| 為 Out of Scope 的功能留路由或入口 | 業務客服介面、下游自助開通、監控儀表板皆已明確不做 |
| 自己算「全叢集是否切完」 | 服務端尚未提供逐台能力，猜就是編造 |
