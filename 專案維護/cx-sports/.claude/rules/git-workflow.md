# Git 工作流程

> git 操作層規範（提交、分支、MR 建立）。開發流程（規劃、TDD、審查）詳見 [development-workflow.md](./development-workflow.md)。
> 團隊使用 **GitLab**，術語以 **Merge Request (MR)** 為準；CLI 使用 `glab`。

## 提交訊息格式

```
<type>: <description>

<optional body>
```

類型：feat、fix、refactor、docs、test、chore、perf、ci

## 分支策略

| 分支 | 用途 | 誰合併 |
|------|------|--------|
| `master` | 正式版本 | 僅 tech lead |
| `developing` | 開發整合 | 開發者（需 MR review） |
| `feature/*` | 功能開發 | 開發者 |
| `hotfix/*` | 緊急修復 | 開發者（需 MR review） |

## Merge Request 建立步驟

1. 分析完整的提交歷史（不只是最新提交）
2. 使用 `git diff [base-branch]...HEAD` 查看所有變更
3. 撰寫完整的 MR 摘要（可用 `glab mr create` 或 GitLab Web UI）
4. 包含含有 TODO 的測試計畫
5. **附 AIDD metrics 段落**（觀察用，不阻擋合入） — 模板見 [development-workflow.md §AIDD metrics 模板](./development-workflow.md)
6. 若為新分支，使用 `-u` 旗標推送

## MR 審查流程

1. 開發者在 `feature/*` 或 `hotfix/*` 分支完成開發
2. 確認建置通過：本地 `mvn -pl <module> -am compile`；CI 走 **Jenkins**（`Jenkinsfile`）— **注意 Jenkins 用 `-Dmaven.test.skip=true`，不跑測試** → 測試需本地手動跑
3. 使用 **code-reviewer** agent 完成自審
4. 涉及金額/金額異動/訂單/狀態機時，額外使用 **business-reviewer** agent
5. 建立 MR 到 `developing`，指定 reviewer / approver
6. 通過 review 與 pipeline 後合併
