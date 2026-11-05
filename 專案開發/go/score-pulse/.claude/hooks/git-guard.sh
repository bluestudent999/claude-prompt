#!/usr/bin/env bash
# git-guard.sh — Bash 工具的 git 指令守門（兩項檢查合一，JSON 只解析一次）
#
# 合併自原本的 PreToolUse(Bash) hook（2026-11-04 提速檢視第 8 項）：
#   1. check-oq：git commit 前 plan/ 不得有「⏳ 待決」OQ
#   2. protected-branch：main/master 鎖定；developing 只收 MR 或本機 --no-ff 合併 feature／hotfix 分支
#      （2026-11-05 使用者指定）；feature 必須從 developing 切
# （.claude/ 與 CLAUDE.md 自 2026-11-02 起隨專案進版控，原本擋 git add .claude 的檢查已移除）
# 規則來源：rules/git-workflow.md §1、§3
#
# Hook 類型：PreToolUse（matcher: Bash）
# 行為：指令裡沒有 git → 立刻 exit 0（不解析其他東西）；命中任一檢查 → exit 2 + stderr 說明
set -euo pipefail

input="$(cat)"

# 指令裡連 git 字樣都沒有就不用解析 JSON
case "$input" in *git*) ;; *) exit 0 ;; esac

cmd="$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))
except Exception:
    pass' 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0
