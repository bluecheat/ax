#!/usr/bin/env bash
# .ax/scripts/bash/next-spec-num.sh — 다음 spec/ADR 번호 계산
#
# Usage:
#   bash next-spec-num.sh [--kind spec|adr] [--json] [--help]
#
# --kind spec (기본) — .ax/docs/spec/NNN-*/ 스캔, NNN 3자리 zero-pad (overflow: 999)
# --kind adr        — .ax/docs/adr/NNNN-*.md 스캔, NNNN 4자리 zero-pad (overflow: 9999)
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
KIND="spec"

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --kind)    shift; KIND="${1:-spec}" ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# //'
    exit "$EXIT_OK"
fi

case "$KIND" in
    spec|adr) ;;
    *) goax_error "invalid --kind: $KIND (spec|adr)"; exit "$EXIT_ERROR" ;;
esac

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"

if [ "$KIND" = "adr" ]; then
    NUM_DIR="$PROJECT_ROOT/.ax/docs/adr"
    WIDTH=4
    MAX=9999
    FIRST_NEXT="0001"
    FIRST_MSG="first ADR — create .ax/docs/adr/0001-<slug>.md"
    OVERFLOW_MSG="ADR number overflow: 9999 초과 — NNNN-* 4자리 규약 위반. ADR 정리 후 재시도."
    NEXT_STEP_TMPL="create .ax/docs/adr/%s-<slug>.md"

    # adr/ 없거나 비어 있으면 "0001"로 시작 (skipped 아님 — 첫 ADR)
    if [ ! -d "$NUM_DIR" ] || [ -z "$(ls -d "$NUM_DIR"/[0-9][0-9][0-9][0-9]-*.md 2>/dev/null || true)" ]; then
        if [ "$JSON_MODE" = true ]; then
            RESULT='{"next":"0001","previous":"0000","existing_count":0}'
            json_output "ok" "$RESULT" "$FIRST_MSG"
        else
            echo "$FIRST_NEXT"
        fi
        exit "$EXIT_OK"
    fi

    # 가장 큰 NNNN 찾기 (4자리 zero-padded)
    PREV=$(ls -d "$NUM_DIR"/[0-9][0-9][0-9][0-9]-*.md 2>/dev/null \
           | sed 's|.*/||' | awk -F- '{print $1}' | sort -n | tail -1 || true)
    PREV="${PREV:-0000}"

    NEXT_NUM=$((10#${PREV} + 1))
    if [ "$NEXT_NUM" -gt "$MAX" ]; then
        if [ "$JSON_MODE" = true ]; then
            json_error "$OVERFLOW_MSG"
        else
            goax_error "$OVERFLOW_MSG"
            exit "$EXIT_ERROR"
        fi
    fi
    NEXT=$(printf "%04d" "$NEXT_NUM")

    EXISTING_COUNT=$(ls -d "$NUM_DIR"/[0-9][0-9][0-9][0-9]-*.md 2>/dev/null | wc -l | tr -d ' ')

    if [ "$JSON_MODE" = true ]; then
        RESULT=$(printf '{"next":"%s","previous":"%s","existing_count":%s}' \
                        "$NEXT" "$PREV" "$EXISTING_COUNT")
        NEXT_STEP=$(printf "$NEXT_STEP_TMPL" "$NEXT")
        json_output "ok" "$RESULT" "$NEXT_STEP"
    else
        echo "$NEXT"
    fi
    exit "$EXIT_OK"
fi

# ── KIND=spec (기본, 기존 동작 그대로) ──
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
if [ "$NEXT_NUM" -gt 999 ]; then
    if [ "$JSON_MODE" = true ]; then
        json_error "spec number overflow: 999 초과 — NNN-* 3자리 규약 위반. spec 정리/아카이브 후 재시도."
    else
        goax_error "spec number overflow: 999 초과 — NNN-* 3자리 규약 위반"
        exit "$EXIT_ERROR"
    fi
fi
NEXT=$(printf "%03d" "$NEXT_NUM")

EXISTING_COUNT=$(ls -d "$SPEC_DIR"/[0-9][0-9][0-9]-* 2>/dev/null | wc -l | tr -d ' ')

if [ "$JSON_MODE" = true ]; then
    RESULT=$(printf '{"next":"%s","previous":"%s","existing_count":%s}' \
                    "$NEXT" "$PREV" "$EXISTING_COUNT")
    json_output "ok" "$RESULT" "create .ax/docs/spec/${NEXT}-<slug>/"
else
    echo "$NEXT"
fi
