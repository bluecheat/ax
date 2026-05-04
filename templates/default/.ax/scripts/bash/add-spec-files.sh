#!/usr/bin/env bash
# .ax/scripts/bash/add-spec-files.sh — 기존 spec에 plan/tasks/research 등 점진 추가
#
# Usage:
#   bash add-spec-files.sh --spec <NNN-slug> --add plan,tasks,... \
#                          [--json] [--dry-run] [--help]
#
# 동작:
#   - 기존 파일 있으면 skip + 알림
#   - tier 메모(.tier) 갱신 (basic→standard→full 자동 승급, slim 정의)
#
# Slim tier 정의:
#   basic     spec.md
#   standard  + plan.md + tasks.md
#   full      + research/data-model/quickstart 중 하나라도 (단일 파일)
#   checklists/contracts 의 lazy 생성은 tier 와 무관 — 사용자 명시 추가만
#
# Output (--json):
#   {"status":"ok","result":{"spec_dir":"...","added":[...],"skipped":[...],"new_tier":"standard"}}

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
SHOW_HELP=false
SPEC=""
ADD=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h) SHOW_HELP=true ;;
        --spec)    shift; SPEC="${1:-}" ;;
        --add)     shift; ADD="${1:-}" ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# //'
    exit "$EXIT_OK"
fi

[ -z "$SPEC" ] && { goax_error "--spec required (e.g., 005-payment-refund)"; exit "$EXIT_ERROR"; }
[ -z "$ADD" ]  && { goax_error "--add required (comma-separated: plan,tasks,research,...)"; exit "$EXIT_ERROR"; }

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
TEMPLATE_DIR="$PROJECT_ROOT/.ax/_templates/spec"

# Spec 디렉토리 찾기
SPEC_DIR="$PROJECT_ROOT/.ax/docs/spec/$SPEC"
if [ ! -d "$SPEC_DIR" ]; then
    # NNN만 줬을 수도 — prefix 매칭
    MATCH=$(ls -d "$PROJECT_ROOT/.ax/docs/spec/${SPEC}-"* 2>/dev/null | head -1 || true)
    if [ -n "$MATCH" ]; then
        SPEC_DIR="$MATCH"
    else
        goax_error "spec not found: $SPEC"
        exit "$EXIT_ERROR"
    fi
fi
SPEC_REL="${SPEC_DIR#$PROJECT_ROOT/}"

# add 항목 → 파일 경로
declare -a TO_ADD
IFS=',' read -ra REQUESTED <<< "$ADD"
for item in "${REQUESTED[@]}"; do
    item="${item## }"; item="${item%% }"  # trim
    case "$item" in
        plan)         TO_ADD+=("plan.md") ;;
        tasks)        TO_ADD+=("tasks.md") ;;
        research)     TO_ADD+=("research.md") ;;
        data-model|data) TO_ADD+=("data-model.md") ;;
        quickstart)   TO_ADD+=("quickstart.md") ;;
        checklists|checklist) TO_ADD+=("checklists/requirements.md") ;;
        contracts|api) TO_ADD+=("contracts/api.yaml" "contracts/events.md") ;;
        full)
            TO_ADD+=("plan.md" "tasks.md" "research.md" "data-model.md" \
                     "quickstart.md" "checklists/requirements.md" \
                     "contracts/api.yaml" "contracts/events.md")
            ;;
        *) goax_warn "unknown add item: $item (skipped)" ;;
    esac
done

ADDED=()
SKIPPED=()
for f in "${TO_ADD[@]}"; do
    src="$TEMPLATE_DIR/$f"
    dst="$SPEC_DIR/$f"
    if [ ! -f "$src" ]; then
        goax_warn "template missing: $f"
        continue
    fi
    if [ -f "$dst" ]; then
        SKIPPED+=("$f")
        continue
    fi
    if [ "$DRY_RUN" = true ]; then
        ADDED+=("$f (dry-run)")
    else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        ADDED+=("$f")
    fi
done

# Tier 갱신 — 추가된 파일에 따라 basic→standard→full 자동 승급
NEW_TIER="basic"
if [ -f "$SPEC_DIR/plan.md" ] && [ -f "$SPEC_DIR/tasks.md" ]; then
    NEW_TIER="standard"
fi
if [ -f "$SPEC_DIR/research.md" ] || [ -f "$SPEC_DIR/data-model.md" ] || \
   [ -f "$SPEC_DIR/quickstart.md" ]; then
    NEW_TIER="full"
fi
# 의도: checklists/contracts 의 lazy 추가는 tier 변경 X — 그건 사용자 명시 의제 (slim 정책)

if [ "$DRY_RUN" = false ]; then
    {
        echo "tier: $NEW_TIER"
        echo "updated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$SPEC_DIR/.tier"
fi

if [ "$JSON_MODE" = true ]; then
    added_json="[$(printf '"%s",' "${ADDED[@]:-}" | sed 's/,$//')]"
    skipped_json="[$(printf '"%s",' "${SKIPPED[@]:-}" | sed 's/,$//')]"
    [ "${#ADDED[@]}" -eq 0 ]   && added_json="[]"
    [ "${#SKIPPED[@]}" -eq 0 ] && skipped_json="[]"
    RESULT=$(printf '{"spec_dir":"%s","added":%s,"skipped":%s,"new_tier":"%s"}' \
                    "$SPEC_REL" "$added_json" "$skipped_json" "$NEW_TIER")
    json_output "ok" "$RESULT" "edit ${ADDED[*]:-existing files}"
else
    goax_log "✓ $SPEC_REL — added: ${ADDED[*]:-(none)}, skipped: ${SKIPPED[*]:-(none)}, tier: $NEW_TIER"
fi
