#!/usr/bin/env bash
# .ax/scripts/bash/tasks-gate.sh — spec 완료 게이트 + [P] 검증
#
# Usage:
#   bash tasks-gate.sh [--spec <NNN-slug>] [--json] [--strict] [--dry-run] [--help]
#   bash tasks-gate.sh --all [--json] [--strict]      # 모든 spec 훑기
#
# 왜 필요한가 — 완료 판정이 "빈 체크박스 0개" 뿐이었어요. 그래서 (a) 수용 기준은
# 안 채워졌는데 task 만 끝난 경우, (b) 미완료 task 를 지워서 통과시킨 경우를
# 구분하지 못했어요. 실사용 리포에서 spec 21개 중 14개가 미완료 task 를 남긴 채
# 끝나 있었는데, 아무도 그걸 알려주지 않았어요.
#
# 검사 6종:
#   G1 미완료  `- [ ]` 가 남아 있나 (`- [~]` 보류는 제외 — 의도적 보류는 정상)
#   G2 커버리지 spec.md §3 의 AC 중 대응 task 가 없는 것 (spec-kit /analyze 의 coverage gap)
#   G3 orphan  어떤 AC 도 참조하지 않는 task
#   G4 유실    task 총 수가 봉인값보다 줄었나 — "미완료를 지워서 통과" 방어
#   G5 원장    디스패치됐는데 보고가 없는 task · 보고 없이 [x] 가 된 task (lanes-dispatch.sh 필드)
#   G6 검증자  review.md **첫 줄**의 `verdict:` — 필수(size L 이상 · M×L3)인데 없거나 `진행` 이 아니면 미완료
#
# G2/G3 는 spec.md 에 `AC<n>` ID 가 있을 때만 검사해요 (없는 기존 spec 은 생략).
# G4 는 `.ax/state.json` 의 spec별 봉인값과 비교해요. 봉인값이 없으면 현재 수를 기록만
#    (`--dry-run` 이면 기록도 안 해요). 봉인 갱신은 goax_lock 으로 직렬화해요 — 락이 없으면
#    두 spec 을 동시에 검사할 때 한쪽 봉인값이 통째로 사라져요 (실측 10회 중 5회).
# G5 는 `레인:`·`디스패치:`·`보고:` 필드가 있는 task 만 봐요 — 단일 레인 spec 은 영향 없어요.
# G6 의 필수 여부는 활성 spec(current-task.json 의 spec_dir) 일 때만 size×risk 로 판정하고,
#    매트릭스 SSOT 는 tier-from-state.sh 예요. verdict 가 `보강 필요`·`재논의 필요` 면
#    필수가 아니어도 막아요 — 받은 리뷰를 무시하고 완료할 수는 없어요.
#
# tasks.md 파싱은 ``` 코드펜스 안을 건너뛰어요 — 형식 설명용 예시 task 가 실 task 로
# 세면 total 도 진행률도 AC 커버리지도 전부 부풀어요.
#
# 왜 G5·G6 인가 — 체크박스를 채우는 쪽과 검사받는 쪽이 같으면 게이트가 아니라 자기보고예요.
# G5 는 "보고를 받았는가" 를, G6 은 "다른 컨텍스트가 봤는가" 를 파일에서 확인해요.
#
# Output (--json):
#   {"status":"ok|warning","result":{"spec":"012-x","total":12,"done":9,"open":2,
#     "paused":1,"ac_total":3,"ac_uncovered":["AC3"],"orphan_tasks":["T007"],
#     "task_count_drop":0,"dispatched_unreported":["T011"],"done_without_report":[],
#     "review_required":true,"review_verdict":"진행","complete":false},...}
#   --all 이면 result 는 {"specs":[위 객체 …],"spec_count":3,"total":…,"done":…,"open":…,
#     "complete":false,"violations":5} — 첫 spec 의 숫자에 전체 합계를 섞지 않아요.
#
# Exit: 0 통과 · 1 위반 (--strict 일 때만) · 2 skipped (검사할 spec 이 없거나 tasks.md 부재)
#       README 의 공통 계약과 같아요 — 2 는 "검사 못 함" 이지 "위반" 이 아니에요.

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; STRICT=false; ALL=false; DRY_RUN=false; SPEC=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --strict)  STRICT=true ;;
        --all)     ALL=true ;;
        --dry-run) DRY_RUN=true ;;         # 읽기 전용으로 — 봉인값도 안 건드려요
        --spec)    shift; SPEC="${1:-}" ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,47p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
SPEC_BASE="$PROJECT_ROOT/.ax/docs/spec"

