---
paths:
  - "**/*.java"
  - "**/pom.xml"
---
# Java Hooks（crypto-payment）

> Java 專屬 hook 設定參考。本 repo `.claude/settings.json` 的 `PostToolUse` 目前**不掛同步 formatter**（Java formatter JVM 冷啟慢會卡互動），改由 IDE + pre-commit 處理。

## 設計取捨

| 時機 | 工具 | 負責 |
|------|------|------|
| IDE 編輯時 | IDE formatter + `.editorconfig` | 縮排 / 空白 / 換行 |
| Claude 編輯後（PostToolUse） | 輕量提示（改業務層檔案提示 `/security-check`） | 不阻塞主流程 |
| 提交前（pre-commit） | 編譯 + 單元測試（CI 若跳測試則這是防線） | 防回歸 |
| commit message（PreToolUse） | `validate_commit_msg.py` 驗 `type(PROJ-XXX)` 格式 | 擋格式錯誤 |

## PostToolUse Hook 選項

於 `.claude/settings.json` 的 `hooks.PostToolUse` 設定。**擇一**：

### 選項 A：不做同步 formatter，僅輕量提示（本專案採用）

改到 `service/` `repository/` `controller/` 時提示執行 `/security-check`（見 settings.json）。

### 選項 B：非同步快速檢查（進階）

```json
{
  "matcher": "Write|Edit",
  "hooks": [
    {
      "type": "command",
      "command": "echo \"$CLAUDE_FILE\" | grep -q '\\.java$' && mvn -pl crypto-payment-service compile -q -o 2>&1 | tail -20 || true",
      "async": true
    }
  ]
}
```

重點：只對 `.java` 觸發、`async: true` 不阻塞、`|| true` 不中斷、`tail` 避免洗版。

## IDE 設定（`.editorconfig`，repo 根）

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

## Pre-commit Hook（推薦）

於 `.git/hooks/pre-commit`：

```bash
#!/bin/bash
changed=$(git diff --cached --name-only --diff-filter=ACM | grep '\.java$')
if [ -n "$changed" ]; then
  mvn -pl crypto-payment-service -am compile -q || exit 1
  # mvn -pl crypto-payment-service test -q || exit 1   # 啟用後確認本地測試環境就緒
fi
```

## 相關

- `rules/coding-style.md` — Java 4 spaces 縮排與通用格式
- `.claude/settings.json` — hook 實際設定位置
- `.claude/hooks/validate_commit_msg.py` — commit message 格式驗證
