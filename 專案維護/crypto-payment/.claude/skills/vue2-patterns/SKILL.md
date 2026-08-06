---
name: vue2-patterns
description: Vue 2 前端開發模式 — API 呼叫（axios）、Session/Auth、下拉選單、表格分頁、排序、日期範圍、金額格式化、密碼加密、路由、角色判斷、報表頁標準結構。編輯 crypto-payment 後台前端 front/crypto-payment-admin-frontend 時參考。
origin: ECC
---

# Vue 2 開發模式

> 適用：`front/crypto-payment-admin-frontend`（Vue 2 + Element UI + Vuex + Webpack 3）。具體 API 路徑與 i18n key 格式以專案為準。
> API 走集中式 Axios 實例 `src/utils/request.js`（下方以 `this.$axios` 示意，實際呼叫請引用該實例）。

Vue 2 前端專案的共用開發模式。涵蓋 API 呼叫、認證、表格、篩選器、金額格式化等常見場景的標準寫法。

---

## 1. API 呼叫模式

### 標準 POST（帶 loading + 錯誤處理）

```javascript
getData() {
    this.loading = true;
    this.$axios.post('/api/module/action', {
        ...this.queryParam
    }).then(response => {
        this.loading = false;
        if (response.data.success) {
            this.tableData = response.data.rows;
            this.totalCount = response.data.total;
        } else {
            this.$message.error(response.data.msg);
        }
    }, response => {
        this.loading = false;
        this.$message.error(response.data.msg);
    });
}
```

### 標準 GET

```javascript
this.$axios.get('/api/module/resource').then(
    res => {
        if (res.data.success) {
            this.list = res.data.rows;
        } else {
            this.$message.error(res.data.msg);
        }
    }, response => {
        console.error(response);
    }
);
```

### 靜默呼叫（不觸發全域 loading）

```javascript
this.$axios.get('/api/module/resource', { suppressLoading: true }).then(...)
```

<!-- TODO: 依專案填入 API 路徑對應表 -->
<!--
### API 路徑對應

| 前端路徑 | 後端 Controller |
|----------|----------------|
| `/api/xxx/*` | `/api/xxx/*` |
-->

---

## 2. Session / Auth 模式

### Token 存取

```javascript
// 取得完整 token info
const tokenInfo = this.$session.getTokenInfo();
// 常用屬性：platformId, queryCode, userId, userType, userName, token

// 設定 token（登入後）
this.$session.setTokenInfo(res.data.t);
```

### 儲存機制

- **token**：存 Cookie（`vue-cookies`）
- **其餘資訊**：存 `localStorage`（`tokenInfo`）

### Axios Request Header 自動注入

```javascript
// axiosInterceptors 中自動處理
config.headers['x-session-token'] = tokenInfo.token;
config.headers['x-lang'] = lang;
// TODO: 依專案補充其他 header
```

### HTTP 狀態處理

- **401**：自動跳轉登入頁
- **403**：跳轉 403 錯誤頁

---

## 3. 下拉選單載入模式

### 標準模式：API 載入 + unshift 預設值

```javascript
loadOptions() {
    this.$axios.get('/api/module/options').then(
        res => {
            if (res.data.success) {
                this.optionList = res.data.rows;
                // 在最前面加入「全部」選項
                this.optionList.unshift({ id: "", name: this.$t('common.all') });
            }
        }
    );
}
```

### 模板

```vue
<el-select filterable default-first-option reserve-keyword
           v-model="queryParam.selectedId"
           :placeholder="$t('common.pleaseSelect')">
    <el-option v-for="item in optionList"
               :key="item.id" :label="item.name" :value="item.id" />
</el-select>
```

### 重點

- `filterable`：啟用搜尋
- `default-first-option`：Enter 選中第一個匹配
- `reserve-keyword`：選中後保留搜尋文字
- `unshift` 的預設值 `id/value` 用空字串 `""`，讓後端視為不篩選

---

## 4. 表格分頁模式

