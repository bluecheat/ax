#!/usr/bin/env bash
# .ax/scripts/bash/init-spec-dir.sh — tier별 selective spec 디렉토리 생성
#
# Usage:
#   bash init-spec-dir.sh --slug <kebab> --tier basic|standard|full \
#                         [--num NNN] [--json] [--dry-run] [--help]
#
# Tier 산출물 (slim default):
#   basic     spec.md                                          (1)
#   standard  + plan.md + tasks.md                             (3)
#   full      + research.md + data-model.md + quickstart.md    (6, 단일 파일만)
#
# Lazy 생성 (필요 시 add-spec-files.sh):
#   checklists/requirements.md          — `--add checklists`
#   contracts/{api.yaml, events.md}     — `--add contracts`
#
# README.md 폐기 — spec.md 가 SSOT (What/Why), plan/tasks 가 본문. README 는 placeholder 였음.
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
[ -z "$TIER" ] && { goax_error "--tier required (basic|standard|full)"; exit "$EXIT_ERROR"; }

case "$TIER" in
    basic|standard|full) ;;
    *) goax_error "invalid --tier: $TIER (basic|standard|full)"; exit "$EXIT_ERROR" ;;
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

# NUM 자동 결정
if [ -z "$NUM" ]; then
    NUM=$(bash "$SCRIPT_DIR/next-spec-num.sh" 2>/dev/null || echo "001")
fi

# 형식 검증
if ! [[ "$NUM" =~ ^[0-9]{3,}$ ]]; then
    goax_error "--num must be 3+ digit number: '$NUM'"
    exit "$EXIT_ERROR"
fi

DEST="$PROJECT_ROOT/.ax/docs/spec/${NUM}-${SLUG}"
DEST_REL=".ax/docs/spec/${NUM}-${SLUG}"

# 중복 체크
if [ -e "$DEST" ]; then
    if [ "$JSON_MODE" = true ]; then
        json_error "spec dir already exists: $DEST_REL"
    else
        goax_error "spec dir already exists: $DEST_REL"
        exit "$EXIT_ERROR"
    fi
fi

# Tier별 파일 목록 — slim (README.md 폐기, 빈 dir 안 만듦)
# checklists/, contracts/ 는 lazy — add-spec-files.sh --add checklists|contracts 로
case "$TIER" in
    basic)
        FILES=("spec.md")
        ;;
    standard)
        FILES=("spec.md" "plan.md" "tasks.md")
        ;;
    full)
        FILES=("spec.md" "plan.md" "tasks.md" "research.md" "data-model.md" "quickstart.md")
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
# 후속 spec-plan/spec-tasks가 깨짐. 0.1.8 fix (PR review).
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
