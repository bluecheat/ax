#!/usr/bin/env bash
# .ax/scripts/bash/next-spec-num.sh — 다음 spec NNN 번호 계산
#
# Usage:
#   bash next-spec-num.sh [--json] [--help]
#
# Output (--json):
#   {"status":"ok","result":{"next":"005","previous":"004","existing_count":4},...}
#
# Output (text):
#   005

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
SHOW_HELP=false

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# //'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
SPEC_DIR="$PROJECT_ROOT/.ax/docs/spec"

# spec/ 없거나 비어 있으면 "001"로 시작 (skipped 아님 — 첫 spec)
if [ ! -d "$SPEC_DIR" ] || [ -z "$(ls -d "$SPEC_DIR"/[0-9][0-9][0-9]-* 2>/dev/null || true)" ]; then
    if [ "$JSON_MODE" = true ]; then
        RESULT='{"next":"001","previous":"000","existing_count":0}'
        json_output "ok" "$RESULT" "first spec — create .ax/docs/spec/001-<slug>/"
    else
        echo "001"
    fi
    exit "$EXIT_OK"
fi

# 가장 큰 NNN 찾기 (3자리 zero-padded)
PREV=$(ls -d "$SPEC_DIR"/[0-9][0-9][0-9]-* 2>/dev/null \
       | sed 's|.*/||' | awk -F- '{print $1}' | sort -n | tail -1 || true)
PREV="${PREV:-000}"

NEXT_NUM=$((10#${PREV} + 1))
NEXT=$(printf "%03d" "$NEXT_NUM")

EXISTING_COUNT=$(ls -d "$SPEC_DIR"/[0-9][0-9][0-9]-* 2>/dev/null | wc -l | tr -d ' ')

if [ "$JSON_MODE" = true ]; then
    RESULT=$(printf '{"next":"%s","previous":"%s","existing_count":%s}' \
                    "$NEXT" "$PREV" "$EXISTING_COUNT")
    json_output "ok" "$RESULT" "create .ax/docs/spec/${NEXT}-<slug>/"
else
    echo "$NEXT"
fi