### 前端分頁（資料量小，一次取回）

```javascript
computed: {
    data() {
        return this.tableData.slice(
            (this.page - 1) * this.pageSize,
            this.page * this.pageSize
        );
    }
},
methods: {
    handleCurrentChange(val) {
        this.page = val;
    },
    handleSizeChange(val) {
        this.pageSize = val;
    },
}
```

### 後端分頁（資料量大）

```javascript
getData() {
    this.queryParam.page = this.page;
    this.queryParam.pageSize = this.pageSize;
    this.$axios.post('/api/module/query', this.queryParam).then(response => {
        this.tableData = response.data.rows;
        this.totalCount = response.data.total;
    });
},
handleCurrentChange(val) {
    this.page = val;
    this.getData();
},
```

### el-pagination 模板

```vue
<el-pagination
    :current-page.sync="page"
    @current-change="handleCurrentChange"
    :page-size="pageSize"
    layout="total, sizes, prev, pager, next, jumper"
    @size-change="handleSizeChange"
    :total="totalCount"
/>
```

---

## 5. 表格排序模式

```vue
<el-table @sort-change="sortChange">
    <el-table-column prop="amount" sortable="custom" />
</el-table>
```

```javascript
sortChange(obj) {
    this.queryParam.orderField = obj.prop;
    this.queryParam.sort = obj.order == 'ascending';
    this.getData();
}
```

**注意：** `sortable="custom"` 表示後端排序；不加 `custom` 是前端排序。

---

## 6. 日期範圍選擇器模式

### 模板

```vue
<el-date-picker
    v-model="timeRange"
    type="daterange"
    range-separator="~"
    value-format="yyyy-MM-dd"
    format="yyyy-MM-dd"
    :picker-options="pickerOptions"
    style="width: 100%;"
/>
```

### Data

```javascript
data() {
    return {
        timeRange: [],
        pickerOptions: {
            disabledDate(time) {
                return time.getTime() > Date.now();  // 不能選未來
            },
            shortcuts: []
        },
    }
},
created() {
    this.timeRange = [
        this.$moment().add(-1, "days").format("YYYY-MM-DD"),
        this.$moment().format("YYYY-MM-DD")
    ];
}
```

### 查詢時轉換

```javascript
if (this.timeRange && this.timeRange.length === 2) {
    this.queryParam.startTime = this.$moment(this.timeRange[0]).format('YYYY-MM-DD');
    this.queryParam.endTime = this.$moment(this.timeRange[1]).format('YYYY-MM-DD');
} else {
    this.$message.error(this.$t('common.enterCorrectTime'));
    return;
}
```

---

## 7. 金額格式化

### 表格列 formatter

```vue
<el-table-column prop="amount" :formatter="$utils.moneyFormatterCell" />
```

### 工具函式（`util/utils.js`）

```javascript
// 千分位格式化
moneyFormatterCell(row, column, cellValue, index) {
    return isNaN(parseFloat(cellValue)) ? '-' : formatMoney(cellValue);
}
```

---

## 8. 密碼加密

<!-- TODO: 依專案確認加密方式（MD5 / SHA256 / 其他） -->

**自動加密**：Axios interceptor 中自動偵測欄位名含 `password` 或 `pwd`，自動加密。

```javascript
// axiosUtils.js / main.js
for (let key in copiedData) {
    if (key.toLowerCase().includes('password') || key.toLowerCase().includes('pwd')) {
        copiedData[key] = encrypt(copiedData[key]);
    }
}
```

**不需手動加密**，只要欄位命名正確即可。

---

## 9. 路由設定模式

<!-- TODO: 依專案選用一種 -->

### 模組化分檔 + require 懶加載

```javascript
// router/moduleRouter.js
export default {
    router: [
        {
            path: '/page-name',
            name: 'page-name',
            component: resolve => require(['../components/Module/PageName.vue'], resolve),
            meta: { title: 'i18n.key', requireAuth: true }
        },
    ]
}
```

### 單檔 + import() 懶加載

