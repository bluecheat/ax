#!/usr/bin/env bash
# .ax/scripts/bash/check-spec-clarity.sh — spec.md 명료성 게이팅 + 진행률 visibility
#
# Usage:
#   bash check-spec-clarity.sh --spec <NNN-slug> [--json] [--help]
#   bash check-spec-clarity.sh --file <path>     [--json] [--help]
#
# 검사 항목 (게이팅 — fail 시 진행 차단):
#   1. 미해결 마커 `**NEEDS CLARIFICATION**` 잔존 → fail
#      (마커 형식만 — 산문에서 이름을 언급하는 건 안 잡아요)
#   2. placeholder `<...>` 본문 잔존        → fail
#      (표 셀 `^|` · URL `<http...>` · code fence ``` 화이트리스트)
#   3. 필수 섹션 본문 1 라인 이상           → fail
#      (§1.1 한 줄 정의, §3 성공 기준, §4 사용자 시나리오)
#
# 진행률 visibility (게이팅 X — 사용자 인지용):
#   4. tasks.md 의 - [ ] / - [x] 비율 (있으면)
#   5. spec.md §3 (성공 기준) AC 의 - [ ] / - [x] 비율
#
# 4·5 는 spec-implement 우회로 코드 commit 했을 때 체크박스 동기화 누락을
# 즉시 노출. status 에 영향 X (warning 으로 표시).
#
# Output (--json):
#   {"status":"ok"|"error",
#    "result":{"file":"...", "needs_clarification":N, "placeholders":N,
#              "empty_sections":[...],
#              "tasks_progress":{"total":N,"completed":N,"open":N},
#              "ac_progress":{"total":N,"completed":N,"open":N}},
#    "next_step":"...",
#    "warnings":[...],
#    "errors":[...]}
#
# Exit: 0 ok | 1 fail | 2 skipped

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
SHOW_HELP=false
SPEC=""
FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --help|-h) SHOW_HELP=true ;;
        --spec)    shift; SPEC="${1:-}" ;;
        --file)    shift; FILE="${1:-}" ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n "2,33p" "${BASH_SOURCE[0]}" | sed 's/^# //; s/^#//'
    exit "$EXIT_OK"
fi

# 대상 파일 결정
if [ -n "$FILE" ]; then
    TARGET="$FILE"
elif [ -n "$SPEC" ]; then
    PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
    SPEC_DIR="$PROJECT_ROOT/.ax/docs/spec/$SPEC"
    if [ ! -d "$SPEC_DIR" ]; then
        MATCH=$(ls -d "$PROJECT_ROOT/.ax/docs/spec/${SPEC}-"* 2>/dev/null | head -1 || true)
        [ -n "$MATCH" ] && SPEC_DIR="$MATCH"
    fi
    TARGET="$SPEC_DIR/spec.md"
else
    if [ "$JSON_MODE" = true ]; then
        json_error "--spec or --file required"
    else
        goax_error "--spec or --file required"
        exit "$EXIT_ERROR"
    fi
fi

if [ ! -f "$TARGET" ]; then
    if [ "$JSON_MODE" = true ]; then
        json_error "file not found: $TARGET"
    else
        goax_error "file not found: $TARGET"
        exit "$EXIT_ERROR"
    fi
fi

