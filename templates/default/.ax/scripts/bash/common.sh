#!/usr/bin/env bash
# .ax/scripts/bash/common.sh — 공통 함수
# 다른 스크립트가 source 해서 사용. 직접 실행되지 않음.
#
# Usage:
#   source "$(dirname "$0")/common.sh"
#   PROJECT_ROOT=$(find_project_root) || exit 1

# Exit codes
EXIT_OK=0
EXIT_ERROR=1
EXIT_SKIPPED=2

# Logging — stderr only ([goax] prefix)
goax_log()   { printf '[goax] %s\n' "$*" >&2; }
goax_warn()  { printf '[goax] WARN: %s\n' "$*" >&2; }
goax_error() { printf '[goax] ERROR: %s\n' "$*" >&2; }

# sensors.mode 통일 판독 — .ax/config.yml에서 mode 추출
# 반환값: warning | fail | off (default: warning — 안전한 도입)
# Usage:
#   MODE=$(goax_mode)
#   [ "$MODE" = "fail" ] && exit 2
goax_mode() {
    local config="${1:-}"
    if [ -z "$config" ]; then
        local root
        root="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
        config="$root/.ax/config.yml"
    fi
    if [ ! -f "$config" ]; then
        printf 'warning'
        return 0
    fi
    local mode
    mode=$(grep -E '^[[:space:]]*mode:[[:space:]]*' "$config" 2>/dev/null \
            | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")
    case "$mode" in
        warning|warn|fail|off) printf '%s' "$mode" ;;
        *) printf 'warning' ;;
    esac
}

# Hook 위반 보고 (non-exiting) — 배치 hook에서 사용 (여러 위반을 모은 뒤 한 번에 exit)
# Usage:  goax_hook_report fail "메시지" "category" "details"
# 동작:  stderr 경고 + capture-mistake 호출. 종료 결정은 caller가.
# goax_hook_exit과 차이: 종료하지 않음. 배치 후 caller가 VIOLATIONS 누적 판단.
goax_hook_report() {
    local severity="${1:-warn}"
    local message="${2:-}"
    local category="${3:-uncategorized}"
    local details="${4:-}"
    [ -z "$message" ] && return 0

    local mode
    mode=$(goax_mode)
    [ "$mode" = "off" ] && return 0

    printf '\033[33m[goax hook]\033[0m %s\n' "$message" >&2

    local root capture
    root="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
    capture="$root/.ax/scripts/bash/capture-mistake.sh"
    if [ -f "$capture" ]; then
        bash "$capture" "$category" "$message" "$details" >/dev/null 2>&1 || true
    fi
    return 0
}

# Hook 표준 종료 — severity와 mode 조합으로 결정론적 결정
# Usage: goax_hook_exit fail "메시지" [category]
#   severity=fail + mode=fail   → exit 2 (차단), capture-mistake 호출
#   severity=fail + mode=warning → exit 0 + 경고, capture-mistake 호출
#   severity=fail + mode=off    → exit 0 (조용)
#   severity=warn               → exit 0 + 경고
goax_hook_exit() {
    local severity="${1:-warn}"
    local message="${2:-}"
    local category="${3:-uncategorized}"
    local mode
    mode=$(goax_mode)

    [ "$mode" = "off" ] && exit 0

    if [ -n "$message" ]; then
        printf '\033[33m[goax hook]\033[0m %s\n' "$message" >&2
    fi

    # capture-mistake 자동 호출 (있을 때만)
    local root capture
    root="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
    capture="$root/.ax/scripts/bash/capture-mistake.sh"
    if [ -f "$capture" ] && [ -n "$message" ]; then
        bash "$capture" "$category" "$message" >/dev/null 2>&1 || true
    fi

    if [ "$severity" = "fail" ] && [ "$mode" = "fail" ]; then
        exit 2
    fi
    exit 0
}