```javascript
// router/index.js
{
    path: 'page-name',
    name: 'page-name',
    component: () => import('@/views/Module/PageName'),
    meta: {
        title: 'i18n.key',
        keepAlive: true,
    },
}
```

---

## 10. 角色判斷模式

### 前端判斷

```javascript
const tokenInfo = this.$session.getTokenInfo();
const isAdmin = tokenInfo.userType === 'ADMIN';
```

### 結合 UI 控制

```vue
<el-col v-if="hasPermission">
    <el-select v-model="queryParam.filter">...</el-select>
</el-col>
```

**原則：** 前端控制 UI 顯示，後端強制資料範圍。兩端都要做，不能只靠前端。

---

## 11. 報表頁面標準結構

```vue
<template>
    <div class="container">
        <!-- 篩選區 -->
        <div class="handle-box">
            <el-row :gutter="5">
                <!-- 篩選元件：Radio / Select / DatePicker / Button -->
            </el-row>
        </div>
        <!-- 表格區 -->
        <div class="container">
            <el-table :data="data" border v-loading="loading" @sort-change="sortChange">
                <!-- columns -->
            </el-table>
            <!-- 分頁 -->
            <div class="pagination">
                <el-pagination ... />
            </div>
        </div>
    </div>
</template>

<script>
export default {
    data() {
        return {
            queryParam: { /* 篩選參數 */ },
            timeRange: [],
            tableData: [],
            page: 1,
            totalCount: 0,
            loading: false,
            pageSize: 10,
        }
    },
    created() {
        // 1. 初始化日期範圍
        // 2. 載入下拉選單資料
        // 3. 首次查詢 getData()
    },
    computed: {
        data() { /* 前端分頁 slice */ }
    },
    methods: {
        search() { this.page = 1; this.getData(); },
        getData() { /* API 呼叫 */ },
        handleCurrentChange(val) { this.page = val; },
        handleSizeChange(val) { this.pageSize = val; this.getData(); },
        sortChange(obj) { /* 排序 */ },
    }
}
</script>
```

---

## 12. Enum-driven UI 顯示模式

UI 顯示 enum 值前，**必先 grep 完整 enum 定義**，對每個值都應有 case 或 fallback。

```bash
# Java 後端 enum（base package com.lion.crypto）
grep -rn "enum <Name>\s*{" crypto-payment-service/src/main/java/
```

### 範例（以入款狀態為例）

```vue
<!-- ❌ 抄某個 caller 局部邏輯，漏其他狀態 -->
<el-tag v-if="status === 0">待確認</el-tag>
<el-tag v-else-if="status === 1">已確認</el-tag>
<el-tag v-else-if="status === 5">失敗</el-tag>
<!-- status === 2/3/4 時 UI 空白 -->

<!-- ✅ cover 完整 enum + fallback -->
<el-tag v-if="status === 0" type="info">待確認</el-tag>
<el-tag v-else-if="status === 1" type="success">已確認</el-tag>
<el-tag v-else-if="status === 2" type="success">已入帳</el-tag>
<el-tag v-else-if="status === 3" type="info">歸集中</el-tag>
<el-tag v-else-if="status === 4" type="warning">已歸集</el-tag>
<el-tag v-else-if="status === 5" type="danger">失敗</el-tag>
<el-tag v-else>-</el-tag>
```

### 頁面限定子集時

業務語意只可能出現特定子集 → 註解原因 + 異常 fallback：

```vue
<!-- 此頁限定 status 0/1；其他值屬資料異常 -->
<el-tag v-if="status === 0">待確認</el-tag>
<el-tag v-else-if="status === 1">已確認</el-tag>
<el-tag v-else type="danger">unknown ({{status}})</el-tag>
```

### Code review 檢查點

- enum case 數 vs Java enum 定義數一致
- 漏的 case 有註解說明為什麼不該出現
- 必有 `v-else` fallback
- 共用子組件（≥ 2 caller）→ cover 全集，不靠 caller 保證範圍
