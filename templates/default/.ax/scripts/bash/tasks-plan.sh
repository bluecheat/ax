#!/usr/bin/env bash
# .ax/scripts/bash/tasks-plan.sh — tasks.md 를 실행 그래프로 읽기
#
# Usage:
#   bash tasks-plan.sh [--spec <id-slug>] [--json] [--help]
#
# 하는 일:
#   ready       지금 바로 시작 가능한 task (미완료 + 의존이 전부 완료 [x] 또는 보류 [~])
#   parallel    그중 `[P]` 가 붙었고 서로 파일이 안 겹치는 것
#   violations  `[P]` 인데 다른 `[P]` 와 파일이 겹치는 것 — 주장 검증
#
# ``` 코드펜스 안의 줄은 건너뛰어요 — 형식 설명용 예시 task 가 실 task 로 세면 같은 ID 가
# ready 와 blocked 양쪽에 나와요. `files:` 경로는 비교 전에 정규화해요 (`./` 제거 · 중복 `/` ·
# 끝 `/`) — `src/a.ts` 와 `./src/a.ts` 는 같은 파일이고 표기 차이로 겹침 검사를 빠져나갈 수 없어요.
#
# **wave 를 만들지 않아요.** "1차 전원 완료 → 2차 시작" 은 배리어라, 가장 느린
# 하나가 나머지를 기다리게 해요. 항목별로 "내 의존이 끝났으면 나는 준비됨" 이 맞아요.
#
# **자동 실행하지 않아요.** 몇 개를 어떻게 돌릴지는 세션이 판단해요. 이 스크립트는
# 어휘와 상태만 줘요 — 도구가 판단 없이 N개를 뿌리면 쓰기 충돌 위험을 도구가
# 스스로 만들게 돼요.
#
# Output (--json):
#   {"status":"ok","result":{"spec":"012-x","ready":["T002"],"parallel":["T002"],
#     "blocked":["T003"],"violations":[{"tasks":["T005","T006"],"file":"a.kt"}]},...}
#
# Exit: 0 ok / 1 error (tasks.md 없음 · --spec 이 여러 spec 에 걸림)

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; SPEC=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) : ;;                       # 읽기 전용
        --spec)    shift; SPEC="${1:-}" ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    goax_help "${BASH_SOURCE[0]}"
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"

if [ -z "$SPEC" ] && command -v jq >/dev/null 2>&1; then
    TF="$PROJECT_ROOT/.ax/current-task.json"
    [ -f "$TF" ] && SPEC=$(basename "$(jq -r '.spec_dir // empty' "$TF" 2>/dev/null || true)")
fi
# --spec 해석은 공통 규칙 (정확 일치 → prefix 1개 → 실패) — 스크립트마다 다르면 같은 인자에 다른 답이 나와요
if [ -n "$SPEC" ]; then
    RESOLVED=$(goax_resolve_spec "$SPEC" "$PROJECT_ROOT/.ax/docs/spec") && RC=0 || RC=$?
    if [ "$RC" -eq 0 ]; then
        SPEC="$RESOLVED"
    elif [ "$RC" -eq 2 ]; then
        if [ "$JSON_MODE" = true ]; then json_error "--spec '$SPEC' 이 여러 spec 에 걸려요: ${GOAX_SPEC_CANDIDATES} — 하나를 정확히 적으세요"; fi
        goax_error "--spec '$SPEC' 이 여러 spec 에 걸려요: ${GOAX_SPEC_CANDIDATES}"; exit "$EXIT_ERROR"
    fi
fi

TASKS="$PROJECT_ROOT/.ax/docs/spec/$SPEC/tasks.md"
if [ ! -f "$TASKS" ]; then
    NO_TASKS="tasks.md 를 찾을 수 없어요: .ax/docs/spec/${SPEC:-<없음>}/tasks.md — spec-tasks skill 로 만들거나 bash .ax/scripts/bash/add-spec-files.sh --spec ${SPEC:-<id>} --add tasks"
    if [ "$JSON_MODE" = true ]; then json_error "$NO_TASKS"; fi
    goax_error "$NO_TASKS"; exit "$EXIT_ERROR"
fi