# 대상 spec 결정 — 미지정이면 current-task.json 의 활성 spec
if [ -z "$SPEC" ] && [ "$ALL" != true ]; then
    TASK_FILE="$PROJECT_ROOT/.ax/current-task.json"
    if [ -f "$TASK_FILE" ] && command -v jq >/dev/null 2>&1; then
        SD=$(jq -r '.spec_dir // empty' "$TASK_FILE" 2>/dev/null || true)
        [ -n "$SD" ] && SPEC=$(basename "$SD")
    fi
fi

# --spec 해석은 공통 규칙 (정확 일치 → prefix 1개 → 실패)
if [ -n "$SPEC" ] && [ "$ALL" != true ]; then
    RESOLVED=$(goax_resolve_spec "$SPEC" "$SPEC_BASE") && RC=0 || RC=$?
    if [ "$RC" -eq 0 ]; then
        SPEC="$RESOLVED"
    elif [ "$RC" -eq 2 ]; then
        if [ "$JSON_MODE" = true ]; then
            json_error "--spec '$SPEC' 이 여러 spec 에 걸려요: ${GOAX_SPEC_CANDIDATES} — 하나를 정확히 적으세요"
        fi
        goax_error "--spec '$SPEC' 이 여러 spec 에 걸려요: ${GOAX_SPEC_CANDIDATES}"; exit "$EXIT_ERROR"
    fi
fi

# 펜스 밖 본문만 — 형식 설명 블록의 예시 task 를 실 task 로 세지 않도록
strip_fences() { awk '/^[[:space:]]*```/{f=!f; next} f{next} {print}' "$1" 2>/dev/null || true; }

