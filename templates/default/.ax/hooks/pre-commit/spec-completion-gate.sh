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

# 활성 spec 이 있을 때만 — 없으면 검사할 대상이 없어요
TASK_FILE="$PROJECT_ROOT/.ax/current-task.json"
[ -f "$TASK_FILE" ] || exit 0
PHASE=$(jq -r '.phase // "idle"' "$TASK_FILE" 2>/dev/null || echo idle)
[ "$PHASE" = "idle" ] && exit 0

OUT=$(bash "$GATE" --json 2>/dev/null || true)
[ -z "$OUT" ] && exit 0
printf '%s' "$OUT" | jq -e '.result' >/dev/null 2>&1 || exit 0

SPEC=$(printf '%s' "$OUT" | jq -r '.result.spec // ""')
OPEN=$(printf '%s' "$OUT" | jq -r '.result.open // 0')
PAUSED=$(printf '%s' "$OUT" | jq -r '.result.paused // 0')
DONE=$(printf '%s' "$OUT" | jq -r '.result.done // 0')
TOTAL=$(printf '%s' "$OUT" | jq -r '.result.total // 0')
UNCOV=$(printf '%s' "$OUT" | jq -r '.result.ac_uncovered | join(", ")')
DROP=$(printf '%s' "$OUT" | jq -r '.result.task_count_drop // 0')
VIOL=$(printf '%s' "$OUT" | jq -r '.result.violations // 0')

[ "${VIOL:-0}" -eq 0 ] && exit 0

printf '\033[33m[goax gate]\033[0m spec %s — %s/%s 완료' "$SPEC" "$DONE" "$TOTAL" >&2
[ "${PAUSED:-0}" -gt 0 ] && printf ' (보류 %s)' "$PAUSED" >&2
printf '\n' >&2
[ "${OPEN:-0}" -gt 0 ] && printf '  · 미완료 task %s개 — 끝내거나 `- [~] … 보류: <사유>` 로 표기하세요\n' "$OPEN" >&2
[ -n "$UNCOV" ] && printf '  · 대응 task 가 없는 수용 기준: %s\n' "$UNCOV" >&2
if [ "${DROP:-0}" -gt 0 ]; then
    printf '\033[31m  · task %s개가 사라졌어요\033[0m — 미완료를 지워서 통과시키는 건 안 돼요.\n' "$DROP" >&2
    printf '    의도적으로 범위를 줄인 거면 spec.md 의 수용 기준도 같이 줄이세요.\n' >&2
fi

if [ "$MODE" = "fail" ]; then
    printf '  차단됨 (sensors.mode=fail). 우회가 필요하면 사용자 승인 후 --no-verify.\n' >&2
    exit 2
fi
exit 0
