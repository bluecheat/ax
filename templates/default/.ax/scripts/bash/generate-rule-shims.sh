#!/usr/bin/env bash
# .ax/scripts/bash/generate-rule-shims.sh
# spirit/rules/<name>.md 의 paths frontmatter → .claude/rules/<name>.md shim 생성
#
# Claude Code 공식 path-scoped rule 메커니즘 활용. spirit이 SSOT, shim은 generated.
# paths가 없거나 빈 배열이면 universal → shim 생성 안 함, CLAUDE.md @import 유지.
#
# Usage:
#   bash generate-rule-shims.sh [--json] [--dry-run] [--clean] [--help]
#
# --dry-run : 변경사항 미리보기 (write 안 함)
# --clean   : 더 이상 paths를 가지지 않는 spirit 룰의 shim 제거 (또는 spirit 파일 자체 삭제됨)
#
# Frontmatter 형식 예 (spirit/rules/<name>.md):
#   ---
#   category: domain
#   paths:
#     - "**/domain/**"
#     - "**/*Entity*.kt"
#   applies_to: [code]
#   ---

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
CLEAN=false
SHOW_HELP=false

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --clean)   CLEAN=true ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# //; s/^#//'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
SPIRIT_DIR="$PROJECT_ROOT/.ax/spirit/rules"
SHIM_DIR="$PROJECT_ROOT/.claude/rules"

if [ ! -d "$SPIRIT_DIR" ]; then
    if [ "$JSON_MODE" = true ]; then json_skip "spirit/rules/ 미존재"
    else goax_warn "spirit/rules/ not found — skip"; fi
    exit "$EXIT_SKIPPED"
fi

# yaml frontmatter에서 paths array 추출 (top-level 'paths:' 다음의 indented '- ' 라인들)
# 빈 배열(`paths: []`)이나 키 없음은 빈 출력.
extract_paths() {
    awk '
        BEGIN { c=0; in_paths=0 }
        /^---$/ {
            c++
            if (c==2) exit
            next
        }
        c==1 {
            if (/^paths:[[:space:]]*$/)        { in_paths=1; next }
            if (/^paths:[[:space:]]*\[[[:space:]]*\]/) { in_paths=0; next }
            if (/^[a-zA-Z_]/)                  { in_paths=0 }
            if (in_paths && /^[[:space:]]+-[[:space:]]/) print
        }
    ' "$1"
}

GENERATED=()
SKIPPED=()
REMOVED=()
UNCHANGED=()

mkdir -p "$SHIM_DIR"

# 1) spirit → shim 생성
for src in "$SPIRIT_DIR"/*.md; do
    [ -f "$src" ] || continue
    name=$(basename "$src")
    paths_block=$(extract_paths "$src")
    if [ -z "$paths_block" ]; then
        SKIPPED+=("$name")
        continue
    fi

    shim="$SHIM_DIR/$name"
    new_content=$(printf -- '---\npaths:\n%s\n---\n@../../.ax/spirit/rules/%s\n' "$paths_block" "$name")

    if [ -f "$shim" ] && [ "$(cat "$shim")" = "$new_content" ]; then
        UNCHANGED+=("$name")
        continue
    fi

    if [ "$DRY_RUN" = true ]; then
        GENERATED+=("$name (dry-run)")
        continue
    fi

    printf '%s' "$new_content" > "$shim"
    GENERATED+=("$name")
done

# 2) stale shim 정리 (--clean 모드)
if [ "$CLEAN" = true ]; then
    for shim in "$SHIM_DIR"/*.md; do
        [ -f "$shim" ] || continue
        name=$(basename "$shim")
        src="$SPIRIT_DIR/$name"
        if [ ! -f "$src" ] || [ -z "$(extract_paths "$src")" ]; then
            [ "$DRY_RUN" = true ] || rm "$shim"
            REMOVED+=("$name")
        fi
    done
fi

# 출력
to_json_array() {
    local arr_name="$1"
    eval "local items=(\"\${${arr_name}[@]:-}\")"
    local out="["
    local first=true
    for it in "${items[@]:-}"; do
        [ -z "$it" ] && continue
        [ "$first" = true ] || out+=","
        out+="\"$it\""
        first=false
    done
    out+="]"
    printf '%s' "$out"
}

if [ "$JSON_MODE" = true ]; then
    RESULT=$(printf '{"generated":%s,"skipped":%s,"removed":%s,"unchanged":%s,"dry_run":%s,"clean":%s}' \
                    "$(to_json_array GENERATED)" \
                    "$(to_json_array SKIPPED)" \
                    "$(to_json_array REMOVED)" \
                    "$(to_json_array UNCHANGED)" \
                    "$DRY_RUN" \
                    "$CLEAN")
    json_output "ok" "$RESULT" "review .claude/rules/ shims"
else
    [ "${#GENERATED[@]}" -gt 0 ] && goax_log "generated: ${GENERATED[*]}" || :
    [ "${#UNCHANGED[@]}" -gt 0 ] && goax_log "unchanged: ${#UNCHANGED[@]}" || :
    [ "${#SKIPPED[@]}" -gt 0 ] && goax_log "skipped (no paths — universal): ${SKIPPED[*]}" || :
    [ "${#REMOVED[@]}" -gt 0 ] && goax_log "removed (stale): ${REMOVED[*]}" || :
fi
exit "$EXIT_OK"
