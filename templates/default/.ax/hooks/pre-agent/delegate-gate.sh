#!/usr/bin/env bash
# pre-agent hook — 구현 단계에서 goax 밖 실행 에이전트를 띄우려 하면 한 번 막고 이유를 물어요.
#
# 대상: phase 가 implementing 또는 review 일 때의 Agent(옛 이름 Task) 호출이에요. subagent_type 의 `:` 뒤 이름이
#   실행 에이전트 목록에 있으면 걸려요. 목록 기본값은 executor, deep-executor, general-purpose 예요 (이름을 비우면
#   general-purpose). 프로젝트는 sensors.foreign_executors 로 바꿔요.
# 이유: lane-worker 에만 소유 파일 제한, 커밋 금지, 명령 인용 보고가 들어 있어요.
# 동작: 세션에서 처음 보는 이름이면 exit 2 로 막아요. 같은 이름을 다시 부르면 통과해요. 세션 id 가 없으면 경고만 해요.
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
    printf '\033[33m[goax hook]\033[0m ⚠ 구현 단계에서 %s 를 띄워요. 세션 id 가 없어 막지 않아요. 코드를 고치는 task 는 lane-worker 로 맡겨요.\n' "$AGENT" >&2
    exit 0
fi
goax_session_marked "$SID" delegate "$BASE" && exit 0
goax_session_mark "$SID" delegate "$BASE"

{
    printf '\033[33m[goax hook]\033[0m ✋ 구현 단계(%s)에서 %s 를 띄우려고 해요.\n' "$PHASE" "$AGENT"
    printf '  코드를 고치는 task 면, 이 세션은 goax:lane-worker 를 띄워요 (vendor 설치면 lane-worker). 브리프는 spec-implement §3.3 을 따라요.\n'
    printf '  모델은 bash .ax/scripts/bash/agent-model.sh lane-worker --json 의 result.models.lane-worker 값을 넘겨요.\n'
    printf '  읽기만 하는 조사면, 이 세션은 lane-scout 를 띄워요.\n'
    printf '  %s 를 써야 하면, 이유를 한 줄 적고 같은 호출을 다시 해요. 두 번째 호출은 통과해요.\n' "$AGENT"
    printf '  이유: 소유 파일 제한과 커밋 금지가 lane-worker 에만 있어요.\n'
    printf '  (끄기: .ax/config.yml sensors.disabled_hooks 에 delegate-gate · 대상 목록: sensors.foreign_executors)\n'
} >&2
exit 2
