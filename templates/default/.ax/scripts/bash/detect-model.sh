#!/usr/bin/env bash
# .ax/scripts/bash/detect-model.sh — 지금 돌고 있는 모델 식별
#
# Usage:
#   bash detect-model.sh [--model <override>] [--json] [--help]
#
# 왜 스크립트인가 — LLM 자가보고에 기대면 틀려도 알 수가 없어요. 이 저장소의
# 원칙("재현 가능한 건 .ax/scripts/bash/ 로")대로 결정론으로 뽑아요.
#
# 해석 순서:
#   1. --model <값>           명시 override
#   2. $GOAX_MODEL            환경 변수 (CI·다른 CLI 어댑터용)
#   3. transcript 스캔        ~/.claude/projects/<cwd-slug>/*.jsonl 중 최신 파일의
#                             마지막 assistant 메시지 `.message.model`
#   4. unknown
#
# 3번이 핵심이에요. Claude Code 는 모델을 환경 변수로 노출하지 않지만
# transcript 에는 매 assistant 메시지마다 기록해요. jq 없으면 grep 으로 degrade.
#
# Output (--json):
#   {"status":"ok","result":{"model":"claude-opus-5","source":"transcript",
#                            "session_ref":"9a1403ec-....jsonl"},...}
#
# Exit: 0 항상 (식별 실패도 unknown 으로 정상 종료 — mistake 캡처를 막으면 안 돼요)

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; OVERRIDE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) : ;;                       # 읽기 전용이라 no-op (인터페이스 통일)
        --model)   shift; OVERRIDE="${1:-}" ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "$EXIT_OK"
fi

MODEL=""; SOURCE=""; SESSION_REF=""

if [ -n "$OVERRIDE" ]; then
    MODEL="$OVERRIDE"; SOURCE="override"
elif [ -n "${GOAX_MODEL:-}" ]; then
    MODEL="$GOAX_MODEL"; SOURCE="env"
else
    # cwd → ~/.claude/projects/<슬래시를 -로 치환한 절대경로>/
    PROJ_DIR=""
    for base in "${CLAUDE_PROJECT_DIR:-}" "$(pwd)"; do
        [ -z "$base" ] && continue
        slug=$(printf '%s' "$base" | sed 's#/#-#g')
        cand="$HOME/.claude/projects/$slug"
        [ -d "$cand" ] && { PROJ_DIR="$cand"; break; }
    done
    if [ -n "$PROJ_DIR" ]; then
        NEWEST=$(ls -t "$PROJ_DIR"/*.jsonl 2>/dev/null | head -1 || true)
        if [ -n "$NEWEST" ]; then
            SESSION_REF=$(basename "$NEWEST")      # 경로가 아니라 파일명만 — mistake 는 커밋돼요
            if command -v jq >/dev/null 2>&1; then
                MODEL=$(grep '"type":"assistant"' "$NEWEST" 2>/dev/null | tail -1 \
                        | jq -r '.message.model // empty' 2>/dev/null || true)
            fi
            # jq 없거나 스키마가 달라진 경우
            [ -z "$MODEL" ] && MODEL=$(grep -o '"model":"[^"]*"' "$NEWEST" 2>/dev/null \
                                        | tail -1 | sed 's/.*:"//; s/"//' || true)
            [ -n "$MODEL" ] && SOURCE="transcript"
        fi
    fi
fi

if [ -z "$MODEL" ]; then MODEL="unknown"; SOURCE="none"; fi

if [ "$JSON_MODE" = true ]; then
    RESULT=$(printf '{"model":"%s","source":"%s","session_ref":"%s"}' \
                    "$MODEL" "$SOURCE" "$SESSION_REF")
    json_output "ok" "$RESULT" "mistake frontmatter 의 model / session_ref 로 기록하세요"
else
    printf '%s\n' "$MODEL"
fi
exit "$EXIT_OK"