# ── 한 spec 검사 → "spec|total|done|open|paused|ac_total|uncovered|orphans|drop|unreported|noreport|verdict|required" ──
check_spec() {
    local dir="$1" name; name=$(basename "$dir")
    local tasks="$dir/tasks.md" spec="$dir/spec.md"
    [ -f "$tasks" ] || { printf '%s|0|0|0|0|0|||0|||%s|false\n' "$name" ""; return 0; }

    local total done_n open_n paused
    IFS='|' read -r total done_n open_n paused <<EOF
$(awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^- \[[ x~X]\] / {
        t++
        if ($0 ~ /^- \[[xX]\] /) d++
        else if ($0 ~ /^- \[~\] /) p++
        else o++
    }
    END { printf "%d|%d|%d|%d", t+0, d+0, o+0, p+0 }
' "$tasks" 2>/dev/null)
EOF
    total=${total:-0}; done_n=${done_n:-0}; open_n=${open_n:-0}; paused=${paused:-0}

    # AC 커버리지 — spec.md 에 AC ID 가 있을 때만
    local ac_total=0 uncovered="" orphans=""
    if [ -f "$spec" ]; then
        local acs; acs=$(grep -ohE '\*\*AC[0-9]+\*\*|(^|[^A-Za-z])AC[0-9]+\b' "$spec" 2>/dev/null \
                          | grep -ohE 'AC[0-9]+' | sort -u || true)
        ac_total=$(printf '%s' "$acs" | grep -c . || true); ac_total=${ac_total:-0}
        if [ "$ac_total" -gt 0 ]; then
            local refs; refs=$(strip_fences "$tasks" | grep -ohE '\[AC[0-9]+\]' 2>/dev/null \
                                | grep -ohE 'AC[0-9]+' | sort -u || true)
            local a
            while IFS= read -r a; do
                [ -z "$a" ] && continue
                printf '%s\n' "$refs" | grep -qx "$a" || uncovered="${uncovered}${a} "
            done <<EOF
$acs
EOF
            # orphan — AC 참조가 없는 task (보류는 제외)
            local line tid
            while IFS= read -r line; do
                case "$line" in *'[AC'*) continue ;; esac
                tid=$(printf '%s' "$line" | grep -ohE 'T[0-9]{3,}' | head -1 || true)
                [ -n "$tid" ] && orphans="${orphans}${tid} "
            done < <(strip_fences "$tasks" | grep -E '^- \[[ xX]\] ' || true)
        fi
    fi

    # G4 유실 — state.json 의 봉인값 대비. 갱신은 락 안에서 (동시 검사에 봉인값이 사라져요)
    local drop=0 sealed=""
    local ST="$PROJECT_ROOT/.ax/state.json"
    if command -v jq >/dev/null 2>&1 && [ -f "$ST" ]; then
        sealed=$(jq -r --arg s "$name" '.task_seal[$s] // empty' "$ST" 2>/dev/null || true)
        if [ -n "$sealed" ] && [ "$total" -lt "$sealed" ]; then
            drop=$((sealed - total))
        fi
        # 봉인값 갱신 — 최대치를 기억해요 (task 는 늘 수 있지만 줄면 안 돼요)
        if [ "$DRY_RUN" != true ] && { [ -z "$sealed" ] || [ "$total" -gt "$sealed" ]; }; then
            if goax_lock "$ST.lock"; then
                local TMP="$ST.tmp.$$"
                jq --arg s "$name" --argjson n "$total" \
                   '.task_seal = ((.task_seal // {}) | .[$s] = $n)' "$ST" > "$TMP" 2>/dev/null \
                   && mv "$TMP" "$ST" || rm -f "$TMP"
                goax_unlock "$ST.lock"
            else
                goax_warn "봉인값 갱신 건너뜀 (락 실패): $name"
            fi
        fi
    fi

    # G5 원장 — lanes-dispatch.sh 가 쓰는 continuation 필드를 같은 규칙으로 읽어요
    local unreported="" noreport=""
    local ledger
    ledger=$(awk '
        function flush() { if (id != "") printf "%s|%s|%s|%s\n", id, st, disp, rep; id=""; st=""; disp=""; rep="" }
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }
        /^- \[[ x~X]\] / {
            flush(); st = "open"
            if ($0 ~ /^- \[[xX]\]/) st = "done"; else if ($0 ~ /^- \[~\]/) st = "paused"
            if (match($0, /T[0-9][0-9][0-9]+/)) id = substr($0, RSTART, RLENGTH)
            next
        }
        id != "" && /^[ \t]+디스패치:/ { v = $0; sub(/^[ \t]*디스패치:[ ]*/, "", v); gsub(/[ \t]+$/, "", v); disp = v; next }
        id != "" && /^[ \t]+보고:/     { v = $0; sub(/^[ \t]*보고:[ ]*/, "", v);     gsub(/[ \t]+$/, "", v); rep = v;  next }
        END { flush() }
    ' "$tasks" 2>/dev/null || true)
    unreported=$(printf '%s\n' "$ledger" | awk -F'|' '$2=="open" && $3!="" && $4==""{printf "%s ", $1}')
    noreport=$(printf '%s\n' "$ledger"   | awk -F'|' '$2=="done" && $3!="" && $4==""{printf "%s ", $1}')

    # G6 검증자 — review.md **첫 줄** 의 verdict. 파일은 evaluator 가 써요 (코디네이터가 대신 쓰지 않아요).
    # 파일 어디서든 첫 매치를 잡으면 코드펜스 안 예시 verdict 로도 게이트가 열려요.
    local verdict="" required=false
    if [ -f "$dir/review.md" ]; then
        verdict=$(head -1 "$dir/review.md" 2>/dev/null \
                  | sed -n 's/^verdict:[[:space:]]*//p' | sed -E 's/[[:space:]]+$//' || true)
    fi
    local TF="$PROJECT_ROOT/.ax/current-task.json"
    if command -v jq >/dev/null 2>&1 && [ -f "$TF" ]; then
        local sd; sd=$(basename "$(jq -r '.spec_dir // "/"' "$TF" 2>/dev/null || echo /)")
        if [ "$sd" = "$name" ]; then
            local sz rk ev
            sz=$(jq -r '.size // empty' "$TF" 2>/dev/null || true)
            rk=$(jq -r '.risk // empty' "$TF" 2>/dev/null || true)
            if [ -n "$sz" ] && [ -n "$rk" ]; then
                ev=$(bash "$SCRIPT_DIR/tier-from-state.sh" --json --size "$sz" --risk "$rk" 2>/dev/null \
                     | jq -r '.result.evaluator // empty' 2>/dev/null || true)
                [ "$ev" = "required" ] && required=true
            fi
        fi
    fi

    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$name" "$total" "$done_n" "$open_n" "$paused" "$ac_total" \
        "${uncovered% }" "${orphans% }" "$drop" "${unreported% }" "${noreport% }" "$verdict" "$required"
}

