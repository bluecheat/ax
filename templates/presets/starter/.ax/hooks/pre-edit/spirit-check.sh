#!/usr/bin/env bash
# pre-edit hook — Spirit 변경 시 명시적 확인 + 매칭 룰 알림
set -euo pipefail

TARGET_PATH="${CLAUDE_EDIT_PATH:-${1:-}}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SPIRIT_DIR="$PROJECT_ROOT/.ax/spirit"

[ -z "${TARGET_PATH:-}" ] && exit 0
[ -d "$SPIRIT_DIR" ] || exit 0

# 1. spirit/ 자체 변경 시 강한 경고
TARGET_REL="${TARGET_PATH#$PROJECT_ROOT/}"
if [[ "$TARGET_REL" == .ax/spirit/* ]]; then
    printf '\033[33m[spirit hook]\033[0m Spirit 디렉토리 변경 시도: %s\n' "$TARGET_REL" >&2
    printf '             values/tone/rules 변경은 모든 sub-agent에 영향. 의도 확인 후 진행해.\n' >&2
fi

# 2. 변경 파일에 적용되는 spirit 룰 알림 (정성)
# applies_to에 'code'가 있는 카테고리들의 ID를 표시
if [ -d "$SPIRIT_DIR/rules" ]; then
    case "$TARGET_PATH" in
        *.ts|*.tsx|*.js|*.jsx|*.py|*.go|*.kt|*.kts|*.rs|*.rb)
            printf '\033[36m[spirit]\033[0m 적용 가능한 룰 (참고):\n' >&2
            grep -hE '^## SP-' "$SPIRIT_DIR/rules"/*.md 2>/dev/null \
                | head -10 \
                | sed 's/^## /  /' >&2 || true
            ;;
    esac
fi

exit 0
