#!/usr/bin/env bash
# .ax/scripts/bash/reset-task.sh — 작업 완료 후 current-task.json 리셋
#
# 호출 시점:
#   - /spec-implement 끝날 때 (작업 완료 신호)
#   - 사용자가 "끝났어요" 명시
#   - /task-done 같은 명령
#
# 효과:
#   - current-task.json → phase=idle, size/risk/domain/spec_* 모두 null, intent_notes={}
#   - handoff(인계 노트)는 남겨요 — next·open·renamed 는 task 를 넘어 살아요
#   - .triage-nudged 마커 삭제 → 다음 사용자 메시지에 nudge 재발동 가능
#
# Usage:
#   bash reset-task.sh         # 일반 출력
#   bash reset-task.sh --json  # JSON 응답

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# --help 는 자기 헤더 — exec 로 넘기면 tier-from-state.sh 의 헤더가 찍혀요
case "${1:-}" in --help|-h)
    # shellcheck source=common.sh
    source "$SCRIPT_DIR/common.sh"; goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK" ;;
esac
exec bash "$SCRIPT_DIR/tier-from-state.sh" --reset "$@"
