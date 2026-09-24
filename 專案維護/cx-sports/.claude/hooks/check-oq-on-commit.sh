#!/usr/bin/env bash
# 攔截 Bash 工具中的 git commit，對 plan/*_plan.md 做兩道檢查：
#   1. §7 仍有「⏳ 待決」OQ → block（原 check-oq 邏輯）
#   2. §0 Meta 的 L 層仍是佔位符 → block（原 check-spec-meta 邏輯）
# 任一檢查失敗即攔截，stderr 列出全部錯誤。
#
# 規則來源：.claude/rules/agents.md §planner agent 特殊原則
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

# --amend 不在攔截範圍（單純改訊息常見）
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

# --- 檢查 1：OQ ⏳ 待決 ---
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  count=$(grep -c "⏳ 待決" "$f" 2>/dev/null || echo 0)
  errors+=("OQ 未決議：${f}（$count 個 ⏳ 待決）")
done < <(grep -l "⏳ 待決" plan/*_plan.md 2>/dev/null || true)

# --- 檢查 2：§0 Meta L 層未填 ---
# 判定條件：§0 存在但 L 層欄位仍是佔位符 "L1 / L2 / L3（從 spec..."
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  if grep -q "^## 0\. Meta" "$f" 2>/dev/null; then
    if grep -q "L1 / L2 / L3（從 spec" "$f" 2>/dev/null; then
      errors+=("L 層未填：$f §0 Meta 的 L 層仍是佔位符，請從 spec Phase B 複製確認值")
    fi
  fi
done < <(ls plan/*_plan.md 2>/dev/null || true)

if [[ ${#errors[@]} -eq 0 ]]; then
  exit 0
fi

{
  echo "[check-oq-on-commit] 偵測到 plan 缺少必要資訊，已攔截 git commit："
  for e in "${errors[@]}"; do
    echo "  - $e"
  done
  echo ""
  echo "處理方式："
  echo "  OQ 未決議 → 與 PO 確認後，將 §7 OQ 從「⏳ 待決」改為「✅ <決議>」"
  echo "  L 層未填  → 從 spec Phase B 摘要複製 L 層到 plan §0 Meta 表格"
  echo ""
  echo "若本次 commit 與 plan/ 無關，可將 plan 暫移至 plan/_archived_xxx.md"
  echo ""
  echo "詳見 .claude/rules/agents.md §planner agent 特殊原則"
} >&2

exit 2
