---
name: vue2-coding-standards
description: Vue 2 + Element UI 前端程式碼規範 — 元件命名、Props 驗證、i18n、樣式、生命週期、事件通訊、表單驗證、目錄結構。在 cx-sports-v2 為跨 repo 編輯 lion-frontend 前端子專案時參考。
origin: ECC
---

# Vue 2 程式碼標準

> 適用：lion-frontend / manage-center 系列前端專案（Vue 2.x + Element UI + Webpack）。版本以各專案 `package.json` 為準。

---

## 1. 元件命名

| 位置 | 慣例 | 範例 |
|------|------|------|
| **檔名** | PascalCase | `GameStatisticList.vue`、`CommonSwitch.vue` |
| **name 屬性** | kebab-case 或 camelCase | `name: 'game-statistics'`、`name: 'CommonSwitch'` |
| **模板引用** | PascalCase | `<ExportGameStatisticReport />` |

---

## 2. Props 驗證

**一律使用完整定義**（type + default/required），不用簡寫陣列：

```javascript
// ✅ 正確
props: {
    data: {
        type: Array,
        required: true,
    },
    itemWidth: {
        type: Number,
        default: 100,
    },
    selectUser: {
        type: Object,
        default: () => ({}),
    },
}

// ❌ 錯誤
props: ['data', 'itemWidth']
```

---

## 3. i18n

<!-- TODO: 依專案選用一種 key 格式 -->

### 常見 key 格式

| 格式 | 範例 | 適用場景 |
|------|------|---------|
| 階層式 `m.模組.key` | `$t('m.statistics.betAmount')` | 模組明確、語意清楚 |
| 編號式 `C/S/D + 數字` | `$t('S030')`、`$t('C003')` | 集中管理、key 簡短 |

### 使用原則

- 模板中：`{{ $t('key') }}`
- 腳本中：`this.$t('key')`
- 新增 key 時**沿用該專案現有格式**，不混用
- 支援語系依專案設定（常見：`zh`、`en`、`vi`、`tw`）

---

## 4. 樣式

```vue
<!-- ✅ 正確：scoped + lang="scss" -->
<style lang="scss" scoped>
.container {
    .handle-box { ... }
}
</style>

<!-- ❌ 避免：全域樣式（除非在 assets/css/ 下的全域檔案） -->
<style>
.container { ... }
</style>
```

- 使用 **CSS 變數**（`var(--primary, #1d92ff)`）支援主題切換
- **BEM-like 巢狀**：用 SCSS `&` 語法組織

---

## 5. 生命週期 Hook

| Hook | 用途 | 頻率 |
|------|------|------|
| `created()` | 初始化資料、載入下拉選單、呼叫 API、註冊 `$bus` 事件 | 最常用 |
| `mounted()` | DOM 操作、第三方 lib 初始化 | 少用 |
| `beforeDestroy()` | 清理 `$bus.$off`、clearInterval | 有 `$bus.$on` 時必須 |

```javascript
created() {
    this.loadGames();
    this.getData();
    this.$bus.$on("event:name", this.handler);
},
beforeDestroy() {
    this.$bus.$off("event:name");
}
```

---

## 6. 事件通訊

| 機制 | 用途 | 範例 |
|------|------|------|
| `$emit` | 子 → 父元件通訊 | `this.$emit('change', value)` |
| `$bus` | 跨元件 / 兄弟元件通訊 | `this.$bus.$emit('collapse', msg)` |
| Vuex / Pinia | 全域狀態共享 | `this.$store.commit('setToken', token)` |

**規則：**
- `$bus.$on` **必須**在 `beforeDestroy` 中 `$bus.$off`
- 優先用 `$emit` + props，`$bus` 僅用於無直接父子關係的場景

---

## 7. 表單驗證

<!-- TODO: 依專案選用驗證方式 -->

### vee-validate 2.x

```vue
<input
    v-validate="'required'"
    name="account"
    :data-vv-as="$t('S001')"
    v-model.trim="form.account"
    :class="{ 's-error': errorBags.first('account') }"
/>
<div class="form__error-info">
    {{ errorBags.first('account') ? '*' + errorBags.first('account') : '' }}
</div>
```

### Element UI el-form rules

```vue
<el-form :model="form" :rules="rules" ref="formRef">
    <el-form-item prop="account">
        <el-input v-model="form.account" />
    </el-form-item>
</el-form>
```

---

## 8. 格式化設定

### Prettier（建議設定）

```json
{
    "tabWidth": 4,
    "printWidth": 160,
    "singleQuote": true,
    "semi": false,
    "trailingComma": "all",
    "bracketSpacing": true,
    "arrowParens": "always"
}
```

### EditorConfig

```
indent_style = space
indent_size = 4
end_of_line = lf
insert_final_newline = true
```

---

## 9. 目錄結構

<!-- TODO: 依專案實際結構調整 -->

```
src/
├── components/          # 可重用元件
│   ├── common/          # 全域共用元件
│   └── <module>/        # 按模組分目錄
├── views/               # 業務頁面（按功能分目錄）
├── router/              # 路由設定
├── store/               # 狀態管理（Vuex 或 Pinia）
├── i18n/                # 多語系設定
├── assets/              # 靜態資源
├── directives/          # 自訂指令
├── plugins/             # 外掛設定
└── util/                # 工具函式
```

---

## 10. 狀態管理

<!-- TODO: 依專案選用 -->

| 框架 | 適用場景 |
|------|---------|
| **Vuex** | Vue 2 傳統選擇，既有專案常見 |
| **Pinia** | Vue 2.7+ 可用，API 更簡潔，推薦新專案 |

**原則：** 沿用專案現有框架，不混用。
