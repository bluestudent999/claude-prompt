#!/usr/bin/env bash
# arch-check.sh - score-pulse 架構邊界檢查（rules/architecture.md §6）
# 用法：bash .claude/skills/arch-check/arch-check.sh [專案根目錄]
# 離開碼：0 全部通過；1 有 FAIL
set -uo pipefail

ROOT="${1:-${CLAUDE_PROJECT_DIR:-.}}"
cd "$ROOT" || { echo "[arch-check] 找不到目錄 $ROOT"; exit 2; }
[ -f go.mod ] || { echo "[arch-check] 不是 Go 專案根目錄（無 go.mod），略過"; exit 0; }

MODULE="$(awk '/^module /{print $2}' go.mod)"
FEATURES="operator match odds member notify admin collector realtime"
TENANT_TABLES="Operator OperatorDomain OperatorBrand RedirectSetting AdSlot AdMaterial RedirectClick RedirectImpression VisitLog Member MemberDevice MemberLogin SmsRecord Favorite MemberSetting SearchLog NoticeSetting Notice PushToken PushRecord HotContentOverride"
APPEND_ONLY_TABLES="odds_history admin_audit redirect_click redirect_impression visit_log"
CMD_WHITELIST="score-pulse thesports-sim gen"
# 白名單：確認為誤報的檔案（相對路徑），一行一個
IGNORE_FILES="$(cat <<'LIST'
LIST
)"

fails=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails+1)); }
ignored() { printf '%s\n' "$IGNORE_FILES" | grep -qx "$1"; }
gofiles() { grep -rl --include=*.go "$@" 2>/dev/null | grep -v _test.go | while read -r f; do ignored "$f" || echo "$f"; done; }

# ---- 1. 依賴方向 -------------------------------------------------------------
dep_fail=0
for f in $FEATURES; do
  [ -d "internal/$f" ] || continue
  for layer in controller service dao model dto consumer job; do
    [ -d "internal/$f/$layer" ] || continue
    deps="$(go list -deps "./internal/$f/$layer" 2>/dev/null | grep "^$MODULE/internal/" | grep -v "^$MODULE/internal/$f/$layer$")"
    while read -r d; do
      [ -n "$d" ] || continue
      rel="${d#$MODULE/internal/}"; pkg="${rel%%/*}"; sub="${rel#*/}"
      if [ "$pkg" = "$f" ]; then
        case "$layer:$sub" in
          controller:service|controller:dto|controller:model|service:dao|service:model|service:dto|dao:model|consumer:service|consumer:dto|consumer:model|job:service|job:dto|job:model) ;;
          *) echo "  依賴違規 internal/$f/$layer -> $rel"; dep_fail=1 ;;
        esac
      elif [ "$pkg" = "platform" ]; then :
      elif [ "$pkg" = "collector" ]; then echo "  collector 被 import：internal/$f/$layer -> $rel"; dep_fail=1
      elif [ "$pkg" = "inject" ]; then echo "  inject 被 import：internal/$f/$layer -> $rel"; dep_fail=1
      else
        case "$sub" in service|dto) ;; *) echo "  跨包只准 service/dto：internal/$f/$layer -> $rel"; dep_fail=1 ;; esac
        [ "$f" = "realtime" ] && [ "$sub" = "dao" ] && { echo "  realtime 不得 import dao：$rel"; dep_fail=1; }
      fi
    done <<< "$deps"
  done
done
if [ -d internal/platform ]; then
  pdeps="$(go list -deps ./internal/platform/... 2>/dev/null | grep "^$MODULE/internal/" | grep -v "^$MODULE/internal/platform")"
  [ -z "$pdeps" ] || { echo "  platform 依賴功能包："; echo "$pdeps" | sed 's/^/    /'; dep_fail=1; }
fi
[ $dep_fail -eq 0 ] && pass "1 依賴方向（controller->service->dao->model；跨包只准 service/dto；platform/collector/inject 邊界）" || fail "1 依賴方向"

