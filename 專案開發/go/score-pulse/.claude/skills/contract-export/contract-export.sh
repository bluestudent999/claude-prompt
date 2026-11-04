#!/usr/bin/env bash
# 已搬進 repo：scripts/contract-export.sh。本檔只轉呼叫，避免本機留過期副本。
ROOT="${1:-${CLAUDE_PROJECT_DIR:-.}}"
exec bash "$ROOT/scripts/contract-export.sh" "$@"
