# Git 工作流與提交規範

---

## 1. 分支策略

- **`main`**：穩定分支
- **`developing`**：集成 / 測試分支
- **功能分支**：`feature/Sxx-<描述>`，對應實作步驟編號（如 `feature/S12-scan-range-calc`）
- **修復分支**：`hotfix/<描述>`

**一步驟一分支。** 步驟的粒度就是 review 與回退的粒度。

---

## 2. Commit 訊息（Conventional Commits）

```
<type>(<scope>): <subject>

[body：改了什麼行為、涉及哪些不變量、驗收結果]
```

**scope 對映 Modulith 模組**（見 `architecture.md` §3）：`chain` / `scanning` / `attribution` / `event` / `delivery` / `tenant` / `reconciliation` / `admin`；建置與骨架類用 `build` / `arch`

**B 軌（維運後台，同 repo）**：`web`（前端）／ `web-api`（後台後端）。

> **同 repo 的好處要用起來**：一個需求同時動 `crypto-node-service` 與 `crypto-node-web` 時，**兩邊放同一個 commit / MR** —— 契約與消費端一起改、一起 review、一起回退。不要拆成兩個 commit 再靠人記得配對。

```
feat(scanning): S12 掃描區間計算，掃至 head - N

- 依鏈別與租戶確認數計算安全上界（D17：只掃已確認區塊）
- 不變量：I2（高度單調遞增）、I7（達確認數才發事件）
- 測試：ScanRangeCalculatorTest、ScannerIT（兩租戶 fixture）、ArchitectureTests 全綠
- 分層：ScanRangeCalculator 落在 scanning/domain（純計算，零框架）
```

**紅線：**
- commit 訊息**嚴禁**含 API Key、RPC provider 憑證、資料庫密碼。
- 涉及對外契約的變更 → **body 必須註明是否需要下游同步**。
- 涉及不變量的變更 → **body 必須列出涉及哪幾條 + 對應測試**。
- 動到架構邊界（新模組、新 Port、跨層改動）→ **body 註明 `ArchitectureTests` 結果**。

---

## 3. 提交前檢查

```bash
./mvnw test                                   # 含 *IT（Testcontainers + 兩租戶 fixture）+ ArchitectureTests
./mvnw -q test -Dtest='ArchitectureTests'     # 架構邊界單獨確認
./mvnw -q checkstyle:check spotbugs:check     # 依專案實際外掛調整
git diff --cached --name-only | grep -E "\.(env|key|pem)$" && echo "⚠️ 有憑證檔"
```

**checklist：**
- [ ] DoD 七條全滿足（`testing.md` §6，含 `ArchitectureTests` 與 migration 版本號驗證器）
- [ ] `plan/` 無「⏳ 待決」OQ（否則 git hook 攔截）
- [ ] **實作步驟企劃書已回填**完成紀錄與進度總表
- [ ] 動到類別 / package / 相依 → `/arch-check` 通過
- [ ] 涉及契約 → `contract-reviewer` 已放行
- [ ] 無憑證、無 API Key 進版控

---

## 4. Merge Request

**標題**：對齊步驟，例：`S12: 掃描區間計算（掃至 head - N）`

**描述**：
1. **變更摘要**：一句話說明改動與影響的模組
2. **涉及不變量**：I2、I7…及其對應測試
3. **測試結果**：`./mvnw test` PASS 證據（含 `*IT`）
4. **契約影響**：無 / 有（需下游同步的具體說明）
5. **進度**：實作步驟企劃書已回填至 `n / 38`
6. **AIDD 指標**（見 §5）

---

## 5. AIDD 開發指標（觀察用，非合入條件）

> **填寫時機**：實質實作的 MR 建議填；純設定 / 文案 / docstring 可省略。累積 10~20 個才有統計意義。

```markdown
### AIDD 指標
- 步驟：Sxx
- 涉及不變量：[I2、I7]
- Plan OQ 數：[3（自答 2、User 決議 1）]
- Reviewer 輪次：[code-reviewer 1 + invariant-guard 1]
- 審查發現：[CRITICAL=0 HIGH=1 MEDIUM=3]
- 估算 vs 實際工時：[企劃書 1 天 / 實際 1.5 天]
- 預估 Token 成本：[~80k]
- Context 壓縮次數：[1]
```

**指標解讀（累積後）：**
- 「估算 vs 實際」持續超出 → 實作步驟企劃書的工時估算需回頭校正
- Reviewer 的 HIGH 平均 ≥ 3 → plan 的 §4 驗收計畫寫得不夠細
- Plan OQ「User 決議」偏多 → 前期決策未拍板完全，回頭檢視 §11 待確認事項

---

## 6. 不要做的事

| ❌ | 為什麼 |
|---|--------|
| 一個 commit 涵蓋多個步驟 | 步驟是驗收與回退的粒度 |
| 把 plan 的回填與程式碼分開 commit | DoD 第 7 條；分開就會忘 |
| `--no-verify` 繞過 hook | hook 擋的是未決 OQ，繞過等於跳過決策 |
| 在功能分支上順手改無關檔案 | 見 `coding-style.md` §8 範圍紀律 |
