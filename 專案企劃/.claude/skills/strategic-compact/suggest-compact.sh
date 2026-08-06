#!/bin/bash
# Strategic Compact Suggester（企劃版）
# Runs on PreToolUse to suggest context compaction at logical intervals.
#
# Track tool call count (increment in a temp file)
# Use CLAUDE_SESSION_ID for session-specific counter
SESSION_ID="${CLAUDE_SESSION_ID:-${PPID:-default}}"
COUNTER_FILE="/tmp/claude-plan-tool-count-${SESSION_ID}"
THRESHOLD=${COMPACT_THRESHOLD:-50}

# Initialize or increment counter
if [ -f "$COUNTER_FILE" ]; then
  count=$(cat "$COUNTER_FILE")
  count=$((count + 1))
  echo "$count" > "$COUNTER_FILE"
else
  echo "1" > "$COUNTER_FILE"
  count=1
fi

# Suggest compact after threshold tool calls
if [ "$count" -eq "$THRESHOLD" ]; then
  echo "[StrategicCompact] 已執行 $THRESHOLD 次工具調用。若正處於企劃階段切換(Brief→Spec→Backlog),請考慮 /compact 壓縮 Context 以維護推理精度。" >&2
fi

# Suggest at regular intervals after threshold
if [ "$count" -gt "$THRESHOLD" ] && [ $((count % 25)) -eq 0 ]; then
  echo "[StrategicCompact] 目前已執行 $count 次工具調用。若 Context 已顯著膨脹,建議執行 /compact 進行精簡。" >&2
fi
