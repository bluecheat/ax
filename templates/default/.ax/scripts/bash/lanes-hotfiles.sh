#!/usr/bin/env bash
# .ax/scripts/bash/lanes-hotfiles.sh — tasks.md 에서 핫 파일을 뽑아요
#
# Usage:
#   bash lanes-hotfiles.sh [--spec <NNN-slug>] [--min <N>] [--json] [--help]
#
# 핫 파일 = **미완료 task 여러 개가 같은 파일을 쓴다**. 레인을 파일 소유권으로
# 가를 때, 이 목록의 파일은 반드시 한 레인이 독점해야 해요. 두 레인이 같은 파일을
# 만지면 Phase 가 달라도 충돌해요.
#
# tasks-plan.sh 와 뭐가 다른가:
#   tasks-plan.sh  ready 인 `[P]` 끼리의 충돌 — 지금 당장 위반인 것
#   이 스크립트    `[P]` 여부·ready 여부와 무관하게 **경합하는 파일 전부** — 레인을
#                  가르기 *전에* 알아야 하는 것
#
# 두 번째 출력 `tasks_missing_files` 가 중요해요. 파일 겹침 검출은 task 줄에 파일
# 경로가 실제로 적혀 있어야 성립해요. `files:` 가 없는 task 는 겹쳐도 조용히 통과해서,
# 게이트가 "위반 없음" 이라고 말하는데 실제로는 검사가 안 된 상태가 돼요.
#
# ``` 코드펜스 안의 줄은 건너뛰어요 — 형식 설명용 예시 task 가 실 task 로 세면 안 되니까요.
# `files:` 경로는 비교 전에 정규화해요 (`./` 제거 · 중복 `/` · 끝 `/`) — `src/a.ts` 와
# `./src/a.ts` 는 같은 파일이고, 표기 차이로 경합 검출을 빠져나갈 수 없어요.
#
# 세는 대상은 `- [ ]` 미완료 task 뿐이에요. 완료(`[x]`)는 이제 안 쓰고,
# 보류(`[~]`)는 이번 라운드에 안 돌아요.
#
# Output (--json):
#   {"status":"ok|warning","result":{"spec":"012-x","open_tasks":8,
#     "hot":[{"file":"packages/ui/src/index.ts","task_count":5,
#             "tasks":["T010","T011"],"parallel_claims":["T010","T011"]}],
#     "tasks_missing_files":["T007"]},...}
#
# 소유 레인은 **정하지 않아요.** 누가 어느 파일을 가질지는 판단이고, 이 스크립트는
# 사실만 줘요. 소유자 배정은 `/lane` skill 이 사람과 함께 해요.
#
# Exit: 0 ok (경합이 있어도 0 — 판단은 caller) / 1 error (tasks.md 없음 · --min 오류 · --spec 모호)

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; SPEC=""; MIN=2

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) : ;;                       # 읽기 전용
        --spec)    shift; SPEC="${1:-}" ;;
        --min)     shift; MIN="${1:-2}" ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    goax_help "${BASH_SOURCE[0]}"
    exit "$EXIT_OK"
fi

case "$MIN" in
    ''|*[!0-9]*) goax_error "--min 은 정수여야 해요: $MIN"; exit "$EXIT_ERROR" ;;
esac
[ "$MIN" -lt 2 ] && MIN=2

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"

if [ -z "$SPEC" ] && command -v jq >/dev/null 2>&1; then
    TF="$PROJECT_ROOT/.ax/current-task.json"
    if [ -f "$TF" ]; then
        SPEC=$(basename "$(jq -r '.spec_dir // empty' "$TF" 2>/dev/null || true)")
    fi
fi
# --spec 해석은 공통 규칙 (정확 일치 → prefix 1개 → 실패)
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
    if [ "$JSON_MODE" = true ]; then json_error "tasks.md 를 찾을 수 없어요: .ax/docs/spec/${SPEC:-<없음>}/tasks.md"; fi
    goax_error "no tasks.md for spec '${SPEC:-<none>}'"; exit "$EXIT_ERROR"
fi

