#!/usr/bin/env bash
# pre-commit hook — CRITICAL 룰 패턴을 staged 파일에서 검출
set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONSTITUTION="$PROJECT_ROOT/CLAUDE.md"
CONFIG="$PROJECT_ROOT/.ax-first/config.yml"

[ -f "$CONSTITUTION" ] || { echo "[ax-first] CLAUDE.md 없음 — skip" >&2; exit 0; }

SENSOR_MODE="warning"
[ -f "$CONFIG" ] && SENSOR_MODE=$(grep -E '^[[:space:]]*mode:' "$CONFIG" | head -1 | awk '{print $2}' || echo warning)

EXIT_CODE=0
STAGED=$(git diff --cached --name-only 2>/dev/null || true)
[ -z "$STAGED" ] && { echo "[ax-first] staged 파일 없음" >&2; exit 0; }

echo "[ax-first] CRITICAL 룰 검사 (mode=$SENSOR_MODE) — 대상 $(echo "$STAGED" | wc -l | tr -d ' ')개 파일"

echo "$STAGED" | while read -r f; do
    [ -z "$f" ] || [ ! -f "$f" ] && continue
    case "$f" in
        *.ts|*.tsx)
            if grep -nE 'typeof window[[:space:]]*[!=]==[[:space:]]*"undefined"' "$f" 2>/dev/null; then
                echo "  ⚠ $f: typeof window 분기 — Hydration 위험" >&2
                [ "$SENSOR_MODE" = "fail" ] && EXIT_CODE=1
            fi
            ;;
        *.kt|*.kts)
            if grep -nE '^[[:space:]]*var[[:space:]]+[a-zA-Z_]+:[[:space:]]+' "$f" 2>/dev/null | grep -qE 'domain/(model|entity)'; then
                echo "  ⚠ $f: domain에 var — val 권장" >&2
                [ "$SENSOR_MODE" = "fail" ] && EXIT_CODE=1
            fi
            ;;
    esac
done

ENTITY_CHANGED=$(echo "$STAGED" | grep -E '(entity|Entity).*\.(kt|ts)$' || true)
if [ -n "$ENTITY_CHANGED" ]; then
    SQL_CHANGED=$(echo "$STAGED" | grep -E 'migrations?/.*\.sql$' || true)
    if [ -z "$SQL_CHANGED" ]; then
        echo "  ⚠ Entity 변경 감지 — 마이그레이션 SQL 동반 누락" >&2
        [ "$SENSOR_MODE" = "fail" ] && EXIT_CODE=1
    fi
fi

if echo "$STAGED" | xargs -I{} sh -c 'test -f "{}" && grep -lE "(password|secret|api[_-]?key|token).*=.*[\"\x27]" "{}" 2>/dev/null' 2>/dev/null | head -1 | grep -q .; then
    echo "  ⚠ Secrets 추정 패턴 발견 — staged 파일 점검" >&2
    [ "$SENSOR_MODE" = "fail" ] && EXIT_CODE=1
fi

[ "$EXIT_CODE" = "0" ] && echo "[ax-first] ✓ CRITICAL 검사 통과 ($SENSOR_MODE)"
exit "$EXIT_CODE"
