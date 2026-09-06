#!/usr/bin/env bash
# UserPromptSubmit hook — implementation intent 감지 + triage idle 시 nudge
#
# Claude Code 공식 동작:
#   stdout으로 출력하면 system-reminder로 모델에 주입됨.
#   exit 0 = pass-through, exit 2 = 차단 (이 hook은 차단 X, 안내만).
#
# 노이즈 방지:
#   - phase=idle 일 때만 nudge (작업 중이면 silent)
#   - 명시적 우회 신호("그냥", "빠르게", "skip", "no triage")가 있으면 silent
#   - 같은 세션에서 한 번만 (.ax/.triage-nudged 마커)

set -uo pipefail   # set -e 제거 — grep returning 1 (no match) 등이 hook 본체를 silent abort하지 않도록

# Bootstrap guard — install 중간이거나 .ax/ 부분 정리 시 silent skip (UX 노이즈 방지)
[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
PROMPT=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // .user_message // empty' 2>/dev/null || true)
fi
[ -z "$PROMPT" ] && exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TASK_FILE="$PROJECT_ROOT/.ax/current-task.json"
NUDGED_MARKER="$PROJECT_ROOT/.ax/.triage-nudged"

# 마커 만료 — 4시간(14400초) 이상이면 무효화 (재nudge 허용)
# 새 작업 사이클이면 다시 nudge 가능해야 함
NUDGE_TTL=14400
if [ -f "$NUDGED_MARKER" ]; then
    # GNU stat 이 먼저예요 — GNU 의 `stat -f` 는 파일시스템 모드라 실패해도 stdout 에 글자를 찍어서 뒤 fallback 과 섞여요
    NUDGED_AT=$(stat -c %Y "$NUDGED_MARKER" 2>/dev/null || stat -f %m "$NUDGED_MARKER" 2>/dev/null || echo 0)
    case "$NUDGED_AT" in ''|*[!0-9]*) NUDGED_AT=0 ;; esac
    NOW=$(date +%s)
    AGE=$((NOW - NUDGED_AT))
    if [ "$AGE" -lt "$NUDGE_TTL" ]; then
        exit 0
    fi
    rm -f "$NUDGED_MARKER"
fi

# phase 확인 — idle 또는 파일 없음만 nudge 대상
# updated_at이 4시간+ 지났으면 stale 작업으로 간주, phase 무시하고 idle 취급
PHASE="idle"
UPDATED_AT=""
if [ -f "$TASK_FILE" ] && command -v jq >/dev/null 2>&1; then
    PHASE=$(jq -r '.phase // "idle"' "$TASK_FILE" 2>/dev/null || echo idle)
    UPDATED_AT=$(jq -r '.updated_at // empty' "$TASK_FILE" 2>/dev/null || echo "")
fi

TASK_TTL=14400  # 4시간
if [ "$PHASE" != "idle" ] && [ -n "$UPDATED_AT" ]; then
    # ISO-8601 (Z=UTC) → epoch
    # BSD/macOS: -j -u -f (UTC 명시 필수), GNU/Linux: -d 가 자동 인식
    UPDATED_EPOCH=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$UPDATED_AT" +%s 2>/dev/null \
                    || date -d "$UPDATED_AT" +%s 2>/dev/null \
                    || echo 0)
    if [ "$UPDATED_EPOCH" -gt 0 ]; then
        NOW=$(date +%s)
        AGE=$((NOW - UPDATED_EPOCH))
        if [ "$AGE" -ge "$TASK_TTL" ]; then
            PHASE="idle"  # stale → 새 작업 시작으로 간주
        fi
    fi
fi
[ "$PHASE" != "idle" ] && exit 0

# 명시적 우회 신호 — *의식적 표명*만 인식 (일반 단어 false silent 방지)
# "그냥/빠르게" 단독은 인식 X — 일반 표현이라 false silent 위험
BYPASS_RE='(skip[[:space:]]+triage|no[[:space:]]+triage|without[[:space:]]+triage|triage[[:space:]]+(없이|건너뛰|skip)|분류[[:space:]]+없이)'
if printf '%s' "$PROMPT" | grep -qiE "$BYPASS_RE"; then
    exit 0
fi

# implementation intent — 광범위 regex (한국어+영어)
INTENT_RE='(구현|만들|추가|고치|수정|변경|리팩토링|리팩터링|버그|만드는|개발|작업.{0,3}계획|어떻게|implement|add[[:space:]]|update[[:space:]]|refactor|create[[:space:]]|build[[:space:]]|develop|fix[[:space:]]|how[[:space:]]+(do|to))'

if ! printf '%s' "$PROMPT" | grep -qiE "$INTENT_RE"; then
    exit 0
fi

# 마커 생성 (같은 세션 재발 방지)
touch "$NUDGED_MARKER" 2>/dev/null || true

# 모델에 nudge 주입
# 주의: Claude Code의 UserPromptSubmit hook은 stdout을 user prompt에 prepend함.
# system-reminder 태그가 인식되지 않으면 일반 텍스트로 들어가도 reminder 효력은 유지.
cat <<'EOF'
<system-reminder>
[goax] 구현 의도 감지 + current-task phase=idle.
권장 다음 행동: triage skill 호출 → Size×Risk 분류 → 권장 경로 결정.
사용자가 "skip triage" / "triage 없이" / "분류 없이" 같이 명시 우회 의사를 보였으면 이 reminder 무시.
이 reminder는 4시간당 1회만 표시.
</system-reminder>
EOF

exit 0
