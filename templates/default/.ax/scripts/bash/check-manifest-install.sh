#!/usr/bin/env bash
# .ax/scripts/bash/check-manifest-install.sh — MANIFEST 기반 install 완전성 검증
#
# Usage:
#   bash check-manifest-install.sh [--json] [--plugin-dir <path>] [--help]
#
# 동작:
#   plugin templates/default/MANIFEST 의 디렉토리 entry 를 모두 walk →
#   plugin tpl side 의 각 파일이 사용자 프로젝트에 존재하는지 + 내용이 같은지 검증.
#
#   - missing: plugin tpl 에 있지만 사용자 프로젝트에 없음 (install gap)
#   - drift:   양쪽 다 있지만 내용 다름 (사용자 수정 또는 plugin 갱신 후 미동기)
#
# rename entry (`src -> dst`) 는 stateful target 이라 skip
# (current-task.json, state.json — drift 정상).
#
# 추가 검증 — MANIFEST 외이지만 install 이 cp 하는 read-only 자산:
#   docs/reference/ → .ax/docs/reference/  (install/SKILL.md §6.6)
#
# Output (--json):
#   {
#     "status": "ok|warning|skipped|error",
#     "result": {
#       "manifest_path": "<abs>",
#       "files_checked": <int>,
#       "missing": ["rel/path", ...],
#       "drift": ["rel/path", ...]
#     },
#     "next_step": "<text>",
#     "warnings": [],
#     "errors": []
#   }
#
# Exit:
#   0  ok or warning (사용자가 결과로 판단)
#   1  hard error (MANIFEST malformed 등)
#   2  skipped (plugin-dir 미해결 — graceful degradation)

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
SHOW_HELP=false
PLUGIN_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)        JSON_MODE=true ;;
        --help|-h)     SHOW_HELP=true ;;
        --plugin-dir)  shift; PLUGIN_DIR="${1:-}" ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,37p' "${BASH_SOURCE[0]}" | sed 's/^#$//; s/^# //'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"

# Resolve plugin root: --plugin-dir > CLAUDE_SKILL_DIR > CLAUDE_PLUGIN_ROOT
if [ -z "$PLUGIN_DIR" ]; then
    if [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
        PLUGIN_DIR="$(cd "${CLAUDE_SKILL_DIR}/../.." 2>/dev/null && pwd)" || PLUGIN_DIR=""
    elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
        PLUGIN_DIR="$CLAUDE_PLUGIN_ROOT"
    fi
fi

PLUGIN_TPL=""
[ -n "$PLUGIN_DIR" ] && [ -d "$PLUGIN_DIR/templates/default" ] && PLUGIN_TPL="$PLUGIN_DIR/templates/default"

MANIFEST=""
[ -n "$PLUGIN_TPL" ] && [ -f "$PLUGIN_TPL/MANIFEST" ] && MANIFEST="$PLUGIN_TPL/MANIFEST"

if [ -z "$MANIFEST" ]; then
    if [ "$JSON_MODE" = true ]; then
        json_skip "MANIFEST not resolvable — pass --plugin-dir or run in plugin context"
    else
        goax_warn "MANIFEST not resolvable — pass --plugin-dir or run in plugin context"
    fi
    exit "$EXIT_SKIPPED"
fi

# Parse MANIFEST — directory entries (trailing /). rename entries skipped.
DIR_ENTRIES=()
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac
    [[ "$line" == *" -> "* ]] && continue
    case "$line" in
        */) DIR_ENTRIES+=("${line%/}") ;;
    esac
done < "$MANIFEST"

MISSING=()
DRIFT=()
TOTAL=0

for entry in ${DIR_ENTRIES[@]+"${DIR_ENTRIES[@]}"}; do
    plugin_dir="$PLUGIN_TPL/$entry"
    [ -d "$plugin_dir" ] || continue
    while IFS= read -r f; do
        rel="${f#$PLUGIN_TPL/}"
        user_f="$PROJECT_ROOT/$rel"
        TOTAL=$((TOTAL + 1))
        if [ ! -f "$user_f" ]; then
            MISSING+=("$rel")
        elif ! cmp -s "$f" "$user_f"; then
            DRIFT+=("$rel")
        fi
    done < <(find "$plugin_dir" -type f -not -path '*/.omc/*')
done

