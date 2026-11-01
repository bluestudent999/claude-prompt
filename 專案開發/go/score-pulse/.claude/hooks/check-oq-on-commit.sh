#!/usr/bin/env bash
# 攔截 Bash 工具中的 git commit，對 plan/ 下的 markdown 檔案做檢查：
# 若含有「⏳ 待決」OQ，即攔截提交並印出警告。
#
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

# 只處理 git commit；其他 Bash 直接放行
case "$command_str" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# --amend 不在攔截範圍
case "$command_str" in
  *"git commit --amend"*|*"git commit -a --amend"*)
    exit 0
    ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

if [[ ! -d plan ]]; then
  exit 0
fi

errors=()

# 檢查 plan/ 目錄下所有 plan 或 markdown 是否有「⏳ 待決」
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  count=$(grep -c "⏳ 待決" "$f" 2>/dev/null || echo 0)
  errors+=("OQ 未決議：${f}（$count 個 ⏳ 待決）")
done < <(grep -l "⏳ 待決" plan/*.md 2>/dev/null || true)

if [[ ${#errors[@]} -eq 0 ]]; then
  exit 0
fi

{
  echo "[check-oq-on-commit] 偵測到 plan 含有未決議的 Open Questions，已攔截 git commit："
  for e in "${errors[@]}"; do
    echo "  - $e"
  done
  echo ""
  echo "處理方式："
  echo "  請與開發團隊或 PO 確認決議後，將 plan 內的 OQ 從「⏳ 待決」改為「✅ <已決議方案>」"
  echo ""
} >&2

exit 2
