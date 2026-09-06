#!/usr/bin/env bash
# Stop hook — 활성 spec 이 미완료인 채 턴이 끝나려 하면 **한 번** 붙잡아요
#
# 왜 필요한가: 완료 게이트(G1~G6)는 파일 게이트라 커밋 시점(spec-completion-gate.sh)엔 걸리지만,
# 커밋 없이 턴이 끝나면 아무도 안 봐요. 실사용 리포에서 spec 21개 중 14개가 미완료 task 를 남긴 채
# 끝나 있었고, 그 세션들은 커밋도 인계 노트도 없이 그냥 멈췄어요. 턴 종료는 스킬을 우회해도
# 반드시 지나는 지점이에요.
#
# 무엇을 하나 — 차단이 아니라 **한 턴 더** 주는 거예요. 세 가지 중 하나를 하고 끝내라고 해요:
#   (1) 남은 task 를 마저   (2) 의도적 보류면 `- [~] … 보류: <사유>`   (3) 여기서 멈추는 거면 인계 노트
# (3) 이 적혀 있으면(STATUS.md "지금 상태" 에 spec 이름) 다시 안 잡아요 — 멈추는 게 의도인 거니까요.
#
# 안전장치 셋:
#   - `stop_hook_active=true` (이미 한 번 붙잡은 뒤의 재시도) → 즉시 통과. 무한 루프는 공식 계약이 막아요
#   - 세션당 최대 GOAX_STOP_GATE_MAX 회 (기본 8) — `.ax/.session/<session_id>/stop-blocks` 카운터
#   - `sensors.mode=off` → 침묵. phase 가 implementing·review 가 아니면(계획 단계) 침묵
#
# 입력: stdin JSON {session_id, cwd, hook_event_name:"Stop", stop_hook_active, ...}
# 출력: 붙잡을 때 stdout {"decision":"block","reason":"..."} + exit 0 — reason 이 모델에게 가요.
#      통과는 출력 없이 exit 0.
set -uo pipefail

[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null)
SID=$(printf '%s' "$SID" | tr -c 'A-Za-z0-9_-' '_')

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
GATE="$PROJECT_ROOT/.ax/scripts/bash/tasks-gate.sh"
[ -f "$COMMON" ] && [ -f "$GATE" ] || exit 0
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"
MODE=$(goax_mode 2>/dev/null || echo warning)
[ "$MODE" = "off" ] && exit 0

TASK_FILE="$PROJECT_ROOT/.ax/current-task.json"
[ -f "$TASK_FILE" ] || exit 0
PHASE=$(jq -r '.phase // "idle"' "$TASK_FILE" 2>/dev/null || echo idle)
case "$PHASE" in implementing|review) ;; *) exit 0 ;; esac
SPEC_DIR=$(jq -r '.spec_dir // empty' "$TASK_FILE" 2>/dev/null || true)
[ -n "$SPEC_DIR" ] || exit 0
SPEC=$(basename "$SPEC_DIR")

# 인계 노트에 이미 적혀 있으면 멈추는 게 의도예요 — 다시 안 잡아요
NOTE="$PROJECT_ROOT/.ax/docs/STATUS.md"
if [ -f "$NOTE" ] && awk '/^## /{inb=($0 ~ /^## 지금 상태/)} inb' "$NOTE" | grep -qF "$SPEC"; then
    exit 0
fi

# 세션당 상한 — 같은 세션에서 계속 잡으면 게이트가 아니라 성가심이에요
CAP="${GOAX_STOP_GATE_MAX:-8}"
MARK_DIR="$PROJECT_ROOT/.ax/.session/$SID"
MARK="$MARK_DIR/stop-blocks"
COUNT=0; [ -f "$MARK" ] && COUNT=$(tr -dc '0-9' < "$MARK" 2>/dev/null); COUNT=${COUNT:-0}
[ "$COUNT" -ge "$CAP" ] && exit 0

OUT=$(bash "$GATE" --spec "$SPEC" --json 2>/dev/null || true)
[ -n "$OUT" ] || exit 0
printf '%s' "$OUT" | jq -e '.result' >/dev/null 2>&1 || exit 0
VIOL=$(printf '%s' "$OUT" | jq -r '.result.violations // 0')
[ "${VIOL:-0}" -eq 0 ] && exit 0

OPEN=$(printf '%s' "$OUT" | jq -r '.result.open // 0')
DONE=$(printf '%s' "$OUT" | jq -r '.result.done // 0')
TOTAL=$(printf '%s' "$OUT" | jq -r '.result.total // 0')
UNCOV=$(printf '%s' "$OUT" | jq -r '(.result.ac_uncovered // []) | length')
UNREP=$(printf '%s' "$OUT" | jq -r '(.result.dispatched_unreported // []) | length')
REQ=$(printf '%s' "$OUT" | jq -r '.result.review_required // false')
VERDICT=$(printf '%s' "$OUT" | jq -r '.result.review_verdict // ""')

WHAT="task ${DONE}/${TOTAL} 완료"
[ "${OPEN:-0}" -gt 0 ] && WHAT="$WHAT · 미완료 ${OPEN}"
[ "${UNCOV:-0}" -gt 0 ] && WHAT="$WHAT · 대응 task 없는 AC ${UNCOV}"
[ "${UNREP:-0}" -gt 0 ] && WHAT="$WHAT · 보고 안 받은 디스패치 ${UNREP}"
if [ "$REQ" = "true" ] && [ -z "$VERDICT" ]; then WHAT="$WHAT · evaluator 필수(review.md 없음)"
elif [ -n "$VERDICT" ] && [ "$VERDICT" != "진행" ]; then WHAT="$WHAT · evaluator verdict \"${VERDICT}\""; fi

mkdir -p "$MARK_DIR" 2>/dev/null && printf '%s' "$((COUNT + 1))" > "$MARK" 2>/dev/null || true

REASON="[goax] spec ${SPEC} 가 ${PHASE} 인데 완료 게이트 미통과 — ${WHAT}.
턴을 끝내기 전에 셋 중 하나를 하세요:
 (1) 남은 task 를 마저 진행 (spec-implement)
 (2) 의도적 보류면 tasks.md 에 \`- [~] T0NN … 보류: <사유>\` 로 표기
 (3) 여기서 멈추는 거면 인계 노트에 적고 끝내세요 — 다음 세션이 대화가 아니라 파일에서 읽어요:
     bash .ax/scripts/bash/status-note.sh --set now \"spec ${SPEC} ${PHASE} 에서 멈춤 — <어디까지 · 왜>\"
     bash .ax/scripts/bash/status-note.sh --add next \"<다음 세션이 처음 할 일>\"
인계 노트의 '지금 상태' 에 ${SPEC} 가 적혀 있으면 이 게이트는 다시 잡지 않아요. (세션당 최대 ${CAP}회 · $((COUNT + 1))/${CAP} · sensors.mode=off 면 침묵)"

jq -nc --arg r "$REASON" '{decision:"block", reason:$r}'
exit 0
