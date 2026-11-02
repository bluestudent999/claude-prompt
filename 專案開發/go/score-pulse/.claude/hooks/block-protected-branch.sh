#!/usr/bin/env bash
# 守住分支規則（rules/git-workflow.md §1）：
#   - main / master 是鎖定分支：不得 commit、不得 push、不得從它切 feature 分支
#   - developing 是集成分支：只收 MR，不得直接 commit
#   - 每張 ticket 的分支必須從 developing 切出
#
# Hook 類型：PreToolUse（matcher: Bash）
# 行為：命中 → exit 2 + stderr 說明；其餘 exit 0
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0
case "$cmd" in *git*) ;; *) exit 0 ;; esac

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"

reason=""
is_locked()      { [[ "$1" == "main" || "$1" == "master" ]]; }
is_integration() { [[ "$1" == "developing" ]]; }

# 1. 在鎖定或集成分支上 commit / merge / cherry-pick / revert
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(commit|merge|cherry-pick|revert)([[:space:]]|$)'; then
  if is_locked "$branch"; then
    reason="目前在 ${branch}（鎖定分支），不得直接 commit / merge"
  elif is_integration "$branch"; then
    reason="目前在 developing（集成分支），只收 MR，不得直接 commit / merge"
  fi
fi

# 2. push 到鎖定分支（顯式指定或在鎖定分支上 push）
if [[ -z "$reason" ]] && printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push'; then
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push([[:space:]]+[^;&|]*)?[[:space:]](origin[[:space:]]+)?([^[:space:]:]+:)?(main|master)([[:space:]]|$|;|&|\|)'; then
    reason="不得 push 到 main / master（鎖定分支）"
  elif is_locked "$branch" && ! printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push[[:space:]].*[[:space:]][^[:space:]-][^[:space:]]*[[:space:]]+[^[:space:]-]'; then
    reason="目前在 ${branch}（鎖定分支），不得 push"
  fi
fi

# 3. 從 main / master 切新分支（feature 必須從 developing 切）
if [[ -z "$reason" ]] && printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(checkout[[:space:]]+-b|switch[[:space:]]+-c|branch)[[:space:]]+[^[:space:]]+[[:space:]]+(origin/)?(main|master)([[:space:]]|$|;|&|\|)'; then
  reason="feature 分支必須從 developing 切出，不得從 main / master 切"
fi

# 4. 把 developing 以外的來源 merge 進 developing 之外的事由 CI 管；這裡只擋 fast-forward main
if [[ -z "$reason" ]] && printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(merge|rebase)[[:space:]]+.*(main|master)([[:space:]]|$|;|&|\|)' && is_integration "$branch"; then
  reason="developing 不以本機 merge / rebase 與 main 同步，走 MR"
fi

[[ -n "$reason" ]] || exit 0

{
  echo "[block-protected-branch] 已攔截：${reason}"
  echo ""
  echo "分支規則（rules/git-workflow.md §1）："
  echo "  main/master 鎖定，只收 developing 的 release MR；developing 只收 MR。"
  echo "  每張 ticket 一條分支，從 developing 切出："
  echo "    git fetch origin && git switch -c feature/<ticket-id>-<slug> origin/developing"
  echo "  完成後 push feature 分支並開 MR 到 developing："
  echo "    git push -u origin feature/<ticket-id>-<slug>"
  echo "目前分支：${branch}"
} >&2
exit 2