# Redact secrets in stdin, print redacted to stdout.
# Strategy: known-prefix tokens (high confidence) + key=value with ≥12-char value (lower).
# Designed for capture-mistake.sh DETAILS only — DO NOT apply to titles (signal loss).
# Patterns chosen to be POSIX sed -E compatible (no \s, no case-flag — bracket classes).
# Usage: REDACTED=$(printf '%s' "$x" | redact_secrets)
redact_secrets() {
    sed -E '
        s/AKIA[A-Z0-9]{16,}/[REDACTED:aws]/g
        s/gh[poshru]_[A-Za-z0-9]{20,}/[REDACTED:github]/g
        s/xox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED:slack]/g
        s/(sk|pk|rk)_live_[A-Za-z0-9]{20,}/[REDACTED:stripe]/g
        s/whsec_[A-Za-z0-9]{20,}/[REDACTED:stripe]/g
        s/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/[REDACTED:jwt]/g
        s/-----BEGIN[A-Z ]*PRIVATE KEY-----/[REDACTED:pem-begin]/g
        s/([Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Tt][Oo][Kk][Ee][Nn]|[Bb][Ee][Aa][Rr][Ee][Rr]|[Pp][Gg][_-]?[Kk][Ee][Yy])([[:space:]]*[:=][[:space:]]*"?)([A-Za-z0-9+\/=_-]{12,})/\1\2[REDACTED]/g
    '
}

# Find project root: $CLAUDE_PROJECT_DIR if it has .ax/, else nearest ancestor with .ax/
# CLAUDE_PROJECT_DIR is the Claude Code official env var pointing at the user's project root.
# Honoring it lets scripts work even when invoked from a different cwd (e.g., smoke fixtures,
# hooks running from a subdirectory, etc).
find_project_root() {
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR/.ax" ]; then
        printf '%s\n' "$CLAUDE_PROJECT_DIR"
        return 0
    fi
    local dir="${1:-$(pwd)}"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.ax" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    goax_error "no .ax/ found in any ancestor of $(pwd) (CLAUDE_PROJECT_DIR=${CLAUDE_PROJECT_DIR:-unset})"
    return 1
}

# JSON output — uses jq if available, else manual escape
# Usage: json_output ok '{"key":"value"}' "next step text"
json_output() {
    local status="$1"
    # bash의 ${2:-{}} 패턴은 default가 깨져서 result에 `}` literal이 붙음.
    # 비어 있으면 사후에 채우는 패턴이 안전.
    local result_json="${2:-}"
    [ -z "$result_json" ] && result_json="{}"
    local next_step="${3:-}"
    local warnings_json="${4:-[]}"
    local errors_json="${5:-[]}"

    if command -v jq >/dev/null 2>&1; then
        jq -nc \
            --arg status "$status" \
            --argjson result "$result_json" \
            --arg next "$next_step" \
            --argjson warnings "$warnings_json" \
            --argjson errors "$errors_json" \
            '{status: $status, result: $result, next_step: $next, warnings: $warnings, errors: $errors}'
    else
        # jq 없는 환경 fallback (간단·완벽X)
        printf '{"status":"%s","result":%s,"next_step":"%s","warnings":%s,"errors":%s}\n' \
            "$status" "$result_json" "$next_step" "$warnings_json" "$errors_json"
    fi
}

# JSON 에러 출력 + exit 1
json_error() {
    local msg="$1"
    json_output "error" "{}" "" "[]" "[\"$msg\"]"
    exit "$EXIT_ERROR"
}

# JSON skip 출력 + exit 2 (graceful degradation)
json_skip() {
    local msg="$1"
    json_output "skipped" "{}" "$msg" "[\"$msg\"]" "[]"
    exit "$EXIT_SKIPPED"
}

# 표준 옵션 parser 헬퍼 — JSON_MODE, DRY_RUN, HELP 공통
# Usage: 각 스크립트의 parse loop 안에서 case로 처리하고
#        --help 시 SHOW_HELP=true로 set
parse_common_opts() {
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h) SHOW_HELP=true ;;
        *) return 1 ;;  # 인식 못 한 옵션은 caller가 처리
    esac
    return 0
}
