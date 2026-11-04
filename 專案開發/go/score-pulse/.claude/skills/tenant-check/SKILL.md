---
name: tenant-check
description: 動到租戶表、認證、Host 解析、總控指定業主（ManageTarget）、業主後台業主注入（MustPlatform）或 WebSocket 握手時跑——盤點本次 diff 的每個 dao 查詢是否經 tenant.Scope、有無呼叫端可控的業主代碼（platform_code）、雙租戶 fixture 是否被用，輸出「租戶過濾盤點」表。派 tenant-isolation-reviewer 之前使用。
---

# tenant-check — 租戶過濾盤點

**用法：** `/tenant-check`，或 `bash scripts/tenant-check.sh . [基準]`（`make tenant-check [BASE=<commit>|--all]` 同義）。基準省略 → 與 `origin/developing` 的分叉點（含已 commit、未 commit、未追蹤）；`--all` 盤全部 dao。

> 腳本在 repo 的 `scripts/`（進版控，CI 與 Makefile 同一份）；本目錄只放說明。改檢查規則請改 `scripts/` 並隨 ticket 提交。

腳本自動做下面 Step 1、2、4 與 Step 3 的「未登記 model」判定，輸出盤點表；「租戶表 + 無範圍」或「呼叫端可控租戶 id」離開碼 1。以下手動指令留作補掃。

這不是 reviewer，是**你自己先盤一遍**，讓 `tenant-isolation-reviewer` 拿到盤點表而不是從零掃。規則見 `rules/tenant-isolation.md`。

---

## Step 1 · 列出本次碰到的查詢

```bash
RANGE="${1:-HEAD}"
git diff --name-only "$RANGE" -- 'internal/*/dao/*.go' 'internal/*/service/*.go' 'internal/*/controller/*.go' 'internal/realtime/*.go' | grep -v _test.go
# 每個 dao 檔的查詢點
git diff "$RANGE" -- 'internal/*/dao/*.go' | grep -nE '^\+.*(\.Where\(|\.Find\(|\.First\(|\.Take\(|\.Scan\(|\.Count\(|\.Updates?\(|\.Delete\(|\.Create\(|Raw\()'
# 是否經 Scope
git diff "$RANGE" -- 'internal/*/dao/*.go' | grep -nE '^\+.*tenant\.(Scope|AllPlatforms|ManageRows|SelfScope)\('
```

## Step 2 · 找呼叫端可控的租戶 id

```bash
git diff "$RANGE" -- 'internal/*/dto/*.go' | grep -niE '^\+.*(platform_?code|PlatformCode)'   # 請求 SO 才算；回應 VO 給畫面顯示可以
git diff "$RANGE" -- 'internal/*/controller/*.go' | grep -niE '^\+.*(Query\("platform|platformCode|x-session-platform-code)'
```

命中 → 那是越權入口。租戶 id 只能來自 `tenant.FromCtx(ctx)`（前台）或 `auth` 的 principal（後台）。總控指定單一業主：`auth.ManageTarget(ctx, code)` 驗證後才放進 ctx；業主後台讀業主只用 `auth.MustPlatform(ctx)`。

## Step 3 · 表的歸屬

對每個被碰到的 `model.<Table>`，查它在 `rules/tenant-isolation.md` §2 哪一欄：

```bash
grep -n "<Table 對應的表名>" .claude/rules/tenant-isolation.md .claude/rules/architecture.md
```

不在任一欄 → 新表沒登記。先決定歸屬並回寫兩份 rules（同一個 commit），再往下。

## Step 4 · 測試用了雙租戶嗎

```bash
git diff --name-only "$RANGE" -- '*_test.go' | xargs grep -lE 'fixtures\.(PlatformA|PlatformB)|op-a|op-b' 2>/dev/null
git diff --name-only "$RANGE" -- '*_test.go' | xargs grep -LE 'OtherTenant|TokenMismatch' 2>/dev/null   # 缺越權案例的測試檔
```

租戶端點的測試必含（`tenant-isolation.md` §5）：以 A 取 B 的資源 → 404／空；A 的業主後台取 B 的設定 → 404；一般總控人員持有代碼看業主列表 → A、B 都在；A 的業主後台身分帶 B 的代碼 → 只有 A；停用 B → A 不受影響、B 的 WebSocket 被拒。

## Step 5 · 本專案容易漏的地方（逐項確認）

| 地方 | 要看什麼 |
|------|---------|
| 搜尋 | 「最近搜尋」是會員的（租戶），聯賽／球隊是共用的；同一 service 兩種表要分開 Scope |
| 熱門內容 | 平台預設份共用、業主覆蓋租戶；合併時覆蓋份有沒有 Scope |
| 通知觸發 | consumer 的 ctx 沒有租戶；逐業主迭代時每一輪都要帶各自的 ctx |
| 匯出 | 檔名、內容、總計都只含該業主 |
| WebSocket | `/platform/{code}/member/{id}/notice` 的 `{code}` 是否與握手業主代碼比對 |
| 操作記錄 | 業主後台只看自己的；總控看全部 |

## 輸出：租戶過濾盤點表（貼進 plan §8 或 reviewer briefing）

```
### 租戶過濾盤點（<ticket>）
| 查詢 / 端點 | 位置（檔案:行） | 表 | 歸屬（租戶 / 共用） | 有無 Scope | 範圍來源（ctx / 認證 / 參數） |
|---|---|---|---|---|---|
| ListFavorites | internal/member/dao/favorite.go:42 | favorite | 租戶 | Scope | ctx |
...
越權案例測試：<檔案與函式名> / 缺：<...>
呼叫端可控租戶 id：無 / <位置>
```

任何一列「租戶 + 無 Scope」或「參數」→ 自己先修，再派 reviewer。

**下一步執行** 派 `tenant-isolation-reviewer`（盤點表作為 briefing）
