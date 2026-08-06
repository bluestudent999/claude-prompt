#!/usr/bin/env bash
# Session 啟動時掃描 plan/*.md 的「⏳ 待決」OQ，提醒主 agent 還有未決議項。
#
# Hook 類型：SessionStart
# 行為：stdout 印警告（Claude Code 將其作為 additionalContext 注入）
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

if [[ ! -d plan ]]; then
  exit 0
fi

pending_files=()
while IFS= read -r f; do
  [[ -n "$f" ]] && pending_files+=("$f")
done < <(grep -l "⏳ 待決" plan/*.md 2>/dev/null || true)

if [[ ${#pending_files[@]} -eq 0 ]]; then
  exit 0
fi

echo "=== Pending Open Questions ==="
for f in "${pending_files[@]}"; do
  count=$(grep -c "⏳ 待決" "$f" 2>/dev/null || echo 0)
  echo "  - $f  ($count 個 ⏳ 待決)"
done
echo ""
echo "提示：請在實作前與開發團隊/PO確認決議，並將 plan 中該條目改為「✅ <已決議方案>」"
echo "詳見 .claude/rules/development-workflow.md"
echo ""
