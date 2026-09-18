#!/usr/bin/env python3
"""
PreToolUse hook：在 git commit 執行前驗證 commit message 格式。
格式要求：type(PREFIX-XXX): 描述
  PREFIX = 2 個以上大寫字母（涵蓋 PROJ / CRYP 及未來其他前綴）
type 允許值：feat / fix / refactor / test / chore / docs
"""
import sys
import json
import re

VALID_TYPES = r'(feat|fix|refactor|test|chore|docs)'
# 工單前綴放寬為 [A-Z]{2,}，不再硬編 PROJ；例：PROJ-123 / CRYP-456
PATTERN = re.compile(
    rf'^{VALID_TYPES}\([A-Z]{{2,}}-\d+\): .{{3,}}'
)

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)  # 無法解析時放行，不阻擋

    command = data.get('tool_input', {}).get('command', '')

    # 只處理 git commit 指令
    if 'git commit' not in command:
        sys.exit(0)

    # 跳過 --amend 不含 -m 的情況
    if '-m' not in command:
        sys.exit(0)

    # 提取 commit message（支援單引號與雙引號）
    match = re.search(r'-m\s+["\'](.+?)["\']', command)
    if not match:
        sys.exit(0)

    msg = match.group(1)

    if PATTERN.match(msg):
        sys.exit(0)  # 格式正確，放行

    # 格式錯誤，印出提示並以 exit 2 阻擋
    print('', flush=True)
    print('[ERROR] Commit message 格式不符合規範', flush=True)
    print(f'   輸入：{msg}', flush=True)
    print('', flush=True)
    print('   正確格式：type(PREFIX-XXX): 簡短描述', flush=True)
    print('   PREFIX：2 個以上大寫字母（如 PROJ / CRYP）', flush=True)
    print('   type 允許值：feat | fix | refactor | test | chore | docs', flush=True)
    print('', flush=True)
    print('   範例：', flush=True)
    print('     feat(PROJ-123): add ETH deposit webhook handler', flush=True)
    print('     fix(CRYP-456): resolve platform_id isolation in collector', flush=True)
    sys.exit(2)

if __name__ == '__main__':
    main()
