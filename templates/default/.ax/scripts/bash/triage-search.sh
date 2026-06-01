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

# ripgrep 가속기 — 있으면 본문 재귀 스캔에 사용(grep fallback). 결과는 grep 으로 재채점하므로
# 점수·스니펫은 rg 유무와 무관하게 동일(결정론 유지). rg 는 후보 파일 listing 만 가속.
HAS_RG=false
if command -v rg >/dev/null 2>&1; then HAS_RG=true; fi

# 동의어 확장 — .ax/search-aliases.yml 의 그룹으로 키워드 OR 확장 (recall 보강).
# 키워드-only grep 의 paraphrase 누락을 메우는 결정론 레이어. 파일 없으면 그대로 통과.
ALIAS_FILE=".ax/search-aliases.yml"
expand_keywords() {
    local kws="$1"
    local expanded="$kws"
    [ -f "$ALIAS_FILE" ] || { printf '%s' "$kws"; return; }
    local line key grp toks kw t hit
    while IFS= read -r line; do
        case "$line" in ''|\#*) continue ;; esac
        case "$line" in *:*\[*\]*) ;; *) continue ;; esac
        key=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([^:]+):.*/\1/' | tr -d ' ')
        grp=$(printf '%s' "$line" | sed -E 's/^[^[]*\[([^]]*)\].*/\1/')
        toks="$key $(printf '%s' "$grp" | tr ',' ' ')"
        hit=0
        for kw in $kws; do
            for t in $toks; do
                [ -z "$t" ] && continue
                if [ "$(printf '%s' "$kw" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')" ]; then
                    hit=1; break
                fi
            done
            [ "$hit" -eq 1 ] && break
        done
        [ "$hit" -eq 1 ] && expanded="$expanded $toks"
    done < "$ALIAS_FILE"
    # 토큰 dedup (대소문자 무시), 공백 구분 재출력
    printf '%s' "$expanded" | tr ' ' '\n' | grep -v '^$' | awk '!seen[tolower($0)]++' | tr '\n' ' '
}

# 키워드 → (동의어 확장) → alternation 패턴 (공백 분리, 빈 토큰 제거).
# 각 토큰의 regex 메타문자 escape — KEYWORDS 는 LLM 추출이라 신뢰 입력이지만,
# `.` `*` `(` 같은 메타가 들어오면 의도치 않은 매칭·ReDoS 가능. 방어적 코딩.
KEYWORDS_EXPANDED=$(expand_keywords "$KEYWORDS")
ALT=""
# shellcheck disable=SC2206
read -ra _GOAX_KW_ARR <<< "$KEYWORDS_EXPANDED"
# bash 3.2: 빈 배열 deref 는 set -u 에서 unbound — :- 가드 (공백-only 키워드 시 아래 ALT 빈값 → json_error)
for _kw in "${_GOAX_KW_ARR[@]:-}"; do
    [ -z "$_kw" ] && continue
    _esc=$(printf '%s' "$_kw" | sed -E 's/[][\.*+?(){}|^$\\]/\\&/g')
    if [ -z "$ALT" ]; then ALT="$_esc"; else ALT="$ALT|$_esc"; fi
done
unset _GOAX_KW_ARR _kw _esc

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
        # ALT 에 escape 된 backslash 포함 가능 → JSON 안전 생성
        if command -v jq >/dev/null 2>&1; then
            RES=$(jq -nc --arg alt "$ALT" '{alt: $alt, dry_run: true}')
        else
            _esc_alt=$(printf '%s' "$ALT" | sed 's/\\/\\\\/g; s/"/\\"/g')
            RES="{\"alt\":\"$_esc_alt\",\"dry_run\":true}"
        fi
        json_output "ok" "$RES" "검색 안 함 — alternation 패턴만 출력했어요"
    else
        printf 'pattern: %s\n' "$ALT"
        printf '(dry-run — 검색 실행 안 함)\n'
    fi
    exit "$EXIT_OK"
fi

# ─────────────────────────────────────────────────────────────
# 검색 + 랭킹 + 스니펫 (Phase 1)
# 단순 grep -ril 대비 핵심 변경:
#   - 본문 카테고리(adrs/mistakes/rules/imported)는 매칭 LINE 수(grep -cE)로 랭킹,
#     상위 K개만 + 매칭 줄 미리보기(snippet) 동봉 → LLM 이 통째 read 전에 연관성 판단(토큰 절감).
#   - specs(디렉토리명)·modules(keywords 라인)는 본문 스캔 대상 아님 → score=1, snippet 없음.
# result 스키마: 카테고리 = [{ "path", "score", "snippets":[..] (, "match") }]
#   score 내림차순. jq 없으면 snippet 생략한 동일 object 스키마로 graceful degrade.

