#!/usr/bin/env bash
# .ax/scripts/bash/rules-index.sh — 룰 통합 인덱스 (Constitution + Spirit + Module 세 소스)
#
# Usage:
#   bash rules-index.sh [--json]
#   bash rules-index.sh --level critical|mandatory|convention [--json]
#   bash rules-index.sh --source constitution|spirit|module [--json]
#   bash rules-index.sh --category <spirit 카테고리|모듈명> [--json]
#   bash rules-index.sh --find <토큰> [--json]        # 정확 매칭 1건 (예: AX:CRITICAL:001 · SP-SEC-002)
#
# 소스 셋 (rules skill 이 "grep 해서 찍어라" 로 시키던 것 — 이제 스크립트가 찍어요):
#   Constitution  AGENTS.md (시그널 라인이 있는 쪽, 없으면 CLAUDE.md) 의 `🔴/🟡/🔵 **`<scope>:<TIER>:<NNN>`**` 라인
#   Spirit        .ax/spirit/rules/<cat>.md 의 `## SP-<CAT>-<NNN>: 제목`   → 🔵 CONVENTION, category=파일명
#   Module        .ax/modules/<name>/rules.md 의 `## SP-<PFX>-<NNN>: 제목`  → 🔵 CONVENTION, category=모듈명
#
# 룰 본문은 요약하지 않아요 — 제목 줄 원문 그대로예요. 위반 검출은 hook (`pre-commit/critical-rule-grep.sh`) 몫이에요.
#
# Output (--json):
#   {"status":"ok","result":{"rules":[{"token":"…","level":"critical|mandatory|convention","source":"constitution|spirit|module",
#     "category":"…","text":"…","file":"…","line":N}],"counts":{"critical":N,"mandatory":N,"convention":N,"total":N},
#     "constitution_file":"AGENTS.md"},…}
# Exit: 0 ok · 1 error · 2 skipped (jq 없음, --json 일 때)

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; DRY_RUN=false
LEVEL=""; SOURCE=""; CATEGORY=""; FIND=""
while [ $# -gt 0 ]; do
    case "$1" in
        --json)     JSON_MODE=true ;;
        --dry-run)  DRY_RUN=true ;;          # 읽기 전용 — 표준 옵션 호환용
        --level)    shift; LEVEL="${1:-}" ;;
        --source)   shift; SOURCE="${1:-}" ;;
        --category) shift; CATEGORY="${1:-}" ;;
        --find)     shift; FIND="${1:-}" ;;
        --help|-h)  SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then
    sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "$EXIT_OK"
fi
case "$LEVEL" in ""|critical|mandatory|convention) ;; *) goax_error "--level 은 critical|mandatory|convention"; exit "$EXIT_ERROR" ;; esac
case "$SOURCE" in ""|constitution|spirit|module) ;; *) goax_error "--source 는 constitution|spirit|module"; exit "$EXIT_ERROR" ;; esac
if [ "$JSON_MODE" = true ] && ! command -v jq >/dev/null 2>&1; then
    printf '{"status":"skipped","result":{},"next_step":"jq 가 필요해요","warnings":["jq not found"],"errors":[]}\n'
    exit "$EXIT_SKIPPED"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
cd "$PROJECT_ROOT" || exit "$EXIT_ERROR"

# Constitution 파일 — 시그널 라인을 실제로 가진 쪽 (CLAUDE.md 가 @AGENTS.md alias 인 경우 대비)
RULES_FILE=""
for c in AGENTS.md CLAUDE.md; do
    [ -f "$c" ] && grep -qE '^(🔴|🟡|🔵) \*\*`' "$c" 2>/dev/null && { RULES_FILE="$c"; break; }
done
[ -z "$RULES_FILE" ] && [ -f AGENTS.md ] && RULES_FILE="AGENTS.md"
[ -z "$RULES_FILE" ] && [ -f CLAUDE.md ] && RULES_FILE="CLAUDE.md"

# 한 줄 = token<TAB>level<TAB>source<TAB>category<TAB>text<TAB>file<TAB>line
ROWS=""
add_row() { ROWS="${ROWS}$1	$2	$3	$4	$5	$6	$7
"; }

if [ -n "$RULES_FILE" ]; then
    while IFS= read -r ln; do
        [ -z "$ln" ] && continue
        n=${ln%%:*}; body=${ln#*:}
        case "$body" in
            🔴*) lv=critical ;; 🟡*) lv=mandatory ;; 🔵*) lv=convention ;; *) continue ;;
        esac
        tok=$(printf '%s' "$body" | sed -E 's/^[^`]*`([^`]+)`.*/\1/')
        txt=$(printf '%s' "$body" | sed -E 's/^[^`]*`[^`]+`\*\*[[:space:]]*//; s/^(—|–|-)[[:space:]]*//; s/[[:space:]]+$//')
        add_row "$tok" "$lv" constitution constitution "$txt" "$RULES_FILE" "$n"
    done < <(grep -nE '^(🔴|🟡|🔵) \*\*`[^`]+`\*\*' "$RULES_FILE" 2>/dev/null || true)
