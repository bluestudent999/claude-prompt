#!/bin/bash
# Strategic Compact Suggester（升級期）
# 在 PreToolUse(Edit|Write) 依工具呼叫次數提醒手動 /compact。
# 升級碰大量檔案（盤點 grep / recipe diff / 編譯錯誤 / reviewer 輸出），context 壓力高，
# 在 Phase 邊界主動壓縮優於讓自動壓縮在 Phase 中途亂砍。

SESSION_ID="${CLAUDE_SESSION_ID:-${PPID:-default}}"
COUNTER_FILE="/tmp/claude-upgrade-tool-count-${SESSION_ID}"
THRESHOLD=${COMPACT_THRESHOLD:-50}

if [ -f "$COUNTER_FILE" ]; then
  count=$(cat "$COUNTER_FILE")
  count=$((count + 1))
  echo "$count" > "$COUNTER_FILE"
else
  echo "1" > "$COUNTER_FILE"
  count=1
fi

if [ "$count" -eq "$THRESHOLD" ]; then
  echo "[StrategicCompact] $THRESHOLD 次工具呼叫 — Phase 邊界可考慮 /compact（先落檔 inventory/plan/commit hash）" >&2
fi

if [ "$count" -gt "$THRESHOLD" ] && [ $((count % 25)) -eq 0 ]; then
  echo "[StrategicCompact] $count 次工具呼叫 — context 若已陳舊，是 /compact 的好檢查點" >&2
fi
