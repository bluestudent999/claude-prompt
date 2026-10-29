# Reviewer Checklists

> 各 reviewer 的審查重點清單。`scripts/generate_reviewer_briefing.py` 從本檔抽取對應段落注入 briefing；主 agent 派 reviewer 時 briefing 只需引用本檔路徑 + 章節名，**禁止整段複製**。
>
> 維護原則：每條規則 ≤ 1 行，引用對應 rules 檔的詳細出處。
>
> **Severity / confidence**：所有 finding 的分級與信心度一律依 [`severity-rubric.md`](./severity-rubric.md)，reviewer 不得自訂標準。
> **標 🔬 的項目**有對應的原子 check 檔（含 grep 指令、判定規則、反例、fix 方向），位於 [`.claude/checks/`](../checks/) —— reviewer 執行該項時**必須先 Read 對應 check 檔**再下判斷，不要憑印象。

---

## code-reviewer

通用程式碼品質、可讀性、安全性首道防線。

- [ ] 命名遵守 VO / SO / BO / Query / Record / Event 慣例，禁 DTO / Request / Entity（見 `rules/patterns.md` §8）
- [ ] Log 英文、等級正確（info / error 為主，warn 限定，debug / trace 上線禁用）（見 `rules/coding-style.md` §4）
- [ ] Magic number / string 抽常數
- [ ] 不可變性優先：能 `final` 就 `final`
- [ ] 空值處理用 `Optional` / 明確 null check，不放任 NPE
- [ ] **短名規則**：禁用 FQCN，必須 `import` 後使用短名（見 `rules/coding-style.md` §3）
- [ ] 🔬 例外不吞 → [`checks/silent-failure.md`](../checks/silent-failure.md)（空 catch、回預設值掩蓋錯誤、忽略 DAO 影響筆數、log 缺上下文）
- [ ] 移除欄位 / 方法 → 確認所有引用點已清理

---

## java-reviewer

Spring Boot 框架模式深度審查。

- [ ] DI 用 `@RequiredArgsConstructor` 建構子注入（新程式碼）
- [ ] 分層：Controller → Service → Connector / DAO，不可跨層
- [ ] Lombok：`@Data` / `@Getter` / `@Setter` 使用得當，model 加 `@EqualsAndHashCode(callSuper = true)`
- [ ] 🔬 `@Transactional` 邊界 → [`checks/transactional-remote-call.md`](../checks/transactional-remote-call.md)（自呼叫 / 非 public / 事務內遠端呼叫 / rollbackFor）
- [ ] Java 8 Stream pipeline ≤ 3 步驟，超過抽方法
- [ ] `Optional` 用於可能為 null 的回傳值，不濫用於欄位
- [ ] Bean 命名 / package 命名遵守 `rules/patterns.md` 與 `skills/package-structure`
- [ ] 例外策略：用既有 framework Exception，不自定散落（見 `rules/patterns.md`）

---

## business-reviewer

業務邏輯正確性 — 金額 / 狀態機 / 第三方對接。**L1 場景主 agent 須帶 `model=opus`**。

- [ ] 🔬 **金額精度** → [`checks/bigdecimal-rounding.md`](../checks/bigdecimal-rounding.md)（`double` 運算、divide 未指定 RoundingMode、方向錯誤、equals 比較）
- [ ] 🔬 **狀態機** → [`checks/state-machine-transition.md`](../checks/state-machine-transition.md)（UPDATE 未帶前置狀態、影響筆數未檢查、新增 enum 漏補分支）
- [ ] 🔬 **冪等與併發** → [`checks/idempotency-orderno.md`](../checks/idempotency-orderno.md)（唯一鍵去重、check-then-act 無鎖、鎖與事務順序）
- [ ] 🔬 **事務邊界** → [`checks/transactional-remote-call.md`](../checks/transactional-remote-call.md)（自呼叫、事務內遠端呼叫、缺 rollbackFor）
- [ ] **第三方對接**：對齊同模組既有對接寫法（cp-service `service/third*`、single-wallet `@SingleWalletType`、collector `SourceProxyService`），不另起框架（見 `skills/api-connector-builder`）
- [ ] **寫流水 vs 變更狀態順序**：先變更後寫流水，配合 `@Transactional` rollback
- [ ] **第三方 API 失敗**：超時 / 異常正確處理，金額異動失敗回滾狀態
- [ ] 🔬 **跨平台 / 跨租戶** → [`checks/platform-isolation.md`](../checks/platform-isolation.md)（金額、報表、排程是否混算多家包網商）
- [ ] **彩票**：賠率只取自伺服器設定、限額檢查與扣額同鎖同事務、封盤以伺服器時間判定、開獎寫入有權限與留痕（見 `rules/security.md` §彩票）
- [ ] **業務語意**對照業務知識正本（見 `rules/modules.md` §業務知識正本），讀不到就標 confidence ≤ 80

