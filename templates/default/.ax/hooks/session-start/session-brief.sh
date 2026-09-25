#!/usr/bin/env bash
# SessionStart hook — 세션 첫머리에 인계 노트 · 버전 지연 · 밀린 audit · 실수 재발을 짧게 알려요
#
# 무엇을 말할지는 session-brief.sh --json 이 정해요 — 이 훅은 전달만 해요 (알릴 게 없으면 출력 없음, 길이 상한 GOAX_SESSION_BRIEF_MAX 자).
# source=compact 면: 세션의 룰 Read 기록·주입 기록을 지우고(다시 읽고·다시 주게) PreCompact 스냅샷을 붙여요.
# 출력: {hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:"…"}}
# 끄기: sensors.disabled_hooks 에 session-brief (compact 초기화는 꺼도 돌아요 — 게이트 정확성 문제라서요)
set -uo pipefail

[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat 2>/dev/null || true)"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
BRIEF="$PROJECT_ROOT/.ax/scripts/bash/session-brief.sh"
[ -f "$COMMON" ] && [ -f "$BRIEF" ] || exit 0
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"

# compaction 직후 — 룰 본문과 주입된 포인터가 컨텍스트에서 빠졌어요. 세션 기록을 그대로 두면 rule-read-gate 는
# "읽었다" 로 통과시키고 주입 훅은 "이미 줬다" 로 다시 주지 않아요. 그래서 둘 다 지워서 다시 읽고·다시 주게 해요.
# 브리핑을 꺼도(session-brief 비활성) 이 초기화는 돌아요 — 게이트의 정확성 문제라서요.
IFS="$(printf '\t')" read -r SID SRC < <(printf '%s' "$INPUT" \
    | jq -r '[(.session_id // ""), (.source // "")] | @tsv' 2>/dev/null) || true
if [ "$SRC" = "compact" ] && [ -n "$SID" ]; then
    SDIR=$(goax_session_dir "$SID")
    rm -f "$SDIR/rules-read.log" 2>/dev/null || true
    rm -rf "$SDIR/injected" 2>/dev/null || true
fi

goax_hook_enabled session-brief standard || exit 0

MODE_ARGS=()
[ "$SRC" = "compact" ] && [ -n "$SID" ] && MODE_ARGS=(--after-compact --session "$SID")   # 압축 직전 스냅샷(pre-compact/snapshot.sh)을 맨 앞에
LINES=$(GOAX_PROJECT_DIR="$PROJECT_ROOT" bash "$BRIEF" --json ${MODE_ARGS[@]+"${MODE_ARGS[@]}"} 2>/dev/null \
        | jq -r '.result.lines // [] | .[]' 2>/dev/null || true)
[ -z "$LINES" ] && exit 0

CTX="[goax] 세션 브리핑
$(printf '%s\n' "$LINES" | sed 's/^/- /')"
jq -nc --arg c "$CTX" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
exit 0
