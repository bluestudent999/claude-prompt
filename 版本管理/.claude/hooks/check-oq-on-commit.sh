#!/usr/bin/env bash
# 攔截 Bash 工具中的 git commit，檢查 upgrade/*-plan.md：
#   §7 仍有「⏳ 待決」OQ → block（升級期目標版本/換庫選型未決議不得提交）
# stderr 列出錯誤。
#
# 規則來源：.claude/rules/upgrade-workflow.md §Step 5 / agents.md
# Hook 類型：PreToolUse（matcher: Bash）
set -euo pipefail

input="$(cat)"

command_str="$(
  printf '%s' "$input" \
    | python3 -c 'import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get("tool_input", {}).get("command", ""))
except Exception:
    pass' 2>/dev/null
)"

# 只處理 git commit；其他 Bash 放行
case "$command_str" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# --amend 不攔截（改訊息常見）
case "$command_str" in
  *"git commit --amend"*|*"git commit -a --amend"*)
    exit 0
    ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

if [[ ! -d upgrade ]]; then
  exit 0
fi

errors=()
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  count=$(grep -c "⏳ 待決" "$f" 2>/dev/null || echo 0)
  errors+=("OQ 未決議：$f（$count 個 ⏳ 待決）")
done < <(grep -l "⏳ 待決" upgrade/*-plan.md 2>/dev/null || true)

if [[ ${#errors[@]} -eq 0 ]]; then
  exit 0
fi

{
  echo "[check-oq-on-commit] 偵測到升級 plan 有未決議 OQ，已攔截 git commit："
  for e in "${errors[@]}"; do
    echo "  - $e"
  done
  echo ""
  echo "處理：與 user 確認後，將 §7 OQ 從「⏳ 待決」改為「✅ <決議>」"
  echo "若本次 commit 與 upgrade/ 無關，可將 plan 暫移至 upgrade/_archived_xxx.md"
  echo ""
  echo "詳見 .claude/rules/upgrade-workflow.md §Step 1"
} >&2

exit 2
