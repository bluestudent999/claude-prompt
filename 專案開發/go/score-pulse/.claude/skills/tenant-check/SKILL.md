---
name: tenant-check
description: 動到租戶表、認證、Host 解析、總控指派範圍或 WebSocket 握手時跑——盤點本次 diff 的每個 dao 查詢是否經 tenant.Scope、有無呼叫端可控 operator_id、雙租戶 fixture 是否被用，輸出「租戶過濾盤點」表。派 tenant-isolation-reviewer 之前使用。
---

# tenant-check — 租戶過濾盤點

**用法：** `/tenant-check`（對當前工作樹 diff）或 `/tenant-check <commit-range>`

這不是 reviewer，是**你自己先盤一遍**，讓 `tenant-isolation-reviewer` 拿到盤點表而不是從零掃。規則見 `rules/tenant-isolation.md`。

---

## Step 1 · 列出本次碰到的查詢

```bash
RANGE="${1:-HEAD}"
git diff --name-only "$RANGE" -- 'internal/*/dao/*.go' 'internal/*/service/*.go' 'internal/*/controller/*.go' 'internal/realtime/*.go' | grep -v _test.go
# 每個 dao 檔的查詢點
git diff "$RANGE" -- 'internal/*/dao/*.go' | grep -nE '^\+.*(\.Where\(|\.Find\(|\.First\(|\.Take\(|\.Scan\(|\.Count\(|\.Updates?\(|\.Delete\(|\.Create\(|Raw\()'
# 是否經 Scope
git diff "$RANGE" -- 'internal/*/dao/*.go' | grep -nE '^\+.*tenant\.(Scope|AdminScope|AllOperators)\('
```

## Step 2 · 找呼叫端可控的租戶 id

```bash
git diff "$RANGE" -- 'internal/*/dto/*.go' | grep -niE '^\+.*(operator_?id|OperatorID|platform_?code)'
git diff "$RANGE" -- 'internal/*/controller/*.go' | grep -niE '^\+.*(Query\("operator|operatorId|x-session-platform-code)'
```

命中 → 那是越權入口。租戶 id 只能來自 `tenant.FromCtx(ctx)`（前台）或 `auth` 的 principal（後台）。總控選單站：`admin` 包的 `AssignedScope(ctx)` 驗證後才放行。

## Step 3 · 表的歸屬

對每個被碰到的 `model.<Table>`，查它在 `rules/tenant-isolation.md` §2 哪一欄：

```bash
grep -n "<Table 對應的表名>" .claude/rules/tenant-isolation.md .claude/rules/architecture.md
```

不在任一欄 → 新表沒登記。先決定歸屬並回寫兩份 rules（同一個 commit），再往下。

## Step 4 · 測試用了雙租戶嗎

```bash
git diff --name-only "$RANGE" -- '*_test.go' | xargs grep -lE 'fixtures\.(OpA|OpB)|op-a|op-b' 2>/dev/null
git diff --name-only "$RANGE" -- '*_test.go' | xargs grep -LE 'OtherTenant|AssignedScope|TokenMismatch' 2>/dev/null   # 缺越權案例的測試檔
```

租戶端點的測試必含（`tenant-isolation.md` §5）：以 A 取 B 的資源 → 404／空；A 的業主後台取 B 的設定 → 404；只指派 A 的總控看匯總 → 只有 A；停用 B → A 不受影響、B 的 WebSocket 被拒。

## Step 5 · 本專案容易漏的地方（逐項確認）

| 地方 | 要看什麼 |
|------|---------|
| 搜尋 | 「最近搜尋」是會員的（租戶），聯賽／球隊是共用的；同一 service 兩種表要分開 Scope |
| 熱門內容 | 平台預設份共用、業主覆蓋租戶；合併時覆蓋份有沒有 Scope |
| 通知觸發 | consumer 的 ctx 沒有租戶；逐業主迭代時每一輪都要帶各自的 ctx |
| 匯出 | 檔名、內容、總計都只含該業主 |
| WebSocket | `/operator/{op}/member/{id}/notice` 的 `{op}` 是否與握手業主比對 |
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
