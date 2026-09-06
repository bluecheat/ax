#!/usr/bin/env bash
# pre-commit hook — staged .ax/mistakes/*.md 본문에서 redact_secrets 가 잡는
# 시크릿 추정 패턴이 남아있는지 재검증.
#
# 왜 별도 hook: init-mistake-file.sh 가 capture 시점에 ONE_LINE 만 redact 적용함.
#   본문 5섹션은 LLM 이 Edit 으로 채우므로, common.sh 의 `goax_secret_rules` 표가 아는
#   토큰 형태와 key=value≥12자 가 그대로 들어갈 수 있음. commit 시점에 한 번 더 막아주는 안전망.
#   무엇을 잡는지는 그 표가 SSOT — 여기도, 아래 안내 문구도 형태를 따로 적지 않아요.
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

# common.sh 가 없으면 redact_secrets 도 없어요 — 조용히 통과하지 않고 "안전망 비활성" 을 말하고 통과해요
# (critical-rule-grep.sh 와 같은 규약. 부분 설치·부분 정리 상태가 가장 흔한 시점이에요)
if [ ! -f "$COMMON" ]; then
    printf '[goax] common.sh 없음 — mistakes secrets 안전망 비활성 (.ax/scripts/bash/common.sh 복구 필요)\n' >&2
    exit 0
fi
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
    # 잡는 형태는 표에서 뽑아요 — 여기 손으로 적어두면 표가 늘 때마다 문구가 거짓말이 돼요
    printf '       (탐지 패턴: %skey=value≥12자)\n' \
        "$(goax_secret_rules | awk -F'\t' '($1=="both"||$1=="mask") && $2!="kv-mask" && !seen[$2]++ {printf "%s·", $2}')" >&2
    if [ "$SENSOR_MODE" = "fail" ]; then
        printf '[goax] ✗ mistake secrets %d건 — 차단 (mode=fail)\n' "$LEAK_COUNT" >&2
        exit 2
    fi
    printf '[goax] ⚠ mistake secrets %d건 — 경고만 (mode=%s)\n' "$LEAK_COUNT" "$SENSOR_MODE" >&2
    exit 0
fi

exit 0
