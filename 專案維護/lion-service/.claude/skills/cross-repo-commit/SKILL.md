---
name: cross-repo-commit
description: 跨 repo 提交前的 checklist 與 MR 模板。當一個需求同時動到 lion-service / lion-common / framework_v3 / lion-core / lion-frontend / lion-manage 等多個 repo 時使用，避免誤帶既有未提交變更、搞錯發版順序、遺漏 MR 交叉引用。
---

# Cross-Repo Commit

一個需求同時動到多個 repo（典型：lion-common + lion-service + lion-frontend）時，commit / MR 操作複雜度放大。本 skill 提供結構化 checklist + MR description 模板，避免常見地雷。

> **Claude 不自行 `git commit`**（`rules/git-workflow.md` 最高優先硬規則，跨 repo 一樣適用）。本 skill 的 Phase 1–2 是 Claude 整理好、交給使用者確認的內容；**每個 repo** 都要使用者當前訊息明確說 commit、範圍與訊息確認過，才對**那個 repo** 執行 commit。在 A repo 拿到的 commit 指令不代表 B repo 也可以 commit。

## 啟用時機

- 同一個需求觸及 ≥ 2 個 repo
- 牽涉 lion-common / framework_v3 等共享層（改一次 VO 可能要連動 lion-service + 前端）
- 結算 / 派彩計算在 lion-core，本 repo 只是呼叫端或寫入端
- 每個 repo 都有獨立 MR / MR 之間需要交叉引用

## lion 生態與發版順序

| repo | 角色 | 本 repo 怎麼引用 |
|------|------|-----------------|
| `framework_v3` | 底層框架（Exception、DAO 抽象、utils；`com.cx.framework.*`） | Maven `com.lc.lion:framework:${framework.version}` |
| `lion-common` | 共享層（VO/SO/BO/Query/Event/Model、共用 DAO、Cache、列舉；`com.lc.common.*`），本身依賴 framework_v3 | Maven `com.lc.lion:common:${common.version}` |
| `lion-service`（本 repo） | 業務服務 4 模組 + `cp-flyway` | — |
| `lion-core` | 結算 / 派彩（`com.lc.lion.settle.*`） | 跨服務；不在本機時先問使用者 |
| `lion-frontend` / `lion-manage` | 前端總倉 / 總控制中心（後端 + 前端） | HTTP API；本範本不改前端 |

**發版順序（硬規則）：`framework_v3` → `lion-common` → `lion-service`（與其他消費共享層的服務）→ 前端。**
上游沒發版（沒 install / deploy 到下游拿得到的位置）前，下游 MR 不得合入——CI 不編譯（Jenkins `-Dmaven.test.skip=true` 只是 install，不驗下游），合錯順序要到部署才炸。

**版號實況：** 根 `pom.xml` 的 `framework.version`（3.1）與 `common.version`（1.1）自 init 起未改過 → 團隊實際做法是**同版號覆蓋發布**。Claude **不自行改 pom 版號**；要改成 bump 是流程變更，問使用者。同版號覆蓋的代價：其他開發者本機 `~/.m2` 要重新拿新版，MR description 要提醒。

## 原則

1. **每 repo 先驗 git status** — 確認沒有不相關的既有未提交變更被一起帶走
2. **不要 `git add -A` / `git add .`** — 明確指定檔案；lion-service 另外**不得**帶到 `.claude/` 與根 `CLAUDE.md`（git 裡追蹤著團隊版，部署本範本後工作目錄會顯示大量改動，那是正常的）
3. **MR 之間交叉引用** — A MR 描述要連到 B MR、反之亦然；避免 reviewer 只看 A 無法理解全貌
4. **合入順序明確** — 依上方發版順序，寫在 MR description
5. **共享層改動後，下游 compile 是硬 gate** — 不要 fire-and-forget

## 操作 checklist（commit 前）

> **若本次涉及 DB schema：** migration 在**同 repo** 的 `cp-flyway/`（不在根 pom `<modules>`，不會跟著 `mvn` reactor 建置），另有 `zz_document/script/changelog/` 手動上版 SQL 一軌。
> - [ ] 新 migration 用**時間戳版號** `V<YYYYMMDDHHMMSS>__<desc>.sql`（`rules/flyway-migration.md`）
> - [ ] changelog 是否同步一份**不得自行判定**：對照同模組近期同類單；判不出 → 問使用者（`rules/flyway-migration.md`）
> - [ ] 兩軌都寫時內容一致，changelog 檔首註明對應 flyway 版號

對**每個**受影響 repo 跑一輪：

### Phase 1：對齊 MR 範圍

```bash
cd <repo>
git status                           # 看整個 uncommitted 清單
git diff --stat                      # 檔案 / 行數統計
```

**硬規則：**
- 逐檔對照「本次需求 plan §2 Architecture Changes 的檔案清單」（`specs/YYYY-MM-DD_<feat>_plan.md`）
- **不屬於本次需求的變更 → 告知使用者**，由使用者決定 stash / 另外 commit / 另開 branch；Claude 不自行 stash 或丟棄別人的變更
- `git status` 出現你認不得的檔案 → 先查（可能是之前 session 留的 / 別人的），不要順手帶進去

### Phase 2：交給使用者的 commit 草稿

