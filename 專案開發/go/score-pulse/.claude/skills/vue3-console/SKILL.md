---
name: vue3-console
description: web/admin（總控與業主後台）的開工程序——確認 Vue 3 技術棧沒被 Vue 2 污染、取得該 ticket 的 AC、判定頁面落點、三態與權限自檢、Vitest 與後端 API 測試、重產 TypeScript client。做 B 類（後台前端）ticket 前載入。
---

# vue3-console — 後台前端開工程序

> 這不是 Vue 教學，也不複述 spec。畫面該長什麼樣 → 讀 ticket 的 Required Spec Sections。技術棧基準與 Vue 2 對照表 → `rules/web-frontend.md`。

---

## Step 1 · 確認技術棧沒被污染（最高頻的錯）

```bash
grep -n '"vue"\|element-plus\|element-ui\|pinia\|vuex\|vite' web/admin/package.json
grep -rn "element-ui\|vuex\|new Vue(\|\$listeners\|filters:\|\.sync\b\|Vue\.component(" --include=*.vue --include=*.ts --include=*.js web/admin/src/ | head
```

`vue` 應為 **3.x**、元件庫 **element-plus**、狀態 **pinia**。命中任何 Vue 2 寫法 → **停手回報**。公司有十幾個 Vue 2 + Element UI 後台在旁邊（cx-sports、lion-*、crypto-payment），**觀念可參考，程式碼不可直接抄**。

## Step 2 · 取得驗收依據

```bash
T=S4-T8
grep -n "^## 驗收條件" -A 12 plan/on-sports-lite/tickets/$T.md
grep -n "^## 只讀這幾節" -A 2 plan/on-sports-lite/tickets/$T.md
grep -n "^## 部門分工" -A 4 plan/on-sports-lite/tickets/$T.md
```

AC 就是完成的定義，也是 `web-reviewer` 的依據。只讀指定的 spec 節。

## Step 3 · 判定頁面落點

| ticket 說的 | 落點 | 路由前綴 | API 前綴 | 登入身分 |
|------|------|---------|---------|---------|
| 總控、平台人員、「管理全部業主／僅指派的業主」 | 總控後台 | `/admin/**` | `/api/admin/**` | 總控帳號 + TOTP |
| 業主、「自己的站點」、業主後台 | 業主後台 | `/operator/**` | `/api/operator/**` | 業主後台帳號 + TOTP |
| 兩套都有（角色權限、帳號、操作記錄） | 共用元件 + 兩條路由 | 兩者 | 兩者 | 各自 |

後台介面**只做中文**（dept-assignment 預設 1），不接 5 語系；會員看得到的內容（App 更新說明、熱門清單名稱）是**資料**不是介面字串。

## Step 4 · 實作中的自檢

| 問句 | 抓的是 |
|------|--------|
| 「取得失敗」和「確實沒有」在畫面上分得出來嗎？ | 把 API 失敗渲染成空清單（E 類最常見） |
| 這個清單是後端依租戶範圍過濾的，還是取全部再前端 filter？ | 範圍外資料已到瀏覽器（I1） |
| 無權限模組是「選單不顯示 + 直接開網址顯示『你沒有這個模組的權限』」兩件都做了嗎？ | Spec-4 R1–R8、AC-11 |
| 有查看無管理的頁面，可操作欄位（含匯出）顯示鎖頭了嗎？ | Spec-4 R60 |
| session token 落到 localStorage／網址／log 了嗎？ | 憑證不落地 |
| 危險操作（停用業主、刪角色、退回審核）有二次確認且原因必填嗎？ | Spec-1 R38、Spec-4 R81 |
| 匯出是後端產檔、前端只拿連結嗎？ | 匯出等待上限 OQ-41 |

## Step 5 · 測試

每個頁面至少三個 Vitest 案例（載入中、空狀態、錯誤狀態）+ 每條 AC 一個；對應的後端 API 必須已有單元測試（`rules/testing.md` §1）：

```bash
cd web/admin && npx vitest run src/views/<page>/   # 三態 + AC
cd - && ls internal/admin/controller/*_test.go      # 後端 API 測試存在
```

## Step 6 · 重產 TypeScript client（API 變更後）

```bash
bash .claude/skills/contract-export/contract-export.sh
cd web/admin && npx openapi-typescript ../../docs/contract/openapi-admin.yaml -o src/api/schema.d.ts
```

手寫 `fetch` 繞過 client → `web-reviewer` HIGH。

## 完成前

- 逐條對映 AC 自檢，不是對映本 skill。
- 派 `web-reviewer`。
- 回報格式與 `/ticket-run` Step 7 相同，另加「落點：總控／業主／共用」與「三態測試：PASS」。

**下一步執行** `/ticket-run` Step 5 審查（派 `web-reviewer` 與 `code-reviewer`）
