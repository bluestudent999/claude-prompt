# Check：@Transactional 邊界

> **適用 reviewer**：`java-reviewer`（結構）/ `business-reviewer`（一致性後果）
> **severity**：CRITICAL（自呼叫導致金額路徑事務失效）/ HIGH（其餘）
> **confidence 上限**：單檔可見 → 無上限；需追 caller 才能判斷自呼叫 → ≤ 80
> **規範**：`rules/patterns.md`、`reviewer-checklists.md` §java-reviewer

事務問題的共同特徵是**靜默** —— 不拋例外、不留 log，只在事後對帳時發現資料不一致。

## 1. 同類自呼叫 → CRITICAL（金額路徑）/ HIGH（其他）

```bash
grep -nB3 -A3 '@Transactional' <file>
# 再搜同一 class 內是否有 this.<method> 或直接呼叫該 method
grep -nE 'this\.<method>|(^|[^.\w])<method>\(' <file>
```

Spring AOP 走 proxy，同類內部呼叫不經過 proxy，`@Transactional` **完全不生效**。金額異動 + 寫流水在同一方法內卻沒有事務保護 → 失敗時只寫了一半。

## 2. 標在非 public 方法 → HIGH

```bash
grep -nA2 '@Transactional' <file> | grep -E 'private|protected'
```

proxy 不攔截，同樣靜默失效。

## 3. 事務內含遠端呼叫 → HIGH

```bash
grep -nA40 '@Transactional' <file> | grep -nE 'restTemplate\.|feignClient|FeignClient|webClient\.|HttpUtil|kafkaTemplate\.send|redisTemplate\.opsFor|\.execute\('
```

兩個後果：

- 遠端呼叫慢 / 超時 → DB 連線被長期占用 → HikariCP 連線池耗盡，影響整個服務
- 遠端呼叫成功但 DB rollback → 對方已扣款 / 已發送，本地卻沒紀錄（dual-write 不一致）

**本專案高風險位置**：三方支付、單一錢包轉帳、三方遊戲登入 / 轉帳。

## 4. checked exception 缺 rollbackFor → HIGH

```bash
grep -nA5 '@Transactional' <file> | grep -E 'throws \w+Exception'
grep -nE '@Transactional(?!.*rollbackFor)' <file>
```

Spring 預設只對 `RuntimeException` rollback。宣告 checked exception 又沒設 `rollbackFor = Exception.class`，例外發生時事務**靜默 commit**。

## 5. 事務內做 cache 失效 / 發事件 → MEDIUM

事務尚未 commit 就清 cache 或發通知，其他執行緒可能讀到舊資料再回填 cache。本專案已有 `cacheNotifyService.notifyOneAfterTransaction` 這類 AFTER_COMMIT 機制，未使用者標 MEDIUM。

## 反例（不要報）

- caller 已在事務內、本方法為其一部分且**只有這一個 caller** → 加 `@Transactional` 是冗餘，不要建議加（見 `agents.md` §主 agent 對 reviewer finding 的判斷責任）
- 唯讀查詢方法沒有 `@Transactional` → 不報
- `@Transactional(readOnly = true)` 內有遠端呼叫 → 降為 LOW（無寫入不一致風險，僅連線占用）

## Fix 方向

- 自呼叫：拆到另一個 bean，或注入自身 proxy
- 遠端呼叫移出事務：先完成 DB 事務 → commit 後再呼叫；或用 `TransactionSynchronization` AFTER_COMMIT
- checked exception：`@Transactional(rollbackFor = Exception.class)`
