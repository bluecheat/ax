#!/usr/bin/env bash
# .ax/scripts/bash/mark-task.sh — tasks.md 체크박스 하나를 켜요 (접두 정확 일치 · 락 · 결과 검증)
#
# Usage:
#   bash mark-task.sh [--spec <id-slug>] --task T013 [--state x|~] [--dry-run] [--json]
#   bash mark-task.sh [--spec <id-slug>] --next [--json]
#
# 왜: 인라인 sed(`/^- \[ \] .*T013/`)는 줄 어디든 ID 가 있으면 매칭해서, 본문에 다른 task 를 언급한 줄까지
#   [x] 로 바꿨어요 (실측 3건이 검증 없이 완료). 락도 없었어요.
# 규칙: 줄 **앞** ID 만(`- [ ] T013 ` · `**T013**` · `[T013]`) · 코드 펜스 안은 건너뜀 · tasks.md.lock ·
#   쓰기 전후 [x] 개수가 정확히 1 늘었는지(이미 켜져 있으면 0) 확인.
# --next 는 읽기만 해요 — 펜스 밖 첫 미완료 task (템플릿 펜스 안의 예시 줄을 집지 않게).
#
# Output (--json):
#   --task: {"status":"ok","result":{"spec":"…","task":"T013","state":"x","line":57,"changed":true,"done_before":11,"done_after":12}}
#   --next: {"status":"ok","result":{"spec":"…","task":"T014","line":63,"text":"- [ ] T014 …"}}  · 없으면 status skipped
# Exit: 0 ok · 1 error (task 없음 · ID 중복 · 락 실패 · 검증 불일치) · 2 skipped (--next 에서 미완료 없음)
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
    HIT=$(outside_fences | grep -m1 -E $'\t''- \[ \] ' || true)
    if [ -z "$HIT" ]; then
        if [ "$JSON_MODE" = true ]; then json_skip "미완료 task 없음 — §8 완료 게이트로"; fi
        goax_log "미완료 task 없음 — §8 완료 게이트로"; exit "$EXIT_SKIPPED"
    fi
    LINE=${HIT%%$'\t'*}; TEXT=${HIT#*$'\t'}
    ID=$(printf '%s' "$TEXT" | sed -E 's/^- \[ \] (\*\*|\[)?(T[0-9]+).*/\2/')
    if [ "$JSON_MODE" = true ]; then
        RESULT=$(jq -nc --arg spec "$SPEC" --arg task "$ID" --argjson line "$LINE" --arg text "$TEXT" \
            '{spec:$spec, task:$task, line:$line, text:$text}')
        json_output "ok" "$RESULT" "다음 task: $ID"
    else
        printf '%s\n' "$TEXT"
    fi
    exit "$EXIT_OK"
fi

[ -n "$TASK" ] || fail "--task <T0NN> 이 필요해요"
case "$STATE" in x|"~") ;; *) fail "--state 는 x(완료) 또는 ~(보류) 만 받아요: $STATE" ;; esac
printf '%s' "$TASK" | grep -Eq '^T[0-9]+$' || fail "task ID 형식이 아니에요: $TASK (예: T013)"

ANY_RE=$(task_line_regex '[ x~]' "$TASK")
OPEN_RE=$(task_line_regex '[ ]' "$TASK")

# 락 안에서 읽어요 — 읽기가 "이 실행이 쓰는가" 를 결정하니 창은 여기서 열려요
goax_lock "$LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || fail "tasks.md 락을 못 잡았어요: $LOCK — 다른 프로세스가 쓰는 중이거나 락이 남아 있어요"
trap 'goax_unlock "$LOCK"' EXIT

ALL_HITS=$(outside_fences | grep -E $'\t'"${ANY_RE#^}" || true)
N_ALL=$(printf '%s\n' "$ALL_HITS" | grep -c . || true); N_ALL=${N_ALL:-0}
[ "$N_ALL" -ge 1 ] || fail "task $TASK 줄이 없어요 (펜스 밖 · 줄 앞 ID 기준) — tasks.md 형식은 '- [ ] T0NN …' 이에요"
[ "$N_ALL" -eq 1 ] || fail "task $TASK 줄이 ${N_ALL}개예요 — ID 가 중복됐어요. 하나만 남기세요"

