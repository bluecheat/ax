#!/usr/bin/env bash
# .ax/scripts/bash/mark-task.sh — tasks.md 체크박스를 켜요 (접두 정확 일치 · 락 · 결과 검증)
#
# Usage:
#   bash mark-task.sh [--spec <id-slug>] --task T013[,T014,…] [--state x|~] [--dry-run] [--json]
#   bash mark-task.sh [--spec <id-slug>] --next [--json]
#
# 왜: 인라인 sed(`/^- \[ \] .*T013/`)는 줄 어디든 ID 가 있으면 매칭해서, 본문에 다른 task 를 언급한 줄까지
#   [x] 로 바꿨어요 (실측 3건이 검증 없이 완료). 락도 없었어요.
# 규칙: 줄 **앞** ID 만(`- [ ] T013 ` · `**T013**` · `[T013]`) · 코드 펜스 안은 건너뜀 · tasks.md.lock ·
#   쓰기 전후 [x] 개수가 바꾼 줄 수만큼만 늘었는지(이미 켜져 있으면 0) 확인.
# --task T013,T014 — 쉼표로 여러 개. 트랜잭션이에요: 하나라도 없거나 중복이면 아무것도 안 켜요.
#   이미 켜진 것은 건너뛰고 unchanged_tasks 에 적어요.
# --next 는 읽기만 해요 — 펜스 밖에서 **의존(`의존:` 줄)이 전부 [x] 또는 [~] 인** 첫 미완료 task 예요
#   (템플릿 펜스 안의 예시 줄을 집지 않게). 파서는 tasks-plan.sh 와 같은 goax_tasks_parse 예요.
#   미완료는 있는데 전부 의존에 막혔으면 status warning · result.blocked=true · blocked_tasks 에 막힌 task 와
#   풀리지 않은 의존(unresolved — tasks.md 에 없는 ID 는 missing 에도)을 돌려줘요. 끝난 게 아니라 완료 게이트로 가면 안 돼요.
#
# Output (--json):
#   --task: {"status":"ok","result":{"spec":"…","task":"T013","tasks":["T013"],"state":"x","line":57,"lines":[57],
#            "changed":true,"changed_tasks":["T013"],"unchanged_tasks":[],"done_before":11,"done_after":12}}
#            (여러 개면 task 는 "T013,T014", line 은 첫 task 의 줄)
#   --next: {"status":"ok","result":{"spec":"…","task":"T014","line":63,"text":"- [ ] T014 …","deps":["T013"],"blocked":false}}
#           · 미완료 없음 → status skipped (exit 2)
#           · 전부 막힘 → {"status":"warning","result":{"spec":"…","task":null,"blocked":true,
#                         "blocked_tasks":[{"task":"T014","line":63,"text":"…","unresolved":["T013"],"missing":[]}]}} (exit 0)
# Exit: 0 ok (--next 의 전부 막힘 warning 포함) · 1 error (task 없음 · ID 중복 · 락 실패 · 검증 불일치) · 2 skipped (--next 에서 미완료 없음)
set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

SPEC=""; TASK=""; STATE="x"; MODE="mark"; DRY_RUN=false; JSON_MODE=false
while [ $# -gt 0 ]; do
    case "$1" in
        --spec)     SPEC="${2:-}"; shift ;;
        --task)     TASK="${2:-}"; shift ;;
        --state)    STATE="${2:-}"; shift ;;
        --next)     MODE="next" ;;
        --dry-run)  DRY_RUN=true ;;
        --json)     JSON_MODE=true ;;
        -h|--help)  goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK" ;;
        *)          goax_error "알 수 없는 옵션: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"   # lanes-dispatch.sh 와 같은 루트 — tasks.md.lock 문자열이 같아야 해요

fail() {
    if [ "$JSON_MODE" = true ]; then json_error "$1"; fi
    goax_error "$1"; exit "$EXIT_ERROR"
}

if [ -z "$SPEC" ] && command -v jq >/dev/null 2>&1; then
    TF="$PROJECT_ROOT/.ax/current-task.json"
    if [ -f "$TF" ]; then
        SD=$(jq -r '.spec_dir // empty' "$TF" 2>/dev/null || true)
        [ -n "$SD" ] && SPEC=$(basename "$SD")
    fi
fi

if [ -n "$SPEC" ]; then
    RESOLVED=$(goax_resolve_spec "$SPEC" "$PROJECT_ROOT/.ax/docs/spec") && RC=0 || RC=$?
    if [ "$RC" -eq 0 ]; then SPEC="$RESOLVED"
    elif [ "$RC" -eq 2 ]; then
        fail "--spec '$SPEC' 이 여러 spec 에 걸려요: ${GOAX_SPEC_CANDIDATES} — 하나를 정확히 적으세요"
    fi
