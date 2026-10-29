#!/usr/bin/env bash
# 攔截 Edit / Write 對 i18n 檔的直寫，強制走 scripts/i18n.py。
# 規則來源：.claude/rules/i18n.md
#
# Hook 類型：PreToolUse（matcher: Edit|Write）
# 行為：命中 i18n 檔路徑 → exit 2 + stderr 訊息（Claude 視為 block）
set -euo pipefail

input="$(cat)"

file_path="$(
  printf '%s' "$input" \
    | python3 -c 'import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get("tool_input", {}).get("file_path", ""))
except Exception:
    pass' 2>/dev/null
)"

if [[ -z "$file_path" ]]; then
  exit 0
fi

# 命中以下任一 → block（case 內 * 會匹配任意字元，含 /）
# lion-service i18n 檔範圍（前端 i18n 在 lion-frontend / lion-manage，不在本 repo）：
#   後端 .properties：cp-service/src/main/resources/i18n/messages*.properties
case "$file_path" in
  */cp-service/src/main/resources/i18n/messages*.properties \
  | cp-service/src/main/resources/i18n/messages*.properties )
    cat >&2 <<EOF
[block-i18n-direct-edit] 禁止直接 Edit / Write i18n 檔：
  $file_path

請改用 scripts/i18n.py：
  # 新增 backend key（--zh-CN 必填，未給的 locale 以 zh-CN fallback 並標 TODO）
  python3 scripts/i18n.py add backend errorCode.NNNN \\
      --zh-CN "..." --zh-TW "..." --en "..." --vi "..." --ko "..." --tl "..." --ceb "..."

  # 修改既有值 / 對齊審查 / 批次補缺
  python3 scripts/i18n.py update backend errorCode.NNNN --zh-CN "..."
  python3 scripts/i18n.py audit --scope backend
  python3 scripts/i18n.py fill-missing --scope backend

查既有 key 用 grep：
  grep -n "errorCode.NNNN" cp-service/src/main/resources/i18n/messages.properties

詳見 .claude/rules/i18n.md
EOF
    exit 2
    ;;
esac

exit 0