# Extra (non-MANIFEST) shipped paths — install/SKILL.md §6.6
# format: <plugin_root_rel>|<project_root_rel>
EXTRA_PATHS=(
    "docs/reference|.ax/docs/reference"
)

for spec in "${EXTRA_PATHS[@]}"; do
    src_rel="${spec%|*}"
    dst_rel="${spec#*|}"
    src_dir="$PLUGIN_DIR/$src_rel"
    [ -d "$src_dir" ] || continue
    while IFS= read -r f; do
        sub="${f#$src_dir/}"
        user_f="$PROJECT_ROOT/$dst_rel/$sub"
        TOTAL=$((TOTAL + 1))
        if [ ! -f "$user_f" ]; then
            MISSING+=("$dst_rel/$sub")
        elif ! cmp -s "$f" "$user_f"; then
            DRIFT+=("$dst_rel/$sub")
        fi
    done < <(find "$src_dir" -type f -not -path '*/.omc/*')
done

# helpers
to_json_array() {
    if [ "$#" -eq 0 ]; then printf '[]'; return; fi
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$@" | jq -Rcn '[inputs]'
    else
        local out="" esc x
        for x in "$@"; do
            esc=$(printf '%s' "$x" | sed 's/\\/\\\\/g; s/"/\\"/g')
            out="${out:+$out,}\"$esc\""
        done
        printf '[%s]' "$out"
    fi
}

MISS_N=${#MISSING[@]}
DRIFT_N=${#DRIFT[@]}

if [ "$MISS_N" -eq 0 ] && [ "$DRIFT_N" -eq 0 ]; then
    STATUS="ok"
    NEXT="all manifest entries present and unmodified ($TOTAL files)"
else
    STATUS="warning"
    NEXT=""
    [ "$MISS_N" -gt 0 ] && NEXT="$MISS_N missing — rerun installer to backfill"
    [ "$DRIFT_N" -gt 0 ] && NEXT="${NEXT:+$NEXT; }$DRIFT_N drift — review for silent regression risk"
fi

if [ "$JSON_MODE" = true ]; then
    if [ "$MISS_N" -gt 0 ]; then
        miss_json=$(to_json_array "${MISSING[@]}")
    else
        miss_json=$(to_json_array)
    fi
    if [ "$DRIFT_N" -gt 0 ]; then
        drift_json=$(to_json_array "${DRIFT[@]}")
    else
        drift_json=$(to_json_array)
    fi

    if command -v jq >/dev/null 2>&1; then
        result=$(jq -nc \
            --arg mp "$MANIFEST" \
            --argjson fc "$TOTAL" \
            --argjson missing "$miss_json" \
            --argjson drift "$drift_json" \
            '{manifest_path: $mp, files_checked: $fc, missing: $missing, drift: $drift}')
    else
        esc_mp=$(printf '%s' "$MANIFEST" | sed 's/\\/\\\\/g; s/"/\\"/g')
        result=$(printf '{"manifest_path":"%s","files_checked":%d,"missing":%s,"drift":%s}' \
            "$esc_mp" "$TOTAL" "$miss_json" "$drift_json")
    fi
    json_output "$STATUS" "$result" "$NEXT"
else
    if [ "$STATUS" = "ok" ]; then
        goax_log "✓ MANIFEST install complete ($TOTAL files)"
    else
        [ "$MISS_N" -gt 0 ] && goax_warn "MANIFEST missing $MISS_N — rerun installer"
        [ "$DRIFT_N" -gt 0 ] && goax_warn "MANIFEST drift $DRIFT_N — silent regression risk"
        if [ "$MISS_N" -gt 0 ]; then
            printf '  missing:\n' >&2
            for m in "${MISSING[@]:0:5}"; do printf '    - %s\n' "$m" >&2; done
            [ "$MISS_N" -gt 5 ] && printf '    ... and %d more\n' "$((MISS_N - 5))" >&2
        fi
        if [ "$DRIFT_N" -gt 0 ]; then
            printf '  drift:\n' >&2
            for d in "${DRIFT[@]:0:5}"; do printf '    - %s\n' "$d" >&2; done
            [ "$DRIFT_N" -gt 5 ] && printf '    ... and %d more\n' "$((DRIFT_N - 5))" >&2
        fi
    fi
fi

exit "$EXIT_OK"
