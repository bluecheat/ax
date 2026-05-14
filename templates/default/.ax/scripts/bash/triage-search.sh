#!/usr/bin/env bash
# .ax/scripts/bash/triage-search.sh — triage 1.2 단계의 관련 자료 grep을 결정론으로 처리
#
# Usage:
#   bash triage-search.sh --keywords "payment refund settlement" [--json] [--help]
#
# Output (--json):
#   {"status":"ok","result":{
#       "specs":[...], "adrs":[...], "mistakes":[...],
#       "rules":[...], "modules":[...], "imported":[...]
#    },"next_step":"...","warnings":[],"errors":[]}
#
# 동작: KEYWORDS를 alternation 패턴(`a|b|c`)으로 만들고 6 군데 grep.
#   - specs:    .ax/docs/spec/NNN-<slug>/ 디렉토리 이름 매칭
#   - adrs:     .ax/docs/adr/*.md 본문 매칭
#   - mistakes: .ax/mistakes/*.md 본문 매칭
#   - rules:    CLAUDE.md + .ax/spirit/rules/*.md 본문 매칭
#   - modules:  .ax/modules/*/rules.md 의 keywords: 배열 word-boundary 매칭
#   - imported: .ax/docs/spec/imported/*.md 본문 매칭

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
SHOW_HELP=false
KEYWORDS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --keywords)
            shift
            [ $# -eq 0 ] && { goax_error "--keywords requires a value"; exit "$EXIT_ERROR"; }
            KEYWORDS="$1"
            ;;
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# //; s/^#//'
    exit "$EXIT_OK"
fi

if [ -z "$KEYWORDS" ]; then
    if [ "$JSON_MODE" = true ]; then
        json_error "--keywords is required"
    else
        goax_error "--keywords is required"
        exit "$EXIT_ERROR"
    fi
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
cd "$PROJECT_ROOT"

# 키워드 → alternation 패턴 (공백 분리, 빈 토큰 제거)
ALT=$(printf '%s' "$KEYWORDS" | tr -s ' ' '|' | sed 's/^|//; s/|$//')

if [ -z "$ALT" ]; then
    if [ "$JSON_MODE" = true ]; then
        json_error "keywords resolved to empty pattern"
    else
        goax_error "keywords resolved to empty pattern"
        exit "$EXIT_ERROR"
    fi
fi

# dry-run: 검색 안 하고 어떤 명령이 실행될지만 출력
if [ "$DRY_RUN" = true ]; then
    if [ "$JSON_MODE" = true ]; then
        json_output "ok" "{\"alt\":\"$ALT\",\"dry_run\":true}" "검색 안 함 — alternation 패턴만 출력했어요"
    else
        printf 'pattern: %s\n' "$ALT"
        printf '(dry-run — 검색 실행 안 함)\n'
    fi
    exit "$EXIT_OK"
fi

# 결과를 줄 단위로 모으는 helper
# (배열 사용 — bash 3.x 호환 위해 일반 array, mapfile 안 씀)
collect_lines() {
    # stdin → 정렬·dedup → 결과 라인. 빈 줄 제거.
    grep -v '^$' | sort -u
}

# 1) specs: 디렉토리 이름 매칭
SPECS=$(find .ax/docs/spec -maxdepth 2 -type d 2>/dev/null \
        | grep -iE "($ALT)" 2>/dev/null \
        | head -10 \
        | collect_lines 2>/dev/null || true)

# 2) adrs: 본문 매칭
ADRS=$(grep -rilE "($ALT)" .ax/docs/adr 2>/dev/null \
       | head -10 \
       | collect_lines 2>/dev/null || true)

# 3) mistakes: 본문 매칭
MISTAKES=$(grep -rilE "($ALT)" .ax/mistakes 2>/dev/null \
           | head -10 \
           | collect_lines 2>/dev/null || true)

# 4) rules: CLAUDE.md + .ax/spirit/rules/
RULES=$(grep -ilE "($ALT)" CLAUDE.md .ax/spirit/rules/*.md 2>/dev/null \
        | head -10 \
        | collect_lines 2>/dev/null || true)

# 5) modules: .ax/modules/<n>/rules.md 의 keywords: 배열 word-boundary 매칭
#    (단어 경계 보장 — "ad"가 "payment" 안에 false-positive 안 남)
MODULES=""
for module_dir in .ax/modules/*/; do
    [ -d "$module_dir" ] || continue
    [ -f "${module_dir}rules.md" ] || continue
    KW_LINE=$(grep -E '^keywords:' "${module_dir}rules.md" 2>/dev/null | head -1)
    [ -z "$KW_LINE" ] && continue
    MATCHED=$(printf '%s' "$KW_LINE" | grep -oiE "(\[|, )($ALT)(\]|,| )" 2>/dev/null \
              | head -1 | tr -d '[],| ' || true)
    if [ -n "$MATCHED" ]; then
        MODULES="${MODULES}${module_dir}rules.md|${MATCHED}"$'\n'
    fi
done
MODULES=$(printf '%s' "$MODULES" | collect_lines 2>/dev/null || true)

# 6) imported: 외부 spec 흡수본
IMPORTED=$(grep -rilE "($ALT)" .ax/docs/spec/imported 2>/dev/null \
           | head -10 \
           | collect_lines 2>/dev/null || true)

# JSON build
to_json_array() {
    # stdin 라인을 JSON array로. jq 있으면 jq, 없으면 manual.
    local lines="$1"
    if [ -z "$lines" ]; then
        printf '[]'
        return
    fi
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$lines" | jq -R -s -c 'split("\n") | map(select(. != ""))'
    else
        local first=1
        printf '['
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            esc=$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')
            if [ $first -eq 1 ]; then
                printf '"%s"' "$esc"; first=0
            else
                printf ',"%s"' "$esc"
            fi
        done <<< "$lines"
        printf ']'
    fi
}

SPECS_J=$(to_json_array "$SPECS")
ADRS_J=$(to_json_array "$ADRS")
MISTAKES_J=$(to_json_array "$MISTAKES")
RULES_J=$(to_json_array "$RULES")
MODULES_J=$(to_json_array "$MODULES")
IMPORTED_J=$(to_json_array "$IMPORTED")

RESULT="{\"specs\":$SPECS_J,\"adrs\":$ADRS_J,\"mistakes\":$MISTAKES_J,\"rules\":$RULES_J,\"modules\":$MODULES_J,\"imported\":$IMPORTED_J}"

# 매칭 카운트로 next_step 작성
TOTAL=$(printf '%s\n%s\n%s\n%s\n%s\n%s' "$SPECS" "$ADRS" "$MISTAKES" "$RULES" "$MODULES" "$IMPORTED" \
        | grep -cv '^$' 2>/dev/null || echo 0)

if [ "$TOTAL" -eq 0 ]; then
    NEXT="매칭 자료 없음 — 기존 컨텍스트 없이 신규 작업으로 분류해요"
else
    NEXT="${TOTAL}개 자료 매칭 — 분류 결과의 Required reading 에 첨부해요 (modules 매칭은 필수 포함)"
fi

if [ "$JSON_MODE" = true ]; then
    json_output "ok" "$RESULT" "$NEXT"
else
    printf 'specs:    %s\n' "${SPECS:-(none)}"
    printf 'adrs:     %s\n' "${ADRS:-(none)}"
    printf 'mistakes: %s\n' "${MISTAKES:-(none)}"
    printf 'rules:    %s\n' "${RULES:-(none)}"
    printf 'modules:  %s\n' "${MODULES:-(none)}"
    printf 'imported: %s\n' "${IMPORTED:-(none)}"
    printf '\n%s\n' "$NEXT"
fi

exit "$EXIT_OK"
