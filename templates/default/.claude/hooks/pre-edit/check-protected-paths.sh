#!/usr/bin/env bash
# pre-edit hook — 보호 경로 변경 시 명시적 확인
set -euo pipefail

TARGET_PATH="${CLAUDE_EDIT_PATH:-${1:-}}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG="$PROJECT_ROOT/.ax-first/config.yml"

[ -f "$CONFIG" ] || exit 0

PROTECTED=$(awk '/^[[:space:]]*protected_paths:/,/^[^[:space:]]/' "$CONFIG" 2>/dev/null \
    | grep -E '^[[:space:]]+- ' \
    | sed -E 's/^[[:space:]]+-[[:space:]]+//; s/[[:space:]]*$//')

[ -z "$PROTECTED" ] && exit 0

TARGET_REL="${TARGET_PATH#$PROJECT_ROOT/}"
for p in $PROTECTED; do
    if [[ "$TARGET_REL" == "$p" ]] || [[ "$TARGET_REL" == "$p"* ]]; then
        printf '\033[33m[ax-first hook]\033[0m 보호 경로 변경 시도: %s\n' "$TARGET_REL" >&2
        printf '이 변경이 의도적인지 사용자에게 확인 후 진행해.\n' >&2
        SENSOR_MODE=$(grep -E '^[[:space:]]*mode:' "$CONFIG" | head -1 | awk '{print $2}')
        if [ "$SENSOR_MODE" = "fail" ]; then
            exit 1
        fi
        exit 0
    fi
done
exit 0