---

## security-reviewer

安全漏洞偵測 — 驗簽 / 加密 / 輸入處理。**L1 場景主 agent 須帶 `model=opus`**。

- [ ] 機密不硬編碼（API Key / Secret 走 config / env）
- [ ] 回調驗簽：簽名算法正確（HMAC / RSA），時間戳防 replay
- [ ] 回調 IP 白名單（若第三方提供）
- [ ] 錯誤訊息不洩漏內部資訊（stack trace / SQL / 路徑）
- [ ] Log 脫敏：手機 / 銀行卡 / Token / 密碼 mask
- [ ] 輸入驗證：`@RequestBody` 加 `@Valid`，SO 欄位 `@NotNull` / `@NotBlank`
- [ ] 🔬 **包網商隔離** → [`checks/platform-isolation.md`](../checks/platform-isolation.md)（platformId 只取自 token、SO 帶的要比對或覆寫、單筆查詢帶 platformId、快取 / ES / 匯出 / 排程維度）
- [ ] 🔬 **filter 防線** → [`checks/filter-bypass.md`](../checks/filter-bypass.md)（動到 `*Filter` / 放行清單 / 白名單時必查：副檔名或子字串放行、未正規化、失敗未 `return`）
- [ ] SQL 注入：`SqlUtil` / 字串拼接 SQL 不得帶入使用者輸入；欄名 / 排序 / 表名要白名單
- [ ] 跨服務呼叫（Feign / RestTemplate）：URL / 參數無使用者輸入直拼

---

## database-reviewer

MySQL / SQL / Schema 審查。

- [ ] ShardingSphere 主從讀寫切換：寫操作走 master，讀操作可走 slave
- [ ] **分片鍵**：sharded table 的 WHERE 必含分片鍵，否則全分片掃描
- [ ] SQL 不拼接使用者輸入（lion 沒有 MyBatis，SQL 由 framework_v3 `SqlUtil` / 字串組成）
- [ ] **新 Flyway migration 用時間戳版號** `V<YYYYMMDDHHMMSS>__<desc>.sql`，放 `cp-flyway/src/main/resources/db/migrations/general/`；既有檔一個字都不能改（見 `rules/flyway-migration.md`）
- [ ] **`zz_document/script/changelog/` 是否要同步一份**：不得自行判定，對照同模組近期同類單；判不出列為 OQ（見 `rules/flyway-migration.md` §兩條 SQL 軌）
- [ ] MySQL 5.7.29 語法（團隊既有記載）：不用 8.x 才有的 window function、CTE 等
- [ ] 查詢 / 更新帶 platformId（見 `rules/platform-isolation.md` §3）
- [ ] 索引策略：高頻 WHERE / JOIN 欄位有索引；無冗餘索引
- [ ] 大表 ALTER：考慮 online DDL / 分批 backfill
- [ ] `NOT NULL` 加欄位：預設值 / backfill 順序考慮鎖表時間

---

## 使用方式

### 主 agent 派 reviewer briefing 範例

```
[reviewer 派遣] l_tier=L1 → business-reviewer (model=opus)

【任務】Review plan specs/2026-05-26_xxx_plan.md
【讀】spec=specs/2026-05-26_xxx_spec.md §R1-R5; plan §2 §7
【變更檔案】(見 plan §2，共 N 檔)
【Checklist】依 .claude/rules/reviewer-checklists.md §business-reviewer
              標 🔬 的項目必須先 Read 對應 .claude/checks/*.md 再判斷
【Severity】依 .claude/rules/severity-rubric.md；Artifacts 每條標 [SEVERITY|c=NN]
【Harness Contract】依 rules/agents.md §Harness Output Contract 五欄位輸出
```

### 自動生成

```bash
python scripts/generate_reviewer_briefing.py <plan_path> <reviewer_name>
```

輸出可直接貼進主 agent 的 Agent tool prompt。
