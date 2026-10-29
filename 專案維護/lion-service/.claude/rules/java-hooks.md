---
paths:
  - "**/*.java"
  - "**/pom.xml"
---
# Java Hooks

> Java 專屬 hook 設定參考。本範本 `.claude/settings.json` 目前採 **§選項 A**（`PostToolUse` 不掛 formatter，因 lion-service 無 spotless / checkstyle plugin、無 `.editorconfig`）— 要改裝 hook 見下方選項。

## 設計取捨

Java formatter / linter（Spotless、Checkstyle、SpotBugs）**JVM 冷啟成本高**，不適合每次 `Write|Edit` 同步執行 → 卡互動。建議分層：

| 時機 | 工具 | 負責 |
|------|------|------|
| IDE 編輯時 | IDE formatter + `.editorconfig` | 縮排 / 空白 / 換行 |
| Claude 編輯後（async hook） | 輕量檢查或跳過 | 不阻塞主流程 |
| 提交前（`pre-commit`） | 單元測試（**CI 跳測試 → 提交前是唯一防線**） | 防回歸 |
| CI（`Jenkinsfile`） | `mvn clean -Dmaven.test.skip=true install` + 部署 | 建置上 server，**不編譯也不跑測試** |

## PostToolUse Hook 選項

於專案根目錄 `.claude/settings.json` 的 `hooks.PostToolUse` 區塊設定。**擇一**或完全不設：

### 選項 A：不做 hook，由 IDE + pre-commit 處理（推薦）

```json
{ "matcher": "Write|Edit", "hooks": [] }
```

Java 編譯慢、hook 同步會卡 Claude → 交給 IDE 即時格式化 + Git pre-commit 整批檢查。

### 選項 B：非同步快速檢查（進階）

```json
{
  "matcher": "Write|Edit",
  "hooks": [
    {
      "type": "command",
      "command": "echo \"$CLAUDE_FILE\" | grep -q '\\.java$' && mvn -pl $(dirname \"$CLAUDE_FILE\" | sed 's|/src/.*||') checkstyle:check -q 2>&1 | tail -20 || true",
      "async": true
    }
  ]
}
```

重點：只對 `.java` 觸發、`async: true` 不阻塞、`|| true` 不中斷 Claude、`tail -20` 避免洗版。

### 選項 C：僅格式化（若專案已裝 Spotless）

```json
{
  "matcher": "Write|Edit",
  "hooks": [
    {
      "type": "command",
      "command": "echo \"$CLAUDE_FILE\" | grep -q '\\.java$' && mvn -pl $(dirname \"$CLAUDE_FILE\" | sed 's|/src/.*||') spotless:apply -q 2>/dev/null || true",
      "async": true
    }
  ]
}
```

## IDE 設定建議

lion-service 目前**沒有** `.editorconfig`；以下為建議值，要加進 repo 屬團隊決定（新增前問使用者），不要自行建檔：

```ini
root = true

[*.java]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true
max_line_length = 120
```

## Pre-commit Hook（推薦放這裡）

於 `.git/hooks/pre-commit`：

```bash
#!/bin/bash
# 本專案 Jenkinsfile 跑 -Dmaven.test.skip=true，CI 不跑測試 → 提交前是測試的唯一執行點
changed=$(git diff --cached --name-only --diff-filter=ACM | grep '\.java$')
if [ -n "$changed" ]; then
  # 找出受影響的模組，僅跑該模組的編譯與測試
  # cp-flyway 不在 reactor，不列入
  modules=$(echo "$changed" | grep -oE "^(cp-service|single-wallet-service|collector-service|upload-service)" | sort -u | tr '\n' ',' | sed 's/,$//')
  if [ -n "$modules" ]; then
    mvn -pl "$modules" -am compile -q || exit 1
    # mvn -pl "$modules" test -q || exit 1   # 啟用後記得本地測試環境就緒
  fi
fi
```

> 本專案目前**無 checkstyle / spotless plugin**（pom.xml 確認），不要在 pre-commit 跑這些指令。
> `.git/hooks/` 不進版控、屬個人機器設定；Claude 不自行安裝或修改 pre-commit，要裝先問使用者。

### 已知坑：`set -e` + `git add` 被 ignore 的檔

`specs/INDEX.md` 是 `scripts/index-specs.py` 產生的本地衍生檔、已被 `.gitignore` 排除。若 pre-commit 同時有 `set -e` 與 `git add specs/INDEX.md`，`git add` 回非零 → hook 中止 → **任何含 `specs/*.md` 的 commit 都失敗**，訊息只有「paths are ignored」，很容易誤判成 git 問題而去加 `-f`（反而把衍生檔塞進版控）。

**規則：pre-commit 內「輔助性、非驗證性」的指令一律加 `|| true`**（例：`git add specs/INDEX.md 2>/dev/null || true`）；只有真正該擋 commit 的檢查（編譯、測試）才允許非零中止。

## 相關

- `rules/coding-style.md` — Java 4 spaces 縮排與通用格式原則
- `.claude/settings.json` — hook 實際設定位置
