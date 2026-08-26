#!/usr/bin/env bash
# .ax/scripts/bash/init-spec-dir.sh — tier별 selective spec 디렉토리 생성
#
# Usage:
#   bash init-spec-dir.sh --slug <kebab> --tier standard|full \
#                         [--num NNN] [--json] [--dry-run] [--help]
#
# Tier 산출물:
#   standard  spec.md + tasks.md                                          (2)
#   full      + research.md + data-model.md + quickstart.md               (5, 단일 파일만)
#
# Lazy 생성 (필요 시 add-spec-files.sh):
#   checklists/requirements.md          — `--add checklists`
#   contracts/{api.yaml, events.md}     — `--add contracts`
#
# 설계 결정 (아키텍처·트레이드오프) 은 ADR 로 기록. plan.md 는 0.1.16 폐기.
#
# Output (--json):
#   {"status":"ok","result":{"spec_dir":"...","spec_id":"005","tier":"full","files":[...]}}

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
SHOW_HELP=false
SLUG=""
TIER=""
NUM=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h) SHOW_HELP=true ;;
        --slug)    shift; SLUG="${1:-}" ;;
        --tier)    shift; TIER="${1:-}" ;;
        --num)     shift; NUM="${1:-}" ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# //'
    exit "$EXIT_OK"
fi

[ -z "$SLUG" ] && { goax_error "--slug required"; exit "$EXIT_ERROR"; }
[ -z "$TIER" ] && { goax_error "--tier required (standard|full)"; exit "$EXIT_ERROR"; }

case "$TIER" in
    standard|full) ;;
    basic) goax_error "tier 'basic' 은 0.1.16 에서 폐기됐어요 — 'standard' 사용해주세요"; exit "$EXIT_ERROR" ;;
    *) goax_error "invalid --tier: $TIER (standard|full)"; exit "$EXIT_ERROR" ;;
esac