# 파싱 — common.sh 의 goax_tasks_parse (mark-task.sh --next 와 같은 파서). task 줄 + 뒤따르는 `의존:` 줄.
# 출력: "ID|state|P|files(,)|deps(,)|line"
PARSED=$(goax_tasks_parse "$TASKS")

# 의존이 풀린 것 = [x] 완료 또는 [~] 의도적 보류 — mark-task.sh --next 와 같은 기준이에요.
# 보류를 안 풀린 걸로 세면 보류 task 에 기대는 task 가 영원히 blocked 인데, 완료 게이트(G1)는 보류를 정상으로 봐요.
DONE_IDS=$(printf '%s\n' "$PARSED" | awk -F'|' '$2=="done" || $2=="paused"{print $1}')
is_done() { printf '%s\n' "$DONE_IDS" | grep -qx "$1"; }

READY=""; BLOCKED=""; PCAND=""
while IFS='|' read -r id st par files deps _ln; do
    [ -z "$id" ] && continue
    [ "$st" = "open" ] || continue
    ok=true
    if [ -n "$deps" ]; then
        oldIFS="$IFS"; IFS=','
        for d in $deps; do
            d=$(printf '%s' "$d" | tr -d ' ')
            [ -z "$d" ] && continue
            is_done "$d" || ok=false
        done
        IFS="$oldIFS"
    fi
    if [ "$ok" = true ]; then
        READY="$READY$id "
        [ "$par" = "1" ] && PCAND="$PCAND$id:$files"$'\n'
    else
        BLOCKED="$BLOCKED$id "
    fi
done <<EOF
$PARSED
EOF

# [P] 주장 검증 — ready 인 [P] 끼리 파일이 겹치면 violation.
# spec-kit 은 이 규칙을 산문으로만 적어놨는데, 검사하지 않으면 규칙이 아니에요.
VIOL=""
while IFS= read -r a; do
    [ -z "$a" ] && continue
    aid="${a%%:*}"; af="${a#*:}"
    while IFS= read -r b; do
        [ -z "$b" ] && continue
        bid="${b%%:*}"; bf="${b#*:}"
        [ "$aid" \< "$bid" ] || continue      # 각 쌍을 한 번만
        oldIFS="$IFS"; IFS=','
        for f1 in $af; do
            [ -z "$f1" ] && continue
            for f2 in $bf; do
                [ "$f1" = "$f2" ] && VIOL="${VIOL}${aid},${bid},${f1}"$'\n'
            done
        done
        IFS="$oldIFS"
    done <<EOF2
$PCAND
EOF2
done <<EOF3
$PCAND
EOF3

PARALLEL=$(printf '%s' "$PCAND" | awk -F: 'NF{print $1}' | tr '\n' ' ')
VIOL_N=$(printf '%s' "$VIOL" | grep -c . || true); VIOL_N=${VIOL_N:-0}

if [ "$JSON_MODE" = true ]; then
    arr() { printf '%s' "$1" | tr ' ' '\n' | jq -Rn '[inputs|select(length>0)]' 2>/dev/null || echo '[]'; }
    V_J='[]'
    if [ "$VIOL_N" -gt 0 ] && command -v jq >/dev/null 2>&1; then
        V_J=$(printf '%s' "$VIOL" | jq -Rn '[inputs|select(length>0)|split(",")|{tasks:[.[0],.[1]],file:.[2]}]')
    fi
    RESULT=$(printf '{"spec":"%s","ready":%s,"parallel":%s,"blocked":%s,"violations":%s}' \
        "$SPEC" "$(arr "$READY")" "$(arr "$PARALLEL")" "$(arr "$BLOCKED")" "$V_J")
    if [ "$VIOL_N" -gt 0 ]; then
        json_output "warning" "$RESULT" "[P] 인데 파일이 겹치는 task 가 ${VIOL_N}쌍 — 겹치는 쪽의 [P] 를 떼거나 의존을 명시하세요"
    else
        json_output "ok" "$RESULT" "ready 한 task 부터 진행하세요. 몇 개를 동시에 돌릴지는 판단해서 결정하세요"
    fi
else
    printf 'ready: %s\nparallel: %s\nblocked: %s\n' "${READY:-없음}" "${PARALLEL:-없음}" "${BLOCKED:-없음}"
    [ "$VIOL_N" -gt 0 ] && printf 'violations:\n%s' "$VIOL"
fi
exit "$EXIT_OK"
