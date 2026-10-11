#!/usr/bin/env bash
# .ax/scripts/bash/lib/ids.sh — spec/ADR ID · --spec 해석 · tasks.md 파서
# common.sh 가 source 해요. 직접 source 하지 않아요.
# shellcheck disable=SC2034  # 여기서 정의한 변수는 common.sh 를 source 한 스크립트가 써요

# ─── spec/ADR ID — 날짜 + 난수 (브랜치끼리 서로 안 봐도 안 겹쳐요) ─────────
# 새 ID: `YYYY-MM-DD-<4hex>` (예: 2026-09-25-a3f1). 옛 순번 `NNN`(spec)·`NNNN`(ADR) 도 계속 읽어요 (next-spec-num.sh).
# 주의: 옛 ADR `0008-x` 와 새 ID `2026-09-25-…` 는 둘 다 "숫자 4개 + 하이픈" 으로 시작해요 —
#       형식 판별은 반드시 GOAX_DOC_ID_ERE 로 하세요 (`[0-9]+-` 로 자르면 새 ID 가 전부 "2026" 이 돼요).
# 반복자 `{4}` 를 안 써요 — ubuntu 기본 mawk 는 구간 반복을 모르는 빌드가 있어요. `[a-f]` 범위도 안 써요 (로케일).
_GOAX_HX='[0123456789abcdef]'
GOAX_DOC_ID_ERE="^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-${_GOAX_HX}${_GOAX_HX}${_GOAX_HX}${_GOAX_HX}"
goax_doc_id() {
    local hex
    hex=$(od -An -N2 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    case "$hex" in [0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef]) ;; *) hex=$(printf '%04x' $(( (RANDOM << 1 ^ RANDOM) & 65535 ))) ;; esac
    printf '%s-%s' "$(date +%Y-%m-%d)" "$hex"
}
# goax_doc_key — stdin 의 항목 이름마다 비교 키: 새 ID 면 `YYYY-MM-DD-hhhh`, 옛 순번이면 앞 숫자.
goax_doc_key() {
    awk -v re="$GOAX_DOC_ID_ERE" '{ if ($0 ~ re) print substr($0, 1, 15); else { n = $0; sub(/[^0-9].*/, "", n); print n } }'
}
# goax_doc_sort — stdin 의 항목 이름을 오래된 순으로: 옛 순번(숫자순) 다음에 새 ID(이름순 = 날짜순).
goax_doc_sort() {
    awk -v re="$GOAX_DOC_ID_ERE" '{ if ($0 ~ re) print "1\t0\t" $0; else { n = $0; sub(/-.*/, "", n); print "0\t" (n + 0) "\t" $0 } }' \
        | sort -t "$(printf '\t')" -k1,1n -k2,2n -k3,3 | cut -f3-
}

# goax_resolve_spec <spec> [spec-base-dir]
#   `--spec 001` 같은 축약을 한 규칙으로 풀어요: 정확 일치 → prefix 일치가 정확히 1개 → 실패.
#   같은 인자에 스크립트마다 다른 답(검사 · 조용한 성공 · 에러)이 나오던 걸 없애요.
#   반환: 0 = 해석됨(디렉토리 이름을 stdout 으로) · 1 = 없음 · 2 = 후보 여럿
#         후보 여럿이면 GOAX_SPEC_CANDIDATES 에 공백 구분으로 담아요.
GOAX_SPEC_CANDIDATES=""
goax_resolve_spec() {
    local want="${1:-}" base="${2:-}" root hits n
    GOAX_SPEC_CANDIDATES=""
    [ -n "$want" ] || return 1
    if [ -z "$base" ]; then
        root="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
        base="$root/.ax/docs/spec"
    fi
    [ -d "$base" ] || return 1
    if [ -d "$base/$want" ]; then printf '%s' "$want"; return 0; fi
    hits=$(find "$base" -mindepth 1 -maxdepth 1 -type d -name "${want}*" 2>/dev/null \
           | sed 's|.*/||' | sort)
    # 새 ID(`2026-09-25-a3f1-slug`) 는 날짜로 시작해서 앞부분 축약으로는 못 찾아요 — 난수·slug 로도 찾아요
    [ -z "$hits" ] && hits=$(find "$base" -mindepth 1 -maxdepth 1 -type d -name "*-${want}*" 2>/dev/null \
           | sed 's|.*/||' | sort)
    n=$(printf '%s\n' "$hits" | grep -c . || true); n=${n:-0}
    if [ "$n" -eq 1 ]; then printf '%s' "$hits"; return 0; fi
    if [ "$n" -gt 1 ]; then
        GOAX_SPEC_CANDIDATES=$(printf '%s' "$hits" | tr '\n' ' ')
        GOAX_SPEC_CANDIDATES="${GOAX_SPEC_CANDIDATES% }"
        return 2
    fi
    return 1
}

