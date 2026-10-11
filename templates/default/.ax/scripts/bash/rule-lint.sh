#!/usr/bin/env bash
# .ax/scripts/bash/rule-lint.sh — 모델이 읽는 글이 docs/reference/writing-for-agents.md 기준을 지키는지 줄 번호로 알려줘요
#
# Usage:
#   bash rule-lint.sh [--json] [--changed] [--mode rule|prose] [<파일>…]
#     파일을 주지 않으면 rule 모드로 .ax/spirit/rules/*.md 와 .ax/modules/*/rules.md 를 봐요.
#     --mode prose 는 SKILL.md, agents, 훅 문구처럼 룰 블록이 없는 글에 써요.
#     --changed 는 git 에서 바뀐 줄이 걸친 룰 블록의 지적만 내요 (추적 안 되는 파일은 전부).
#
# 지적 종류 (kind):
#   trace     사건 경위 — 날짜, 커밋 해시, `PR #N`·`(#N)`, "실측(…)", "이번 세션", "N건 통과", mistakes 경로
#   metaphor  비유와 구어 — 구멍, 통째로, 먹혀, 기울어, 이겨요, 몫, 침묵, 새어
#   dots      한 줄에 `·` 로 셋 이상 나열 (표와 코드 펜스는 빼요)
#   length    룰 본문이 8줄을 넘어요 (빈 줄, 코드 펜스, ✅/❌ 줄, 주석은 세지 않아요)          — rule 모드
#   examples  ❌ 예시가 둘 이상이거나 코드 펜스가 둘 이상이에요                                — rule 모드
#   adr       ADR 을 링크 한 줄보다 길게 적었어요                                              — rule 모드
#   marker    검출 패턴 마커가 한국어 문장이에요 (한국어 글자 옆에 공백 — ERE 로 아무것도 못 잡아요)  — rule 모드
#   harness   goax 에이전트·skill·게이트 이름을 지시해요 — 프로젝트 룰이 아니라 goax 이슈 후보예요 — rule 모드
#
# 금지 예시를 인용한 줄이나 출처 날짜는 줄 끝에 `<!-- rule-lint: 예시 -->` 를 달면 건너뛰어요.
# 판정이 아니라 지적이에요. 고칠지는 rule skill 과 사용자가 정해요. 예외 단어는 config.yml sensors.rule_lint_allow 에 둬요.
#
# Output (--json):
#   {"status":"ok|warning","result":{"mode":"rule","files":N,"total":N,"counts":{"trace":N,…},
#     "findings":[{"file":"…","line":N,"kind":"trace","id":"SP-X-001","text":"…"}]},…}
# Exit: 0 (지적이 있어도) · 1 error · 2 skipped (볼 파일 없음)

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; CHANGED=false; MODE="rule"; FILES=()
while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) ;;                       # 읽기 전용 — 표준 옵션 호환
        --changed) CHANGED=true ;;
        --mode)    shift; MODE="${1:-}" ;;
        --help|-h) SHOW_HELP=true ;;
        -*)        goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
        *)         FILES+=("$1") ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
case "$MODE" in rule|prose) ;; *) goax_error "--mode 는 rule 또는 prose 예요 (받은 값: '$MODE')"; exit "$EXIT_ERROR" ;; esac

PROJECT_ROOT=$(find_project_root 2>/dev/null || pwd)
if [ "${#FILES[@]}" -eq 0 ]; then
    for f in "$PROJECT_ROOT"/.ax/spirit/rules/*.md "$PROJECT_ROOT"/.ax/modules/*/rules.md; do
        [ -f "$f" ] && FILES+=("$f")
    done
fi
if [ "${#FILES[@]}" -eq 0 ]; then
    if [ "$JSON_MODE" = true ]; then json_skip "볼 룰 파일이 없어요 (.ax/spirit/rules/*.md · .ax/modules/*/rules.md)"; fi
    goax_log "볼 룰 파일이 없어요"; exit "$EXIT_SKIPPED"
fi

ALLOW=$(goax_yaml_list "$PROJECT_ROOT/.ax/config.yml" rule_lint_allow 2>/dev/null | paste -sd'|' - || true)