fi

scan_sp() {   # $1=file $2=source $3=category
    local f="$1" src="$2" cat="$3" ln n body tok txt
    while IFS= read -r ln; do
        [ -z "$ln" ] && continue
        n=${ln%%:*}; body=${ln#*:}
        tok=$(printf '%s' "$body" | sed -E 's/^## (SP-[A-Z]+-[0-9]{3}):.*/\1/')
        txt=$(printf '%s' "$body" | sed -E 's/^## SP-[A-Z]+-[0-9]{3}:[[:space:]]*//; s/[[:space:]]+$//')
        add_row "$tok" convention "$src" "$cat" "$txt" "${f#./}" "$n"
    done < <(grep -nE '^## SP-[A-Z]+-[0-9]{3}:' "$f" 2>/dev/null || true)
}
for f in .ax/spirit/rules/*.md; do
    [ -f "$f" ] || continue
    case "$f" in */README.md) continue ;; esac
    b=$(basename "$f" .md); scan_sp "$f" spirit "$b"
done
for f in .ax/modules/*/rules.md; do
    [ -f "$f" ] || continue
    m=$(basename "$(dirname "$f")"); scan_sp "$f" module "$m"
done

# 필터
FILTERED=$(printf '%s' "$ROWS" | awk -F'\t' -v lv="$LEVEL" -v src="$SOURCE" -v cat="$CATEGORY" -v find="$FIND" '
    NF < 7 { next }
    lv   != "" && $2 != lv   { next }
    src  != "" && $3 != src  { next }
    cat  != "" && $4 != cat  { next }
    find != "" && $1 != find { next }
    { print }')

count_lv() { printf '%s' "$FILTERED" | awk -F'\t' -v lv="$1" '$2==lv' | grep -c . || true; }
C_N=$(count_lv critical); M_N=$(count_lv mandatory); V_N=$(count_lv convention)
T_N=$(( C_N + M_N + V_N ))

if [ "$JSON_MODE" = true ]; then
    RJ=$(printf '%s' "$FILTERED" | jq -Rc 'split("\t") | select(length>=7) | {token:.[0],level:.[1],source:.[2],category:.[3],text:.[4],file:.[5],line:(.[6]|tonumber)}' | jq -sc .)
    RESULT=$(jq -nc --argjson r "$RJ" --arg c "$C_N" --arg m "$M_N" --arg v "$V_N" --arg t "$T_N" --arg cf "$RULES_FILE" \
        '{rules:$r,counts:{critical:($c|tonumber),mandatory:($m|tonumber),convention:($v|tonumber),total:($t|tonumber)},constitution_file:$cf}')
    if [ -n "$FIND" ] && [ "$T_N" -eq 0 ]; then
        json_output "warning" "$RESULT" "토큰 ${FIND} 없음 — 세 소스(Constitution·Spirit·Module) 어디에도 정의가 없어요"
    else
        json_output "ok" "$RESULT" "룰 ${T_N}개 (CRITICAL ${C_N} · MANDATORY ${M_N} · CONVENTION ${V_N})"
    fi
    exit "$EXIT_OK"
fi

print_level() {   # $1=level $2=헤더
    local lv="$1" hdr="$2" n
    n=$(count_lv "$lv"); [ "$n" -gt 0 ] || return 0
    printf '\n%s — %s\n' "$hdr" "$n"
    printf '%s' "$FILTERED" | awk -F'\t' -v lv="$lv" '$2==lv {
        src = ($3=="constitution") ? "Constitution" : (($3=="spirit") ? "Spirit/" $4 : "Module/" $4)
        printf " - %s — %s [%s]\n     📍 %s:%s\n", $1, $5, src, $6, $7 }'
}
printf '📜 goax rules — %s' "${RULES_FILE:-Constitution 없음}"
[ -n "$LEVEL$SOURCE$CATEGORY$FIND" ] && printf ' (필터: %s%s%s%s)' "${LEVEL:+level=$LEVEL }" "${SOURCE:+source=$SOURCE }" "${CATEGORY:+category=$CATEGORY }" "${FIND:+find=$FIND}"
printf '\n'
print_level critical   '🔴 CRITICAL (자동 차단)'
print_level mandatory  '🟡 MANDATORY (사람 게이트)'
print_level convention '🔵 CONVENTION (가이드)'
printf '\n총 %s개 룰 (CRITICAL %s / MANDATORY %s / CONVENTION %s)\n' "$T_N" "$C_N" "$M_N" "$V_N"
[ -n "$FIND" ] && [ "$T_N" -eq 0 ] && printf '  → 토큰 %s 는 어디에도 정의가 없어요\n' "$FIND"
exit "$EXIT_OK"
