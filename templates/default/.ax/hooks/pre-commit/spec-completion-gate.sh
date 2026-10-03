#!/usr/bin/env bash
# pre-commit hook — 진행 중인 spec 의 완료 조건 확인
#
# 왜 훅인가: 완료 판정이 `spec-implement/SKILL.md` 안에만 있었어요. 그러면 그
# skill 을 안 돌리고 끝내는 순간 아무도 확인하지 않아요. 실사용 리포에서 spec
# 21개 중 14개가 미완료 task 를 남긴 채 끝나 있었는데, 그 사실을 알려준 곳이
# 없었어요. 커밋 시점은 스킬을 우회해도 반드시 지나는 지점이에요.
#
# 성격: **차단이 아니라 가시화**가 기본이에요 (sensors.mode=warning).
#   mode=fail 로 올리면 차단해요. 다만 그 전에 `- [~]` 보류 표기를 팀이
#   쓰고 있어야 해요 — 안 그러면 "의도적 보류" 를 표현할 방법이 없어서
#   게이트가 그냥 성가신 게 되고, 결국 우회 대상이 돼요.
#
# 진행 중인 spec 이 없으면(phase=idle) 조용히 통과. 커밋마다 떠들지 않아요.
# 스테이지 파일이 그 spec 에 안 걸리면(spec 디렉토리 밖 · tasks.md `files:` 와 무관) 한 줄만 내고 통과해요 —
# mode=fail 에서도요. 막는 건 그 spec 을 건드리는 커밋이에요.
set -uo pipefail

