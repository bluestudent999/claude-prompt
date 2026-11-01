#!/usr/bin/env bash
# contract-export.sh - 產出 docs/contract 並判斷契約是否變更（rules/api-contract.md）
# 用法：bash .claude/skills/contract-export/contract-export.sh [專案根目錄]
# 離開碼：0 正常；1 附件缺或 swag 失敗；2 環境問題
set -uo pipefail

ROOT="${1:-${CLAUDE_PROJECT_DIR:-.}}"
cd "$ROOT" || exit 2
[ -f go.mod ] || { echo "[contract-export] 無 go.mod，略過"; exit 0; }
command -v swag >/dev/null || { echo "[contract-export] 缺 swag：go install github.com/swaggo/swag/cmd/swag@latest"; exit 2; }

OUT=docs/contract
mkdir -p "$OUT"
rc=0

FRONT_DIRS="./internal/match/controller,./internal/odds/controller,./internal/member/controller,./internal/notify/controller,./internal/operator/controller"
ADMIN_DIRS="./internal/admin/controller,./internal/operator/controller"

echo "== 1. swag =="
swag init -g cmd/score-pulse/main.go --instanceName front --dir "$FRONT_DIRS" --parseDependency --parseInternal -o "$OUT/.swag-front" --outputTypes yaml >/dev/null 2>&1 \
  && mv "$OUT/.swag-front/swagger.yaml" "$OUT/openapi-front.yaml" && echo "  openapi-front.yaml 已更新" \
  || { echo "  FAIL swag front（檢查 @router / @success 註解）"; rc=1; }
swag init -g cmd/score-pulse/main.go --instanceName admin --dir "$ADMIN_DIRS" --parseDependency --parseInternal -o "$OUT/.swag-admin" --outputTypes yaml >/dev/null 2>&1 \
  && mv "$OUT/.swag-admin/swagger.yaml" "$OUT/openapi-admin.yaml" && echo "  openapi-admin.yaml 已更新" \
  || { echo "  FAIL swag admin"; rc=1; }
rm -rf "$OUT/.swag-front" "$OUT/.swag-admin"

echo "== 2. envelope 欄位 vs realtime.md =="
if [ -d internal/platform/envelope ] && [ -f "$OUT/realtime.md" ]; then
  tags="$(grep -rhoE 'json:"[a-zA-Z_]+' internal/platform/envelope/*.go 2>/dev/null | sed 's/json:"//' | sort -u)"
  missing=""
  for t in $tags; do grep -qE "\`$t\`|\"$t\"" "$OUT/realtime.md" || missing="$missing $t"; done
  [ -z "$missing" ] && echo "  短欄位名已全部出現在 realtime.md" || { echo "  WARN realtime.md 缺欄位：$missing"; }
else
  echo "  略過（envelope 包或 realtime.md 尚未建立）"
fi

echo "== 3. 固定附件 =="
for f in README.md realtime.md ws-client.example.ts CHANGELOG.md; do
  [ -f "$OUT/$f" ] && echo "  ok $f" || { echo "  FAIL 缺 $OUT/$f（api-contract.md §5）"; rc=1; }
done

echo "== 4. 契約是否變更 =="
changed="$(git status --porcelain -- "$OUT" 2>/dev/null | awk '{print $2}')"
if [ -z "$changed" ]; then
  echo "  契約無變更"
else
  echo "  變更檔案："; echo "$changed" | sed 's/^/    /'
  if ! git diff --quiet -- "$OUT/CHANGELOG.md" 2>/dev/null || git status --porcelain -- "$OUT/CHANGELOG.md" | grep -q .; then
    echo "  CHANGELOG.md 已有異動"
  else
    echo "  WARN 契約變了但 CHANGELOG.md 沒有本次條目"
  fi
  echo "== 5. 契約有更新 =="
  for f in openapi-front.yaml openapi-admin.yaml; do
    git diff -- "$OUT/$f" 2>/dev/null | grep -E '^\+ {2}/api' | sed 's/^+ *//; s/:$//' | sed "s|^|  - $f: |"
  done
  git diff -- "$OUT/realtime.md" 2>/dev/null | grep -E '^\+.*\| `/' | sed 's/^+//' | sed 's/^/  - realtime: /'
fi
exit $rc
