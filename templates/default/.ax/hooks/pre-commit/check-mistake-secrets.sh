#!/usr/bin/env bash
# pre-commit hook — staged .ax/mistakes/*.md 본문에서 redact_secrets 가 잡는
# 시크릿 추정 패턴이 남아있는지 재검증.
#
# 왜 별도 hook: init-mistake-file.sh 가 capture 시점에 ONE_LINE 만 redact 적용함.
#   본문 5섹션은 LLM 이 Edit 으로 채우므로, AWS AKIA / GitHub ghp_ / Slack xox /
#   Stripe sk_live / JWT / PEM / key=value≥12자 가 그대로 들어갈 수 있음. commit
#   시점에 한 번 더 막아주는 안전망.
#
# Dual-use:
#   1) Claude Code PreToolUse:Bash on `git commit` (grep-on-commit.sh chain)
#   2) git pre-commit symlink — 동일 동작
#
# 위반 발견 시:
#   - mode=fail   → exit 2 (차단)
#   - mode=warn   → stderr 경고 + exit 0
# mistake 기록은 사용자 명시 `mistake` skill 호출로만 — hook 자동 capture 폐기.

set -uo pipefail

# Bootstrap guard — install 중간이거나 .ax/ 부분 정리 시 silent skip
[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"

# common.sh 없으면 silent skip (redact_secrets 함수 의존)
[ -f "$COMMON" ] || exit 0
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"

SENSOR_MODE=$(goax_mode 2>/dev/null || echo warning)
[ "$SENSOR_MODE" = "off" ] && exit 0

# staged .ax/mistakes/*.md 만 검사 (subdirectory 제외 — _archive/ 등)
STAGED=$(cd "$PROJECT_ROOT" && git diff --cached --name-only --diff-filter=ACMR 2>/dev/null \
        | grep -E '^\.ax/mistakes/[^/]+\.md$' \
        | grep -v '/README\.md$' || true)
[ -z "$STAGED" ] && exit 0

LEAK_FILES=""
LEAK_COUNT=0
while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    f="$PROJECT_ROOT/$rel"
    [ -f "$f" ] || continue
    ORIG=$(cat "$f")
    RED=$(printf '%s' "$ORIG" | redact_secrets)
    if [ "$ORIG" != "$RED" ]; then
        LEAK_FILES="${LEAK_FILES}${rel}\n"
        LEAK_COUNT=$((LEAK_COUNT + 1))
    fi
done <<< "$STAGED"

if [ "$LEAK_COUNT" -gt 0 ]; then
    printf '\033[31m[goax pre-commit]\033[0m mistake 파일에 시크릿 추정 패턴이 남아있어요 (%d건):\n' "$LEAK_COUNT" >&2
    printf '%b' "$LEAK_FILES" | sed 's/^/  - /' >&2
    printf '\n조치: 해당 파일을 열어 [REDACTED:...] 로 치환 후 다시 commit 하세요.\n' >&2
    printf '       (탐지 패턴: AWS AKIA·GitHub ghp_·Slack xox·Stripe sk_live·JWT·PEM·key=value≥12자)\n' >&2
    if [ "$SENSOR_MODE" = "fail" ]; then
        printf '[goax] ✗ mistake secrets %d건 — 차단 (mode=fail)\n' "$LEAK_COUNT" >&2
        exit 2
    fi
    printf '[goax] ⚠ mistake secrets %d건 — 경고만 (mode=%s)\n' "$LEAK_COUNT" "$SENSOR_MODE" >&2
    exit 0
fi

exit 0