# slug 검증 — kebab-case만
if ! [[ "$SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    goax_error "slug must be kebab-case: '$SLUG'"
    exit "$EXIT_ERROR"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
TEMPLATE_DIR="$PROJECT_ROOT/.ax/_templates/spec"

if [ ! -d "$TEMPLATE_DIR" ]; then
    goax_error "_templates not found at $TEMPLATE_DIR"
    exit "$EXIT_ERROR"
fi

# NUM 자동 결정 — 계산이 아니라 *예약*이에요.
# 계산만 하면 여기서 mkdir 까지 사이에 다른 세션이 같은 번호를 가져가요
# (실사용 리포에서 spec 2 쌍·ADR 7 쌍이 이렇게 겹쳤어요).
# --reserve 는 번호 원장에 원자적으로 선점하고 디렉토리까지 만들어 줘요.
RESERVED_BY_US=false
if [ -z "$NUM" ]; then
    if command -v jq >/dev/null 2>&1; then
        RES=$(bash "$SCRIPT_DIR/next-spec-num.sh" --reserve --slug "$SLUG" --json 2>/dev/null || true)
        NUM=$(printf '%s' "$RES" | jq -r 'select(.status=="ok") | .result.next // empty' 2>/dev/null || true)
        [ -n "$NUM" ] && RESERVED_BY_US=true
    fi
    # jq 없거나 예약 실패 — 계산 fallback (경합 방어는 못 하지만 동작은 함)
    [ -z "$NUM" ] && NUM=$(bash "$SCRIPT_DIR/next-spec-num.sh" 2>/dev/null || echo "001")
fi

# 형식 검증
if ! [[ "$NUM" =~ ^[0-9]{3,}$ ]]; then
    goax_error "--num must be 3+ digit number: '$NUM'"
    exit "$EXIT_ERROR"
fi

DEST="$PROJECT_ROOT/.ax/docs/spec/${NUM}-${SLUG}"
DEST_REL=".ax/docs/spec/${NUM}-${SLUG}"

# 중복 체크 — 단, 바로 위에서 우리가 예약해 만든 디렉토리는 예외예요.
# (--reserve 가 번호 선점과 동시에 디렉토리를 만들기 때문에, 이 가드가
#  자기 자신의 예약에 걸리면 항상 실패해요.)
if [ -e "$DEST" ] && [ "$RESERVED_BY_US" != true ]; then
    if [ "$JSON_MODE" = true ]; then
        json_error "spec dir already exists: $DEST_REL"
    else
        goax_error "spec dir already exists: $DEST_REL"
        exit "$EXIT_ERROR"
    fi
fi

# 예약된 디렉토리는 비어 있어야 정상 — 내용이 있으면 예약이 아니라 기존 spec 이에요
if [ "$RESERVED_BY_US" = true ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
    if [ "$JSON_MODE" = true ]; then
        json_error "reserved dir is not empty: $DEST_REL"
    else
        goax_error "reserved dir is not empty: $DEST_REL"
        exit "$EXIT_ERROR"
    fi
fi

# Tier별 파일 목록 — slim (plan.md·README.md 폐기, 빈 dir 안 만듦)
# checklists/, contracts/ 는 lazy — add-spec-files.sh --add checklists|contracts 로
case "$TIER" in
    standard)
        FILES=("spec.md" "tasks.md")
        ;;
    full)
        FILES=("spec.md" "tasks.md" "research.md" "data-model.md" "quickstart.md")
        ;;
esac

# Dry-run
if [ "$DRY_RUN" = true ]; then
    if [ "$JSON_MODE" = true ]; then
        files_json="["
        first=true
        for f in "${FILES[@]}"; do
            [ "$first" = true ] || files_json+=","
            files_json+="\"$f\""
            first=false
        done
        files_json+="]"
        RESULT=$(printf '{"spec_dir":"%s","spec_id":"%s","tier":"%s","files":%s,"dry_run":true}' \
                        "$DEST_REL" "$NUM" "$TIER" "$files_json")
        json_output "ok" "$RESULT" "would create $DEST_REL with ${#FILES[@]} files"
    else
        goax_log "DRY RUN — would create $DEST_REL with files: ${FILES[*]}"
    fi
    exit "$EXIT_OK"
fi

# 실제 생성 — spec dir 만. checklists/contracts 는 lazy (add-spec-files.sh).
mkdir -p "$DEST"

CREATED=()
MISSING=()
for f in "${FILES[@]}"; do
    src="$TEMPLATE_DIR/$f"
    dst="$DEST/$f"
    if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        CREATED+=("$f")
    else
        MISSING+=("$f")
    fi
done

# Mandatory templates 누락 시 fail — silent continue로 빈 spec dir 생성하면
# 후속 spec-tasks/spec-implement 가 깨짐. 0.1.8 fix (PR review).
if [ ${#MISSING[@]} -gt 0 ]; then
    if [ "$JSON_MODE" = true ]; then
        json_error "mandatory templates missing in $TEMPLATE_DIR: ${MISSING[*]}"
    else
        goax_error "mandatory templates missing in $TEMPLATE_DIR: ${MISSING[*]}"
        exit "$EXIT_ERROR"
    fi
fi

# .tier 메모
{
    echo "tier: $TIER"
    echo "created_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "files: ${#CREATED[@]}"
} > "$DEST/.tier"

if [ "$JSON_MODE" = true ]; then
    files_json="["
    first=true
    for f in "${CREATED[@]}"; do
        [ "$first" = true ] || files_json+=","
        files_json+="\"$f\""
        first=false
    done
    files_json+="]"
    RESULT=$(printf '{"spec_dir":"%s","spec_id":"%s","tier":"%s","files":%s,"file_count":%s}' \
                    "$DEST_REL" "$NUM" "$TIER" "$files_json" "${#CREATED[@]}")
    json_output "ok" "$RESULT" "edit $DEST_REL/spec.md to fill NEEDS CLARIFICATION"
else
    goax_log "✓ created $DEST_REL (tier=$TIER, ${#CREATED[@]} files)"
fi
