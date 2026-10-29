#!/bin/bash
# <!-- shared:suggest-compact -->
# Strategic Compact Suggester
# 掛在 settings.json 的 PreToolUse(Edit|Write)，依本 session 的工具呼叫次數提醒手動 /compact。
#
# 本檔在所有範本間逐字一致（prompt-lint 的 shared 檢查會盯住），不要只改單一範本的副本；
# 各範本專屬的壓縮時機與保留／清除原則，寫在同目錄的 SKILL.md。
set -eu

# 以 CLAUDE_SESSION_ID 做每個 session 獨立的計數器（不用 $$，每次 hook 啟動都不同）
SESSION_ID="${CLAUDE_SESSION_ID:-${PPID:-default}}"
COUNTER_FILE="/tmp/claude-tool-count-${SESSION_ID}"
THRESHOLD="${COMPACT_THRESHOLD:-50}"

# 讀取並遞增計數；檔案內容不是數字時歸零重數
count=0
if [ -f "$COUNTER_FILE" ]; then
  count=$(cat "$COUNTER_FILE")
  case "$count" in
    ''|*[!0-9]*) count=0 ;;
  esac
fi
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

# 達到門檻時提醒一次
if [ "$count" -eq "$THRESHOLD" ]; then
  echo "[StrategicCompact] 已執行 $THRESHOLD 次工具調用。若正處於階段切換點，請考慮執行 /compact 壓縮 Context 以維護推理精度。" >&2
fi

# 門檻之後每 25 次再提醒
if [ "$count" -gt "$THRESHOLD" ] && [ $((count % 25)) -eq 0 ]; then
  echo "[StrategicCompact] 目前已執行 $count 次工具調用。若 Context 已顯著膨脹，建議執行 /compact 進行精簡。" >&2
fi
# <!-- /shared -->