TARGETS=""
if [ "$ALL" = true ]; then
    TARGETS=$(find "$SPEC_BASE" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' 2>/dev/null | sort || true)
elif [ -n "$SPEC" ] && [ -d "$SPEC_BASE/$SPEC" ] && [ -f "$SPEC_BASE/$SPEC/tasks.md" ]; then
    TARGETS="$SPEC_BASE/$SPEC"
fi

# 검사할 게 없으면 "검사 못 함" — 통과가 아니에요. README 공통 계약대로 exit 2.
if [ -z "$TARGETS" ]; then
    if [ "$JSON_MODE" = true ]; then
        json_skip "검사할 spec 이 없어요 — --spec <NNN-slug> 또는 --all (지정: '${SPEC:-<없음>}')"
    fi
    goax_log "검사할 spec 없음 (지정: '${SPEC:-<없음>}')"
    exit "$EXIT_SKIPPED"
fi

VIOLATIONS=0; ROWS=""
while IFS= read -r d; do
    [ -z "$d" ] && continue
    ROWS="${ROWS}$(check_spec "$d")"$'\n'
done <<EOF
$TARGETS
EOF

# 집계 + 보고
# verdict 가 게이트를 막는가 — 필수인데 없거나, 무엇이든 `진행` 이 아니면 막아요
review_blocks() {   # $1 verdict · $2 required
    if [ "$2" = "true" ]; then
        [ "$1" = "진행" ] && return 1 || return 0
    fi
    [ -n "$1" ] && [ "$1" != "진행" ] && return 0
    return 1
}

FIRST=""; ROWS_X=""; SPEC_N=0
SUM_TOTAL=0; SUM_DONE=0; SUM_OPEN=0; SUM_PAUSED=0; ALL_COMPLETE=true
while IFS='|' read -r name total done_n open_n paused ac_total uncovered orphans drop unreported noreport verdict required; do
    [ -z "$name" ] && continue
    [ -z "$FIRST" ] && FIRST="$name|$total|$done_n|$open_n|$paused|$ac_total|$uncovered|$orphans|$drop|$unreported|$noreport|$verdict|$required"
    SPEC_N=$((SPEC_N + 1))
    SUM_TOTAL=$((SUM_TOTAL + total)); SUM_DONE=$((SUM_DONE + done_n))
    SUM_OPEN=$((SUM_OPEN + open_n));  SUM_PAUSED=$((SUM_PAUSED + paused))

    V=0
    [ "$open_n" -gt 0 ] && V=$((V + 1))
    [ -n "$uncovered" ] && V=$((V + 1))
    [ "$drop" -gt 0 ] && V=$((V + 1))
    [ -n "$unreported" ] && V=$((V + 1))
    [ -n "$noreport" ] && V=$((V + 1))
    review_blocks "$verdict" "$required" && V=$((V + 1))
    VIOLATIONS=$((VIOLATIONS + V))
    C=true; [ "$V" -gt 0 ] && { C=false; ALL_COMPLETE=false; }
    ROWS_X="${ROWS_X}${name}|${total}|${done_n}|${open_n}|${paused}|${ac_total}|${uncovered}|${orphans}|${drop}|${unreported}|${noreport}|${verdict}|${required}|${V}|${C}"$'\n'

    if [ "$JSON_MODE" != true ]; then
        printf '%s: %s/%s 완료' "$name" "$done_n" "$total"
        [ "$paused" -gt 0 ] && printf ' (보류 %s)' "$paused"
        [ "$open_n" -gt 0 ] && printf '  ⚠ 미완료 %s' "$open_n"
        [ -n "$uncovered" ] && printf '  ⚠ 대응 task 없는 AC: %s' "$uncovered"
        [ -n "$orphans" ] && printf '  · AC 미참조 task: %s' "$orphans"
        [ "$drop" -gt 0 ] && printf '  ❌ task %s개 사라짐' "$drop"
        [ -n "$unreported" ] && printf '  ⚠ 보고 안 받은 디스패치: %s' "$unreported"
        [ -n "$noreport" ] && printf '  ❌ 보고 없이 완료 표시: %s' "$noreport"
        if review_blocks "$verdict" "$required"; then
            [ -z "$verdict" ] && printf '  ⚠ evaluator 리뷰 필수 — review.md 첫 줄에 verdict 없음' \
                              || printf '  ⚠ evaluator verdict: %s' "$verdict"
        fi
        printf '\n'
    fi
done <<EOF
$ROWS
EOF

row_to_json() {   # stdin: 확장 row(|구분) → JSON 객체 배열
    jq -Rn '[inputs | select(length>0) | split("|") | {
        spec: .[0], total: (.[1]|tonumber), done: (.[2]|tonumber), open: (.[3]|tonumber),
        paused: (.[4]|tonumber), ac_total: (.[5]|tonumber),
        ac_uncovered: (if .[6]=="" then [] else (.[6]|split(" ")) end),
        orphan_tasks: (if .[7]=="" then [] else (.[7]|split(" ")) end),
        task_count_drop: (.[8]|tonumber),
        dispatched_unreported: (if .[9]=="" then [] else (.[9]|split(" ")) end),
        done_without_report: (if .[10]=="" then [] else (.[10]|split(" ")) end),
        review_verdict: (if .[11]=="" then null else .[11] end),
        review_required: (.[12]=="true"),
        violations: (.[13]|tonumber), complete: (.[14]=="true") }]'
}

