---
name: cross-repo-commit
description: 跨 repo 提交前的 checklist 與 MR 模板。當一個需求同時動到 sport / cx-sport-common / lion-frontend/admin-frontend / manage-center 等多個 repo 時使用，避免誤 commit 既有未提交變更、遺漏 MR 交叉引用。
---

# Cross-Repo Commit

一個需求同時動到多個 repo（典型：sport + cx-sport-common + lion-frontend/admin-frontend）時，commit / MR 操作複雜度放大。本 skill 提供結構化 checklist + MR description 模板，避免常見地雷。

## 啟用時機

- 同一個需求觸及 ≥ 2 個 repo
- 牽涉 cx-sport-common / sport-framework 等共享層（改一次 VO 可能要連動 sport + lion-frontend/admin-frontend）
- 每個 repo 都有獨立 MR / MR 之間需要交叉引用

## 原則

1. **每 repo 先驗 git status** — 確認沒有不相關的既有未提交變更被一起帶走
2. **不要 `git add -A` 或 `git add .`** — 明確指定檔案
3. **MR 之間交叉引用** — A MR 描述要連到 B MR、反之亦然；避免 reviewer 只看 A 無法理解全貌
4. **合入順序明確** — 在 MR description 寫清楚誰先誰後
5. **共享層 bump 後，下游 smoke test 是硬 gate** — 不要 fire-and-forget

## 操作 checklist（commit 前）

> ⚠️ **若本次涉及 DB schema：`Flyway` 是獨立 repo，不會跟著 sport 的 CI 跑。**
> - [ ] Flyway repo 的 migration 已用**時間戳版本號**（`rules/flyway-migration.md`）
> - [ ] **Flyway repo 自己的版本號驗證器已通過**（同上 §7）—— sport 這邊全綠不代表那邊沒問題
> - [ ] 兩邊 MR 已交叉引用，且註明合入順序

對**每個**受影響 repo 跑一輪：

### Phase 1：對齊 MR 範圍

```bash
cd <repo>
git status                           # 看整個 uncommitted 清單
git diff --stat                      # 檔案 / 行數統計
```

**硬規則：**
- 逐檔對照「本次需求 plan §2 Architecture Changes 的檔案清單」
- **不屬於本次需求的變更 → stash / 另外 commit / 另開 branch**
- 如果 `git status` 出現你認不得的檔案 → 先查（可能是之前 session 留的 / 別人的）

### Phase 2：明確 add 指定檔案

```bash
# ✅ 正確：明確列檔案
git add src/main/java/com/lc/common/bean/vo/front/game/FrontConfigVO.java

# ❌ 錯誤：避免這兩個指令在跨 repo 場景
git add -A
git add .
```

### Phase 3：commit 訊息使用 conventional commit

```
<type>: <description> (<Jira ticket>)

<body: 一段話說明 why + 跨 repo 的位置脈絡>

Related MRs:
- <repo>: <MR URL or "pending">
- <repo>: <MR URL or "pending">
```

**範例：**

```
feat: add customerServiceTg2 field to FrontConfigVO (TEST-1)

新增平台在線客服 TG2 欄位到 FrontConfigVO，支援後台管理 TG 備援頻道。
反射機制（ConfigService.getFrontConfig L269-282）自動 wire，cx-sports-v2 零變更。

Related MRs:
- lion-frontend/admin-frontend: <pending or URL>
```

### Phase 4：MR description 模板

每個 MR description **必含**：

```markdown
## 需求
- Jira: <ticket URL>
- Spec: <spec.md 路徑>
- Plan: <plan.md 路徑>

## 跨 repo 變更（整體 blast radius）

| Repo | MR | 狀態 | 本 MR 的角色 |
|------|----|----|------------|
| cx-sport-common | !NNN | merged | **本 MR** |
| lion-frontend/admin-frontend | !MMM | open | 對應前端 UI |
| sport | 無 code 變更 | — | 僅需本地 mvn install 同步 |

## 本 MR 範圍
<檔案 / 行數 / why>

## 合入順序
1. cx-sport-common（本 MR）→ merged + 發版
2. 等 cx-sport-common 發版後，bump 下游 / 前端對接
3. ...

## 版本 bump 策略
- (A) 正規 bump 小版本：<version> → <new version>
- (B) 同版號 overwrite：需 Nexus 允許 + 協調清 ~/.m2
- 本 MR 採：<A 或 B，附理由>

## 手動 QA checklist（對應 spec R1-Rn）
- [ ] R1 ...
- [ ] R2 ...

## 風險提示
- <附 plan §5 Risk Callouts 的 HIGH / MEDIUM 項>
```

### Phase 5：下游 smoke test（若改共享層）

**硬 gate：** cx-sport-common / sport-framework 升版後，**本地** compile + 啟動這些服務驗證：

- activity-service
- manage-center
- (sport 無獨立驗證碼服務)
- 其他消費該 VO / 模組的服務

```bash
# 每個下游 repo：
cd <downstream>
# 若走 bump 策略：修 pom version 後
mvn -pl <主模組> -am compile -q || echo "❌ FAILED"
# 啟動 smoke test
mvn -pl <主模組> spring-boot:run -q  # 測 Spring context 能起來
```

任一下游失敗 → **不要合入 cx-sport-common MR**，回頭修 Jackson / 相容性問題。

## 常見地雷

| 地雷 | 防範 |
|------|------|
| `git status` 顯示除了本次變更外還有別的 modified 檔（可能是別人或之前 session 的） | Phase 1 手動核對 plan §2 清單；非本次變更的先 stash |
| 只開了 A MR 忘開 B MR → reviewer 審到一半「這個 VO 欄位要用在哪」 | Phase 4 MR description 列出全部關聯 MR（即使是 pending） |
| cx-sport-common 合入了但忘了 bump `sport/pom.xml` → CI 綠但 runtime 吃到舊 VO | MR description 明確寫「合入順序」；建立合入後 checklist |
| 同版號 overwrite 但其他開發者本地 ~/.m2 沒清 → 他 build 還是舊版 | MR description 通知所有開發者 + Slack 廣播；或直接走 bump 版本 |
| 下游 activity-service Jackson 嚴格 → cx-sport-common VO 加欄位後下游炸 | Phase 5 smoke test；I4 預先檢查 FAIL_ON_UNKNOWN_PROPERTIES 配置 |

## 相關

- `rules/git-workflow.md` — 單 repo commit 規範
- `rules/patterns.md` §8 — cx-sport-common 共享物件放置原則
- `skills/spec-review` — spec §6 版本 bump 策略
