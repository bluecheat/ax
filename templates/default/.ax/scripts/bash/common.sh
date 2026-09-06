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

# ─── 세션 내 중복 주입 제거 ─────────────────────────────────────────
# goax_inject_fresh <session_id> <key>
#   같은 세션에서 같은 포인터를 이미 주입했으면 1 (건너뛰어요), 아니면 마커를 찍고 0.
#   실측(statusface 프로젝트 한 세션): path-scoped 룰 포인터가 1,200회 주입 · 편집 파일은 196개 ·
#   주입 본문 529KB — 같은 룰 파일 경로가 편집마다 다시 들어갔어요. 서브에이전트 하나가 168회 받은 적도.
#   마커: .ax/.session/<sid>/injected/<key>. TTL GOAX_INJECT_TTL(기본 4시간) — compaction 뒤엔 다시 줄 여지.
#   세션 id 가 없으면(수동 실행·옛 런타임) 항상 0 — dedupe 없이 예전처럼 동작해요.
#   하루 넘은 세션 디렉토리는 지나가며 지워요.
goax_inject_fresh() {
    local sid="${1:-}" key="${2:-}" root ttl dir f now mt
    [ -n "$sid" ] && [ -n "$key" ] || return 0
    root="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
    sid=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9_-' '_')
    key=$(printf '%s' "$key" | tr -c 'A-Za-z0-9_.-' '_')
    ttl="${GOAX_INJECT_TTL:-14400}"
    dir="$root/.ax/.session/$sid/injected"
    mkdir -p "$dir" 2>/dev/null || return 0
    find "$root/.ax/.session" -mindepth 1 -maxdepth 1 -type d -mmin +1440 -exec rm -rf {} + 2>/dev/null || true
    f="$dir/$key"
    if [ -f "$f" ]; then
        now=$(date +%s); mt=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
        [ $((now - mt)) -lt "$ttl" ] && return 1
    fi
    : > "$f" 2>/dev/null || true
    return 0
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

# goax_glob_match <glob> <path>
#   `**` 를 이해하는 glob 매칭. 0 = 매치.
#   path-scoped 룰 주입(Layer 2 module / Spirit rules)이 공유해요 —
#   훅마다 따로 구현하면 같은 룰이 훅에 따라 다르게 매칭돼요.
#   python3 가 있으면 정확히, 없으면 보수적 substring 으로 degrade.
goax_glob_match() {
    local pattern="${1:-}" path="${2:-}"
    [ -z "$pattern" ] && return 1
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$pattern" "$path" <<'PYGLOB' 2>/dev/null
import sys, re
pattern, path = sys.argv[1], sys.argv[2]
def glob_to_regex(g):
    out, i, n = [], 0, len(g)
    while i < n:
        c = g[i]
        if c == '*':
            if i + 1 < n and g[i+1] == '*':
                out.append('.*'); i += 2
                if i < n and g[i] == '/': i += 1
                continue
            out.append('[^/]*')
        elif c == '?':
            out.append('[^/]')
        elif c in r'.+(){}[]|^$\\':
            out.append('\\' + c)
        else:
            out.append(c)
        i += 1
    return '^' + ''.join(out) + '$'
sys.exit(0 if re.match(glob_to_regex(pattern), path) else 1)
PYGLOB
        return $?
    fi
    # python3 없음 — `**/` 접두를 걷어낸 나머지로 substring 판정 (보수적)
    local tail="${pattern##*\*\*/}"
    case "$path" in *"$tail"*) return 0 ;; esac
    return 1
}

# goax_rules_matching <rules-dir> <rel-path>
#   frontmatter 의 `paths:` 글롭이 rel-path 에 매칭되는 룰 파일들의 상대 경로를 출력.
#   본문이 아니라 **경로만** 돌려줘요 (B-pointer) — 룰 전문을 컨텍스트에 밀어 넣으면
#   편집 한 번에 수천 토큰이 들어가고, 정작 필요 없는 룰까지 같이 들어와요.
goax_rules_matching() {
    local dir="${1:-}" rel="${2:-}" prefix="${3:-}" f glob
    [ -d "$dir" ] || return 0
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in README.md) continue ;; esac
        while IFS= read -r glob; do
            [ -z "$glob" ] && continue
            if goax_glob_match "$glob" "$rel"; then
                printf '%s%s\n' "$prefix" "$(basename "$f")"
                break
            fi
        done < <(goax_yaml_list "$f" paths)
    done
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
    local start="$dir"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.ax" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    # 4) `.goax-root` 포인터 — ADE 루트 ≠ 프로젝트 루트인 모노레포용.
    #    세션이 저장소 루트에서 시작하면 .ax/ 가 *하위* 에 있어서 조상 탐색으로는
    #    영영 못 찾아요 (.claude/skills 는 저장소 루트, .ax 는 projects/<app>/ 처럼).
    #    그래서 저장소 루트에 "하네스는 여기 있다" 를 적어둬요.
    dir="$start"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/.goax-root" ]; then
            local rel
            rel=$(grep -vE '^[[:space:]]*(#|$)' "$dir/.goax-root" 2>/dev/null | head -1 | tr -d '\r')
            rel="${rel#./}"; rel="${rel%/}"
            if [ -n "$rel" ] && [ -d "$dir/$rel/.ax" ]; then
                printf '%s\n' "$dir/$rel"
                return 0
            fi
            if [ -d "$dir/.ax" ]; then
                printf '%s\n' "$dir"
                return 0
            fi
        fi
        dir="$(dirname "$dir")"
    done

    goax_error "no .ax/ found in any ancestor of $(pwd), and no .goax-root pointer (GOAX_PROJECT_DIR=${GOAX_PROJECT_DIR:-unset}, CLAUDE_PROJECT_DIR=${CLAUDE_PROJECT_DIR:-unset})"
    return 1
}

# goax_ade_root [start]
#   ADE 루트 — 에이전트가 스킬을 찾는 곳 (.claude/ 가 있는 곳, 없으면 git 루트).
#   프로젝트 루트(.ax 가 있는 곳) 와 다를 수 있어요. 단일 저장소면 보통 같아요.
goax_ade_root() {
    local dir="${1:-$(pwd)}"
    local scan="$dir"
    while [ "$scan" != "/" ]; do
        [ -d "$scan/.claude" ] && { printf '%s\n' "$scan"; return 0; }
        scan="$(dirname "$scan")"
    done
    git -C "$dir" rev-parse --show-toplevel 2>/dev/null && return 0
    printf '%s\n' "$dir"
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