LINE=${ALL_HITS%%$'\t'*}
TEXT=${ALL_HITS#*$'\t'}
DONE_BEFORE=$(grep -cE '^- \[x\] ' "$TASKS" || true); DONE_BEFORE=${DONE_BEFORE:-0}

if ! printf '%s' "$TEXT" | grep -Eq "$OPEN_RE"; then
    # 이미 [x] 또는 [~] — 다시 켤 게 없어요 (idempotent). 상태가 다르면 알려만 줘요
    CUR=$(printf '%s' "$TEXT" | sed -E 's/^- \[(.)\].*/\1/')
    if [ "$JSON_MODE" = true ]; then
        RESULT=$(jq -nc --arg spec "$SPEC" --arg task "$TASK" --arg state "$CUR" --argjson line "$LINE" \
            --argjson before "$DONE_BEFORE" '{spec:$spec, task:$task, state:$state, line:$line, changed:false, done_before:$before, done_after:$before}')
        json_output "ok" "$RESULT" "이미 [$CUR] 예요 — 바꾸지 않았어요"
    else
        goax_log "$TASK 는 이미 [$CUR] 예요 — 바꾸지 않았어요"
    fi
    exit "$EXIT_OK"
fi

if [ "$DRY_RUN" = true ]; then
    if [ "$JSON_MODE" = true ]; then
        RESULT=$(jq -nc --arg spec "$SPEC" --arg task "$TASK" --arg state "$STATE" --argjson line "$LINE" \
            --argjson before "$DONE_BEFORE" '{spec:$spec, task:$task, state:$state, line:$line, changed:false, dry_run:true, done_before:$before}')
        json_output "ok" "$RESULT" "dry-run — ${LINE}행을 [$STATE] 로 바꿀 거예요"
    else
        printf '(dry-run) %s행: %s → [%s]\n' "$LINE" "$TEXT" "$STATE"
    fi
    exit "$EXIT_OK"
fi

tmp=$(goax_mktemp "$PROJECT_ROOT") || { goax_tmp_error; exit "$EXIT_ERROR"; }
# 그 한 줄만 바꿔요 — 줄 번호로 집어요 (같은 ID 가 둘이면 위에서 이미 막았어요)
awk -v n="$LINE" -v st="$STATE" 'NR==n { sub(/^- \[ \]/, "- [" st "]") } { print }' "$TASKS" > "$tmp" \
    && mv "$tmp" "$TASKS" || { rm -f "$tmp"; fail "tasks.md 갱신 실패: $TASKS"; }

# 사후 검증 — 정확히 한 줄만 바뀌었는지. 한 줄 매칭인데 개수가 2 이상 뛰면 awk 가 잘못 집은 거예요
DONE_AFTER=$(grep -cE '^- \[x\] ' "$TASKS" || true); DONE_AFTER=${DONE_AFTER:-0}
EXPECT=$DONE_BEFORE; [ "$STATE" = "x" ] && EXPECT=$((DONE_BEFORE + 1))
[ "$DONE_AFTER" -eq "$EXPECT" ] || fail "마킹 뒤 [x] 개수가 어긋나요: 전 $DONE_BEFORE → 후 $DONE_AFTER (기대 $EXPECT). tasks.md 를 눈으로 확인하세요"

if [ "$JSON_MODE" = true ]; then
    RESULT=$(jq -nc --arg spec "$SPEC" --arg task "$TASK" --arg state "$STATE" --argjson line "$LINE" \
        --argjson before "$DONE_BEFORE" --argjson after "$DONE_AFTER" \
        '{spec:$spec, task:$task, state:$state, line:$line, changed:true, done_before:$before, done_after:$after}')
    json_output "ok" "$RESULT" "$TASK → [$STATE] (${DONE_AFTER} 완료)"
else
    goax_log "$TASK → [$STATE] (${LINE}행, 완료 ${DONE_BEFORE} → ${DONE_AFTER})"
fi
exit "$EXIT_OK"
