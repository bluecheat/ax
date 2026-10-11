#!/usr/bin/env bash
# .ax/scripts/bash/lib/rules.sh — 룰 파일 파서 — 검출 패턴, 예시, frontmatter, 계약 테스트
# common.sh 가 source 해요. 직접 source 하지 않아요.
# shellcheck disable=SC2034  # 여기서 정의한 변수는 common.sh 를 source 한 스크립트가 써요

# ─── 룰 패턴 — 룰 파일의 `<!-- 검출 패턴: <ERE> -->` 를 기계가 읽어요 ──────────
# goax_rule_patterns <rule-file>
#   출력: TSV `SP-<CAT>-<NNN>\t<ERE>` — 마커 한 줄에 한 행, 파일 순서대로.
#   `## SP-<CAT>-<NNN>:` 헤더가 현재 룰이고, 그 아래 `<!-- 검출 패턴: X -->` 의 X 가 패턴이에요
#   (`검출 패턴:` 뒤 공백부터 ` -->` 앞까지, 앞뒤 공백 trim, 따옴표 없음). `<regex>`·`<ERE>` 처럼
#   `<…>` 로만 된 값은 자리표시자라 버려요. frontmatter 와 코드펜스(```·~~~) 안은 안 봐요 — 출고 템플릿이 사용법을 펜스 안에 적어요.
#   헤더 앞에 나온 마커는 귀속할 룰이 없어서 버려요.
#
#   이 마커는 오래전부터 두 템플릿에 있었지만 읽는 쪽이 없어서 장식이었어요 —
#   `critical-rule-grep.sh` 가 이걸로 staged 파일을 검사하고, `zero-probe.sh` 가
#   ❌/✅ 예시로 패턴 자체를 검증해요. 같은 마커를 두 곳이 따로 파싱하면 갈라져요 — 여기 하나예요.
goax_rule_patterns() {
    local file="${1:-}"
    [ -f "$file" ] || return 0
    awk '
        BEGIN { fm=0; fmdone=0; fence=0; tok="" }
        NR==1 && /^---[[:space:]]*$/ { fm=1; next }
        fm==1 { if (/^---[[:space:]]*$/) { fm=0; fmdone=1 } next }
        /^[[:space:]]*(```|~~~)/ { fence=!fence; next }
        fence { next }
        /^## SP-[[:upper:][:digit:]]+-[[:digit:]]+:/ {
            tok=$0; sub(/^## /, "", tok); sub(/:.*$/, "", tok); next
        }
        /^[[:space:]]*<!--[[:space:]]*검출 패턴:/ {
            if (tok == "") next
            pat=$0
            sub(/^[[:space:]]*<!--[[:space:]]*검출 패턴:[[:space:]]*/, "", pat)
            sub(/[[:space:]]*-->[[:space:]]*$/, "", pat)
            if (pat == "" || pat ~ /^<[^>]*>$/) next    # `<regex>`·`<ERE>` 같은 자리표시자는 패턴이 아니에요
            printf "%s\t%s\n", tok, pat
        }
    ' "$file"
}

# goax_rule_examples <rule-file>
#   출력: TSV `SP-<CAT>-<NNN>\t<bad|good>\t<예시 텍스트>`.
#   룰 본문의 `❌ …`/`✅ …` 줄(템플릿 형식)과 `- 위반 예: …`/`- 대안: …` 줄(audit 승격 형식)을 읽어요.
#   백틱 span 이 있으면 span 마다 한 행(위반 예를 여러 개 나열하는 형식), 없으면 줄 전체가 한 행이에요.
#   `zero-probe.sh` 의 pattern-rules 프로브가 "❌ 는 걸리고 ✅ 는 안 걸린다" 를 재는 데 써요.
goax_rule_examples() {
    local file="${1:-}"
    [ -f "$file" ] || return 0
    awk '
        function emit(kind, text,   n, i, parts, s) {
            if (tok == "") return
            n = split(text, parts, "`")
            if (n >= 3) {
                for (i = 2; i <= n; i += 2) { s = parts[i]; if (s != "") printf "%s\t%s\t%s\n", tok, kind, s }
                return
            }
            sub(/^[[:space:]]+|[[:space:]]+$/, "", text)
            if (text != "" && text !~ /^<.*>$/) printf "%s\t%s\t%s\n", tok, kind, text
        }
        BEGIN { fm=0; fence=0; tok="" }
        NR==1 && /^---[[:space:]]*$/ { fm=1; next }
        fm==1 { if (/^---[[:space:]]*$/) fm=0; next }
        /^[[:space:]]*(```|~~~)/ { fence=!fence; next }
        fence { next }
        /^## SP-[[:upper:][:digit:]]+-[[:digit:]]+:/ { tok=$0; sub(/^## /, "", tok); sub(/:.*$/, "", tok); next }
        /^[[:space:]]*❌/            { t=$0; sub(/^[[:space:]]*❌[[:space:]]*/, "", t); emit("bad", t); next }
        /^[[:space:]]*✅/            { t=$0; sub(/^[[:space:]]*✅[[:space:]]*/, "", t); emit("good", t); next }
        /^[[:space:]]*-[[:space:]]*위반 예:/ { t=$0; sub(/^[[:space:]]*-[[:space:]]*위반 예:[[:space:]]*/, "", t); emit("bad", t); next }
        /^[[:space:]]*-[[:space:]]*대안:/    { t=$0; sub(/^[[:space:]]*-[[:space:]]*대안:[[:space:]]*/, "", t); emit("good", t); next }
    ' "$file"
}

# goax_frontmatter_scalar <file> <key>
#   frontmatter 의 스칼라 값 하나 (따옴표·인라인 주석 제거). 없으면 빈 문자열.
#   `severity:` 처럼 파일 단위 메타를 읽을 때 써요 — 배열은 goax_yaml_list.
goax_frontmatter_scalar() {
    local file="${1:-}" key="${2:-}"
    [ -f "$file" ] || return 0
    awk -v key="$key" '
        BEGIN { c=0 }
        /^---[[:space:]]*$/ { c++; if (c==2) exit; next }
        c==1 && $0 ~ ("^" key ":") {
            v=$0; sub("^" key ":[[:space:]]*", "", v)
            sub(/(^|[[:space:]])#.*$/, "", v)
            gsub(/^[[:space:]\042\047]+|[[:space:]\042\047]+$/, "", v)
            print v; exit
        }
    ' "$file"
}

# goax_rule_contracts <file>
#   룰 파일 frontmatter 의 `contract:`(그 룰을 막는 짝 테스트 경로)와 `contract_ids:`(계약 대상 SP-ID)를
#   `path<TAB>값` · `id<TAB>값` 줄로 내요. 스칼라(`contract: a.test.ts  # 주석`) · 인라인 목록(`[a, b]`) ·
#   블록 목록(`- a`) 셋 다 받아요. frontmatter 밖은 안 봐요 — 본문 예시가 계약으로 읽히면 안 돼요.
goax_rule_contracts() {
    local file="${1:-}"
    [ -f "$file" ] || return 0
    awk '
        function clean(v) { sub(/(^|[[:space:]])#.*$/, "", v); gsub(/^[[:space:]\042\047`]+|[[:space:]\042\047`]+$/, "", v); return v }
        function emit(k, v,   n, i, a) {
            v = clean(v)
            if (v ~ /^\[/) { sub(/^\[/, "", v); sub(/\].*$/, "", v); n = split(v, a, ",")
                             for (i = 1; i <= n; i++) { a[i] = clean(a[i]); if (a[i] != "") print k "\t" a[i] } }
            else if (v != "") print k "\t" v
        }
        NR == 1 && !/^---[[:space:]]*$/ { exit }
        NR == 1 { next }
        /^---[[:space:]]*$/ { exit }
        /^contract:/     { cur = "path"; v = $0; sub(/^contract:/, "", v); emit(cur, v); next }
        /^contract_ids:/ { cur = "id";   v = $0; sub(/^contract_ids:/, "", v); emit(cur, v); next }
        cur != "" && /^[[:space:]]+-[[:space:]]+/ { v = $0; sub(/^[[:space:]]+-[[:space:]]+/, "", v); emit(cur, v); next }
        /^[^[:space:]]/ { cur = "" }
    ' "$file"
}
