#!/usr/bin/env bash
# pre-edit hook — Spirit 변경 시 명시적 확인 + 매칭 룰 알림
#
# Claude Code 공식 hook 입력: stdin JSON ({tool_name, tool_input.file_path, ...}).
# 정보 출력만 — 차단 안 함 (exit 0).
set -uo pipefail   # set -e 제거 — grep returning 1 (no match) 등이 hook 본체를 silent abort하지 않도록

# Bootstrap guard — install 중간이거나 .ax/ 부분 정리 시 silent skip (UX 노이즈 방지)
[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

# stdin JSON 파싱
INPUT="$(cat 2>/dev/null || true)"
TARGET_PATH=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    TARGET_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
fi
TARGET_PATH="${TARGET_PATH:-${CLAUDE_EDIT_PATH:-${1:-}}}"
[ -z "$TARGET_PATH" ] && exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SPIRIT_DIR="$PROJECT_ROOT/.ax/spirit"

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
