#!/usr/bin/env bash
# PreCompact hook — 압축 직전 "어디까지 했나" 를 사실로 적어 둬요 (session-brief.sh --snapshot 이 정해요)
#
# 브랜치·HEAD · 커밋 안 된 파일 · 진행 중 spec 의 tasks 진행률 → `.ax/.session/<sid>/precompact.txt`.
# LLM 요약이 아니에요. compaction 직후 SessionStart(source=compact)가 한 번 보여줘요. 늘 exit 0 — 압축을 막지 않아요.
# 끄기: sensors.disabled_hooks 에 snapshot, 또는 sensors.hook_profile: minimal
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
