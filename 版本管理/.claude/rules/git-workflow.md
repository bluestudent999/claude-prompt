# Git 工作流（升級期）

> 升級期的分支與 commit 策略，重點是**可二分、可回溯、可審查**——大規模機械遷移與人工修復必須在歷史上分得開。

---

## 1. 分支策略

- 從 `developing`（或團隊整合分支）切**升級專用分支**：`upgrade/boot3-java21-<模組>`（如 `upgrade/boot3-java21-app-service`）。
- 多模組大升級：可在升級分支下用一系列 commit 推進；若工時長，每個模組或每個 Phase 可拆獨立 MR 漸進合入。
- **禁止**在 `master` / `developing` 直接改 `pom.xml` 版本號（見 `settings.json` soft_deny）。

---

## 2. Commit 粒度（一個 Phase 一個 commit — 硬規則）

升級的 commit 必須能讓 `git bisect` 二分出「行為從哪個 commit 開始變」。**機械遷移與人工修復分開**：

| 順序 | commit | 類型 |
|------|--------|------|
| 1 | 升 parent / Spring Cloud train / 第三方相容版本（根 pom） | `chore` |
| 2 | OpenRewrite 自動遷移（jakarta + Boot 3 + API） | `chore` |
| 3 | 設定遷移（yml/properties Boot 3 屬性） | `chore` |
| 4 | 編譯收斂（recipe 未覆蓋的人工修復） | `fix` |
| 5 | 換庫（如 springfox → springdoc） | `refactor`（升級範圍內的必要替換） |
| 6 | 回歸測試調整（依賴舊版行為的測試修正） | `test` |

> **禁止**把「recipe 自動改」和「人工改」混在同一 commit——出問題無法二分來源。

---

## 3. 提交訊息（Conventional Commits）

```
<type>: <description>

升級範圍：<模組>
版本：Java <from> → <to>，Spring Boot <from> → <to>
[行為差異：<若有>]
```

類型：`chore`（版本/依賴/自動遷移）、`fix`（編譯/行為修復）、`refactor`（換庫）、`test`（測試調整）、`docs`。

範例：
```
chore: OpenRewrite 自動遷移 Spring Boot 3 + jakarta namespace

升級範圍：cx-xxx-app-service
版本：Java 8 → 21，Spring Boot 2.7.11 → 3.3.x
```

---

## 4. Merge Request

MR 到 `developing`，描述**必含**：

1. **版本前後對照表**：Java / Spring Boot / Spring Cloud / 高風險第三方依賴的 from → to（引用 `version-matrix.md §0` + plan §1）。
2. **行為差異記錄**：哪些行為因升級而改變、為何可接受、是否已同步調整 client（對照 `breaking-changes.md §F`）。
3. **回歸測試證據**：baseline vs 升級後對照（pass/fail 數 + 新紅燈判定），手動 QA 清單（`verification.md §4`）。
4. **換庫說明**（若有）：springfox→springdoc 等的影響面（API 文件 URL 變更、註解改動）。
5. **AIDD metrics**（觀察用，見 §5）。

---

## 5. AIDD 升級指標模板（MR 必附段落）

```markdown
### AIDD 升級指標
- 升級範圍：<模組>
- 版本：Java 8→21 / Boot 2.7→3.3
- 風險層：[L1 / L2 / L3]（見 agents.md）
- OpenRewrite 覆蓋率：[recipe 自動修 ~N 處 / 人工收尾 M 處]
- 編譯錯誤收斂輪次：[mvn compile 反覆次數]
- 換庫項：[springfox→springdoc 等，N 項]
- 回歸：baseline PASS=X → 升級後 PASS=Y（新紅燈 Z：已修 a / 改測試 b / 已知 c）
- Reviewer 輪次：[增量 N + 最終 1]
- Reviewer 發現：CRITICAL=0 HIGH=1 MEDIUM=3
- 預估 token 成本：[~k]
- Compact 次數：[N]
```

> 累積多個升級 MR 後，可回答「recipe 覆蓋率多少 / 哪類 breaking change 最耗收斂時間 / reviewer 抓真行為差異的命中率」。

---

## 6. 不繞過 hook

- commit 被 OQ hook 擋 → 讀訊息回填 plan 的 OQ，**不要** `--no-verify` 繞過。
- 被 jakarta 單向性 hook 擋（新增了非白名單 javax）→ 改用 jakarta 對應 package，不要繞過。
