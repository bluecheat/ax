#!/usr/bin/env bash
# .ax/scripts/bash/build-index.sh — 역색인 + BM25 랭킹 (대형 코퍼스 가속, tiered).
#
# 소형 프로젝트는 triage-search 의 grep 경로로 충분(속도 비문제) — 이 인덱스는
# 코퍼스가 수백 파일을 넘는 대형 프로젝트에서만 triage-search 가 후보 탐색을
# 가속하려고 써요. markdown 이 여전히 SSOT, 이 인덱스는 *재생성 캐시*.
#
# 인덱스 파일 .ax/.search-index (탭 구분 평문 — git-diff 가능, 바이너리 아님):
#   #goax-search-index\tv1
#   #docs\t<N>
#   #avgdl\t<평균 doc 길이>
#   #built\t<ISO>
#   @D\t<docid>\t<category>\t<doclen>\t<path>
#   <term>\t<docid>\t<tf>           (term = ASCII 소문자 토큰; 한글은 grep 경로가 담당)
#
# 모드:
#   build-index.sh                 # .ax/.search-index 재생성 (stale 여부 무관)
#   build-index.sh --json          # 빌드 요약 JSON
#   build-index.sh --query "a b"   # BM25 랭킹 (stale 면 자동 재빌드). --json 권장
#   build-index.sh --query "a b" --json --top 10
#   build-index.sh --dry-run       # 빌드 안 하고 코퍼스 규모만
#   build-index.sh --help
#
# 의존: grep, sed, sort, uniq, awk, find. (jq 는 --json 출력 escape 에만)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
SHOW_HELP=false
QUERY=""
DO_QUERY=false
TOP=10

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --query)   shift; [ $# -eq 0 ] && { goax_error "--query requires a value"; exit "$EXIT_ERROR"; }; QUERY="$1"; DO_QUERY=true ;;
        --top)     shift; [ $# -eq 0 ] && { goax_error "--top requires a value"; exit "$EXIT_ERROR"; }; TOP="$1" ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,33p' "${BASH_SOURCE[0]}" | sed 's/^# //; s/^#//'
    exit "$EXIT_OK"
fi

WS="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
cd "$WS" 2>/dev/null || { goax_error "프로젝트 루트 진입 실패: $WS"; exit "$EXIT_ERROR"; }

INDEX=".ax/.search-index"
TAB=$(printf '\t')

# ── 코퍼스 열거: "category<TAB>path" 라인 ──
list_corpus() {
    [ -f CLAUDE.md ] && printf 'rule\tCLAUDE.md\n'
    [ -f AGENTS.md ] && printf 'rule\tAGENTS.md\n'
    if [ -d .ax/spirit/rules ]; then
        find .ax/spirit/rules -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null \
            | sort | sed 's/^/rule\t/'
    fi
    if [ -d .ax/docs/adr ]; then
        find .ax/docs/adr -maxdepth 1 -name '[0-9]*-*.md' 2>/dev/null | sort | sed 's/^/adr\t/'
    fi
    if [ -d .ax/mistakes ]; then
        find .ax/mistakes -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null | sort | sed 's/^/mistake\t/'
    fi
    if [ -d .ax/docs/spec ]; then
        find .ax/docs/spec -mindepth 2 -name 'spec.md' 2>/dev/null | sort | sed 's/^/spec\t/'
    fi
    if [ -d .ax/modules ]; then
        find .ax/modules -mindepth 2 -maxdepth 2 -name 'rules.md' 2>/dev/null | sort | sed 's/^/module\t/'
    fi
    if [ -d .ax/docs/spec/imported ]; then
        find .ax/docs/spec/imported -maxdepth 1 -name '*.md' 2>/dev/null | sort | sed 's/^/imported\t/'
    fi
}

# ── stale 판정: 인덱스 없거나 / 코퍼스 파일이 인덱스보다 새로움 / 코퍼스 파일 수 변동(삭제) ──
is_stale() {
    [ -f "$INDEX" ] || return 0
    local newer idx_docs cur
    # 추가·수정 감지 (mtime)
    newer=$(find .ax CLAUDE.md AGENTS.md -name '*.md' -newer "$INDEX" 2>/dev/null | head -1)
    [ -n "$newer" ] && return 0
    # 삭제 감지 — 현재 코퍼스 수 != 인덱스 #docs (mtime 으로는 못 잡음)
    idx_docs=$(awk -F"$TAB" '$1=="#docs"{print $2; exit}' "$INDEX" 2>/dev/null || true)
    cur=$(list_corpus | grep -c . || true)
    [ -n "$idx_docs" ] && [ "${cur:-0}" != "$idx_docs" ] && return 0
    return 1
}

# ── 빌드: list_corpus → .ax/.search-index ──
build_index() {
    local corpus; corpus=$(list_corpus)
    local docid=0 total=0
    local doctable="" postings=""
    local POST_TMP; POST_TMP=$(mktemp "${TMPDIR:-/tmp}/goax-post.XXXXXX")
    local DOC_TMP;  DOC_TMP=$(mktemp "${TMPDIR:-/tmp}/goax-doc.XXXXXX")

    local cat path toks doclen
    while IFS="$TAB" read -r cat path; do
        [ -z "$path" ] && continue
        [ -f "$path" ] || continue
        docid=$((docid + 1))
        # ASCII 토큰: 영숫자/언더스코어 2자 이상, 소문자화 (한글은 인덱스 제외 — grep 경로 담당)
        toks=$(grep -hoE '[A-Za-z0-9_]{2,}' "$path" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
        if [ -z "$toks" ]; then doclen=0; else doclen=$(printf '%s\n' "$toks" | grep -c . || true); fi
        doclen=${doclen:-0}
        total=$((total + doclen))
        printf '@D\t%s\t%s\t%s\t%s\n' "$docid" "$cat" "$doclen" "$path" >> "$DOC_TMP"
        if [ "$doclen" -gt 0 ]; then
            printf '%s\n' "$toks" | sort | uniq -c \
                | awk -v d="$docid" '{cnt=$1; $1=""; sub(/^ /,""); if($0!="") printf "%s\t%s\t%s\n", $0, d, cnt}' >> "$POST_TMP"
        fi
    done <<< "$corpus"

    local N=$docid avg
    avg=$(awk -v t="$total" -v n="$N" 'BEGIN{ printf "%.4f", (n>0)?t/n:0 }')

    local NOW; NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    {
        printf '#goax-search-index\tv1\n'
        printf '#docs\t%s\n' "$N"
        printf '#avgdl\t%s\n' "$avg"
        printf '#built\t%s\n' "$NOW"
        cat "$DOC_TMP"
        cat "$POST_TMP"
    } > "$INDEX.tmp.$$" 2>/dev/null && mv "$INDEX.tmp.$$" "$INDEX" || { rm -f "$INDEX.tmp.$$" "$POST_TMP" "$DOC_TMP"; return 1; }
    rm -f "$POST_TMP" "$DOC_TMP"
    printf '%s' "$N"   # echo doc count
    return 0
}

# ── BM25 query: index + query terms → "score<TAB>category<TAB>path" (내림차순) ──
bm25_rank() {
    local q="$1"
    # 질의 토큰도 동일 규칙(ASCII 소문자)
    local qterms
    qterms=$(printf '%s' "$q" | grep -oE '[A-Za-z0-9_]{2,}' | tr '[:upper:]' '[:lower:]' | tr '\n' ' ' || true)
    [ -z "$qterms" ] && return 0
    awk -F"$TAB" -v qterms="$qterms" -v top="$TOP" '
        BEGIN{ qn=split(qterms,Q," "); for(i=1;i<=qn;i++) isq[Q[i]]=1; k1=1.2; b=0.75 }
        $1=="#docs"  { N=$2; next }
        $1=="#avgdl" { A=$2; next }
        $1=="@D"     { d=$2; cat[d]=$3; dl[d]=$4; path[d]=$5; next }
        {
            if($1 in isq){
                term=$1; d=$2; f=$3
                postf[term SUBSEP d]=f
                if(!(term in seenterm)){ seenterm[term]=1 }
                df[term]++
                dlist[term]=dlist[term] d ","
            }
        }
        END{
            if(A+0==0) A=1
            for(term in df){
                idf=log(1+(N-df[term]+0.5)/(df[term]+0.5))
                n=split(dlist[term],DD,",")
                for(j=1;j<=n;j++){
                    d=DD[j]; if(d=="") continue
                    f=postf[term SUBSEP d]+0
                    denom=f+k1*(1-b+b*(dl[d]/A))
                    if(denom>0) score[d]+=idf*(f*(k1+1))/denom
                }
            }
            cnt=0
            for(d in score){ out[cnt++]= sprintf("%.6f\t%s\t%s", score[d], cat[d], path[d]) }
            # 내림차순 정렬 (간단 삽입정렬 — 결과 수 작음)
            for(i=0;i<cnt;i++) for(j=i+1;j<cnt;j++){ if((out[j]+0)>(out[i]+0)){ t=out[i]; out[i]=out[j]; out[j]=t } }
            lim=(top<cnt)?top:cnt
            for(i=0;i<lim;i++) print out[i]
        }
    ' "$INDEX"
}

# ─────────────────────────── 모드 분기 ───────────────────────────

if [ "$DRY_RUN" = true ]; then
    CN=$(list_corpus | grep -c . || true); CN=${CN:-0}
    if [ "$JSON_MODE" = true ]; then
        json_output "ok" "$(printf '{"corpus_files":%s,"index":"%s","dry_run":true}' "$CN" "$INDEX")" "빌드 안 함 — 코퍼스 ${CN}개"
    else
        printf 'corpus files: %s\n(dry-run — 인덱스 빌드 안 함)\n' "$CN"
    fi
    exit "$EXIT_OK"
fi

if [ "$DO_QUERY" = true ]; then
    # stale 면 재빌드
    if is_stale; then build_index >/dev/null 2>&1 || true; fi
    if [ ! -f "$INDEX" ]; then
        if [ "$JSON_MODE" = true ]; then json_skip "인덱스 없음 — grep 경로 사용 권장"; else goax_warn "인덱스 없음"; exit "$EXIT_SKIPPED"; fi
    fi
    RANKED=$(bm25_rank "$QUERY")
    if [ "$JSON_MODE" = true ]; then
        # ranked → JSON hits
        if command -v jq >/dev/null 2>&1; then
            HITS=$(printf '%s\n' "$RANKED" | grep -v '^$' \
                | jq -R -s -c 'split("\n") | map(select(.!="")) | map(split("\t")) | map({score:(.[0]|tonumber), category:.[1], path:.[2]})')
            [ -z "$HITS" ] && HITS="[]"
        else
            HITS="[]"
        fi
        CNT=$(printf '%s\n' "$RANKED" | grep -c . || true); CNT=${CNT:-0}
        json_output "ok" "$(printf '{"hits":%s,"count":%s}' "$HITS" "$CNT")" "BM25 상위 ${CNT}건"
    else
        printf '%s\n' "$RANKED"
    fi
    exit "$EXIT_OK"
fi

# 기본: 빌드
N=$(build_index) || { if [ "$JSON_MODE" = true ]; then json_error "인덱스 빌드 실패"; else goax_error "인덱스 빌드 실패"; exit "$EXIT_ERROR"; fi; }
N=${N:-0}
BYTES=$(wc -c < "$INDEX" 2>/dev/null | tr -d ' ')
if [ "$JSON_MODE" = true ]; then
    json_output "ok" "$(printf '{"index":"%s","docs":%s,"bytes":%s}' "$INDEX" "$N" "${BYTES:-0}")" "역색인 재생성 — ${N} docs"
else
    goax_log "역색인 재생성 — ${N} docs / ${BYTES:-0}B → $INDEX"
fi
exit "$EXIT_OK"
