#!/usr/bin/env bash
# 攔截 Edit / Write 對 i18n 檔的直寫，強制走 scripts/i18n-add-key.py。
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

# 命中以下任一 → block
# cx-sports-v2 i18n 檔範圍：
#   後端 .properties：cx-sport-app-service/src/main/resources/i18n/messages*.properties
#   前端 global.js：lion-frontend/admin-frontend/src/i18n/langs/*/global.js
case "$file_path" in
  */resources/i18n/messages*.properties \
  | */i18n/langs/*/global.js )
    cat >&2 <<EOF
[block-i18n-direct-edit] 禁止直接 Edit / Write i18n 檔：
  $file_path

前端 global.js 請改用 scripts/i18n-add-key.py：
  python3 scripts/i18n-add-key.py KEY AFTER_KEY ZH EN VI JA KO

  # 例：在 gameTotalFee 後插入 rewardCommission
  python3 scripts/i18n-add-key.py rewardCommission gameTotalFee \\
      "打賞抽成" "Reward Commission" "Hoa hồng thưởng" "チップ抽成" "보상 수수료"

後端 .properties 請用 grep 確認現有 key，再以 Bash + python3 寫入（避免 \\uXXXX 編碼問題）：
  grep -n "errorCode.NNNN" cx-sport-app-service/src/main/resources/i18n/messages.properties

詳見 .claude/rules/i18n.md
EOF
    exit 2
    ;;
esac

exit 0
