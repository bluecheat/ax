#!/usr/bin/env bash
# pre-bash hook — 파괴적 명령 차단 (mode-aware)
#
# Claude Code 공식 hook 입력: stdin JSON ({tool_name, tool_input.command, ...}).
# 차단은 exit 2. 경고는 stderr + exit 0.
#
# 두 단계:
#   1. CATASTROPHIC — mode 무관 항상 차단 (안전망)
#   2. RECOVERABLE  — mode-aware (warning: 경고+capture, fail: 차단)

set -uo pipefail   # set -e 제거 — grep returning 1 (no match) 등이 hook 본체를 silent abort하지 않도록

# Bootstrap guard — install 중간이거나 .ax/ 부분 정리 시 silent skip (UX 노이즈 방지)
[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

# stdin JSON 파싱 — fallback chain: stdin → 구식 env var → argv (직접 실행 호환)
INPUT="$(cat 2>/dev/null || true)"
CMD=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
fi
CMD="${CMD:-${CLAUDE_BASH_COMMAND:-${1:-}}}"
[ -z "$CMD" ] && exit 0

# PROJECT_ROOT 결정: CLAUDE_PROJECT_DIR → BASH_SOURCE 기반 fallback (이 hook은 .ax/hooks/pre-bash/에 있음)
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd || pwd)}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
CAPTURE="$PROJECT_ROOT/.ax/scripts/bash/capture-mistake.sh"

SENSOR_MODE="warning"
if [ -f "$COMMON" ]; then
    # shellcheck source=../../scripts/bash/common.sh
    source "$COMMON"
    SENSOR_MODE=$(goax_mode 2>/dev/null || echo warning)
fi

# 1) CATASTROPHIC — 복구 불가, mode 무관 항상 차단
CATASTROPHIC_PATTERNS=(
    'rm[[:space:]]+-rf?[[:space:]]+/[[:space:]]*$'      # rm -rf /
    'rm[[:space:]]+-rf?[[:space:]]+/[[:space:]]'         # rm -rf / <something>
    'mkfs\.'                                              # 디스크 포맷
    ':\(\)\{[[:space:]]*:\|:[[:space:]]*&[[:space:]]*\};:' # fork bomb
    'dd[[:space:]]+if=/dev/(zero|random|urandom).*of=/dev/' # 디바이스 덮어쓰기
    'chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/'
)

# 2) RECOVERABLE — mode-aware
RECOVERABLE_PATTERNS=(
    'rm[[:space:]]+-rf?[[:space:]]+~'
    'rm[[:space:]]+-rf?[[:space:]]+\$HOME'
    'rm[[:space:]]+-rf?[[:space:]]+\.\.'
    'git[[:space:]]+push[[:space:]]+(--force[^-]|-f[[:space:]])'
    'git[[:space:]]+push[[:space:]].*--force-with-lease'
    'git[[:space:]]+reset[[:space:]]+--hard[[:space:]]+(origin|HEAD~|main|master)'
    'sudo[[:space:]]+rm'
)

capture() {
    local cat="$1"; local msg="$2"
    if [ -f "$CAPTURE" ]; then
        bash "$CAPTURE" "$cat" "$msg" "$CMD" >/dev/null 2>&1 || true
    fi
}

for pattern in "${CATASTROPHIC_PATTERNS[@]}"; do
    if printf '%s' "$CMD" | grep -qE "$pattern"; then
        printf '\033[31m[goax hook]\033[0m 🚨 CATASTROPHIC 명령 차단 (mode 무관): %s\n' "$pattern" >&2
        printf '명령: %s\n' "$CMD" >&2
        capture "destructive-catastrophic" "차단된 catastrophic 패턴: $pattern"
        exit 2
    fi
done

[ "$SENSOR_MODE" = "off" ] && exit 0

for pattern in "${RECOVERABLE_PATTERNS[@]}"; do
    if printf '%s' "$CMD" | grep -qE "$pattern"; then
        if [ "$SENSOR_MODE" = "fail" ]; then
            printf '\033[31m[goax hook]\033[0m 차단된 파괴적 패턴 (mode=fail): %s\n' "$pattern" >&2
            printf '명령: %s\n' "$CMD" >&2
            printf '우회가 필요하면 사용자에게 명시적 승인을 받아 직접 실행해.\n' >&2
            capture "destructive-recoverable" "mode=fail 차단: $pattern"
            exit 2
        else
            printf '\033[33m[goax hook]\033[0m ⚠ 파괴적 패턴 (mode=%s, 경고만): %s\n' "$SENSOR_MODE" "$pattern" >&2
            printf '명령: %s\n' "$CMD" >&2
            capture "destructive-recoverable" "mode=$SENSOR_MODE 경고: $pattern"
            exit 0
        fi
    fi
done

exit 0
