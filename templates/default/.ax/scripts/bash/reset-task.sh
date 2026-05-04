#!/usr/bin/env bash
# .ax/scripts/bash/reset-task.sh — 작업 완료 후 current-task.json 리셋
#
# 호출 시점:
#   - /spec-implement 끝날 때 (작업 완료 신호)
#   - 사용자가 "끝났어요" 명시
#   - /task-done 같은 명령
#
# 효과:
#   - current-task.json → phase=idle, size/risk/domain/spec_* 모두 null
#   - .triage-nudged 마커 삭제 → 다음 사용자 메시지에 nudge 재발동 가능
#
# Usage:
#   bash reset-task.sh         # 일반 출력
#   bash reset-task.sh --json  # JSON 응답

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/tier-from-state.sh" --reset "$@"
