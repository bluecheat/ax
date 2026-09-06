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
# 매트릭스 (standard/full 2 단계 — basic·plan 폐기):
#   S/M/L × L0~L2   → standard (spec.md + tasks.md)
#   L     × L3      → full     (+ research/data-model/quickstart + ADR)
#   XL    × *       → full
#
# evaluator (완료 시 새 컨텍스트 리뷰 — spec-implement 가 tasks-gate G6 으로 강제):
#   S × * · M × L0~L2 → optional
#   M × L3 · L × * · XL × * → required
#
# spec_review (spec 합의 리뷰 — spec-validate 가 spec-review.sh 로 강제). **Size 축만** 봐요:
#   S → none · M → optional (--consensus 로 강제) · L / XL → required
#   risk 는 안 봐요 — risk 는 evaluator(G6) 가 이미 반영해서 두 축을 다 걸면 이중 반영이에요.
#
# Output (--json):
#   {"status":"ok","result":{"tier":"full","size":"L","risk":"L3","evaluator":"required","spec_review":"required","reason":"..."}}

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

# enum 검증 — 오타·비표준 값(소문자 l, "Large" 등)이 조용히 standard 로 fallback 되면
# L×L3/XL 이 full 로 못 가서 L3 게이팅이 우회된다. fallback 이 아니라 에러가 맞다.
case "$SIZE" in
    S|M|L|XL) ;;
    *) goax_error "invalid size '$SIZE' — S|M|L|XL 만 허용. triage 를 다시 돌리거나 --size 로 교정."
       exit "$EXIT_ERROR" ;;
esac
case "$RISK" in
    L0|L1|L2|L3) ;;
    *) goax_error "invalid risk '$RISK' — L0|L1|L2|L3 만 허용. triage 를 다시 돌리거나 --risk 로 교정."
       exit "$EXIT_ERROR" ;;
esac

# 매트릭스 (standard/full 2 단계로 슬림화)
case "$SIZE-$RISK" in
    S-*|M-*)        TIER="standard"; REASON="S/M size — spec + tasks" ;;
    L-L0|L-L1|L-L2) TIER="standard"; REASON="L size, low~mid risk — spec + tasks" ;;
    L-L3)           TIER="full";     REASON="L × L3 — full SDD + ADR" ;;
    XL-*)           TIER="full";     REASON="XL — full SDD + ADR" ;;
    *)              TIER="standard"; REASON="unknown — default standard" ;;
esac

# evaluator 필수 여부 — triage 매트릭스와 agents/evaluator.md ("L 이상 강제, M 이하 선택") 의 SSOT
case "$SIZE-$RISK" in
    M-L3|L-*|XL-*) EVALUATOR="required" ;;
    *)             EVALUATOR="optional" ;;
esac

# spec 합의 리뷰 필수 여부 — Size 축만 (사용자 결정: "옷 사이즈로")
case "$SIZE" in
    L|XL) SPEC_REVIEW="required" ;;
    M)    SPEC_REVIEW="optional" ;;
    *)    SPEC_REVIEW="none" ;;
esac

if [ "$JSON_MODE" = true ]; then
    RESULT=$(printf '{"tier":"%s","size":"%s","risk":"%s","evaluator":"%s","spec_review":"%s","reason":"%s"}' \
                    "$TIER" "$SIZE" "$RISK" "$EVALUATOR" "$SPEC_REVIEW" "$REASON")
    json_output "ok" "$RESULT" "use --tier $TIER for spec"
else
    echo "$TIER"
fi
