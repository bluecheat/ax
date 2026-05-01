#!/usr/bin/env bash
# pre-bash hook — 파괴적 명령 차단
set -euo pipefail

CMD="${CLAUDE_BASH_COMMAND:-${1:-}}"

DESTRUCTIVE_PATTERNS=(
    'rm[[:space:]]+-rf?[[:space:]]+/'
    'rm[[:space:]]+-rf?[[:space:]]+~'
    'rm[[:space:]]+-rf?[[:space:]]+\$HOME'
    'rm[[:space:]]+-rf?[[:space:]]+\.\.'
    'git[[:space:]]+push[[:space:]]+(--force|-f)'
    'git[[:space:]]+push[[:space:]].*--force-with-lease'
    'git[[:space:]]+reset[[:space:]]+--hard[[:space:]]+(origin|HEAD~|main|master)'
    'sudo[[:space:]]+rm'
    'mkfs\.'
    ':\(\)\{[[:space:]]*:\|:[[:space:]]*&[[:space:]]*\};:'
    'dd[[:space:]]+if=/dev/(zero|random).*of=/dev/'
    'chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/'
)

for pattern in "${DESTRUCTIVE_PATTERNS[@]}"; do
    if echo "$CMD" | grep -qE "$pattern"; then
        printf '\033[31m[goax hook]\033[0m 차단된 파괴적 명령 패턴: %s\n' "$pattern" >&2
        printf '명령: %s\n' "$CMD" >&2
        printf '우회가 필요하면 사용자에게 명시적 승인을 받아 직접 실행해.\n' >&2
        exit 1
    fi
done

exit 0
