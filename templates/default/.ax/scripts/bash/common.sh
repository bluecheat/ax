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
# JSON_MODE=true 면 goax_error 는 stdout 에 json_output error 한 줄을 emit.
# caller 의 exit 흐름은 보존 (이 함수는 exit 안 함). exit 까지 묶고 싶으면 'json_error'.
goax_log()   { printf '[goax] %s\n' "$*" >&2; }
goax_warn()  { printf '[goax] WARN: %s\n' "$*" >&2; }
goax_error() {
    if [ "${JSON_MODE:-false}" = "true" ]; then
        local errs
        errs=$(_goax_json_array "$*")
        json_output "error" "{}" "" "[]" "$errs"
    else
        printf '[goax] ERROR: %s\n' "$*" >&2
    fi
}

# 단일 문자열 → JSON array (잘 escape 된 1-element). arg-based, stdin 안 씀.
# 다른 _goax_* helper와 명명 일관 + caller 호출이 깔끔.
_goax_json_array() {
    if command -v jq >/dev/null 2>&1; then
        jq -nc --arg m "$1" '[$m]'
    else
        local esc
        esc=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf '["%s"]' "$esc"
    fi
}

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
# 동작:  stderr 경고만. 종료 결정은 caller가.
# mistake 기록은 사용자 명시 `mistake` skill 호출로 — hook 자동 capture 폐기 (의도된 capture 만).
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
    return 0
}

# Hook 표준 종료 — severity와 mode 조합으로 결정론적 결정
# Usage: goax_hook_exit fail "메시지" [category]
#   severity=fail + mode=fail    → exit 2 (차단)
#   severity=fail + mode=warning → exit 0 + 경고
#   severity=fail + mode=off     → exit 0 (조용)
#   severity=warn                → exit 0 + 경고
# mistake 기록은 사용자 명시 `mistake` skill 호출로 — hook 자동 capture 폐기 (의도된 capture 만).
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

    if [ "$severity" = "fail" ] && [ "$mode" = "fail" ]; then
        exit 2
    fi
    exit 0
}

# Redact secrets in stdin, print redacted to stdout.
# Strategy: known-prefix tokens (high confidence) + key=value with ≥12-char value (lower).
# Designed for init-mistake-file.sh / mistake skill DETAILS only — DO NOT apply to titles (signal loss).
# Patterns chosen to be POSIX sed -E compatible (no \s, no case-flag — bracket classes).
# Usage: REDACTED=$(printf '%s' "$x" | redact_secrets)
redact_secrets() {
    sed -E '
        s/AKIA[A-Z0-9]{16,}/[REDACTED:aws]/g
        s/gh[poshru]_[A-Za-z0-9]{20,}/[REDACTED:github]/g
        s/github_pat_[A-Za-z0-9_]{20,}/[REDACTED:github]/g
        s/sk-(ant|proj)-[A-Za-z0-9_-]{20,}/[REDACTED:llm-key]/g
        s/sk-[A-Za-z0-9]{20,}/[REDACTED:llm-key]/g
        s/AIza[0-9A-Za-z_-]{35}/[REDACTED:google]/g
        s/npm_[A-Za-z0-9]{30,}/[REDACTED:npm]/g
        s#https://hooks\.slack\.com/services/[A-Za-z0-9/+]{20,}#[REDACTED:slack-webhook]#g
        s/xox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED:slack]/g
        s/(sk|pk|rk)_live_[A-Za-z0-9]{20,}/[REDACTED:stripe]/g
        s/whsec_[A-Za-z0-9]{20,}/[REDACTED:stripe]/g
        s/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/[REDACTED:jwt]/g
        s/-----BEGIN[A-Z ]*PRIVATE KEY-----/[REDACTED:pem-begin]/g
        s/([Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Tt][Oo][Kk][Ee][Nn]|[Bb][Ee][Aa][Rr][Ee][Rr]|[Pp][Gg][_-]?[Kk][Ee][Yy])([[:space:]]*[:=][[:space:]]*"?)([A-Za-z0-9+\/=_-]{12,})/\1\2[REDACTED]/g
    '
}

