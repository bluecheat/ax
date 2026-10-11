#!/usr/bin/env bash
# pre-agent hook — 구현 중에 goax 밖 실행 에이전트로 코드를 맡기려 하면 한 번 물어요 (fact-forcing)
#
# 대상: current-task.json 의 phase 가 implementing·review 일 때의 Agent(옛 이름 Task) 호출 가운데,
#   subagent_type 이 실행 에이전트 목록에 있는 것 — 기본 executor · deep-executor · general-purpose
#   (비우면 general-purpose 로 떠요), 프로젝트는 sensors.foreign_executors 로 바꿔요. `oh-my-claudecode:executor`
#   처럼 접두사가 붙어도 `:` 뒤 이름으로 봐요. goax 에이전트(lane-worker 등)와 읽기 전용 조사 에이전트는 안 막아요.
# 이유: 구현 위임은 lane-worker 예요 — 소유 파일 밖 편집 금지 · 커밋 금지 · 명령 인용 보고가 에이전트에 들어 있어요.
#   다른 플러그인 훅의 "executor 로 위임" 권고를 따라가면 그 규율이 통째로 빠져요.
# 동작: 세션에서 처음 보는 에이전트 이름이면 exit 2 로 막고 이유를 적게 해요. 같은 이름으로 다시 부르면 통과.
# 끄기: sensors.disabled_hooks 에 delegate-gate.
set -uo pipefail

[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
AGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)
AGENT="${AGENT:-general-purpose}"

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd || pwd)}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
[ -f "$COMMON" ] || exit 0
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"

goax_hook_enabled delegate-gate standard || exit 0
[ "$(goax_mode)" = "off" ] && exit 0

PHASE=$(jq -r '.phase // empty' "$PROJECT_ROOT/.ax/current-task.json" 2>/dev/null || true)
case "$PHASE" in implementing|review) ;; *) exit 0 ;; esac

BASE="${AGENT##*:}"
LIST=$(goax_yaml_list "$PROJECT_ROOT/.ax/config.yml" foreign_executors 2>/dev/null || true)
[ -n "$LIST" ] || LIST=$(printf 'executor\ndeep-executor\ngeneral-purpose\n')
printf '%s\n' "$LIST" | sed 's/.*://' | grep -qxF "$BASE" || exit 0

if [ -z "$SID" ]; then
    printf '\033[33m[goax hook]\033[0m ⚠ 구현 중 %s 위임 (세션 추적 불가 — 경고만): 코드 편집은 lane-worker 로 맡겨요\n' "$AGENT" >&2
    exit 0
fi
goax_session_marked "$SID" delegate "$BASE" && exit 0
goax_session_mark "$SID" delegate "$BASE"

{
    printf '\033[33m[goax hook]\033[0m ✋ 지금은 구현 단계(%s)예요 — %s 에게 맡기기 전에 확인해요.\n' "$PHASE" "$AGENT"
    printf '  코드를 고치는 일이면 goax:lane-worker 로 맡겨요 (vendor 설치면 lane-worker). 브리프는 spec-implement §3.3 그대로예요.\n'
    printf '  모델은 bash .ax/scripts/bash/agent-model.sh lane-worker --json 의 result.models.lane-worker 를 넘겨요.\n'
    printf '  읽기만 하는 조사면 lane-scout 도 있어요.\n'
    printf '  그래도 %s 여야 하면 이유 한 줄(예: 사용자가 지정함 · 편집 없는 조사)을 적고 같은 호출을 다시 하세요 — 통과해요.\n' "$AGENT"
    printf '  (끄기: .ax/config.yml sensors.disabled_hooks 에 delegate-gate · 대상 바꾸기: sensors.foreign_executors)\n'
} >&2
exit 2
