---
name: fidelity-check
description: 盤點「規則實作跟 spec 對不對得起來」—— 有沒有標依據、spec 有沒有同步、有沒有第二份真實來源。動到玩法規則的提交前跑。
---

# fidelity-check — 依據追溯盤點

**用法：** `/fidelity-check`

回答一個問題：**我們寫出來的每條規則，都指得出 `plan/yummy/spec.md` 的哪一條嗎？**

對應 `spec.md` §1.1.3 的 **M-1 規則對拍一致率，目標 100%**。

> 這個 skill **不判斷規則訂得對不對**（那由你決定，見 `rules/plan-authority.md`），
> 只檢查**依據有沒有寫下來、文件與程式有沒有同步**。

---

## Step 1 · 有標依據的 vs 沒標的

```bash
echo "=== 有標 spec 編號的（好的）==="
grep -rnE "spec\.md|§1\.[0-9]|\bR-[0-9]+|\bE-[0-9]+|\bAC-[0-9]+" \
  --include="*.java" --include="*.ts" --include="*.vue" src/ web/ 2>/dev/null

echo "=== 判定引擎裡沒有任何編號的檔案（可疑）==="
for f in $(grep -rl "" --include="*.java" src/main/java 2>/dev/null | grep -iE "payline|payout|symbol|reel|jackpot|badge|bonus|freespin"); do
  grep -qE "R-[0-9]+|AC-[0-9]+" "$f" || echo "  無編號：$f"
done
```

---

## Step 2 · 反向查：程式做了 spec 沒寫的事

這一步最常被跳過，卻最容易發現問題。

```bash
echo "=== 本次改動的檔案 ==="
git diff --name-only HEAD

echo "=== 硬編的門檻／數量／上限（可能是沒寫進 spec 的規則）==="
grep -rnE "(>=|<=|==|>|<)\s*[0-9]{1,3}\b" --include="*.java" src/main/ \
  | grep -viE "test|log|index|size\(\)|length" | head -30
```

看到程式裡有 spec 沒提過的判斷 → **補進 spec**（`plan-authority.md` §2），不是刪掉它。

---

## Step 3 · 第二份真實來源

規則只能有一份，就是 `plan/yummy/spec.md`。

```bash
grep -rniE "賠率|paytable|線型|payline\s*=|符號表" .claude/ README.md 2>/dev/null
```

`.claude/` 或 README 出現規則內容 = 多了一份會過期的來源 → 刪掉，改成只標編號。

---

## Step 4 · spec 與 backlog 是否同步

```bash
echo "=== spec 的 AC 數 ==="
grep -cE "^\| *AC-[0-9]" plan/yummy/spec.md

echo "=== backlog 引用到的 AC ==="
grep -oE "AC-[0-9.]+" plan/yummy/backlog.md | sort -u | wc -l

echo "=== backlog 中標為受影響需重做的任務 ==="
grep -nE "⚠️|重做|標回" plan/yummy/backlog.md
```

改過 spec 卻沒更新 backlog 的「對應 AC」，或改了規則卻沒把受影響的已完成任務標回去 → 補上（`plan-authority.md` §3）。

---

## Step 5 · 產出盤點表

```markdown
## 依據追溯盤點（<日期>）

| 檢查 | 結果 |
|---|---|
| 玩法規則實作總數 | |
| 有 spec 編號 | |
| 編號實際對得上 | |
| 程式做了 spec 沒寫的事 | |
| 第二份真實來源 | |
| spec ↔ backlog 同步 | |

### 要補的項目
| 項目 | 位置 | 處置 |
|---|---|---|
| 徽章上限判斷無依據 | Badge.java:22 | 補進 spec §1.4.3，給 R 編號 |
```

---

## Step 6 · 判定

| 情況 | 處置 |
|---|---|
| 規則實作**指不出編號** | **block**，補編號或補 spec |
| 編號對不上內容 | **block** |
| 程式做了 spec 沒寫的事，且未補 spec | **block** |
| `.claude/` 或 README 抄了規則 | **block**，改成只標編號 |
| 規則有編號但沒有對拍測試 | **block**（`rules/testing.md` §2.1） |
| 規則與參考站不同但已標 `🔧 自訂` | **通過**。這是合法的自訂 |
| 本次未動玩法 | 直接通過，不硬找問題 |

---

## 判定紀律

**「還沒做到」與「做錯了」要分清楚。**

backlog 第 9 批的任務還沒開始 → 正常，不是缺口。
已完成任務的規則沒有依據 → 缺陷。

盤點表若把兩者混為一談，每次都看到一堆紅，就沒人會認真看了。