# code fence 라인 제거한 본문을 임시 파일로
TMP_BODY=$(mktemp)
trap 'rm -f "$TMP_BODY"' EXIT
awk '
    /^```/ { in_fence = !in_fence; print ""; next }
    { if (in_fence) print ""; else print }
' "$TARGET" > "$TMP_BODY"

# 1. NEEDS CLARIFICATION 검사
# 마커 형식 `**NEEDS CLARIFICATION**` 만 — 템플릿 헤더·안내문이 이름을 산문으로
# 언급하는 걸 마커로 세면 "성실히 채운 spec" 이 통과할 수 없어요.
NEEDS_LINES=$(grep -nE '\*\*NEEDS CLARIFICATION\*\*' "$TMP_BODY" 2>/dev/null || true)
if [ -z "$NEEDS_LINES" ]; then
    NEEDS_COUNT=0
else
    NEEDS_COUNT=$(printf '%s\n' "$NEEDS_LINES" | wc -l | tr -d ' ')
fi

# 2. placeholder `<...>` 검사 — 표 row · URL 제외
PLACEHOLDER_LINES=$(grep -nE "<[가-힣A-Za-z0-9 _·,/\.\-]+>" "$TMP_BODY" 2>/dev/null \
    | grep -vE "^[0-9]+:[[:space:]]*\|" \
    | grep -vE "<https?://" \
    | grep -vE "<[A-Za-z][A-Za-z0-9.+-]*@" \
    || true)
if [ -z "$PLACEHOLDER_LINES" ]; then
    PLACEHOLDER_COUNT=0
else
    PLACEHOLDER_COUNT=$(printf '%s\n' "$PLACEHOLDER_LINES" | wc -l | tr -d ' ')
fi

# 3. 필수 섹션 본문 검사 (§1.1, §3, §4)
# 본문 = 다음 `## ` 또는 `### ` 가 나오기 전까지의 비어있지 않은 라인
EMPTY_SECTIONS=()

