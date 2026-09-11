#!/usr/bin/env bash
# .ax/scripts/bash/check-templates-drift.sh — _templates SSOT drift 체크
#
# Usage:
#  bash check-templates-drift.sh [--json] [--plugin-dir <path>] [--help]
#
# 비교:
#  1. .ax/_templates/spec/.origin (installer 기록 출고본 sha)
#  2. .ax/_templates/spec/ 현재 sha
#  3. (옵션) plugin templates/default/.ax/_templates/spec/ 최신 출고본
#
# 결과:
#  - user_modified: .origin과 현재 다르면 true (사용자 도메인 적응 — 정상)
#  - plugin_updated: plugin 출고본이 .origin과 다르면 true (plugin 갱신됨)
#
# Output (--json):
#  {"status":"ok","result":{"user_modified":true,"plugin_updated":false,
#              "drift_files":["spec.md"],"origin_present":true}}

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
SHOW_HELP=false
PLUGIN_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --json)    JSON_MODE=true ;;
    --help|-h)  SHOW_HELP=true ;;
    --plugin-dir) shift; PLUGIN_DIR="${1:-}" ;;
    *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
  esac
  shift
done

if [ "$SHOW_HELP" = true ]; then
  goax_help "${BASH_SOURCE[0]}"
  exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
TMPL_DIR="$PROJECT_ROOT/.ax/_templates/spec"
ORIGIN="$TMPL_DIR/.origin"

if [ ! -d "$TMPL_DIR" ]; then
  if [ "$JSON_MODE" = true ]; then
    json_skip "_templates directory not found"
  else
    goax_warn "_templates not found"
  fi
  exit "$EXIT_SKIPPED"
fi

# 현재 sha 계산
compute_sha() {
  local dir="$1"
  (
    cd "$dir" 2>/dev/null && \
    find . -type f \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' \) \
      ! -name '.origin' ! -name '.tier' | sort | xargs shasum -a 256 2>/dev/null
  )
}

ACTUAL=$(compute_sha "$TMPL_DIR")
USER_MODIFIED=false
DRIFT_FILES=()
ORIGIN_PRESENT=false

if [ -f "$ORIGIN" ]; then
  ORIGIN_PRESENT=true
  EXPECTED=$(grep -v '^#' "$ORIGIN" || true)
  if [ "$ACTUAL" != "$EXPECTED" ]; then
    USER_MODIFIED=true
    # diff 파일 목록 — diff exit-1 + pipefail이 set -e에 잡혀 죽지 않게 wrap
    DRIFT_FILES=($(
        { diff <(echo "$EXPECTED") <(echo "$ACTUAL") 2>/dev/null || true; } \
            | { grep -E '^[<>]' || true; } \
            | awk '{print $NF}' \
            | sort -u | head -20
    ))
  fi
fi

PLUGIN_UPDATED=false
if [ -n "$PLUGIN_DIR" ] && [ -d "$PLUGIN_DIR/templates/default/.ax/_templates/spec" ]; then
  PLUGIN_SHA=$(compute_sha "$PLUGIN_DIR/templates/default/.ax/_templates/spec")
  if [ "$ORIGIN_PRESENT" = true ] && [ "$EXPECTED" != "$PLUGIN_SHA" ]; then
    PLUGIN_UPDATED=true
  fi
fi

if [ "$JSON_MODE" = true ]; then
  drift_json="[$(printf '"%s",' "${DRIFT_FILES[@]:-}" | sed 's/,$//')]"
  [ "${#DRIFT_FILES[@]}" -eq 0 ] && drift_json="[]"
  RESULT=$(printf '{"user_modified":%s,"plugin_updated":%s,"drift_files":%s,"origin_present":%s}' \
          "$USER_MODIFIED" "$PLUGIN_UPDATED" "$drift_json" "$ORIGIN_PRESENT")

  NEXT=""
  if [ "$ORIGIN_PRESENT" = false ]; then
    NEXT="install with to get .origin marker"
  elif [ "$PLUGIN_UPDATED" = true ]; then
    NEXT="plugin updated — drop _templates.suggested for user merge"
  elif [ "$USER_MODIFIED" = true ]; then
    NEXT="user customized templates (this is the SSOT)"
  else
    NEXT="templates pristine"
  fi
  json_output "ok" "$RESULT" "$NEXT"
else
  if [ "$ORIGIN_PRESENT" = false ]; then
    goax_warn ".origin not found (older install — re-run installer to mark)"
  elif [ "$USER_MODIFIED" = true ]; then
    goax_log "· user-modified (${#DRIFT_FILES[@]} files): ${DRIFT_FILES[*]:-}"
  else
    goax_log "✓ pristine"
  fi
  [ "$PLUGIN_UPDATED" = true ] && goax_warn "plugin _templates updated — consider .suggested"
fi