# 파싱 — tasks-plan.sh 와 같은 한 줄 형식을 읽어요: "ID|state|P|files(,)"
PARSED=$(awk '
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
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^- \[[ x~X]\] / {
        line = $0
        st = "open"
        if (line ~ /^- \[[xX]\]/) st = "done"
        else if (line ~ /^- \[~\]/) st = "paused"
        par = (match(line, /\[P\]/)) ? "1" : "0"
        id = (match(line, /T[0-9][0-9][0-9]+/)) ? substr(line, RSTART, RLENGTH) : ""
        files = ""
        f = line
        if (match(f, /files:[ ]*/)) {
            f = substr(f, RSTART + RLENGTH)
            gsub(/[ ]*,[ ]*/, ",", f); gsub(/^[ ]+|[ ]+$/, "", f)
            files = normlist(f)
        }
        if (id != "") printf "%s|%s|%s|%s\n", id, st, par, files
    }
' "$TASKS")

OPEN_N=$(printf '%s\n' "$PARSED" | awk -F'|' '$2=="open" && $1!=""{n++} END{print n+0}')

# 파일 → 미완료 task 목록
HOT=$(printf '%s\n' "$PARSED" | awk -F'|' -v MIN="$MIN" '
    $2=="open" && $1!="" && $4!="" {
        n = split($4, fs, ",")
        for (i = 1; i <= n; i++) {
            f = fs[i]; gsub(/^[ \t]+|[ \t]+$/, "", f)
            if (f == "") continue
            if (f in cnt) ids[f] = ids[f] "," $1; else ids[f] = $1
            cnt[f]++
            if ($3 == "1") { if (f in pid) pid[f] = pid[f] "," $1; else pid[f] = $1 }
        }
    }
    END {
        for (f in cnt)
            if (cnt[f] >= MIN) printf "%s|%d|%s|%s\n", f, cnt[f], ids[f], (f in pid ? pid[f] : "")
    }
' | sort)

# `files:` 가 없는 미완료 task — 겹침 검사가 아예 안 닿는 사각지대
NOFILES=$(printf '%s\n' "$PARSED" | awk -F'|' '$2=="open" && $1!="" && $4==""{print $1}' | sort)

HOT_N=$(printf '%s\n' "$HOT" | awk 'NF{n++} END{print n+0}')
NOF_N=$(printf '%s\n' "$NOFILES" | awk 'NF{n++} END{print n+0}')

if [ "$JSON_MODE" = true ]; then
    HOT_J='[]'; NOF_J='[]'
    if command -v jq >/dev/null 2>&1; then
        if [ "$HOT_N" -gt 0 ]; then
            HOT_J=$(printf '%s\n' "$HOT" | jq -Rn '[inputs|select(length>0)|split("|")
                | {file:.[0], task_count:(.[1]|tonumber), tasks:(.[2]|split(",")),
                   parallel_claims:(if .[3]=="" then [] else (.[3]|split(",")) end)}]')
        fi
        if [ "$NOF_N" -gt 0 ]; then
            NOF_J=$(printf '%s\n' "$NOFILES" | jq -Rn '[inputs|select(length>0)]')
        fi
    fi
    RESULT=$(printf '{"spec":"%s","open_tasks":%s,"hot":%s,"tasks_missing_files":%s}' \
        "$SPEC" "$OPEN_N" "$HOT_J" "$NOF_J")
    if [ "$NOF_N" -gt 0 ]; then
        json_output "warning" "$RESULT" \
            "files: 없는 task 가 ${NOF_N}개 — 겹침 검사가 이 task 들엔 닿지 않아요. 파일 경로부터 적으세요"
    elif [ "$HOT_N" -gt 0 ]; then
        json_output "warning" "$RESULT" \
            "핫 파일 ${HOT_N}개 — 각각 소유 레인을 하나만 지정하거나, 공유 파일을 별도 task 로 떼세요"
    else
        json_output "ok" "$RESULT" "경합하는 파일이 없어요. 파일 소유권으로 레인을 가를 수 있어요"
    fi
else
    printf '미완료 task: %s개\n' "$OPEN_N"
    if [ "$HOT_N" -gt 0 ]; then
        printf '\n핫 파일 (%s개) — 소유 레인을 하나만 정하세요\n' "$HOT_N"
        printf '%s\n' "$HOT" | awk -F'|' 'NF{
            printf "  %-52s %s task (%s)", $1, $2, $3
            if ($4 != "") printf "  ⚠ [P] 주장: %s", $4
            printf "\n"
        }'
    else
        printf '\n핫 파일: 없음\n'
    fi
    if [ "$NOF_N" -gt 0 ]; then
        printf '\nfiles: 누락 (%s개) — 이 task 들은 겹침 검사가 안 돼요\n  %s\n' \
            "$NOF_N" "$(printf '%s\n' "$NOFILES" | tr '\n' ' ')"
    fi
fi
exit "$EXIT_OK"