case "$cmd" in *git*) ;; *) exit 0 ;; esac

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# ---- 1. git commit 前 plan/ 不得有未決 OQ ------------------------------------
check_oq() {
  case "$cmd" in *"git commit"*) ;; *) return 0 ;; esac
  case "$cmd" in *"git commit --amend"*|*"git commit -a --amend"*) return 0 ;; esac
  [[ -d plan ]] || return 0

  local errors=() f count
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    count=$(grep -c "⏳ 待決" "$f" 2>/dev/null || echo 0)
    errors+=("OQ 未決議：${f}（$count 個 ⏳ 待決）")
  done < <(grep -l "⏳ 待決" plan/*.md 2>/dev/null || true)
  [[ ${#errors[@]} -eq 0 ]] && return 0

  {
    echo "[git-guard/check-oq] 偵測到 plan 含有未決議的 Open Questions，已攔截 git commit："
    local e; for e in "${errors[@]}"; do echo "  - $e"; done
    echo ""
    echo "處理方式："
    echo "  請與開發團隊或 PO 確認決議後，將 plan 內的 OQ 從「⏳ 待決」改為「✅ <已決議方案>」"
    echo ""
  } >&2
  exit 2
}

# ---- 2. 分支規則 ---------------------------------------------------------------
check_protected_branch() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local branch reason=""
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
  is_locked()      { [[ "$1" == "main" || "$1" == "master" ]]; }
  is_integration() { [[ "$1" == "developing" ]]; }

  # 2a. 在鎖定分支上 commit / merge / cherry-pick / revert；在集成分支上 commit / cherry-pick / revert
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(commit|merge|cherry-pick|revert)([[:space:]]|$)'; then
    if is_locked "$branch"; then
      reason="目前在 ${branch}（鎖定分支），不得直接 commit / merge"
    elif is_integration "$branch" && printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(commit|cherry-pick|revert)([[:space:]]|$)'; then
      reason="目前在 developing（集成分支），不得直接 commit / cherry-pick / revert；改動一律在 feature 分支做"
    fi
  fi

  # 2a'. developing 上的 merge 只准「--no-ff 合併 feature／hotfix 分支」（git-workflow.md §1.2，2026-11-05 使用者指定）
  if [[ -z "$reason" ]] && is_integration "$branch" && printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+merge([[:space:]]|$)'; then
    if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+merge[[:space:]].*(_test|-test)([[:space:]]|$|;|&|\|)'; then
      reason="不得把測試分支合併進 developing（測試分支單向流動，git-workflow.md §1）"
    elif ! printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+merge[[:space:]]([^;&|]*[[:space:]])?--no-ff([[:space:]]|$)'; then
      reason="developing 上的 merge 必須帶 --no-ff（保留合併 commit，可整筆 revert）"
    elif ! printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+merge[[:space:]][^;&|]*[[:space:]](origin/)?(feature|hotfix)/[^[:space:];&|]+'; then
      reason="developing 只能合併 feature/<ticket-id>-<slug> 或 hotfix/<slug> 分支"
    elif printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+merge[[:space:]][^;&|]*(--squash|--ff-only)'; then
      reason="developing 上的 merge 不得 --squash／--ff-only"
    fi
  fi

  # 2a''. developing 不改寫歷史：不 rebase、不 reset；pull 只准 --ff-only
  if [[ -z "$reason" ]] && is_integration "$branch"; then
    if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(rebase|reset)([[:space:]]|$)'; then
      reason="目前在 developing（集成分支），不得 rebase / reset（會改寫共用歷史）"
    elif printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+pull([[:space:]]|$)' && ! printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+pull[[:space:]][^;&|]*--ff-only'; then
      reason="developing 上的 pull 只准 --ff-only（不在本機產生同步用的合併 commit）"
    fi
  fi

  # 2b. push 到鎖定分支（顯式指定或在鎖定分支上 push）
  if [[ -z "$reason" ]] && printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push'; then
    if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push([[:space:]]+[^;&|]*)?[[:space:]](origin[[:space:]]+)?([^[:space:]:]+:)?(main|master)([[:space:]]|$|;|&|\|)'; then
      reason="不得 push 到 main / master（鎖定分支）"
    elif is_locked "$branch" && ! printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push[[:space:]].*[[:space:]][^[:space:]-][^[:space:]]*[[:space:]]+[^[:space:]-]'; then
      reason="目前在 ${branch}（鎖定分支），不得 push"
    elif printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push([[:space:]][^;&|]*)?[[:space:]]((--force[^[:space:]]*|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)|\+[^[:space:]]*developing)' \
         && { is_integration "$branch" || printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push[[:space:]][^;&|]*developing'; }; then
      reason="不得 force push developing（改寫共用歷史）"
    fi
  fi

  # 2c. 從 main / master 切新分支（feature 必須從 developing 切）
  if [[ -z "$reason" ]] && printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(checkout[[:space:]]+-b|switch[[:space:]]+-c|branch)[[:space:]]+[^[:space:]]+[[:space:]]+(origin/)?(main|master)([[:space:]]|$|;|&|\|)'; then
    reason="feature 分支必須從 developing 切出，不得從 main / master 切"
  fi

  # 2d. developing 不以本機 merge / rebase 與 main 同步
  if [[ -z "$reason" ]] && printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(merge|rebase)[[:space:]]+.*[[:space:]/](main|master)([[:space:]]|$|;|&|\|)' && is_integration "$branch"; then
    reason="developing 不以本機 merge / rebase 與 main 同步，走 MR"
  fi

  [[ -n "$reason" ]] || return 0

  {
    echo "[git-guard/protected-branch] 已攔截：${reason}"
    echo ""
    echo "分支規則（rules/git-workflow.md §1）："
    echo "  main/master 鎖定，只收 developing 的 release MR；developing 只收 MR 或本機 --no-ff 合併 feature 分支（§1.2）。"
    echo "  每張 ticket 一條分支，從 developing 切出："
    echo "    git fetch origin && git switch -c feature/<ticket-id>-<slug> origin/developing"
    echo "  完成後 push feature 分支，開 MR 或在本機合併回 developing："
    echo "    git switch developing && git pull --ff-only origin developing"
    echo "    git merge --no-ff feature/<ticket-id>-<slug> && git push origin developing"
    echo "目前分支：${branch}"
  } >&2
  exit 2
}

check_oq
check_protected_branch
exit 0
