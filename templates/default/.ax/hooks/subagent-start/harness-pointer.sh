#!/usr/bin/env bash
# SubagentStart hook — 서브에이전트에 하네스 포인터를 줘요 (경로만, B-pointer)
#
# 왜 필요한가: 메인 세션은 CLAUDE.md(@AGENTS.md) · spirit · 활성 spec 을 훅과 skill 로 받지만,
# Explore·Plan·general-purpose 같은 내장 서브에이전트와 다른 플러그인의 에이전트는 **새 컨텍스트**로
# 떠요. Constitution 도 Spirit 도 현재 spec 도 모른 채 코드를 읽고 고쳐요 — 하네스의 도달 범위가
# 메인 세션에서 끝나던 거예요. 이 훅이 그 경계를 넘겨요.
#
# 본문이 아니라 **경로**만 줘요. 룰 전문을 밀어 넣으면 서브에이전트마다 수천 토큰이 들어가고, 읽을지는
# 그쪽이 판단해요 (lazy Read). goax 자기 에이전트(evaluator·architect·lane-*)는 "시작 전 필수" 로
# 이미 spirit 를 읽으니 건너뛰어요.
#
# 입력: stdin JSON {session_id, cwd, hook_event_name:"SubagentStart", agent_id, agent_type}
# 출력: stdout {hookSpecificOutput:{hookEventName:"SubagentStart", additionalContext:"..."}}
set -uo pipefail

[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"
AGENT=$(printf '%s' "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null || true)
case "$AGENT" in
    goax:*|evaluator|architect|lane-scout|lane-worker) exit 0 ;;   # 자기 에이전트 — 이미 spirit 를 선언해요
esac

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$PROJECT_ROOT" 2>/dev/null || exit 0

LINES=""
# Layer 1 — 시그널 라인을 실제로 가진 쪽 (CLAUDE.md 가 @AGENTS.md alias 인 경우 대비)
CONST=""
for c in AGENTS.md CLAUDE.md; do
    [ -f "$c" ] && grep -qE '^(🔴|🟡|🔵) \*\*`' "$c" 2>/dev/null && { CONST="$c"; break; }
done
[ -z "$CONST" ] && [ -f AGENTS.md ] && CONST="AGENTS.md"
[ -z "$CONST" ] && [ -f CLAUDE.md ] && CONST="CLAUDE.md"
[ -n "$CONST" ] && LINES="${LINES}  Layer 1 · Constitution  →  ${CONST}  (🔴 CRITICAL 은 hook 이 막아요 · 🟡 는 사람 승인)"$'\n'

# Spirit
[ -f .ax/spirit/values.md ] && LINES="${LINES}  Spirit · 가치·말투        →  .ax/spirit/values.md · .ax/spirit/tone.md"$'\n'

# Layer 3 — 진행 중인 spec
if [ -f .ax/current-task.json ]; then
    PHASE=$(jq -r '.phase // "idle"' .ax/current-task.json 2>/dev/null || echo idle)
    SPEC_DIR=$(jq -r '.spec_dir // empty' .ax/current-task.json 2>/dev/null || true)
    if [ "$PHASE" != "idle" ] && [ -n "$SPEC_DIR" ] && [ -f "$SPEC_DIR/spec.md" ]; then
        LINES="${LINES}  Layer 3 · 현재 spec (${PHASE})  →  ${SPEC_DIR}/spec.md"
        [ -f "$SPEC_DIR/tasks.md" ] && LINES="${LINES} · ${SPEC_DIR}/tasks.md"
        LINES="${LINES}"$'\n'
    fi
fi

# 인계 노트
[ -f .ax/docs/STATUS.md ] && LINES="${LINES}  인계 노트                →  .ax/docs/STATUS.md  (막힌 것 · 열린 질문 · 바뀐 이름)"$'\n'

[ -z "$LINES" ] && exit 0

CTX="[goax] 이 프로젝트에는 하네스가 있어요. 편집이나 판단 전에 아래를 Read 하세요 (경로만 드려요):
${LINES}규율: 커밋하지 않아요 · 브리프에 소유 파일 목록이 있으면 그 밖은 건드리지 않아요 · 정량 주장엔 센 명령과 출력을 붙여요."

jq -nc --arg c "$CTX" '{hookSpecificOutput:{hookEventName:"SubagentStart", additionalContext:$c}}'
exit 0
