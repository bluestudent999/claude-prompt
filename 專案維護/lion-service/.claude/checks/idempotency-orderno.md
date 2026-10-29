# Check：冪等與併發保護

> **適用 reviewer**：`business-reviewer`（L1 場景 model=opus）
> **severity**：CRITICAL（金額路徑）/ HIGH（非金額路徑）
> **confidence 上限**：需確認 DB 唯一鍵是否存在 → ≤ 70（要查 migration / schema 才算數）
> **規範**：`rules/patterns.md` §併發、`reviewer-checklists.md` §business-reviewer

第三方回調重送、使用者連點、MQ 重投都會造成同一筆業務被執行兩次。金額路徑重複執行 = 重複派彩 / 重複加款。

## 1. 寫入金額但無唯一鍵去重 → CRITICAL

```bash
# 找金額異動進入點
grep -nE '(addMoney|subMoney|changeMoney|updateBalance|payout|派彩|加款|扣款)' <file>
# 確認是否有 orderNo / transactionNo / 業務單號參與去重
grep -nE 'orderNo|orderId|transactionNo|serialNo|billNo' <file>
```

**判定**：金額異動方法的入參中沒有業務單號，或有單號但沒有任何 `select ... where orderNo=` / 唯一索引攔截 → CRITICAL。

**必須查證**：唯一鍵是否真的存在於 schema。只看到 code 有 `orderNo` 欄位不代表 DB 有 unique index。

```bash
grep -rn "UNIQUE\|unique key\|uk_" cp-flyway/src/main/resources/db/migrations/ zz_document/script/changelog/ | grep -i <table>
```

查不到就標 confidence ≤ 70 並在 issue 註明「未能確認唯一索引」。

## 2. 先查後寫但無鎖 → CRITICAL

```bash
grep -nB5 -A15 'selectBy\|getBy\|queryBy' <file> | grep -nE 'update|insert|save'
```

`if (查不到) { 寫入 }` 這種 check-then-act 在併發下兩個執行緒會同時通過檢查。**必須**有下列其一：

- Redis 分散式鎖（本專案 `@AccessLimit` 或顯式鎖）
- DB `SELECT ... FOR UPDATE`
- DB 唯一索引 + catch `DuplicateKeyException`

三者皆無 → CRITICAL。

## 3. 鎖的粒度錯誤 → HIGH

鎖 key 沒帶上區分業務的維度（例：只鎖 `userId` 但同一使用者可並行多筆不同訂單，或反過來鎖全域造成串行）→ HIGH。

## 4. 鎖範圍未覆蓋整個臨界區 → HIGH

```bash
# 確認鎖的釋放點是否在寫入完成之後
grep -nA30 'lock\|tryLock\|@AccessLimit' <file>
```

先釋放鎖再寫 DB，等同沒鎖。

## 5. 事務與鎖的順序 → HIGH

鎖在 `@Transactional` **內部**取得 → 事務先開啟、鎖後取得，其他執行緒可能在本執行緒 commit 前就拿到鎖讀到舊資料。正確順序是**先取鎖、再開事務**。

## 反例（不要報）

- 純查詢介面 → 不需冪等
- 已有唯一索引且 code 明確 catch 重複鍵 → 這就是正確做法，不要因為「沒看到分散式鎖」而報
- 冪等由上游閘道保證且有註解說明 → 降為 LOW

## Fix 方向

- 金額路徑：業務單號 unique index（DB 層兜底）+ 應用層先查
- check-then-act：改 `INSERT ... ON DUPLICATE KEY` 或 `SELECT FOR UPDATE`
- 順序：取鎖 → 開事務 → 查 → 寫 → commit → 釋放鎖