給使用者看「要 add 的檔案清單 + commit 訊息草稿」，**等使用者明確說 commit**：

```bash
# 正確：明確列檔案
git add src/main/java/com/lc/common/bean/vo/front/game/FrontConfigVO.java

# 錯誤：跨 repo 場景禁用
git add -A
git add .
git add .claude CLAUDE.md
```

commit 訊息用 conventional commit，描述用繁體中文、帶單號（以 `git log --oneline -20` 對齊近期寫法）：

```
<type>: <單號> <description>

<body: 一段話說明 why + 跨 repo 的位置脈絡>

Related MRs:
- <repo>: <MR URL or "pending">
- <repo>: <MR URL or "pending">
```

**範例：**

```
feat: TEST-1 FrontConfigVO 新增 customerServiceTg2 欄位

新增平台在線客服 TG2 欄位，支援後台管理 TG 備援頻道。
欄位由 cp-service ConfigService.getFrontConfig 的反射機制自動 wire，lion-service 零 code 變更。

Related MRs:
- lion-frontend/admin-frontend: pending
```

### Phase 3：MR description 模板

每個 MR description **必含**：

```markdown
## 需求
- Jira: <ticket URL>
- Spec: specs/YYYY-MM-DD_<feat>_spec.md
- Plan: specs/YYYY-MM-DD_<feat>_plan.md

## 跨 repo 變更（整體 blast radius）

| Repo | MR | 狀態 | 本 MR 的角色 |
|------|----|----|------------|
| lion-common | !NNN | merged | **本 MR** |
| lion-service | !MMM | open | 引用新欄位 |
| lion-frontend/admin-frontend | !KKK | open | 對應前端 UI |

## 本 MR 範圍
<檔案 / 行數 / why>

## 合入順序
1. framework_v3（若有）→ merged + 發版
2. lion-common → merged + 發版
3. lion-service / 其他消費方 → 確認拿到新版後合入
4. 前端 → 後端 API 上線後對接

## 版本策略
- 沿用同版號覆蓋發布（lion 既有做法）/ 改 bump（需使用者決定）：<採哪個>
- 同版號覆蓋時：提醒其他開發者更新本機 `~/.m2`

## 手動 QA checklist（對應 spec R1-Rn）
- [ ] R1 ...
- [ ] R2 ...
- [ ] 涉及資料查詢 / 寫入：用至少兩個 platformId 驗證 A 家看不到 B 家（`rules/platform-isolation.md`）

## 風險提示
- <附 plan §5 Risk Callouts 的 HIGH / MEDIUM 項>
```

### Phase 4：下游 compile（若改共享層）

**硬 gate：** lion-common / framework_v3 改動後，**本地** compile 受影響的消費方：

- lion-service 受影響模組：`mvn -pl <module> compile -q`（`cp-service` / `single-wallet-service` / `collector-service` / `upload-service`）
- 其他引用共享層的 repo（團隊文件記載有 `activity-service`、`lion-manage`、`lion-captcha`、`lion-core` 等，本機不一定有）→ **實際清單問使用者**，不憑印象宣稱「已驗證所有下游」
- 改的是 Kafka Event / 跨服務 VO 的欄位 → 消費端是否容忍未知欄位要逐一確認（Jackson `FAIL_ON_UNKNOWN_PROPERTIES`）

```bash
# 每個下游 repo（共享層已在本機 install 後）：
cd <downstream>
mvn -pl <主模組> -am compile -q || echo "[FAILED] <downstream>"
```

任一下游失敗 → **不要合入共享層 MR**，回頭修相容性問題；拿不到的下游在 MR description 標「未驗證」。

## 常見地雷

| 地雷 | 防範 |
|------|------|
| `git status` 顯示除了本次變更外還有別的 modified 檔（可能是別人或之前 session 的） | Phase 1 逐檔核對 plan §2 清單；非本次變更告知使用者 |
| lion-service 的 `.claude/` / `CLAUDE.md` 被一起 add | 一律指名檔案 add；commit 前 `git diff --cached --name-only` 確認 |
| 只開了 A MR 忘開 B MR → reviewer 審到一半「這個 VO 欄位要用在哪」 | Phase 3 MR description 列出全部關聯 MR（即使是 pending） |
| lion-common 還沒發版就合了 lion-service → 部署時吃到舊 VO 或編譯失敗 | 依發版順序；MR description 明寫合入順序 |
| 同版號覆蓋但其他開發者本機 `~/.m2` 還是舊版 → 他 build 出來行為不同 | MR description 提醒；必要時使用者在團隊頻道廣播 |
| 共享層 VO 加欄位，下游 Jackson 嚴格 → 反序列化炸 | Phase 4 逐一確認消費端設定 |
| 結算規則改在 lion-service，但真正計算在 lion-core | spec 階段就確認計算歸屬（`skills/spec-review/SKILL.md` 跨 repo 觸發詞） |

## 相關

- `rules/git-workflow.md` — 單 repo commit 規範（Claude 不自行 commit、不帶 `.claude/`）
- `rules/patterns.md` §8 — lion-common 共享物件放置原則
- `rules/flyway-migration.md` — 時間戳版號、兩條 SQL 軌
- `skills/spec-review/SKILL.md` — 跨 repo 觸發詞與 spec §6 版本策略
