#!/usr/bin/env bash
# PreCompact hook — 압축 직전에 "어디까지 했나" 를 사실로 적어 둬요
#
# 무엇을 적을지는 `.ax/scripts/bash/session-brief.sh --snapshot` 이 정해요 (결정론 경계 — 이 훅은 부르기만).
# 브랜치·HEAD · 커밋 안 된 변경 파일 · 진행 중 spec 의 tasks 진행률. LLM 요약이 아니에요 — 요약은 Claude Code 가 하고,
# 요약이 흘리기 쉬운 "무슨 파일을 고치던 중이었나" 를 파일이 붙잡아요. compaction 직후 SessionStart(source=compact)
# 훅이 이 스냅샷을 브리핑 맨 앞에 붙여요.
#
# 입력: stdin JSON {session_id, trigger, …}. 출력 없음 · 늘 exit 0 (압축을 막지 않아요).
# 끄기: .ax/config.yml sensors.disabled_hooks 에 snapshot, 또는 sensors.hook_profile: minimal
set -uo pipefail

[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat 2>/dev/null || true)"
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -n "$SID" ] || exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
BRIEF="$PROJECT_ROOT/.ax/scripts/bash/session-brief.sh"
[ -f "$COMMON" ] && [ -f "$BRIEF" ] || exit 0
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"
goax_hook_enabled snapshot standard || exit 0

GOAX_PROJECT_DIR="$PROJECT_ROOT" bash "$BRIEF" --snapshot --session "$SID" --json >/dev/null 2>&1 || true
exit 0