[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
GATE="$PROJECT_ROOT/.ax/scripts/bash/tasks-gate.sh"
[ -f "$COMMON" ] && [ -f "$GATE" ] || exit 0
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"

MODE=$(goax_mode 2>/dev/null || echo warning)
[ "$MODE" = "off" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

# 진행 중인 작업들의 spec — 지금 작업(current-task.json)과 병렬 작업(.ax/tasks/*.json) 중 phase ≠ idle 이고
# spec_dir 이 있는 것. 같은 spec 은 한 번만 봐요. 없으면 검사할 대상이 없어요.
TASK_FILE="$PROJECT_ROOT/.ax/current-task.json"
SPECS=$(for f in "$TASK_FILE" "$PROJECT_ROOT"/.ax/tasks/*.json; do
            [ -f "$f" ] || continue
            jq -r 'select((.phase // "idle") != "idle") | .spec_dir // empty' "$f" 2>/dev/null
        done | while IFS= read -r d; do [ -n "$d" ] && basename "$d"; done | awk '!seen[$0]++')
[ -n "$SPECS" ] || exit 0

check_spec() {   # $1 = spec 이름 — 막아야 하면 2
    OUT=$(bash "$GATE" --spec "$1" --json 2>/dev/null || true)
    [ -z "$OUT" ] && return 0
    printf '%s' "$OUT" | jq -e '.result' >/dev/null 2>&1 || return 0

    # skipped/error 는 result 가 항상 {} — 검사 못 했다는 뜻이지 위반이 아니에요.
    # tasks-gate.sh 가 이미 자기 next_step 으로 사유를 말하니 여기선 조용히 통과.
    STATUS=$(printf '%s' "$OUT" | jq -r '.status // ""')
    case "$STATUS" in
        ok|warning) ;;
        *) return 0 ;;
    esac

    SPEC=$(printf '%s' "$OUT" | jq -r '.result.spec // ""')
    OPEN=$(printf '%s' "$OUT" | jq -r '.result.open // 0')
    PAUSED=$(printf '%s' "$OUT" | jq -r '.result.paused // 0')
    DONE=$(printf '%s' "$OUT" | jq -r '.result.done // 0')
    TOTAL=$(printf '%s' "$OUT" | jq -r '.result.total // 0')
    UNCOV=$(printf '%s' "$OUT" | jq -r '(.result.ac_uncovered // []) | join(", ")')
    DROP=$(printf '%s' "$OUT" | jq -r '.result.task_count_drop // 0')
    UNREP=$(printf '%s' "$OUT" | jq -r '(.result.dispatched_unreported // []) | join(", ")')
    NOREP=$(printf '%s' "$OUT" | jq -r '(.result.done_without_report // []) | join(", ")')
    REQ=$(printf '%s' "$OUT" | jq -r '.result.review_required // false')
    VERDICT=$(printf '%s' "$OUT" | jq -r '.result.review_verdict // ""')
    VIOL=$(printf '%s' "$OUT" | jq -r '.result.violations // 0')

    [ "${VIOL:-0}" -eq 0 ] && return 0

    # 이번 커밋이 그 spec 에 걸릴 때만 자세히 말해요. 무관한 커밋(문서 한 줄)마다 같은 경고가 나오면
    # 아무도 읽지 않게 되고, 정작 그 spec 을 커밋할 때의 경고도 묻혀요 (실측: 커밋마다 반복).
    # 걸린다 = 스테이지 파일이 spec 디렉토리 안이거나, tasks.md 의 `files:` 경로(파일 또는 디렉토리)와 겹쳐요.
    SPEC_DIR_REL=".ax/docs/spec/$SPEC"
    STAGED=$(git -C "$PROJECT_ROOT" -c core.quotePath=false diff --cached --name-only 2>/dev/null || true)
    if [ -n "$SPEC" ] && [ -n "$STAGED" ]; then
        TASK_PATHS=""
        if [ -f "$PROJECT_ROOT/$SPEC_DIR_REL/tasks.md" ]; then
            # 펜스 안은 형식 설명이에요 — 템플릿 예시 `path/a.kt` 를 실제 경로로 세지 않아요
            TASK_PATHS=$(awk '
                /^[[:space:]]*```/ { fence = !fence; next }
                fence { next }
                /^- \[[ x~X]\] / && match($0, /files:[ ]*/) {
                    n = split(substr($0, RSTART + RLENGTH), a, ",")
                    for (i = 1; i <= n; i++) {
                        p = a[i]; gsub(/^[ `]+|[ `]+$/, "", p); sub(/^\.\//, "", p); gsub(/\/+/, "/", p); sub(/\/$/, "", p)
                        if (p != "") print p
                    }
                }' "$PROJECT_ROOT/$SPEC_DIR_REL/tasks.md")
        fi
        # 경로 목록은 ENVIRON 으로 넘겨요 — 줄바꿈이 든 값을 -v 로 주면 mawk 가 거부해요
        RELATED=$(printf '%s\n' "$STAGED" | GOAX_TP="$TASK_PATHS" awk -v sd="$SPEC_DIR_REL" '
            BEGIN { n = split(ENVIRON["GOAX_TP"], P, "\n") }
            { s = $0
              if (index(s, sd "/") == 1) { print s; exit }
              for (i = 1; i <= n; i++) if (P[i] != "" && (s == P[i] || index(s, P[i] "/") == 1)) { print s; exit } }')
        if [ -z "$RELATED" ]; then
            printf '\033[33m[goax gate]\033[0m spec %s 미완료 %s — 이번 커밋과 무관해 건너뛰어요\n' "$SPEC" "$OPEN" >&2
            return 0
        fi
    fi

    printf '\033[33m[goax gate]\033[0m spec %s — %s/%s 완료' "$SPEC" "$DONE" "$TOTAL" >&2
    [ "${PAUSED:-0}" -gt 0 ] && printf ' (보류 %s)' "$PAUSED" >&2
    printf '\n' >&2
    [ "${OPEN:-0}" -gt 0 ] && printf '  · 미완료 task %s개 — 끝내거나 `- [~] … 보류: <사유>` 로 표기하세요\n' "$OPEN" >&2
    [ -n "$UNCOV" ] && printf '  · 대응 task 가 없는 수용 기준: %s\n' "$UNCOV" >&2
    if [ "${DROP:-0}" -gt 0 ]; then
        printf '\033[31m  · task %s개가 사라졌어요\033[0m — 미완료를 지워서 통과시키는 건 안 돼요.\n' "$DROP" >&2
        printf '    의도적으로 범위를 줄인 거면 spec.md 의 수용 기준도 같이 줄이세요.\n' >&2
    fi
    [ -n "$UNREP" ] && printf '  · 보고 안 받은 디스패치: %s — 산출물을 받고 lanes-dispatch.sh --report 로 기록하세요\n' "$UNREP" >&2
    [ -n "$NOREP" ] && printf '\033[31m  · 보고 없이 완료 표시: %s\033[0m — 레인이 자기 체크박스를 켰어요. 코디네이터가 검증 뒤에 켜야 해요\n' "$NOREP" >&2
    if [ "$REQ" = "true" ] && [ -z "$VERDICT" ]; then
        printf '  · evaluator 리뷰 필수 (size×risk) — review.md 가 없어요. 새 컨텍스트로 evaluator 를 띄우세요\n' >&2
    elif [ -n "$VERDICT" ] && [ "$VERDICT" != "진행" ]; then
        printf '  · evaluator verdict "%s" — 지적을 task 로 옮기거나 재논의한 뒤 커밋하세요\n' "$VERDICT" >&2
    fi

    if [ "$MODE" = "fail" ]; then
        printf '  차단됨 (sensors.mode=fail). 우회가 필요하면 사용자가 직접 커밋해요 (`! git commit --no-verify …`) — 에이전트의 --no-verify 는 block-hook-bypass 가 막아요.\n' >&2
        return 2
    fi
    return 0
}

RC=0
while IFS= read -r sp; do
    [ -n "$sp" ] || continue
    check_spec "$sp" || RC=$?
done <<< "$SPECS"
exit "$RC"