fi

TASKS="$PROJECT_ROOT/.ax/docs/spec/$SPEC/tasks.md"
LOCK="$TASKS.lock"
if [ -z "$SPEC" ] || [ ! -f "$TASKS" ]; then
    fail "tasks.md 를 찾을 수 없어요: .ax/docs/spec/${SPEC:-<없음>}/tasks.md"
fi

# task 줄 판정 — 펜스 밖 · 줄 앞이 체크박스 · 바로 뒤가 ID (장식 `**`·`[ ]` 허용) · 그 뒤가 비영숫자
# ID 뒤에 영숫자가 오면 매칭 안 함 → T001 이 T0011 을 건드리지 않아요. `\b` 는 GNU 전용이라 안 써요
task_line_regex() {
    # $1 = 상태 클래스(예: "[ ]" 또는 "[x ~]"), $2 = task ID
    printf '^- \\[%s\\] (\\*\\*|\\[)?%s(\\*\\*|\\])?([^[:alnum:]]|$)' "$1" "$2"
}

# 펜스 밖 줄만 "번호<TAB>내용" 으로 — awk 는 ``` 를 만날 때마다 토글해요
outside_fences() {
    awk 'BEGIN{f=0} /^```/{f=!f; next} !f {printf "%d\t%s\n", NR, $0}' "$TASKS"
}

if [ "$MODE" = "next" ]; then
    # 그래프는 tasks-plan.sh 와 같은 파서(goax_tasks_parse)로 읽어요 — 둘이 다르게 읽으면 plan 은 blocked 라는데
    # --next 는 그 task 를 집어요. 의존이 전부 [x] 또는 [~] 인 첫 미완료 task 가 다음이에요.
    PARSED=$(goax_tasks_parse "$TASKS")
    if ! printf '%s\n' "$PARSED" | awk -F'|' '$2=="open"{f=1} END{exit !f}'; then
        if [ "$JSON_MODE" = true ]; then json_skip "미완료 task 없음 — §8 완료 게이트로"; fi
        goax_log "미완료 task 없음 — §8 완료 게이트로"; exit "$EXIT_SKIPPED"
    fi
    # 각 미완료 task → "ID|line|unresolved(,)|missing(,)" — unresolved 는 아직 [ ] 이거나 tasks.md 에 없는 의존
    GRAPH=$(printf '%s\n' "$PARSED" | awk -F'|' '
        NF { id[NR] = $1; st[NR] = $2; dp[NR] = $5; ln[NR] = $6; state[$1] = $2; n = NR }
        END {
            for (i = 1; i <= n; i++) {
                if (st[i] != "open") continue
                un = ""; ms = ""
                k = split(dp[i], d, ",")
                for (j = 1; j <= k; j++) {
                    if (d[j] == "") continue
                    if (!(d[j] in state)) { un = un (un == "" ? "" : ",") d[j]; ms = ms (ms == "" ? "" : ",") d[j] }
                    else if (state[d[j]] == "open") un = un (un == "" ? "" : ",") d[j]
                }
                printf "%s|%s|%s|%s\n", id[i], ln[i], un, ms
            }
        }')
    HIT=$(printf '%s\n' "$GRAPH" | awk -F'|' 'NF && $3 == "" {print; exit}')
    if [ -z "$HIT" ]; then
        # 미완료는 있는데 전부 의존이 안 풀렸어요 — 끝난 게 아니라 막힌 거예요 (완료 게이트로 가면 안 돼요)
        if [ "$JSON_MODE" = true ]; then
            BLK=$(printf '%s\n' "$GRAPH" | while IFS='|' read -r bid bln bun bms; do
                    [ -n "$bid" ] || continue
                    btx=$(sed -n "${bln}p" "$TASKS")
                    jq -nc --arg t "$bid" --argjson l "$bln" --arg x "$btx" --arg u "$bun" --arg m "$bms" \
                        'def l: split(",") | map(select(length > 0)); {task:$t, line:$l, text:$x, unresolved:($u|l), missing:($m|l)}'
                  done | jq -sc .)
            RESULT=$(jq -nc --arg spec "$SPEC" --argjson b "$BLK" '{spec:$spec, task:null, blocked:true, blocked_tasks:$b}')
            MSG="미완료 task 가 전부 의존에 막혀 있어요 — $(printf '%s' "$BLK" | jq -r 'map("\(.task)←\(.unresolved|join(","))") | join(" · ")'). 의존 task 를 먼저 끝내거나, tasks.md 에 없는 의존(missing)은 고치세요"
            json_output "warning" "$RESULT" "$MSG" "$(_goax_json_array "$MSG")"
        else
            goax_warn "미완료 task 가 전부 의존에 막혀 있어요:"
            printf '%s\n' "$GRAPH" | awk -F'|' 'NF{printf "  %s ← %s%s\n", $1, $3, ($4 != "" ? " (tasks.md 에 없음: " $4 ")" : "")}' >&2
        fi
        exit "$EXIT_OK"
    fi
    IFS='|' read -r ID LINE _UN _MS <<EOF
$HIT
EOF
    TEXT=$(sed -n "${LINE}p" "$TASKS")
    DEPS=$(printf '%s\n' "$PARSED" | awk -F'|' -v id="$ID" '$1==id{print $5; exit}')
    if [ "$JSON_MODE" = true ]; then
        RESULT=$(jq -nc --arg spec "$SPEC" --arg task "$ID" --argjson line "$LINE" --arg text "$TEXT" --arg deps "$DEPS" \
            '{spec:$spec, task:$task, line:$line, text:$text, deps:($deps | split(",") | map(select(length > 0))), blocked:false}')
        json_output "ok" "$RESULT" "다음 task: $ID"
    else
        printf '%s\n' "$TEXT"
    fi
    exit "$EXIT_OK"
fi

[ -n "$TASK" ] || fail "--task <T0NN> 이 필요해요"
case "$STATE" in x|"~") ;; *) fail "--state 는 x(완료) 또는 ~(보류) 만 받아요: $STATE" ;; esac
# 쉼표로 여러 개 — 순서 유지 · 중복 제거. 하나라도 형식이 틀리면 아무것도 안 해요
IDS=$(printf '%s' "$TASK" | tr -d ' ' | tr ',' '\n' | awk 'NF && !seen[$0]++')
[ -n "$IDS" ] || fail "--task <T0NN> 이 필요해요"
for id in $IDS; do
    printf '%s' "$id" | grep -Eq '^T[0-9]+$' || fail "task ID 형식이 아니에요: $id (예: T013 또는 T013,T014)"
