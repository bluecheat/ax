#!/usr/bin/env bash
# pre-commit hook — CRITICAL 룰 패턴을 staged 파일에서 검출
#
# Dual-use:
#   1) git pre-commit symlink: exit 1+ → commit 차단
#   2) Claude Code PreToolUse:Bash on `git commit`: exit 2 → tool call 차단
#
# 위반 발견 시:
#   - mode=fail   → exit 2 (차단)
#   - mode=warn   → stderr 경고 + exit 0
#   - 어느 모드든 capture-mistake.sh 자동 호출 (Mistake Loop cold-start 해소)

set -uo pipefail   # set -e 제거 — grep returning 1 (no match) 등이 hook 본체를 silent abort하지 않도록

# Bootstrap guard — install 중간이거나 .ax/ 부분 정리 시 silent skip (UX 노이즈 방지)
[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONSTITUTION="$PROJECT_ROOT/CLAUDE.md"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
CAPTURE="$PROJECT_ROOT/.ax/scripts/bash/capture-mistake.sh"

[ -f "$CONSTITUTION" ] || { echo "[goax] CLAUDE.md 없음 — skip" >&2; exit 0; }

# common.sh 사용 가능하면 goax_mode 통일 helper 활용
SENSOR_MODE="warning"
if [ -f "$COMMON" ]; then
    # shellcheck source=../../scripts/bash/common.sh
    source "$COMMON"
    SENSOR_MODE=$(goax_mode 2>/dev/null || echo warning)
else
    CONFIG="$PROJECT_ROOT/.ax/config.yml"
    [ -f "$CONFIG" ] && SENSOR_MODE=$(grep -E '^[[:space:]]*mode:' "$CONFIG" | head -1 | awk '{print $2}' || echo warning)
fi

[ "$SENSOR_MODE" = "off" ] && exit 0

VIOLATIONS=0

# 위반 보고 + capture
report() {
    local category="$1"; local message="$2"; local detail="${3:-}"
    printf '  ⚠ %s\n' "$message" >&2
    if [ -f "$CAPTURE" ]; then
        bash "$CAPTURE" "$category" "$message" "$detail" >/dev/null 2>&1 || true
    fi
    VIOLATIONS=$((VIOLATIONS + 1))
}

STAGED=$(git diff --cached --name-only 2>/dev/null || true)
[ -z "$STAGED" ] && { echo "[goax] staged 파일 없음" >&2; exit 0; }

echo "[goax] CRITICAL 룰 검사 (mode=$SENSOR_MODE) — 대상 $(echo "$STAGED" | wc -l | tr -d ' ')개 파일"

while IFS= read -r f; do
    [ -z "$f" ] || [ ! -f "$f" ] && continue
    case "$f" in
        *.ts|*.tsx)
            if grep -nE 'typeof window[[:space:]]*[!=]==[[:space:]]*"undefined"' "$f" >/dev/null 2>&1; then
                report "hydration" "$f: typeof window 분기 — Hydration 위험"
            fi
            ;;
        *.kt|*.kts)
            # 파일 경로가 domain/(model|entity) 하위인 경우에만 var 검출 (이전: grep -n 출력에 대한
            # 후속 grep으로 영원히 안 켜지던 dead code).
            if echo "$f" | grep -qE 'domain/(model|entity)' \
                    && grep -qE '^[[:space:]]*var[[:space:]]+[a-zA-Z_]+:[[:space:]]+' "$f" 2>/dev/null; then
                report "kotlin-mutable-domain" "$f: domain에 var — val 권장"
            fi
            ;;
    esac
done <<< "$STAGED"

ENTITY_CHANGED=$(echo "$STAGED" | grep -E '(entity|Entity).*\.(kt|ts)$' || true)
if [ -n "$ENTITY_CHANGED" ]; then
    SQL_CHANGED=$(echo "$STAGED" | grep -E 'migrations?/.*\.sql$' || true)
    if [ -z "$SQL_CHANGED" ]; then
        report "entity-without-migration" "Entity 변경 감지 — 마이그레이션 SQL 동반 누락" "$ENTITY_CHANGED"
    fi
fi

# secrets 검출 — xargs -I{} sh -c '...{}...'는 파일명에 `"`/백틱/`$` 들어가면 명령 주입 가능 → while-read 안전 loop으로 변경
SECRETS_HIT=0
while IFS= read -r f; do
    [ -z "$f" ] || [ ! -f "$f" ] && continue
    if grep -lE "(password|secret|api[_-]?key|token).*=.*[\"']" "$f" 2>/dev/null >/dev/null; then
        SECRETS_HIT=1
        break
    fi
done <<< "$STAGED"
if [ "$SECRETS_HIT" -eq 1 ]; then
    report "secrets" "Secrets 추정 패턴 발견 — staged 파일 점검"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
    if [ "$SENSOR_MODE" = "fail" ]; then
        echo "[goax] ✗ CRITICAL 위반 ${VIOLATIONS}건 — 차단 (mode=fail)" >&2
        exit 2
    fi
    echo "[goax] ⚠ CRITICAL 위반 ${VIOLATIONS}건 — 경고만 (mode=$SENSOR_MODE). .ax/mistakes/에 캡처됨" >&2
    exit 0
fi

echo "[goax] ✓ CRITICAL 검사 통과 (mode=$SENSOR_MODE)"
exit 0
