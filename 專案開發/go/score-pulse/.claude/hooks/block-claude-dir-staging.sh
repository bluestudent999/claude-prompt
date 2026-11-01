#!/usr/bin/env bash
# 攔截會把本機範本（.claude/ 與根 CLAUDE.md）帶進 score-pulse 版控的 git 指令。
# 規則來源：.claude/rules/git-workflow.md「不要把 .claude/ 與 CLAUDE.md 一起提交」
#
# 為什麼要攔：score-pulse 的 .gitignore 已排除 .claude/* 與 CLAUDE.md（含 settings.json），
# 這兩者是本機範本；git add -f、git add -A 配合錯誤的 .gitignore 仍可能把它們帶進版控。
#
# Hook 類型：PreToolUse（matcher: Bash）
# 行為：命中 → exit 2 + stderr 說明；其餘 exit 0
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"

[[ -n "$cmd" ]] || exit 0

reason=""

# git add 的整包 / 範本路徑寫法
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+add([[:space:]]+[^;&|]*)?[[:space:]](-A|--all|\.|\./?|:/|\.claude(/[^[:space:]]*)?|CLAUDE\.md)([[:space:]]|$|;|&|\|)'; then
  reason="git add 含 -A / . / .claude / CLAUDE.md"
fi

# git commit -a / --all 會把已追蹤的 .claude/、CLAUDE.md 改動一起提交
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+commit([[:space:]]+[^;&|]*)?[[:space:]](-a|-[a-zA-Z]*a[a-zA-Z]*|--all)([[:space:]]|$)'; then
  reason="git commit -a / --all"
fi

[[ -n "$reason" ]] || exit 0

{
  echo "[block-claude-dir-staging] 已攔截：${reason}"
  echo ""
  echo ".claude/ 與根 CLAUDE.md 是本機範本，不進 score-pulse 版控（.gitignore 已排除）；"
  echo "不要用 -A / . / -f 整包加入。"
  echo ""
  echo "處理：指名要提交的檔案，例如"
  echo "  git add internal/match/service/apply.go"
  echo "然後用 git diff --cached --name-only 確認暫存區沒有 .claude/ 與 CLAUDE.md。"
} >&2
exit 2