check_section_body() {
    local section_re="$1"
    local label="$2"
    local count
    count=$(awk -v re="$section_re" '
        $0 ~ re { in_sec=1; next }
        in_sec && /^(## |### )/ { in_sec=0 }
        in_sec && /^---$/ { next }
        in_sec && NF { print }
    ' "$TMP_BODY" | grep -cvE "^[[:space:]]*$" || true)
    if [ "${count:-0}" -lt 1 ]; then
        EMPTY_SECTIONS+=("$label")
    fi
}

check_section_body '^### 1\.1' "§1.1 한 줄 정의"
check_section_body '^## 3\.' "§3 성공 기준"
check_section_body '^## 4\.' "§4 사용자 시나리오"

# 4. tasks.md 진행률 (visibility — 게이팅 X)
TASKS_FILE="$(dirname "$TARGET")/tasks.md"
TASKS_TOTAL=0
TASKS_COMPLETED=0
TASKS_OPEN=0
if [ -f "$TASKS_FILE" ]; then
    # code fence 안의 형식 설명 (`- [ ] T001 …`) 은 실 task 가 아니에요 — 걷어내고 세요
    TASKS_BODY=$(awk '
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }
        { print }
    ' "$TASKS_FILE")
    TASKS_COMPLETED=$(printf '%s\n' "$TASKS_BODY" | grep -cE '^- \[x\]' 2>/dev/null || true)
    TASKS_OPEN=$(printf '%s\n' "$TASKS_BODY" | grep -cE '^- \[ \]' 2>/dev/null || true)
    TASKS_TOTAL=$((TASKS_COMPLETED + TASKS_OPEN))
fi

# 5. AC (성공 기준) 진행률 (visibility — 게이팅 X)
# spec.md §3 안의 - [ ] / - [x] 만 추출 — 다른 섹션의 체크박스는 무시
AC_TOTAL=0
AC_COMPLETED=0
AC_OPEN=0
AC_BODY=$(awk '
    /^## 3\./ { in_sec=1; next }
    in_sec && /^## / { in_sec=0 }
    in_sec { print }
' "$TMP_BODY")
if [ -n "$AC_BODY" ]; then
    AC_COMPLETED=$(printf '%s\n' "$AC_BODY" | grep -cE '^- \[x\]' 2>/dev/null || true)
    AC_OPEN=$(printf '%s\n' "$AC_BODY" | grep -cE '^- \[ \]' 2>/dev/null || true)
    AC_TOTAL=$((AC_COMPLETED + AC_OPEN))
fi

# 결과 집계
ERRORS=()
[ "$NEEDS_COUNT" -gt 0 ] && ERRORS+=("NEEDS CLARIFICATION 잔존: ${NEEDS_COUNT}건")
[ "$PLACEHOLDER_COUNT" -gt 0 ] && ERRORS+=("placeholder 잔존: ${PLACEHOLDER_COUNT}건")
[ ${#EMPTY_SECTIONS[@]} -gt 0 ] && ERRORS+=("빈 섹션: ${EMPTY_SECTIONS[*]}")

# warnings — 진행률 visibility (게이팅 영향 X)
WARNINGS=()
if [ "$TASKS_TOTAL" -gt 0 ] && [ "$TASKS_OPEN" -gt 0 ]; then
    WARNINGS+=("tasks 진행률: ${TASKS_COMPLETED}/${TASKS_TOTAL} (미체크 ${TASKS_OPEN}건)")
fi
if [ "$AC_TOTAL" -gt 0 ] && [ "$AC_OPEN" -gt 0 ]; then
    WARNINGS+=("AC 진행률: ${AC_COMPLETED}/${AC_TOTAL} (미체크 ${AC_OPEN}건)")
fi

STATUS="ok"
NEXT_STEP="spec.md 명료성 통과 — plan/tasks 진행 가능"
if [ ${#ERRORS[@]} -gt 0 ]; then
    STATUS="error"
    NEXT_STEP="errors 항목 해소 후 재검사"
elif [ ${#WARNINGS[@]} -gt 0 ]; then
    NEXT_STEP="명료성 통과 — 진행률 미동기화 항목 검토 (spec-implement 우회 여부)"
fi

# JSON 출력
if [ "$JSON_MODE" = true ]; then
    # empty_sections array
    if [ ${#EMPTY_SECTIONS[@]} -eq 0 ]; then
        empty_json="[]"
    else
        empty_json="["
        first=true
        for s in "${EMPTY_SECTIONS[@]}"; do
            [ "$first" = true ] || empty_json+=","
            empty_json+="\"$(printf '%s' "$s" | sed 's/"/\\"/g')\""
            first=false
        done
        empty_json+="]"
    fi

    # warnings array
    if [ ${#WARNINGS[@]} -eq 0 ]; then
        warnings_json="[]"
    else
        warnings_json="["
        first=true
        for w in "${WARNINGS[@]}"; do
            [ "$first" = true ] || warnings_json+=","
            warnings_json+="\"$(printf '%s' "$w" | sed 's/"/\\"/g')\""
            first=false
        done
        warnings_json+="]"
    fi

    RESULT=$(printf '{"file":"%s","needs_clarification":%s,"placeholders":%s,"empty_sections":%s,"tasks_progress":{"total":%s,"completed":%s,"open":%s},"ac_progress":{"total":%s,"completed":%s,"open":%s}}' \
                    "$TARGET" "$NEEDS_COUNT" "$PLACEHOLDER_COUNT" "$empty_json" \
                    "$TASKS_TOTAL" "$TASKS_COMPLETED" "$TASKS_OPEN" \
                    "$AC_TOTAL" "$AC_COMPLETED" "$AC_OPEN")

    if [ "$STATUS" = "ok" ]; then
        printf '{"status":"ok","result":%s,"next_step":"%s","warnings":%s}\n' \
               "$RESULT" "$NEXT_STEP" "$warnings_json"
    else
        # errors array
        errors_json="["
        first=true
        for e in "${ERRORS[@]}"; do
            [ "$first" = true ] || errors_json+=","
            errors_json+="\"$(printf '%s' "$e" | sed 's/"/\\"/g')\""
            first=false
        done
        errors_json+="]"
        printf '{"status":"error","result":%s,"next_step":"%s","warnings":%s,"errors":%s}\n' \
               "$RESULT" "$NEXT_STEP" "$warnings_json" "$errors_json"
        exit "$EXIT_ERROR"
    fi
else
    if [ "$STATUS" = "ok" ]; then
        goax_log "✓ $TARGET — 명료성 통과 (NEEDS=0, placeholders=0, 빈 섹션 없음)"
        if [ ${#WARNINGS[@]} -gt 0 ]; then
            for w in "${WARNINGS[@]}"; do
                goax_warn "$w"
            done
        fi
    else
        goax_error "✗ $TARGET — 명료성 미통과"
        for e in "${ERRORS[@]}"; do
            printf '  - %s\n' "$e" >&2
        done
        if [ ${#WARNINGS[@]} -gt 0 ]; then
            for w in "${WARNINGS[@]}"; do
                goax_warn "$w"
            done
        fi
        exit "$EXIT_ERROR"
    fi
fi