# goax_tasks_parse <tasks.md>
#   tasks.md 를 실행 그래프 한 줄씩으로 읽어요 — tasks-plan.sh · mark-task.sh --next 가 같은 파서를 써요
#   (둘이 다르게 읽으면 plan 은 blocked 라는데 --next 는 그 task 를 집어요).
#   출력: "ID|state|P|files(,)|deps(,)|line"   state = open|done|paused · P = 0|1 · line = task 줄 번호
#   - ``` 코드펜스 안은 건너뛰어요 (템플릿의 형식 설명 예시가 실 task 로 세지 않게)
#   - files: 경로는 정규화해요 (`./` 제거 · 중복 `/` · 끝 `/`) — 표기 차이로 겹침 검사를 빠져나갈 수 없어요
#   - deps 는 task 다음 들여쓰기 `의존:` 줄의 T-ID 만 뽑아요 — `없음`·`none`·`-` 은 빈 값(뒤에 설명이 붙어도),
#     `T001 (스키마)` 처럼 설명이 붙어도 T001 만 남아요. T-ID 가 하나도 없는 다른 표기는 원문 그대로 남겨
#     (없는 task 에 의존한 것처럼) 풀리지 않게 해요 — 오타가 "의존 없음" 으로 조용히 통과하지 않게요
goax_tasks_parse() {
    awk '
        function norm(p) {
            gsub(/\/+/, "/", p)
            while (sub(/^\.\//, "", p)) ;
            while (sub(/\/\.\//, "/", p)) ;
            sub(/\/+$/, "", p)
            return p
        }
        function normlist(s,   n, a, i, v, out) {
            if (s == "") return ""
            n = split(s, a, ",")
            out = ""
            for (i = 1; i <= n; i++) { v = norm(a[i]); if (v != "") out = (out == "" ? v : out "," v) }
            return out
        }
        function flush() {
            if (id != "") printf "%s|%s|%s|%s|%s|%s\n", id, st, par, files, deps, ln
            id=""; st=""; par="0"; files=""; deps=""; ln=""
        }
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }
        /^- \[[ x~X]\] / {
            flush()
            line = $0; ln = NR
            st = "open"
            if (line ~ /^- \[[xX]\]/) st = "done"
            else if (line ~ /^- \[~\]/) st = "paused"
            if (match(line, /\[P\]/)) par = "1"
            if (match(line, /T[0-9][0-9][0-9]+/)) id = substr(line, RSTART, RLENGTH)
            f = line
            if (match(f, /files:[ ]*/)) {
                f = substr(f, RSTART + RLENGTH)
                gsub(/[ ]*,[ ]*/, ",", f); gsub(/^[ ]+|[ ]+$/, "", f)
                files = normlist(f)
            }
            next
        }
        id != "" && /^[ \t]+의존:/ {
            d = $0; sub(/^[ \t]*의존:[ ]*/, "", d); raw = d
            while (match(d, /T[0-9]+/)) {
                v = substr(d, RSTART, RLENGTH); d = substr(d, RSTART + RLENGTH)
                deps = (deps == "" ? v : deps "," v)
            }
            # T-ID 가 없는데 없음/none/- 도 아니면 읽을 수 없는 의존 — 조용히 "의존 없음" 으로 풀지 않고
            # 그대로 남겨요 (tasks.md 에 없는 ID 처럼 영원히 안 풀려서 눈에 띄어요).
            # `없음 (첫 task)` · `none — 독립` 처럼 값 뒤에 설명을 붙인 건 의존 없음이에요 (예전 파서도 그렇게 읽었어요)
            gsub(/^[ \t]+|[ \t]+$/, "", raw)
            if (deps == "" && raw !~ /^((없음|none|-)([[:space:](].*)?)?$/) { gsub(/[|,]/, ";", raw); deps = raw }
            next
        }
        END { flush() }
    ' "$1"
}
