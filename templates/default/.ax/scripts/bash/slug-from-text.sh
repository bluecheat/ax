#!/usr/bin/env bash
# .ax/scripts/bash/slug-from-text.sh — 영문 텍스트를 kebab-case slug로
#
# Usage:
#   bash slug-from-text.sh [--json] "free-form text"
#
# 한국어/일본어/중국어 등 비-ASCII 텍스트는 *그대로 두지 않고* LLM이
# 의역해서 영문 slug를 만든 후 이 스크립트로 검증·정규화하는 게 정확해요.
# 이 스크립트는 영문 후처리 검증/정규화 도구.
#
# 동작:
#   - lower-case
#   - 비-alphanumeric → -
#   - 연속 - 압축
#   - 양 끝 - 제거
#   - 50자 제한
#
# Output (--json):
#   {"status":"ok","result":{"slug":"payment-refund-policy","valid":true}}

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
SHOW_HELP=false
TEXT=""

# JSON_MODE 플래그를 먼저 스캔 — error 출력을 일관되게 JSON 모드로 보내기 위해
# (parse loop 진행 중 unknown option 에러 시점에 JSON_MODE 가 set 돼있어야 함)
for arg in "$@"; do
    [ "$arg" = "--json" ] && JSON_MODE=true && break
done

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --help|-h) SHOW_HELP=true ;;
        -*) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
        *)  TEXT="$1" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# //'
    exit "$EXIT_OK"
fi

[ -z "$TEXT" ] && { goax_error "text argument required"; exit "$EXIT_ERROR"; }

# 정규화
SLUG=$(printf '%s' "$TEXT" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g' \
        | sed -E 's/^-+|-+$//g' \
        | cut -c1-50)

# 검증
VALID=true
if [[ ! "$SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || [ -z "$SLUG" ]; then
    VALID=false
fi

if [ "$JSON_MODE" = true ]; then
    # jq로 안전 escape — backslash, quote, newline, CR, tab 모두 처리
    if command -v jq >/dev/null 2>&1; then
        RESULT=$(jq -nc --arg slug "$SLUG" --argjson valid "$VALID" --arg original "$TEXT" \
                       '{slug:$slug, valid:$valid, original:$original}')
    else
        # jq 부재 fallback
        ORIGINAL_ESCAPED=$(printf '%s' "$TEXT" \
            | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
            | awk 'BEGIN{ORS=""} {gsub(/\r/,"\\r"); gsub(/\t/,"\\t"); if(NR>1)printf "\\n"; print}')
        RESULT=$(printf '{"slug":"%s","valid":%s,"original":"%s"}' "$SLUG" "$VALID" "$ORIGINAL_ESCAPED")
    fi
    if [ "$VALID" = true ]; then
        json_output "ok" "$RESULT" "use --slug $SLUG"
    else
        json_output "error" "$RESULT" "slug invalid — provide ASCII text or LLM-translated equivalent" "[]" "[\"slug invalid: $SLUG\"]"
        exit "$EXIT_ERROR"
    fi
else
    if [ "$VALID" = true ]; then
        echo "$SLUG"
    else
        goax_error "slug invalid: $SLUG"
        exit "$EXIT_ERROR"
    fi
fi