HAS_JQ=false
if command -v jq >/dev/null 2>&1; then HAS_JQ=true; fi

TAB=$(printf '\t')
SNIPPET_MAX=3       # 파일당 미리보기 줄 수
SNIPPET_WIDTH=200   # 줄당 최대 글자(과도한 토큰 방지)
TOPK=10             # 카테고리당 상위 K
SCAN_CAP=50         # 본문 랭킹 전 후보 파일 상한

# recency boost — 현재 작업 도메인(current-task.json)과 관련된 자료를 상위로 끌어올림.
# score 표시값은 raw 매칭수 그대로 두고, 정렬키에만 BOOST_AMT 를 더해 boosted 항목을 위로.
BOOST_RE=""
if [ "$HAS_JQ" = true ] && [ -f .ax/current-task.json ]; then
    _dom=$(jq -r '.domain // empty' .ax/current-task.json 2>/dev/null || true)
    if [ -n "${_dom:-}" ] && [ "$_dom" != "null" ]; then
        BOOST_RE=$(printf '%s' "$_dom" | sed -E 's/[][\.*+?(){}|^$\\]/\\&/g')
    fi
fi
BOOST_AMT=100000

# jq 없을 때만 쓰는 단순 escape (path/keyword 처럼 통제된 입력 대상)
_json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# 본문 카테고리 처리.
#   stdin : 매칭 후보 파일 경로(줄단위, grep -ril 결과)
#   stdout: JSON array of {path, score, snippets:[...]} — score 내림차순 상위 K
process_body() {
    local files; files=$(cat)
    [ -z "$files" ] && { printf '[]'; return; }

    # 파일별 매칭 줄수로 랭킹(+도메인 boost) → 상위 K
    # ranked 라인: <정렬키>\t<raw점수>\t<boost 0/1>\t<path>
    local ranked
    ranked=$(
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            [ -f "$f" ] || continue
            c=$(grep -cE "($ALT)" "$f" 2>/dev/null | head -1)
            [ -z "$c" ] && c=0
            if [ "$c" -gt 0 ] 2>/dev/null; then
                b=0; key=$c
                if [ -n "$BOOST_RE" ] && grep -qiE "$BOOST_RE" "$f" 2>/dev/null; then
                    b=1; key=$((c + BOOST_AMT))
                fi
                printf '%s\t%s\t%s\t%s\n' "$key" "$c" "$b" "$f"
            fi
        done <<< "$files" \
        | sort -t"$TAB" -k1,1 -rn \
        | head -"$TOPK" || true
    )
    [ -z "$ranked" ] && { printf '[]'; return; }

    local objs="" n=0 key score boost f snip_json o esc boostbool
    while IFS="$TAB" read -r key score boost f; do
        [ -z "$f" ] && continue
        boostbool=false
        [ "${boost:-0}" = "1" ] && boostbool=true
        if [ "$HAS_JQ" = true ]; then
            snip_json=$(grep -nE "($ALT)" "$f" 2>/dev/null \
                | head -"$SNIPPET_MAX" \
                | awk -v w="$SNIPPET_WIDTH" '{print substr($0,1,w)}' \
                | jq -R -s -c 'split("\n") | map(select(. != ""))' 2>/dev/null) || snip_json="[]"
            [ -z "$snip_json" ] && snip_json="[]"
            o=$(jq -nc --arg p "$f" --argjson s "${score:-0}" --argjson sn "$snip_json" --argjson b "$boostbool" \
                '{path:$p, score:$s, snippets:$sn, boosted:$b}' 2>/dev/null) || continue
        else
            esc=$(_json_esc "$f")
            o="{\"path\":\"$esc\",\"score\":${score:-0},\"snippets\":[],\"boosted\":$boostbool}"
        fi
        if [ "$n" -eq 0 ]; then objs="$o"; else objs="$objs,$o"; fi
        n=$((n + 1))
    done <<< "$ranked"
    printf '[%s]' "$objs"
}