# 바뀐 줄 번호 — "a-b a-b …". 추적 안 되는 파일이면 "all"
changed_ranges() {
    local f="$1"
    git -C "$PROJECT_ROOT" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || { printf 'all'; return; }
    git -C "$PROJECT_ROOT" diff -U0 HEAD -- "$f" 2>/dev/null \
        | sed -nE 's/^@@ -[0-9,]+ \+([0-9]+)(,([0-9]+))? @@.*/\1 \3/p' \
        | awk '{ n = ($2 == "" ? 1 : $2); if (n > 0) printf "%d-%d ", $1, $1 + n - 1 }'
}

ROWS=""
for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    rel="${f#"$PROJECT_ROOT"/}"
    ranges=""; [ "$CHANGED" = true ] && ranges=$(changed_ranges "$f")
    [ "$CHANGED" = true ] && [ -z "$ranges" ] && continue
    ROWS="${ROWS}$(LC_ALL=C awk -v mode="$MODE" -v file="$rel" -v ranges="$ranges" -v allow="$ALLOW" "$GOAX_AWK_CLIP"'
        function out(ln, kind, txt) {
            if (allow != "" && txt ~ allow) return
            if (mode == "rule" && ranges != "" && ranges != "all" && !touched) { pend[++np] = ln "\t" kind "\t" id "\t" clip(txt, 120); return }
            printf "%s\t%d\t%s\t%s\t%s\n", file, ln, kind, id, clip(txt, 120)
        }
        function inrange(ln,   n, a, i, b) {
            if (ranges == "" || ranges == "all") return 1
            n = split(ranges, a, " ")
            for (i = 1; i <= n; i++) { split(a[i], b, "-"); if (ln >= b[1] + 0 && ln <= b[2] + 0) return 1 }
            return 0
        }
        function flush_block(   i) {
            if (mode == "rule" && id != "") {
                if (body > 8)   out(start, "length", "본문 " body "줄 — 8줄 이하로 줄이고 사례는 references 로 옮겨요")
                if (bad > 1 || fences > 1) out(start, "examples", "❌ 예시 " bad "개 · 코드 펜스 " fences "개 — 한 쌍만 남겨요")
                if (adr > 1)    out(start, "adr", "ADR 언급 " adr "줄 — <!-- adr: 경로 --> 한 줄로")
                if (touched) for (i = 1; i <= np; i++) { split(pend[i], p, "\t"); printf "%s\t%s\t%s\t%s\t%s\n", file, p[1], p[2], p[3], p[4] }
            }
            id = ""; body = 0; bad = 0; fences = 0; adr = 0; touched = 0; np = 0
        }
        function trace(s,   t, rest, pos) {
            t = s
            # 날짜 — spec/ADR ID(YYYY-MM-DD-<4hex>)는 경위가 아니라 이름이라 빼요
            while (match(t, /20[0-9][0-9]-[01][0-9]-[0-3][0-9]/)) {
                rest = substr(t, RSTART + RLENGTH)
                if (rest !~ /^-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]/) return "날짜"
                t = rest
            }
            t = s
            while (match(t, /[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]+/)) {
                pos = substr(t, RSTART, RLENGTH)
                pre = (RSTART > 1 ? substr(t, RSTART - 1, 1) : " "); post = substr(t, RSTART + RLENGTH, 1)
                if (RLENGTH <= 40 && pos ~ /[0-9]/ && pos ~ /[a-f]/ && pre !~ /[0-9A-Za-z_-]/ && post !~ /[0-9A-Za-z_]/) return "커밋 해시"
                t = substr(t, RSTART + RLENGTH)
            }
            if (s ~ /(PR|이슈|issue) ?#[0-9]+|\(#[0-9]+\)/) return "PR·이슈 번호"
            if (s ~ /실측 ?[(:]|이번 세션|[0-9]+ ?건 (통과|실패)|\.ax\/mistakes\/20/) return "사건 경위"
            return ""
        }
        BEGIN { id = "" }
        { ln = NR; line = $0 }
        /^[[:space:]]*(```|~~~)/ { infence = !infence; if (id != "" && infence) fences++; next }
        mode == "rule" && /^## / {
            flush_block()
            if ($0 ~ /^## SP-/) {
                id = $2; sub(/:$/, "", id); start = NR; touched = inrange(NR)
                # 제목도 봐요 — "2026-09-30 사고 이후 …" 같은 제목이 가장 오래 남아요
                k = trace($0); if (k != "") out(NR, "trace", k ": " $0)
                if ($0 ~ /구멍|통째로|먹혀|먹어요|기울어|이겨요|몫|침묵|새어 ?들어/) out(NR, "metaphor", $0)
            }
            next
        }
        mode == "rule" && /^---[[:space:]]*$/ { flush_block(); next }
        {
            # 빈 줄은 블록 사이 구분이라 "바뀐 블록" 판정에 쓰지 않아요 — 새 블록을 붙일 때 앞 블록이 끌려와요
            if (mode == "rule" && id != "" && inrange(ln) && line !~ /^[[:space:]]*$/) touched = 1
            if (mode == "rule" && id == "") next
            if (infence) next
            # 마커는 따로 봐요 — 다른 검사에 걸지 않아요
            if (line ~ /<!--[[:space:]]*검출 패턴:/) {
                m = line; sub(/.*검출 패턴:[[:space:]]*/, "", m); sub(/[[:space:]]*-->.*/, "", m)
                # 한국어 글자 바로 옆에 공백이 있으면 문장이에요. `(후속|이번) PR` 처럼 ERE 안의 한국어는 괜찮아요
                if (mode == "rule" && m !~ /^<.*>$/ && (m ~ /[\352-\355][\200-\277][\200-\277] / || m ~ / [\352-\355][\200-\277][\200-\277]/)) out(ln, "marker", "검출 패턴에 한국어 문장 — 실제 ERE 로: " m)
                next
            }
            if (line ~ /<!--[[:space:]]*adr:/ || line ~ /<!--[[:space:]]*rule-lint:/) next
            k = trace(line); if (k != "") out(ln, "trace", k ": " line)
            if (line ~ /구멍|통째로|먹혀|먹어요|기울어|이겨요|몫|침묵|새어 ?들어/) out(ln, "metaphor", line)
            if (line !~ /^[[:space:]]*\|/) { n = gsub(/ · /, " · ", line); if (n >= 2) out(ln, "dots", line) }
            if (mode == "rule") {
                if (line ~ /^[[:space:]]*$/) next
                if (line ~ /^[[:space:]]*(✅|❌)/) { if (line ~ /❌/) bad++; next }
                if (line ~ /^[[:space:]]*<!--/) next
                body++
                if (line ~ /ADR|adr\//) adr++
                if (line ~ /lane-worker|lane-scout|rules-auditor|evaluator|spec-validate|spec-implement|tasks-gate|spec-review\.sh|합의 리뷰/) out(ln, "harness", "goax 동작을 지시해요 — 프로젝트 룰이 아니라 goax 이슈 후보: " line)
            }
        }
        END { flush_block() }
    ' "$f")"$'\n'
done

ROWS=$(printf '%s' "$ROWS" | awk 'NF' || true)
TOTAL=$(printf '%s' "$ROWS" | grep -c . || true); TOTAL=${TOTAL:-0}

if [ "$JSON_MODE" = true ]; then
    FIND_J=$(printf '%s\n' "$ROWS" | jq -Rn '[inputs | select(length>0) | split("\t")
        | {file:.[0], line:(.[1]|tonumber), kind:.[2], id:(if .[3]=="" then null else .[3] end), text:.[4]}]')
    RESULT=$(jq -nc --arg mode "$MODE" --argjson n "${#FILES[@]}" --argjson f "$FIND_J" \
        '{mode:$mode, files:$n, total:($f|length), counts:($f|group_by(.kind)|map({key:.[0].kind, value:length})|from_entries), findings:$f}')
    if [ "$TOTAL" -gt 0 ]; then
        json_output "warning" "$RESULT" "지적 ${TOTAL}건이에요. 기준은 .ax/docs/reference/writing-for-agents.md 예요. 룰이면 rule skill 이 고쳐요"
    else
        json_output "ok" "$RESULT" "지적이 없어요"
    fi
else
    if [ "$TOTAL" -gt 0 ]; then
        printf '%s\n' "$ROWS" | awk -F'\t' '{ printf "%s:%s  %-8s %s %s\n", $1, $2, $3, ($4 == "" ? "" : "[" $4 "]"), $5 }'
    fi
    goax_log "지적 ${TOTAL}건 (${MODE} 모드, 파일 ${#FILES[@]}개)"
fi
exit "$EXIT_OK"