# ---- 2. 禁用相依 -------------------------------------------------------------
ban_fail=0
hit="$(gofiles -E 'sp-common/|olivere/elastic|/ignite' internal cmd 2>/dev/null)"; [ -z "$hit" ] || { echo "  禁用 import："; echo "$hit" | sed 's/^/    /'; ban_fail=1; }
hit="$(find internal cmd -name '*.proto' 2>/dev/null)"; [ -z "$hit" ] || { echo "  .proto 檔："; echo "$hit" | sed 's/^/    /'; ban_fail=1; }
hit="$(gofiles -E 'proto\.Marshal|proto\.Unmarshal' internal/realtime internal/match internal/odds 2>/dev/null)"; [ -z "$hit" ] || { echo "  protobuf 用於推送路徑："; echo "$hit" | sed 's/^/    /'; ban_fail=1; }
[ -f go.work ] && grep -q sp-framework go.work && { echo "  go.work 指向同層 sp-framework（D2a）"; ban_fail=1; }
hit="$(gofiles -E '\.(P)?Subscribe\(' internal/realtime internal/match 2>/dev/null)"; [ -z "$hit" ] || { echo "  Redis Subscribe 用於扇出（D4）："; echo "$hit" | sed 's/^/    /'; ban_fail=1; }
for d in cmd/*/; do n="$(basename "$d")"; echo " $CMD_WHITELIST " | grep -q " $n " || { echo "  非白名單 cmd 目錄：$d（D3 單 binary）"; ban_fail=1; }; done
[ $ban_fail -eq 0 ] && pass "2 禁用相依（sp-common/Ignite/ES/protobuf/go.work/Redis Pub-Sub/多 binary）" || fail "2 禁用相依"

# ---- 3. 租戶表 dao 經 tenant.Scope ------------------------------------------
scope_fail=0
for f in $FEATURES; do
  [ -d "internal/$f/dao" ] || continue
  for file in internal/"$f"/dao/*.go; do
    [ -f "$file" ] || continue; case "$file" in *_test.go) continue;; esac
    ignored "$file" && continue
    for t in $TENANT_TABLES; do
      if grep -qE "model\.$t\b" "$file" && ! grep -qE "tenant\.(Scope|AdminScope|AllOperators)\(" "$file"; then
        echo "  $file 使用 model.$t 但未見 tenant.Scope"; scope_fail=1; break
      fi
    done
  done
done
[ $scope_fail -eq 0 ] && pass "3 租戶表 dao 經 tenant.Scope（近似）" || fail "3 租戶表 dao 經 tenant.Scope"

# ---- 4. append-only 表 ------------------------------------------------------
ao_fail=0
for t in $APPEND_ONLY_TABLES; do
  hit="$(grep -rn --include=*.go --include=*.sql -iE "(update|delete)[^;]{0,60}$t\b|$t[^;]{0,40}\.(Updates?|Delete)\(" internal migrations 2>/dev/null | grep -v _test.go | grep -vi 'create table\|-- ' )"
  [ -z "$hit" ] || { echo "  $t 有 UPDATE/DELETE："; echo "$hit" | sed 's/^/    /'; ao_fail=1; }
done
hit="$(grep -rn --include=*.go -E "model\.MatchEvent[^;]{0,60}\.Delete\(" internal 2>/dev/null)"; [ -z "$hit" ] || { echo "  match_event 有 Delete："; echo "$hit" | sed 's/^/    /'; ao_fail=1; }
[ $ao_fail -eq 0 ] && pass "4 append-only 表無 UPDATE/DELETE" || fail "4 append-only 表無 UPDATE/DELETE"

# ---- 5. 每個 handler 有測試 --------------------------------------------------
t_fail=0
for f in $FEATURES; do
  [ -d "internal/$f/controller" ] || continue
  for file in internal/"$f"/controller/*.go; do
    [ -f "$file" ] || continue; case "$file" in *_test.go|*/inject.go|*/router.go) continue;; esac
    ignored "$file" && continue
    grep -qE "func \([a-zA-Z]+ \*[A-Za-z]+Controller\) [A-Z]" "$file" || continue
    tf="${file%.go}_test.go"
    if [ ! -f "$tf" ]; then echo "  無測試：$file"; t_fail=1; continue; fi
    if [ "$f" != "match" ] && [ "$f" != "odds" ] && [ "$f" != "collector" ]; then
      grep -qE "OtherTenant|Unauthorized|Forbidden" "$tf" || { echo "  測試缺越權/未登入案例：$tf"; t_fail=1; }
    fi
  done
done
for file in internal/realtime/*.go; do
  [ -f "$file" ] || continue; case "$file" in *_test.go|*/inject.go) continue;; esac
  grep -qE "SubscribePath\(\)|HandshakeHandler" "$file" || continue
  [ -f "${file%.go}_test.go" ] || { echo "  WS action 無測試：$file"; t_fail=1; }
done
[ $t_fail -eq 0 ] && pass "5 每個 handler / WS action 有單元測試" || fail "5 每個 handler / WS action 有單元測試"

# ---- 6. 投注字眼 -------------------------------------------------------------
hit="$(grep -rn --include=*.go -iE '\b(settle|settlement|stake|payout|bet)[a-z]*\b' internal 2>/dev/null | grep -v '^\s*//' | grep -v '_test.go' | grep -vE 'alphabet|better|between' )"
[ -z "$hit" ] && pass "6 無投注字眼" || { echo "$hit" | sed 's/^/    /'; fail "6 無投注字眼（D3 不做結算）"; }

# ---- 7. 繞過框架 -------------------------------------------------------------
hit="$(grep -rn --include=*.go -E 'os\.Getenv\(|gin\.New\(|gin\.Default\(|gorm\.Open\(|redis\.NewClient\(|cron\.New\(|websocket\.Upgrader\{' internal 2>/dev/null | grep -v _test.go | grep -v 'internal/platform/conf/')"
[ -z "$hit" ] && pass "7 未繞過 sp-framework" || { echo "$hit" | sed 's/^/    /'; fail "7 未繞過 sp-framework（framework-conventions §9）"; }

echo "----"
if [ $fails -eq 0 ]; then echo "arch-check: PASS"; exit 0; else echo "arch-check: FAIL ($fails)"; exit 1; fi