# ─── 경로 정규화 / 경계 매칭 ────────────────────────────────────────
# 보호 경로 검사처럼 "이 경로가 저 경로 안에 있나" 를 판정하는 곳은 반드시 이 둘을
# 거쳐야 해요. 문자열 접두 비교만 하면 `./x`·`a/../x` 같은 표기 변형으로 우회되고,
# `CLAUDE.md.bak` 같은 무관 파일이 오탐돼요.
#
# goax_normalize_path <path> [base]
#   렉시컬 정규화 — `.`·`..`·중복 슬래시 해소 후 절대경로 출력.
#   파일시스템을 건드리지 않아요 (아직 없는 파일도 처리 — Write 는 새 파일을 만듦).
#   realpath 비의존 = macOS/Linux 동일 동작. bash 3.2 호환.
goax_normalize_path() {
    local p="${1:-}" base="${2:-$PWD}" out="" seg oldIFS
    [ -z "$p" ] && return 0
    case "$p" in /*) ;; *) p="$base/$p" ;; esac
    oldIFS="$IFS"
    set -f                      # `set --` 시 glob 확장 방지
    IFS='/'
    # shellcheck disable=SC2086
    set -- $p
    IFS="$oldIFS"
    set +f
    for seg in "$@"; do
        case "$seg" in
            ''|'.') continue ;;
            '..')   out="${out%/*}" ;;
            *)      out="$out/$seg" ;;
        esac
    done
    printf '%s' "${out:-/}"
}

# goax_path_under <rel-path> <pattern>
#   rel 이 pattern 과 동일하거나 그 하위 경로면 0. 경로 경계(`/`)를 지켜서
#   `CLAUDE.md` 패턴이 `CLAUDE.md.bak` 을 잡지 않아요.
goax_path_under() {
    local rel="${1:-}" pat="${2:-}"
    [ -z "$pat" ] && return 1
    pat="${pat%/}"              # 후행 슬래시 정규화 (`.ax/hooks/` → `.ax/hooks`)
    [ "$rel" = "$pat" ] && return 0
    case "$rel" in "$pat"/*) return 0 ;; esac
    return 1
}

# goax_yaml_list <file> <key>
#   YAML 시퀀스를 들여쓰기 인식으로 추출 (awk range 연산자는 시작 라인이 종료
#   패턴에도 매칭되면 1줄로 붕괴해서 조용히 빈 값을 냄 — 보안 컨트롤에선 치명적).
#   블록 형식(`key:` + `  - v`) 과 flow 형식(`key: [a, b]`) 둘 다 지원.
goax_yaml_list() {
    local file="${1:-}" key="${2:-}"
    [ -f "$file" ] || return 0
    awk -v key="$key" '
        function ind(s,   i) { if (s ~ /^[ \t]*$/) return -1; i = match(s, /[^ \t]/); return i - 1 }
        BEGIN { inlist = 0; keyind = -1 }
        {
            t = $0; sub(/\r$/, "", t)
            if (t ~ /^[ \t]*#/ || t ~ /^[ \t]*$/) next
            i = ind(t)
            if (!inlist) {
                if (t ~ ("^[ \t]*" key ":[ \t]*$")) { inlist = 1; keyind = i; next }
                if (t ~ ("^[ \t]*" key ":[ \t]*\\[")) {
                    s = t; sub(/^[^[]*\[/, "", s); sub(/\].*$/, "", s)
                    n = split(s, arr, ",")
                    for (j = 1; j <= n; j++) {
                        v = arr[j]
                        gsub(/^[ \t\042\047]+|[ \t\042\047]+$/, "", v)
                        if (v != "") print v
                    }
                }
                next
            }
            if (i > keyind && t ~ /^[ \t]*-[ \t]+/) {
                v = t; sub(/^[ \t]*-[ \t]+/, "", v)
                sub(/[ \t]+$/, "", v)
                gsub(/^[\042\047]+|[\042\047]+$/, "", v)
                if (v != "") print v
                next
            }
            if (i <= keyind) inlist = 0
        }
    ' "$file"
}

# Find project root — fallback chain:
#   1) $GOAX_PROJECT_DIR  — CLI-agnostic override. Claude Code 외 환경 (직접 호출, CI,
#      다른 AI CLI 의 어댑터) 에서 결정론 스크립트를 standalone 으로 부를 때 사용.
#   2) $CLAUDE_PROJECT_DIR — Claude Code 가 자동 주입하는 사용자 프로젝트 루트.
#   3) cwd 부터 ancestor 탐색 — .ax/ 디렉토리 가진 첫 조상.
find_project_root() {
    if [ -n "${GOAX_PROJECT_DIR:-}" ] && [ -d "$GOAX_PROJECT_DIR/.ax" ]; then
        printf '%s\n' "$GOAX_PROJECT_DIR"
        return 0
    fi
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
    goax_error "no .ax/ found in any ancestor of $(pwd) (GOAX_PROJECT_DIR=${GOAX_PROJECT_DIR:-unset}, CLAUDE_PROJECT_DIR=${CLAUDE_PROJECT_DIR:-unset})"
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

# JSON 에러 출력 + exit 1 — msg에 따옴표/역슬래시 있어도 jq로 안전 escape
json_error() {
    local msg="$1"
    local errors_json
    errors_json=$(_goax_json_array "$msg")
    json_output "error" "{}" "" "[]" "$errors_json"
    exit "$EXIT_ERROR"
}

# JSON skip 출력 + exit 2 (graceful degradation) — 동일하게 escape
json_skip() {
    local msg="$1"
    local warnings_json
    warnings_json=$(_goax_json_array "$msg")
    json_output "skipped" "{}" "$msg" "$warnings_json" "[]"
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
