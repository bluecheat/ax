#!/usr/bin/env bash
# .ax/scripts/bash/tier-from-state.sh — current-task.json + config.yml → spec tier 결정
#
# Usage:
#   bash tier-from-state.sh [--json] [--size S|M|L|XL] [--risk L0|L1|L2|L3] [--help]
#
# 우선순위:
#   1. CLI --size --risk 인자
#   2. .ax/current-task.json 의 size/risk
#   3. default standard
#
# 매트릭스 (0.1.16 — basic·plan 폐기, 2 단계):
#   S/M/L × L0~L2   → standard (spec.md + tasks.md)
#   L     × L3      → full     (+ research/data-model/quickstart + ADR)
#   XL    × *       → full
#
# Output (--json):
#   {"status":"ok","result":{"tier":"full","size":"L","risk":"L3","reason":"..."}}

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
SHOW_HELP=false
SIZE_ARG=""
RISK_ARG=""
RESET=false

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --reset)   RESET=true ;;
        --help|-h) SHOW_HELP=true ;;
        --size)    shift; SIZE_ARG="${1:-}" ;;
        --risk)    shift; RISK_ARG="${1:-}" ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# //'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
TASK_FILE="$PROJECT_ROOT/.ax/current-task.json"

# --reset: current-task.json을 phase=idle 로 리셋 (작업 완료 후 호출)
# 새 작업이 들어오면 triage가 다시 발동해야 하므로 size/risk/domain 등도 모두 null
if [ "$RESET" = true ]; then
    if [ ! -f "$TASK_FILE" ]; then
        TEMPLATE="$PROJECT_ROOT/.ax/current-task.json.template"
        [ -f "$TEMPLATE" ] && cp "$TEMPLATE" "$TASK_FILE"
    fi
    if [ -f "$TASK_FILE" ] && command -v jq >/dev/null 2>&1; then
        jq '.task_id = null
            | .description = null
            | .size = null
            | .risk = null
            | .domain = null
            | .spec_id = null
            | .spec_dir = null
            | .spec_tier = null
            | .started_at = null
            | .updated_at = (now | todate)
            | .phase = "idle"
            | .intent_notes = {}
            | .blocked_by = []' "$TASK_FILE" \
            > "${TASK_FILE}.tmp" && mv "${TASK_FILE}.tmp" "$TASK_FILE"
    fi
    # 다음 nudge 허용 — 마커 정리
    rm -f "$PROJECT_ROOT/.ax/.triage-nudged"
    if [ "$JSON_MODE" = true ]; then
        json_output "ok" '{"reset":true,"phase":"idle"}' "current-task.json reset to idle. triage-nudge re-armed."
    else
        echo "[goax] current-task.json → phase=idle (triage-nudge 재발동 가능)"
    fi
    exit "$EXIT_OK"
fi

# size/risk 결정 — CLI 우선, 없으면 task 파일.
# CLI override가 없는데 task 파일이 비어있거나 phase=idle이면 SKIP (silent default 금지).
SIZE="$SIZE_ARG"
RISK="$RISK_ARG"

if [ -z "$SIZE" ] && [ -z "$RISK" ]; then
    PHASE="idle"
    RAW_SIZE=""
    RAW_RISK=""
    if [ -f "$TASK_FILE" ] && command -v jq >/dev/null 2>&1; then
        PHASE=$(jq -r '.phase // "idle"' "$TASK_FILE" 2>/dev/null || echo idle)
        RAW_SIZE=$(jq -r '.size // empty' "$TASK_FILE" 2>/dev/null || true)
        RAW_RISK=$(jq -r '.risk // empty' "$TASK_FILE" 2>/dev/null || true)
    fi

    if [ "$PHASE" = "idle" ] || [ -z "$RAW_SIZE" ] || [ -z "$RAW_RISK" ]; then
        if [ "$JSON_MODE" = true ]; then
            json_skip "current-task.json 비어있음 (phase=$PHASE, size=$RAW_SIZE, risk=$RAW_RISK). triage 먼저 돌리거나 --size/--risk 명시."
        else
            goax_warn "current-task.json 비어있음 (phase=$PHASE, size=$RAW_SIZE, risk=$RAW_RISK)"
            goax_warn "triage 먼저 실행하세요: '<작업> 작업 계획 세워줘'"
            goax_warn "또는 명시 override: --size L --risk L3"
            exit "$EXIT_SKIPPED"
        fi
    fi

    SIZE="$RAW_SIZE"
    RISK="$RAW_RISK"
elif [ -z "$SIZE" ] || [ -z "$RISK" ]; then
    # 한쪽만 CLI로 준 경우 — 나머지는 task 파일에서 보충
    if [ -f "$TASK_FILE" ] && command -v jq >/dev/null 2>&1; then
        [ -z "$SIZE" ] && SIZE=$(jq -r '.size // empty' "$TASK_FILE" 2>/dev/null || true)
        [ -z "$RISK" ] && RISK=$(jq -r '.risk // empty' "$TASK_FILE" 2>/dev/null || true)
    fi
    # 그래도 비면 합리적 default (CLI 의도가 명시적이라)
    SIZE="${SIZE:-M}"
    RISK="${RISK:-L1}"
fi

# 매트릭스 (0.1.16 — 2 단계로 슬림화)
case "$SIZE-$RISK" in
    S-*|M-*)        TIER="standard"; REASON="S/M size — spec + tasks" ;;
    L-L0|L-L1|L-L2) TIER="standard"; REASON="L size, low~mid risk — spec + tasks" ;;
    L-L3)           TIER="full";     REASON="L × L3 — full SDD + ADR" ;;
    XL-*)           TIER="full";     REASON="XL — full SDD + ADR" ;;
    *)              TIER="standard"; REASON="unknown — default standard" ;;
esac

if [ "$JSON_MODE" = true ]; then
    RESULT=$(printf '{"tier":"%s","size":"%s","risk":"%s","reason":"%s"}' \
                    "$TIER" "$SIZE" "$RISK" "$REASON")
    json_output "ok" "$RESULT" "use --tier $TIER for spec"
else
    echo "$TIER"
fi