done
TASK=$(printf '%s\n' "$IDS" | paste -sd, -)

# 락 안에서 읽어요 — 읽기가 "이 실행이 쓰는가" 를 결정하니 창은 여기서 열려요
goax_lock "$LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || fail "tasks.md 락을 못 잡았어요: $LOCK — 다른 프로세스가 쓰는 중이거나 락이 남아 있어요"
trap 'goax_unlock "$LOCK"' EXIT

# 1단계: 전부 검증만 — 하나라도 없거나 중복이면 파일을 안 건드려요 (반쯤 켜진 체크박스는 더 나빠요)
FENCED=$(outside_fences)
LINES=""; CHANGE_LINES=""; CHANGED_IDS=""; KEPT=""; FIRST_LINE=""; FIRST_TEXT=""; CUR=""
for id in $IDS; do
    ANY_RE=$(task_line_regex '[ x~]' "$id")
    OPEN_RE=$(task_line_regex '[ ]' "$id")
    HITS=$(printf '%s\n' "$FENCED" | grep -E $'\t'"${ANY_RE#^}" || true)
    N_ALL=$(printf '%s\n' "$HITS" | grep -c . || true); N_ALL=${N_ALL:-0}
    [ "$N_ALL" -ge 1 ] || fail "task $id 줄이 없어요 (펜스 밖 · 줄 앞 ID 기준) — tasks.md 형식은 '- [ ] T0NN …' 이에요"
    [ "$N_ALL" -eq 1 ] || fail "task $id 줄이 ${N_ALL}개예요 — ID 가 중복됐어요. 하나만 남기세요"
    LN=${HITS%%$'\t'*}; TX=${HITS#*$'\t'}
    [ -z "$FIRST_LINE" ] && { FIRST_LINE=$LN; FIRST_TEXT=$TX; }
    LINES="${LINES:+$LINES,}$LN"
    if printf '%s' "$TX" | grep -Eq "$OPEN_RE"; then
        CHANGE_LINES="${CHANGE_LINES:+$CHANGE_LINES,}$LN"; CHANGED_IDS="${CHANGED_IDS:+$CHANGED_IDS,}$id"
    else
        KEPT="${KEPT:+$KEPT,}$id"
        [ -z "$CUR" ] && CUR=$(printf '%s' "$TX" | sed -E 's/^- \[(.)\].*/\1/')
    fi
done
DONE_BEFORE=$(grep -cE '^- \[x\] ' "$TASKS" || true); DONE_BEFORE=${DONE_BEFORE:-0}
N_CHANGE=$(printf '%s' "$CHANGED_IDS" | awk -F, 'NF{print NF; exit} END{if(!NR) print 0}')

# result — 단일 ID 때의 모양(task·line·changed)을 그대로 두고 tasks·changed_tasks·lines 를 더해요
result_json() {   # $1 changed(bool) · $2 done_after · $3 dry_run(bool) · $4 state
    jq -nc --arg spec "$SPEC" --arg task "$TASK" --arg state "$4" --argjson line "$FIRST_LINE" \
        --arg lines "$LINES" --arg ch "$CHANGED_IDS" --arg kept "$KEPT" \
        --argjson changed "$1" --argjson before "$DONE_BEFORE" --argjson after "$2" --argjson dry "$3" '
        def l: split(",") | map(select(length > 0));
        {spec:$spec, task:$task, tasks:($task|l), state:$state, line:$line, lines:($lines|l|map(tonumber)),
         changed:$changed, changed_tasks:($ch|l), unchanged_tasks:($kept|l),
         done_before:$before, done_after:$after} + (if $dry then {dry_run:true} else {} end)'
}

if [ "$N_CHANGE" -eq 0 ]; then
    # 전부 이미 [x] 또는 [~] — 다시 켤 게 없어요 (idempotent)
    if [ "$JSON_MODE" = true ]; then
        json_output "ok" "$(result_json false "$DONE_BEFORE" false "$CUR")" "이미 [$CUR] 예요 — 바꾸지 않았어요"
    else
        goax_log "$TASK 는 이미 [$CUR] 예요 — 바꾸지 않았어요"
    fi
    exit "$EXIT_OK"
fi

if [ "$DRY_RUN" = true ]; then
    if [ "$JSON_MODE" = true ]; then
        json_output "ok" "$(result_json false "$DONE_BEFORE" true "$STATE")" "dry-run — ${CHANGE_LINES}행을 [$STATE] 로 바꿀 거예요"
    else
        if [ "$N_CHANGE" -eq 1 ] && [ -z "$KEPT" ]; then
            printf '(dry-run) %s행: %s → [%s]\n' "$FIRST_LINE" "$FIRST_TEXT" "$STATE"
        else
            printf '(dry-run) %s (%s행) → [%s]%s\n' "$CHANGED_IDS" "$CHANGE_LINES" "$STATE" "${KEPT:+ · 이미 켜짐: $KEPT}"
        fi
    fi
    exit "$EXIT_OK"
fi

tmp=$(goax_mktemp "$PROJECT_ROOT") || { goax_tmp_error; exit "$EXIT_ERROR"; }
# 그 줄들만 바꿔요 — 줄 번호로 집어요 (같은 ID 가 둘이면 위에서 이미 막았어요)
awk -v ns="$CHANGE_LINES" -v st="$STATE" '
    BEGIN { n = split(ns, a, ","); for (i = 1; i <= n; i++) want[a[i]] = 1 }
    (NR in want) { sub(/^- \[ \]/, "- [" st "]") } { print }' "$TASKS" > "$tmp" \
    && mv "$tmp" "$TASKS" || { rm -f "$tmp"; fail "tasks.md 갱신 실패: $TASKS"; }

# 사후 검증 — 바꾼 줄 수만큼만 늘었는지. 더 뛰면 awk 가 잘못 집은 거예요
DONE_AFTER=$(grep -cE '^- \[x\] ' "$TASKS" || true); DONE_AFTER=${DONE_AFTER:-0}
EXPECT=$DONE_BEFORE; [ "$STATE" = "x" ] && EXPECT=$((DONE_BEFORE + N_CHANGE))
[ "$DONE_AFTER" -eq "$EXPECT" ] || fail "마킹 뒤 [x] 개수가 어긋나요: 전 $DONE_BEFORE → 후 $DONE_AFTER (기대 $EXPECT). tasks.md 를 눈으로 확인하세요"

if [ "$JSON_MODE" = true ]; then
    json_output "ok" "$(result_json true "$DONE_AFTER" false "$STATE")" "$CHANGED_IDS → [$STATE] (${DONE_AFTER} 완료)${KEPT:+ · 이미 켜져 있던 $KEPT 는 그대로}"
else
    goax_log "$CHANGED_IDS → [$STATE] (${CHANGE_LINES}행, 완료 ${DONE_BEFORE} → ${DONE_AFTER})${KEPT:+ · 이미 켜져 있던 $KEPT 는 그대로}"
fi
exit "$EXIT_OK"