# 단순 카테고리(경로 목록 → score=1, snippet 없음).
#   stdin: 경로(줄단위)
simple_objs() {
    local lines; lines=$(cat)
    [ -z "$lines" ] && { printf '[]'; return; }
    local objs="" n=0 p o esc
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        if [ "$HAS_JQ" = true ]; then
            o=$(jq -nc --arg p "$p" '{path:$p, score:1, snippets:[]}' 2>/dev/null) || continue
        else
            esc=$(_json_esc "$p")
            o="{\"path\":\"$esc\",\"score\":1,\"snippets\":[]}"
        fi
        if [ "$n" -eq 0 ]; then objs="$o"; else objs="$objs,$o"; fi
        n=$((n + 1))
    done <<< "$lines"
    printf '[%s]' "$objs"
}

# ── Phase 4 tier: 대형 코퍼스면 BM25 역색인으로 후보를 *추가* (union — recall 절대 손실 없음).
# 소형(임계 이하)은 USE_INDEX=false → grep 경로 그대로(회귀 0). 한글 등 인덱스 미수록 토큰은
# grep 이 잡으므로 union 이 안전. 인덱스는 ASCII BM25 로 연관 높은 후보를 *보태는* 역할.
INDEX_THRESHOLD=120
USE_INDEX=false
IDX_HITS=""   # 라인: <category>\t<path>
if [ -f "$SCRIPT_DIR/build-index.sh" ]; then
    CORPUS_N=0
    for _cd in .ax/docs .ax/mistakes .ax/modules .ax/spirit/rules; do
        [ -d "$_cd" ] || continue
        _cc=$(find "$_cd" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
        CORPUS_N=$((CORPUS_N + ${_cc:-0}))
    done
    if [ "${CORPUS_N:-0}" -gt "$INDEX_THRESHOLD" ] && [ "$HAS_JQ" = true ]; then
        _idx_json=$(bash "$SCRIPT_DIR/build-index.sh" --query "$KEYWORDS_EXPANDED" --top 50 --json 2>/dev/null || true)
        if [ -n "$_idx_json" ]; then
            IDX_HITS=$(printf '%s' "$_idx_json" | jq -r '.result.hits[]? | "\(.category)\t\(.path)"' 2>/dev/null || true)
            [ -n "$IDX_HITS" ] && USE_INDEX=true
        fi
    fi
fi

# 매칭 후보 파일 listing (재귀) — rg 있으면 가속, 없으면 grep. 둘 다 정답집합 동일(텍스트 md).
# rg 플래그는 grep 의미와 맞춤: --no-ignore(.gitignore 무시) --hidden(.ax 하위) -i -l.
# $2=category 주면 USE_INDEX 시 그 카테고리 BM25 후보를 union (recall 보존).
list_matching_recursive() {
    local dir="$1" cat="${2:-}"
    [ -d "$dir" ] || { [ "$USE_INDEX" = true ] && [ -n "$cat" ] || return 0; }
    {
        if [ -d "$dir" ]; then
            if [ "$HAS_RG" = true ]; then
                rg --no-config --no-ignore --hidden -i -l -e "($ALT)" "$dir" 2>/dev/null || true
            else
                grep -rilE "($ALT)" "$dir" 2>/dev/null || true
            fi
        fi
        if [ "$USE_INDEX" = true ] && [ -n "$cat" ]; then
            printf '%s\n' "$IDX_HITS" | awk -F"$TAB" -v c="$cat" '$1==c && $2!=""{print $2}'
        fi
    } | grep -v '^$' | sort -u
}

# 1) specs: 디렉토리 이름 매칭 (본문 스캔 아님)
SPECS_J=$(find .ax/docs/spec -maxdepth 2 -type d 2>/dev/null \
        | grep -iE "($ALT)" 2>/dev/null \
        | grep -v '^$' | sort -u | head -"$TOPK" \
        | simple_objs || true)
[ -z "$SPECS_J" ] && SPECS_J="[]"

# 2) adrs: 본문 랭킹 + 스니펫
ADRS_J=$(list_matching_recursive .ax/docs/adr adr | head -"$SCAN_CAP" | process_body || true)
[ -z "$ADRS_J" ] && ADRS_J="[]"

# 3) mistakes: 본문 랭킹 + 스니펫
MISTAKES_J=$(list_matching_recursive .ax/mistakes mistake | head -"$SCAN_CAP" | process_body || true)
[ -z "$MISTAKES_J" ] && MISTAKES_J="[]"

# 4) rules: CLAUDE.md + .ax/spirit/rules/ 본문 랭킹 + 스니펫
RULES_J=$(grep -ilE "($ALT)" CLAUDE.md .ax/spirit/rules/*.md 2>/dev/null | head -"$SCAN_CAP" | process_body || true)
[ -z "$RULES_J" ] && RULES_J="[]"

# 5) modules: keywords: 라인 word-boundary 매칭 (score=1, match 동봉)
#    (단어 경계 보장 — "ad"가 "payment" 안에 false-positive 안 남)
_mod_objs=""
_mod_n=0
for module_dir in .ax/modules/*/; do
    [ -d "$module_dir" ] || continue
    [ -f "${module_dir}rules.md" ] || continue
    KW_LINE=$(grep -E '^keywords:' "${module_dir}rules.md" 2>/dev/null | head -1 || true)
    [ -z "$KW_LINE" ] && continue
    MATCHED=$(printf '%s' "$KW_LINE" | grep -oiE "(\[|, )($ALT)(\]|,| )" 2>/dev/null \
              | head -1 | tr -d '[],| ' || true)
    [ -z "$MATCHED" ] && continue
    _mpath="${module_dir}rules.md"
    if [ "$HAS_JQ" = true ]; then
        _mo=$(jq -nc --arg p "$_mpath" --arg m "$MATCHED" \
            '{path:$p, score:1, snippets:[], match:$m}' 2>/dev/null) || continue
    else
        _mo="{\"path\":\"$(_json_esc "$_mpath")\",\"score\":1,\"snippets\":[],\"match\":\"$(_json_esc "$MATCHED")\"}"
    fi
    if [ "$_mod_n" -eq 0 ]; then _mod_objs="$_mo"; else _mod_objs="$_mod_objs,$_mo"; fi
    _mod_n=$((_mod_n + 1))
done
MODULES_J="[$_mod_objs]"

# 6) imported: 외부 spec 흡수본 본문 랭킹 + 스니펫
IMPORTED_J=$(list_matching_recursive .ax/docs/spec/imported imported | head -"$SCAN_CAP" | process_body || true)
[ -z "$IMPORTED_J" ] && IMPORTED_J="[]"

# result 조립 (배열이 이미 JSON → jq 없이 문자열 결합으로 envelope 구성)
RESULT="{\"specs\":$SPECS_J,\"adrs\":$ADRS_J,\"mistakes\":$MISTAKES_J,\"rules\":$RULES_J,\"modules\":$MODULES_J,\"imported\":$IMPORTED_J}"

# 매칭 자료 수 — jq 있으면 정확 카운트, 없으면 "path": 키 휴리스틱
if [ "$HAS_JQ" = true ]; then
    TOTAL=$(printf '%s' "$RESULT" \
        | jq '[.specs,.adrs,.mistakes,.rules,.modules,.imported] | map(length) | add' 2>/dev/null || echo 0)
else
    TOTAL=$(printf '%s' "$RESULT" | { grep -o '"path":' 2>/dev/null || true; } | wc -l | tr -d ' ')
fi
case "${TOTAL:-0}" in ''|*[!0-9]*) TOTAL=0 ;; esac

if [ "$TOTAL" -eq 0 ]; then
    NEXT="매칭 자료 없음 — 기존 컨텍스트 없이 신규 작업으로 분류해요"
else
    NEXT="${TOTAL}개 자료 매칭 (score 내림차순) — snippet 으로 연관성 먼저 확인하고 필요한 것만 본문 read. Required reading 에 첨부 (modules 매칭은 필수 포함)"
fi

if [ "$JSON_MODE" = true ]; then
    json_output "ok" "$RESULT" "$NEXT"
else
    if [ "$HAS_JQ" = true ]; then
        for _cat in specs adrs mistakes rules modules imported; do
            printf '%s:\n' "$_cat"
            printf '%s' "$RESULT" | jq -r --arg c "$_cat" '
                .[$c][]?
                | "  [score \(.score)] \(.path)" + (if .match then " («\(.match)»)" else "" end)
                + (if (.snippets | length) > 0 then "\n      " + (.snippets | join("\n      ")) else "" end)
            ' 2>/dev/null || printf '  (none)\n'
        done
    else
        printf '%s\n' "$RESULT"
    fi
    printf '\n%s\n' "$NEXT"
fi

exit "$EXIT_OK"
