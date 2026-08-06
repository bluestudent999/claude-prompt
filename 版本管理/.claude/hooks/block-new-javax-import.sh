#!/usr/bin/env bash
# jakarta 單向性守門：進入 Boot 3 階段（Phase B 完成）後，攔截新增「非 Java SE 白名單」的 javax.* import。
# 規則來源：.claude/rules/jakarta-migration.md §1 §4
#
# Hook 類型：PreToolUse（matcher: Edit|Write）
# 啟用方式：把下方 GUARD_ENABLED 改為 1（Phase A / baseline 期間維持 0，避免擋到尚未遷移的存量檔案）。
set -euo pipefail

# ── 開關（預設停用）──
GUARD_ENABLED=0
[[ "$GUARD_ENABLED" != "1" ]] && exit 0

input="$(cat)"

# 取出 Edit 的 new_string 或 Write 的 content
new_content="$(
  printf '%s' "$input" \
    | python3 -c 'import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get("tool_input", {})
    print(ti.get("new_string", "") or ti.get("content", ""))
except Exception:
    pass' 2>/dev/null
)"

[[ -z "$new_content" ]] && exit 0

# Java SE 白名單（這些永遠是 javax.*，不可改 jakarta，不攔截）
SE_WHITELIST='javax\.(crypto|net|sql|naming|management|security\.auth|sound|imageio|swing|accessibility|xml\.(parsers|transform|xpath|namespace)|lang\.model|tools|script)'

# 找出新增的「import javax.*」中，不屬於 SE 白名單的（即 Jakarta EE 類，應改 jakarta）
violations="$(
  printf '%s' "$new_content" \
    | grep -E "^\s*import\s+javax\." \
    | grep -vE "$SE_WHITELIST" || true
)"

[[ -z "$violations" ]] && exit 0

{
  echo "[block-new-javax-import] 偵測到新增「非 Java SE 白名單」的 javax.* import，已攔截："
  printf '%s\n' "$violations" | sed 's/^/  ✗ /'
  echo ""
  echo "Boot 3 階段後 Jakarta EE 類 API 一律用 jakarta.*（servlet / persistence / validation / annotation ...）。"
  echo "若這是 Java SE API（crypto / net / sql / naming ...），代表白名單需補，請更新本 hook 的 SE_WHITELIST。"
  echo "詳見 .claude/rules/jakarta-migration.md §1"
} >&2

exit 2
