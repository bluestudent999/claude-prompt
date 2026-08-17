---
name: invariant-check
description: 盤點 I1~I10 十條不變量的測試覆蓋狀況——哪些有測試、哪些是空的、哪些沒過。提交前、階段結束時，或想知道正確性防護到哪了時使用。
---

# invariant-check — 不變量測試覆蓋盤點

**用法：** `/invariant-check`（提交涉及不變量的變更前必跑；每個階段 P0~P5 結束時跑一次）

不變量是本系統**正確性的定義**。這個 skill 回答一個問題：**這 10 條，現在有幾條真的被測試守住了？**

---

## Step 1 · 搜集現有測試

```bash
echo "=== 整合測試檔 ==="
find src/test -name "*IT.java" | sort

echo "=== 兩租戶 fixture 是否存在 ==="
grep -rln "tenant-a\|tenant_a\|TENANT_A" src/test/ || echo "⚠️ 找不到兩租戶 fixture"

echo "=== 各不變量的關鍵字命中 ==="
grep -rn "rollback\|@Transactional" src/test/ | head          # I1
grep -rn "monotonic\|never_decrease\|last_block" src/test/    # I2
grep -rn "advisory\|pg_try_advisory\|concurrent_scanner" src/test/  # I3
grep -rn "ON CONFLICT\|duplicate\|unique" src/test/ src/main/resources/db/ | head  # I4/I5
grep -rn "rescan\|idempotent\|twice\|three_times" src/test/   # I6
grep -rn "confirmation\|depth\|receipt" src/test/             # I7
grep -rn "other_tenant\|cross_tenant\|belongs_to_another" src/test/  # I8/I9
grep -rn "rate_limit\|backfill\|p95\|latency" src/test/       # I10
```

---

## Step 2 · 實際執行

```bash
./mvnw -q test -Dtest='*IT' 2>&1 | tail -30
./mvnw -q test 2>&1 | grep -E "Tests run|FAIL" | tail -10
```

> **只確認測試檔存在是不夠的。** 空的測試、被 `@Disabled` 的測試、沒有斷言的測試都不算數。

---

## Step 3 · 產出盤點表

```markdown
## 不變量覆蓋盤點（<日期>）

| # | 不變量 | 對應測試（類別#方法） | 狀態 | 備註 |
|---|--------|---------------------|------|------|
| I1 | 單一資料庫事務 | `BlockWriterIT#should_rollback_all_when_event_write_fails` | ✅ PASS | |
| I2 | 高度單調遞增 | `ScanRangeCalculatorTest#should_never_decrease...` | ✅ PASS | |
| I3 | 每鏈單一寫入者 | — | ❌ 缺 | S13 尚未完成 |
| I4 | 交易唯一 | DB 約束 + `RescanIT#...` | ✅ PASS | |
| I5 | 事件唯一 | DB 約束 + `RescanIT#...` | ✅ PASS | |
| I6 | 重掃冪等 | `RescanIT#should_not_duplicate_when_rescanned_three_times` | ✅ PASS | |
| I7 | 確認深度 | `ScannerIT#should_emit_at_tenant_specific_depth` | ⚠️ @Disabled | 待 I7/D17 矛盾釐清 |
| I8 | 租戶隔離 | `PullApiIT#should_return_empty_when_cursor_belongs_to_other_tenant` | ✅ PASS | 兩租戶 fixture |
| I9 | 歸屬唯一 | DB 約束 + `WatchlistImportIT#should_reject_when_address_belongs_to_another_tenant` | ✅ PASS | |
| I10 | 負載隔離 | — | ❌ 缺 | S32（P5） |

**覆蓋：<n> / 10**

### 缺口與原因
| 不變量 | 缺口 | 是「尚未做到該步驟」還是「該做卻漏了」 |
|--------|------|----------------------------------|

### 兩租戶 fixture
- 狀態：✅ 已建立（`<檔案>`）/ ❌ 未建立
- 使用該 fixture 的整合測試：<n> / <總 IT 數>
```

---

## Step 4 · 判定

| 情境 | 處置 |
|------|------|
| 該步驟涉及的不變量**沒有對應測試** | **block 提交**。不變量沒測試等於沒實作 |
| 測試存在但 `@Disabled` | 視同缺口。要嘛啟用，要嘛在盤點表寫明停用理由與恢復條件 |
| 測試存在但沒有斷言 / 斷言不到位 | 視同缺口 |
| 尚未做到的步驟造成的缺口（如 I10 在 P5） | 正常，標「尚未做到該步驟」即可 |
| 整合測試**未使用兩租戶 fixture** | **block**。單租戶測不出隔離 bug |

---

## 判定紀律

**「尚未做到」與「該做卻漏了」必須分清楚。**

對照 `rules/invariants.md` 的「由哪些步驟保證」欄位：

- I10 由 S32 保證，現在做到 S18 → **正常缺口**，不擋。
- I8 由 S11 / S16 保證，現在做到 S18 卻沒測試 → **該做卻漏了**，擋。

盤點表若把兩者混為一談，這個 skill 就失去意義了——每次都看到「10 條缺 5 條」而無法判斷嚴重性。

---

## ⚠ I7 的特別處置

`rules/invariants.md` 末段記載了 I7 與 D17 的文件矛盾（I7 提到 `reorged`，但 D17 已取消 Reorg 且該事件已自契約移除）。

盤點時：
- 若 I7 的測試在驗證 `reorged` 行為 → **標為需修正**，那是照著已失效的描述寫的。
- I7 的有效部分是：達該租戶確認數才發事件 + 發出前 Receipt 重查一致。
- 這個矛盾**尚未由使用者裁決前**，I7 標 ⚠️ 而非 ❌，並在備註註明「待裁決」。