if [ "$JSON_MODE" = true ]; then
    if [ "$ALL" = true ] && command -v jq >/dev/null 2>&1; then
        SPECS_J=$(printf '%s' "$ROWS_X" | row_to_json)
        RESULT=$(jq -nc --argjson specs "$SPECS_J" --argjson n "$SPEC_N" \
            --argjson t "$SUM_TOTAL" --argjson d "$SUM_DONE" --argjson o "$SUM_OPEN" \
            --argjson p "$SUM_PAUSED" --argjson v "$VIOLATIONS" --argjson c "$ALL_COMPLETE" \
            '{specs:$specs, spec_count:$n, total:$t, done:$d, open:$o, paused:$p, complete:$c, violations:$v}')
        if [ "$VIOLATIONS" -gt 0 ]; then
            json_output "warning" "$RESULT" "spec ${SPEC_N}개 중 완료 조건 미충족 ${VIOLATIONS}건 — specs[] 의 violations 가 0 이 아닌 spec 부터 보세요"
        else
            json_output "ok" "$RESULT" "spec ${SPEC_N}개 전부 완료 조건 충족"
        fi
    else
        IFS='|' read -r name total done_n open_n paused ac_total uncovered orphans drop unreported noreport verdict required <<EOF
$FIRST
EOF
        UNC_J="[]"; ORP_J="[]"; UNR_J="[]"; NOR_J="[]"; VER_J="null"
        if command -v jq >/dev/null 2>&1; then
            [ -n "$uncovered" ]  && UNC_J=$(printf '%s' "$uncovered"  | tr ' ' '\n' | jq -Rn '[inputs|select(length>0)]')
            [ -n "$orphans" ]    && ORP_J=$(printf '%s' "$orphans"    | tr ' ' '\n' | jq -Rn '[inputs|select(length>0)]')
            [ -n "$unreported" ] && UNR_J=$(printf '%s' "$unreported" | tr ' ' '\n' | jq -Rn '[inputs|select(length>0)]')
            [ -n "$noreport" ]   && NOR_J=$(printf '%s' "$noreport"   | tr ' ' '\n' | jq -Rn '[inputs|select(length>0)]')
            [ -n "$verdict" ]    && VER_J=$(jq -n --arg v "$verdict" '$v')
        fi
        COMPLETE=false
        [ "$VIOLATIONS" -eq 0 ] && COMPLETE=true
        RESULT=$(printf '{"spec":"%s","total":%s,"done":%s,"open":%s,"paused":%s,"ac_total":%s,"ac_uncovered":%s,"orphan_tasks":%s,"task_count_drop":%s,"dispatched_unreported":%s,"done_without_report":%s,"review_required":%s,"review_verdict":%s,"complete":%s,"violations":%s}' \
            "${name:-}" "${total:-0}" "${done_n:-0}" "${open_n:-0}" "${paused:-0}" "${ac_total:-0}" \
            "$UNC_J" "$ORP_J" "${drop:-0}" "$UNR_J" "$NOR_J" "${required:-false}" "$VER_J" "$COMPLETE" "$VIOLATIONS")
        if [ "$VIOLATIONS" -gt 0 ]; then
            if review_blocks "$verdict" "$required" && [ "${open_n:-0}" -eq 0 ]; then
                [ -z "$verdict" ] \
                    && json_output "warning" "$RESULT" "task 는 끝났지만 evaluator 리뷰가 필수예요 — 새 컨텍스트로 evaluator 를 띄워 review.md 첫 줄에 verdict 를 받으세요" \
                    || json_output "warning" "$RESULT" "evaluator verdict '${verdict}' — 지적을 task 로 옮겨 처리하거나 재논의하세요"
            elif [ -n "$unreported" ] || [ -n "$noreport" ]; then
                json_output "warning" "$RESULT" "레인 원장 불일치 — 산출물을 받고 lanes-dispatch.sh --report 로 기록한 뒤에만 체크박스를 켜세요"
            else
                json_output "warning" "$RESULT" "완료 조건 미충족 ${VIOLATIONS}건 — 미완료 task 는 끝내거나 [~] 로 사유와 함께 보류 처리하세요"
            fi
        else
            json_output "ok" "$RESULT" "완료 조건 충족"
        fi
    fi
fi

[ "$VIOLATIONS" -gt 0 ] && [ "$STRICT" = true ] && exit "$EXIT_ERROR"
exit "$EXIT_OK"
