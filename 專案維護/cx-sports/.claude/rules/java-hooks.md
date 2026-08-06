---
paths:
  - "**/*.java"
  - "**/pom.xml"
---
# Java Hooks

> Java 專屬 hook 設定參考。本 repo `.claude/settings.json` 目前採 **§選項 A**（`PostToolUse: []` 不掛 formatter，因專案無 spotless/checkstyle/.editorconfig）— 要改裝 hook 見下方選項。

## 設計取捨

Java formatter / linter（Spotless、Checkstyle、SpotBugs）**JVM 冷啟成本高**，不適合每次 `Write|Edit` 同步執行 → 卡互動。建議分層：

| 時機 | 工具 | 負責 |
|------|------|------|
| IDE 編輯時 | IDE formatter + `.editorconfig` | 縮排 / 空白 / 換行 |
| Claude 編輯後（async hook） | 輕量檢查或跳過 | 不阻塞主流程 |
| 提交前（`pre-commit`） | 單元測試（**CI 跳測試 → 提交前是唯一防線**） | 防回歸 |
| CI（`Jenkinsfile`） | `mvn install -Dmaven.test.skip=true` + 部署 | 建置上 server，**不跑測試** |

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

統一透過 `.editorconfig` 於 repo 根目錄：

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
  modules=$(echo "$changed" | grep -oE "^(cx-sports-v2|cx-sport-single-wallet-service)" | sort -u | tr '\n' ',' | sed 's/,$//')
  if [ -n "$modules" ]; then
    mvn -pl "$modules" -am compile -q || exit 1
    # mvn -pl "$modules" test -q || exit 1   # 啟用後記得本地測試環境就緒
  fi
fi
```

> 本專案目前**無 checkstyle / spotless plugin**（pom.xml 確認），不要在 pre-commit 跑這些指令。

## 相關

- `rules/coding-style.md` — Java 4 spaces 縮排與通用格式原則
- `.claude/settings.json` — hook 實際設定位置
