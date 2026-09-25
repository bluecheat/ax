#!/usr/bin/env bash
# .ax/scripts/bash/common.sh — 공통 함수
# 다른 스크립트가 source 해서 사용. 직접 실행되지 않음.
#
# Usage:
#   source "$(dirname "$0")/common.sh"
#   PROJECT_ROOT=$(find_project_root) || exit 1

# 로케일 — 글롭·정규식의 문자 범위를 바이트 순서로 고정해요.
# en_US.UTF-8 collation 에서 `[a-z]` 는 대문자를 삼켜요 (정렬이 aAbB…zZ 라 `[a-z]` 가 `Z` 만
# 뺀 전부를 포함). 실측: `case "$x" in [a-z]*)` 검증이 `Payment` 를 통과시키고 뒤이은 `sed -E`
# 가 같은 값을 거부해서, config.yml 의 domain_risk 4개가 status: ok 인 채로 사라졌어요.
# 새 코드는 `[[:lower:]]`·`[[:upper:]]`·`[[:alnum:]]` 를 쓰고, 이 export 는 옛 브래킷의 안전망이에요.
export LC_COLLATE=C

# ─── awk 길이 상한 SSOT — GOAX_AWK_CLIP ──────────────────────────────
# awk 프로그램 앞에 `awk "$GOAX_AWK_CLIP"'…'` 로 붙이면 `clip(s, n)` 을 쓸 수 있어요.
#
# **길이 상한은 낱말 경계로만 적용해요. substr 로 바이트를 자르면 안 돼요.**
# macOS 기본 awk(BWK)는 바이트 단위라 한글 한 글자를 반으로 가르면 `towc: multibyte conversion failure` 로
# awk 가 통째로 죽어요 (build-memory 의 룰 목록이 조용히 사라졌어요). 공백은 UTF-8 연속 바이트가 될 수 없어서
# 공백에서만 끊으면 어느 awk 에서도 안 깨져요 (smoke §44).
# 첫 낱말이 이미 상한을 넘으면 자르지 않고 그대로 내보내요 — 깨진 출력보다 긴 출력이 나아요.
# 상한 n 은 length 의 단위를 따라가요 — BWK/mawk 는 바이트, gawk 는 문자라 같은 n 이어도 한글
# 프리뷰 길이가 플랫폼마다 달라요. 정확한 절단이 아니라 soft cap 이에요.
# 이 파일은 훅마다 source 돼요 (큰 세션이면 주입만 네 자릿수 번). 그래서 `$(cat <<EOF)` 가
# 아니라 fork 없는 순수 문자열 할당이에요. 본문에 작은따옴표를 쓰지 마세요.
GOAX_AWK_CLIP='
function clip(s, n,   nw, w, out, cand, i) {
    if (length(s) <= n) return s
    nw = split(s, w, " ")
    out = ""
    for (i = 1; i <= nw; i++) {
        cand = (out == "" ? w[i] : out " " w[i])
        if (length(cand) > n) break
        out = cand
    }
    if (out == "") return s
    sub(/[.]$/, "", out)
    return out " …"
}
'

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

# --help — 헤더 주석 블록(2행부터 첫 비-`#` 행 전까지)을 `# ` 벗겨서 그대로 찍어요.
#   예전엔 스크립트마다 `sed -n '2,NNp'` 로 줄 번호를 손으로 들고 있었는데, 헤더가 자라면 `Exit:` 계약 줄이
#   잘리고 줄면 `set -euo pipefail` 까지 찍혔어요 (실측 19/37 스크립트가 어긋나 있었어요). 줄 번호를 없애요.
# Usage: if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
goax_help() {
    awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$1"
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

# ─── 시크릿 패턴 SSOT ───────────────────────────────────────────────
# 시크릿의 형태를 아는 곳은 이 표 하나예요. 검출(grep)도 마스킹(sed)도 같은 행에서 나와요.
# 예전엔 훅이 자기 상수를, 여기가 자기 sed 를 따로 갖고 있어서 여덟 군데가 이미 서로 달라져 있었어요
# (AWS·GitHub·Stripe·PEM·JWT 정량자 · Slack 웹훅은 마스킹만 · key=value 는 키 이름까지).
#
#   goax_secret_rules()     표 자체. 한 행 = <use> TAB <label> TAB <ERE> TAB <sed 치환문>
#   goax_secret_patterns()  use=both|detect 행의 ERE 만 (검출용)
#   redact_secrets()        use=both|mask 행에서 sed 스크립트를 만들어 실행 (시그니처 불변)
#
# 행을 더할 때 지킬 것:
#   - ERE 는 grep -E 와 sed -E 양쪽에서 그대로 도는 POSIX ERE. `\s`·case-flag 금지, 소문자 단독
#     브래킷 범위 대신 `[[:lower:]]` (이 파일 위쪽 LC_COLLATE 주석 참고)
#   - ERE 에도 치환문에도 `#` 을 쓰지 마세요 — sed 구분자예요. 치환문의 `&` 도 금지 (전체 매치를 뜻해요)
#   - use=detect 행의 치환문은 `-` 고정. 다른 문자열을 두면 나중에 use 를 both 로 바꾸는 순간
#     그 문자열이 조용히 시크릿 자리에 들어가요
#   - 행 순서 = 적용 순서. 좁은 패턴이 위 (`sk-(ant|proj)-` 가 `sk-` 보다 위여야 라벨이 섞이지 않아요)
#   - 검출과 마스킹의 폭은 같게. 다르면 `check-mistake-secrets.sh` 와 `critical-rule-grep.sh` 가
#     같은 파일에 다른 답을 내요
#
# key=value 두 행이 공유하는 키 이름이에요. 두 행은 정량자와 캡처만 달라야 해서 조각을 하나로 둬요 —
# 이게 이 축의 드리프트(검출에만 `passwd`·`access_key`, 마스킹에만 `pg_key`)를 막는 유일한 장치예요.
# 대소문자는 브래킷으로 써요 (sed 에는 grep 의 `-i` 가 없어요).
_GOAX_SECRET_KV_KEYS='[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Aa][Cc][Cc][Ee][Ss][Ss][_-]?[Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Bb][Ee][Aa][Rr][Ee][Rr]|[Pp][Gg][_-]?[Kk][Ee][Yy]'

goax_secret_rules() {
    # 표는 인용 heredoc 이에요 — 행에 `\.`·`\1`·`$`·`%`·`{`·양쪽 따옴표가 다 들어가서 printf 나
    # 따옴표 없는 heredoc 은 그중 일부를 해석해 버려요. `@KV@` 만 위 조각으로 치환해요.
    cat <<'AXEOF' | sed "s#@KV@#${_GOAX_SECRET_KV_KEYS}#g"
both	aws	AKIA[0-9A-Z]{16,}	[REDACTED:aws]
both	github	gh[hoprsu]_[A-Za-z0-9]{20,}	[REDACTED:github]
both	github	github_pat_[A-Za-z0-9_]{20,}	[REDACTED:github]
both	llm-key	sk-(ant|proj)-[A-Za-z0-9_-]{20,}	[REDACTED:llm-key]
both	llm-key	sk-[A-Za-z0-9]{20,}	[REDACTED:llm-key]
both	google	AIza[0-9A-Za-z_-]{35}	[REDACTED:google]
both	npm	npm_[A-Za-z0-9]{30,}	[REDACTED:npm]
both	slack-webhook	https://hooks\.slack\.com/services/[A-Za-z0-9/+]{20,}	[REDACTED:slack-webhook]
both	slack	xox[abprs]-[A-Za-z0-9-]{10,}	[REDACTED:slack]
both	stripe	(sk|pk|rk)_live_[A-Za-z0-9]{16,}	[REDACTED:stripe]
both	stripe	whsec_[A-Za-z0-9]{20,}	[REDACTED:stripe]
both	jwt	eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}(\.[A-Za-z0-9_-]+)?	[REDACTED:jwt]
both	pem-begin	-----BEGIN[A-Z ]*PRIVATE KEY-----	[REDACTED:pem-begin]
detect	kv-detect	(@KV@)[[:space:]]*[:=][[:space:]]*['"]?[^[:space:]'"$<{%(][^[:space:]'"]{5,}	-
mask	kv-mask	(@KV@)([[:space:]]*[:=][[:space:]]*"?)([A-Za-z0-9+/=_-]{12,})	\1\2[REDACTED]
AXEOF
}

# 검출용 — use=both|detect 행의 ERE. 호출부는 `grep -E -e "$pat"` 로 쓰세요 (`-e` 필수: PEM 행이
# `-----` 로 시작해서 옵션으로 읽혀요).
goax_secret_patterns() {
    goax_secret_rules | awk -F'\t' '$1=="both"||$1=="detect"{print $3}'
}

# Redact secrets in stdin, print redacted to stdout.
# Strategy: known-prefix tokens (high confidence) + key=value with ≥12-char value (lower).
# Designed for init-mistake-file.sh / mistake skill DETAILS only — DO NOT apply to titles (signal loss).
# Usage: REDACTED=$(printf '%s' "$x" | redact_secrets)
redact_secrets() {
    local script
    script=$(goax_secret_rules | awk -F'\t' '$1=="both"||$1=="mask"{printf "s#%s#%s#g\n", $3, $4}')
    [ -n "$script" ] || { cat; return 0; }      # 표가 비면 통과 (sed -E "" 방지)
    sed -E "$script"
}

# ─── 세션 내 중복 주입 제거 ─────────────────────────────────────────
# goax_inject_fresh <session_id> <key>
#   같은 세션에서 같은 포인터를 이미 주입했으면 1 (건너뛰어요), 아니면 마커를 찍고 0.
#   실측(statusface 프로젝트 한 세션): path-scoped 룰 포인터가 1,200회 주입 · 편집 파일은 196개 ·
#   주입 본문 529KB — 같은 룰 파일 경로가 편집마다 다시 들어갔어요. 서브에이전트 하나가 168회 받은 적도.
#   마커: .ax/.session/<sid>/injected/<key>. TTL GOAX_INJECT_TTL(기본 4시간) — compaction 뒤엔 다시 줄 여지.
#   세션 id 가 없으면(수동 실행·옛 런타임) 항상 0 — dedupe 없이 예전처럼 동작해요.
#   하루 넘은 세션 디렉토리는 실행될 때 함께 지워요.
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
        now=$(date +%s); mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
        case "$mt" in ''|*[!0-9]*) mt=0 ;; esac   # GNU `stat -f` 는 실패해도 stdout 에 파일시스템 요약을 찍어요 — GNU 형식을 먼저
        [ $((now - mt)) -lt "$ttl" ] && return 1
    fi
    : > "$f" 2>/dev/null || true
    return 0
}

# ─── 세션 마커 — "이번 세션에 이미 했나" 를 파일로 기억해요 ──────────────
# goax_session_mark <sid> <ns> <key>     마커를 찍어요 (mtime 갱신)
# goax_session_marked <sid> <ns> <key>   TTL(GOAX_INJECT_TTL, 기본 4시간) 안에 찍힌 마커가 있으면 0
# goax_session_count <sid> <name>        세션 카운터를 1 올리고 새 값을 출력해요
#   위치: .ax/.session/<sid>/<ns>/<key>. goax_inject_fresh 와 같은 디렉토리 규칙이라 하루 넘은 세션은
#   그쪽이 실행될 때 함께 지워요. 세션 id 가 없으면 mark/count 는 아무것도 안 하고, marked 는 1(안 찍힘),
#   count 는 0 을 출력해요 — 호출자가 "추적 불가" 를 판단할 수 있게요.
# goax_session_dir <sid>  — .ax/.session/<sid> 절대 경로 (sid 는 파일 이름에 안전하게)
goax_session_dir() {
    local root sid
    root="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
    sid=$(printf '%s' "${1:-}" | tr -c '[:alnum:]_-' '_')
    printf '%s/.ax/.session/%s' "$root" "$sid"
}

_goax_session_path() {
    local sid="${1:-}" ns="${2:-}" key="${3:-}" root
    root="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
    sid=$(printf '%s' "$sid" | tr -c '[:alnum:]_-' '_')
    ns=$(printf '%s' "$ns" | tr -c '[:alnum:]_.-' '_')
    # 키는 읽을 수 있는 앞부분 + 원문 해시예요. 치환만 하면 한글 이름이 전부 `_` 가 돼서
    # `.ax/spirit/rules/결제.md` 와 `배송.md` 가 같은 마커가 됐어요 (하나만 읽어도 둘 다 읽은 걸로).
    local h; h=$(printf '%s' "$key" | cksum | awk '{print $1 "-" $2}')
    key=$(printf '%s' "$key" | tr -c '[:alnum:]_.-' '_' | cut -c1-60)
    printf '%s/.ax/.session/%s/%s/%s-%s' "$root" "$sid" "$ns" "$key" "$h"
}
goax_session_mark() {
    [ -n "${1:-}" ] && [ -n "${3:-}" ] || return 0
    local f; f=$(_goax_session_path "$1" "$2" "$3")
    mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
    : > "$f" 2>/dev/null || true
}
goax_session_marked() {
    [ -n "${1:-}" ] && [ -n "${3:-}" ] || return 1
    local f now mt ttl="${GOAX_INJECT_TTL:-14400}"
    f=$(_goax_session_path "$1" "$2" "$3")
    [ -f "$f" ] || return 1
    now=$(date +%s); mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
    [ $((now - mt)) -lt "$ttl" ]
}
goax_session_count() {
    [ -n "${1:-}" ] && [ -n "${2:-}" ] || { printf '0'; return 0; }
    local f n
    f=$(_goax_session_path "$1" counters "$2")
    mkdir -p "$(dirname "$f")" 2>/dev/null || { printf '0'; return 0; }
    n=$(cat "$f" 2>/dev/null || echo 0)
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    n=$((n + 1))
    printf '%s' "$n" > "$f" 2>/dev/null || true
    printf '%s' "$n"
}

# ─── 훅 프로필 · 끄기 — 게이트마다 탈출구가 있어야 해요 ──────────────────
# goax_hook_enabled <hook-id> <minimal|standard>
#   0 = 이 훅을 돌려요. hook-id 는 훅 파일 이름에서 `.sh` 를 뺀 것 (예: rule-read-gate).
#   두 번째 인자는 이 훅이 켜지는 **가장 낮은** 프로필이에요 — 안전망은 minimal, 주입·게이트는 standard.
#   끄는 법 (앞에 적은 것이 우선): GOAX_DISABLED_HOOKS=a,b · GOAX_HOOK_PROFILE=minimal · sensors.disabled_hooks · sensors.hook_profile.
#   키가 없는 옛 config 는 standard + 아무것도 안 끔 — 업데이트가 동작을 몰래 바꾸지 않아요.
#   CATASTROPHIC(루트 삭제 등)은 이 함수를 거치지 않아요 — 끌 수 있는 안전망이 아니에요.
goax_hook_profile() {
    local p="${GOAX_HOOK_PROFILE:-}" root config
    if [ -z "$p" ]; then
        root="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
        config="$root/.ax/config.yml"
        [ -f "$config" ] && p=$(grep -E '^[[:space:]]*hook_profile:' "$config" 2>/dev/null \
            | head -1 | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*#.*$//' | tr -d '"'"'"' ')
    fi
    case "$p" in minimal) printf 'minimal' ;; *) printf 'standard' ;; esac
}
goax_hook_enabled() {
    local id="${1:-}" min="${2:-standard}" root config
    [ -n "$id" ] || return 0
    case ",${GOAX_DISABLED_HOOKS:-}," in *",$id,"*) return 1 ;; esac
    root="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
    config="$root/.ax/config.yml"
    if [ -f "$config" ] && goax_yaml_list "$config" disabled_hooks | grep -qxF "$id"; then
        return 1
    fi
    [ "$min" = "minimal" ] && return 0
    [ "$(goax_hook_profile)" = "standard" ]
}

# ─── python3 가 실제로 도는지 — 있는 것 ≠ 도는 것 ─────────────────────────
# goax_py_ok   0 = python3 로 re·shlex 를 import 할 수 있어요. 한 프로세스 안에서는 결과를 기억해요.
#   `command -v python3` 만 보면 안 돼요 — macOS 의 /usr/bin/python3 는 xcrun shim 이라 Xcode CLT 가 없거나
#   샌드박스에서 막히면 **있는데 실패**해요. 그때 `2>/dev/null` 로 삼키면 판정 함수가 빈 결과를 내고 게이트가
#   전부 통과해요 (리뷰 실측: 가짜 python3 로 --no-verify · rm -rf · 룰 미독 편집이 셋 다 rc=0).
goax_py_ok() {
    if [ -z "${_GOAX_PY_OK:-}" ]; then
        if command -v python3 >/dev/null 2>&1 && python3 -c 'import re, shlex' >/dev/null 2>&1; then
            _GOAX_PY_OK=1
        else
            _GOAX_PY_OK=0
        fi
    fi
    [ "$_GOAX_PY_OK" = 1 ]
}

# ─── 셸 명령 스캔 — 따옴표·세미콜론·heredoc 을 셸처럼 읽어요 ─────────────
# goax_shell_scan <bypass|destructive> <project-root> [cwd]   (명령은 stdin)
#   출력: 걸린 것마다 한 줄 `<사유>`. 없으면 빈 출력. python3 가 없으면 exit 3 (호출자가 degrade).
#   bypass       에이전트가 git 훅을 끄는 형태 — `--no-verify` · `git commit -n` · `-c core.hooksPath=` ·
#                `git config core.hooksPath <값>` · `HUSKY=0`/`LEFTHOOK=0`
#   destructive  프로젝트 안에서 되돌리기 어려운 형태 — 재귀 rm(재생성 가능한 build·node_modules 등 제외,
#                프로젝트 밖 경로 제외) · `find -delete` · `git clean -f` · `git checkout -- <경로>`/`.`/`-f` ·
#                `git restore`(작업 트리) · `git reset --hard` · `git stash drop|clear` · `git branch -D`
#   정규식 한 줄로는 `git commit -m "fix -n handling"` 의 `-n` 을 플래그로 읽어요 — 그래서 토큰 단위로 봐요.
#   `sh -c '…'`·`bash -lc "…"` 안쪽도 한 번 더 읽고, heredoc 본문은 명령이 아니라 버려요.
#   값이 변수(`$X`)인 경로는 판단하지 않아요 — 사고 방지용 안전망이지 보안 경계가 아니에요.
goax_shell_scan() {
    local mode="${1:-}" root="${2:-}" cwd="${3:-}" cmd extra
    cmd=$(cat)
    goax_py_ok || return 3
    [ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$(pwd)"
    extra=$(goax_yaml_list "$root/.ax/config.yml" regenerable_paths 2>/dev/null || true)
    # 명령은 argv 로 넘겨요 — python 프로그램 자체가 heredoc(stdin) 으로 들어가서 stdin 은 비어 있어요.
    # python 이 도중에 죽으면(exit ≠ 0) 판정을 못 한 거예요 — 빈 결과(= 통과)가 아니라 3 으로 돌려서 호출자가 degrade 해요.
    ( cd "$cwd" 2>/dev/null && python3 - "$mode" "$root" "$cmd" "$extra" <<'PYSCAN'
import os, re, shlex, sys
mode = sys.argv[1]
root = os.path.realpath(sys.argv[2]) if sys.argv[2] else ""
raw = sys.argv[3]

def strip_comment(line, q):
    # 따옴표 밖, 낱말 첫머리의 `#` 부터 줄 끝이 주석이에요 (셸 규칙). `${#a}` 나 `a#b` 는 주석이 아니에요.
    # shlex 의 commenters 는 이걸 구분 못 하고 줄바꿈을 합친 뒤라 **명령 나머지 전부**를 먹어서 끄고 여기서 해요.
    # q 는 여러 줄에 걸친 따옴표 상태 (커밋 메시지 본문 같은 것).
    out, prev = [], " "
    i = 0
    while i < len(line):
        c = line[i]
        if q:
            if c == "\\" and q == "\"" and i + 1 < len(line):
                out.append(line[i:i+2]); i += 2; prev = "x"; continue
            if c == q:
                q = None
        elif c in "'\"":
            q = c
        elif c == "\\" and i + 1 < len(line):
            out.append(line[i:i+2]); i += 2; prev = "x"; continue
        elif c == "#" and (prev.isspace() or prev in ";&|("):
            break
        out.append(c); prev = c; i += 1
    return "".join(out), q

def strip_heredocs(s):
    out, delims, q = [], [], None
    for line in s.split("\n"):
        if delims:
            if line.strip().lstrip("\t") == delims[0]:
                delims.pop(0)
            continue
        line, q = strip_comment(line, q)
        out.append(line)
        # `<<<` 는 here-string 이라 끝 표지가 없어요 — heredoc 으로 읽으면 뒤 줄을 전부 버려요
        for m in re.finditer(r"(?<!<)<<(?!<)-?[ \t]*([\"']?)([A-Za-z_][A-Za-z0-9_]*)\1", line):
            delims.append(m.group(2))
    return "\n".join(out)

PUNCT = set(";&|()")
def segments(s):
    s = strip_heredocs(s).replace("\n", " ; ")
    lx = shlex.shlex(s, posix=True, punctuation_chars=";&|()")
    lx.whitespace_split = True
    lx.commenters = ""
    try:
        toks = list(lx)
    except ValueError:
        return None
    segs, cur = [], []
    for t in toks:
        if t and all(c in PUNCT for c in t):
            segs.append(cur); cur = []
        else:
            cur.append(t)
    segs.append(cur)
    return [x for x in segs if x]

WRAP = {"sudo", "env", "command", "exec", "nohup", "time", "nice", "xargs", "caffeinate"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
def unwrap(seg):
    env, i = {}, 0
    while i < len(seg):
        t = seg[i]
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", t)
        if m:
            env[m.group(1)] = m.group(2); i += 1; continue
        b = os.path.basename(t)
        if b in WRAP:
            i += 1
            while i < len(seg) and seg[i].startswith("-"):
                if b == "sudo" and seg[i] in ("-u", "-g", "-C", "-D", "-h", "-p", "-U"):
                    i += 1
                elif b == "xargs" and seg[i] in ("-n", "-I", "-L", "-P", "-s", "-d", "-E", "-a"):
                    i += 1
                i += 1
            continue
        break
    return env, seg[i:]

def inner_script(args):
    for k, a in enumerate(args):
        if a.startswith("-") and not a.startswith("--") and "c" in a[1:]:
            return args[k + 1] if k + 1 < len(args) else None
    return None

GIT_C = [None]   # 마지막 git_split 이 본 `-C <경로>`
GIT_OPT_NEXT = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
def git_split(args):
    cfg, i = [], 0
    GIT_C[0] = None
    while i < len(args):
        a = args[i]
        if a == "-C" and i + 1 < len(args):
            GIT_C[0] = args[i + 1]; i += 2; continue
        if a == "-c" or a == "--config-env":
            cfg.append(args[i + 1] if i + 1 < len(args) else ""); i += 2; continue
        if a.startswith("-c") and len(a) > 2 and not a.startswith("--"):
            cfg.append(a[2:]); i += 1; continue
        if a.startswith("--config-env="):
            cfg.append(a.split("=", 1)[1]); i += 1; continue
        if a in GIT_OPT_NEXT:
            i += 2; continue
        if a.startswith("-"):
            i += 1; continue
        return cfg, a, args[i + 1:]
    return cfg, None, []

NOVERIFY_SUBS = {"commit", "push", "merge", "cherry-pick", "rebase", "am", "pull"}
ARG_NEXT = {"-m", "-F", "-C", "-c", "-t", "-o", "--message", "--file", "--author", "--date",
            "--reuse-message", "--reedit-message", "--fixup", "--squash", "--template",
            "--trailer", "--cleanup", "--push-option", "--pathspec-from-file", "--strategy",
            "--strategy-option", "-s", "-X", "--onto", "--exec", "-x"}
COMMIT_ARG_SHORT = set("mFCctSu")

def hook_env_reason(env, git_cmd):
    # 훅 매니저마다 끄는 변수가 달라요 — husky(HUSKY=0, v4 HUSKY_SKIP_HOOKS) · lefthook(LEFTHOOK=0, LEFTHOOK_EXCLUDE) ·
    # pre-commit 프레임워크(SKIP=<훅id>). SKIP 은 흔한 이름이라 git 명령 앞에 붙었거나 export 될 때만 봐요.
    for k in ("HUSKY", "LEFTHOOK"):
        if env.get(k, "").lower() in ("0", "false"):
            return "%s=%s (프로젝트 git 훅 끄기)" % (k, env[k])
    for k in ("HUSKY_SKIP_HOOKS", "LEFTHOOK_EXCLUDE") + (("SKIP",) if git_cmd else ()):
        v = env.get(k, "")
        if v and v.lower() not in ("0", "false"):
            return "%s=%s (프로젝트 git 훅 건너뛰기)" % (k, v)
    return None

def bypass_seg(seg, depth):
    env, seg = unwrap(seg)
    if seg and seg[0] in ("export", "declare", "typeset"):
        ex = {}
        for a in seg[1:]:
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", a)
            if m:
                ex[m.group(1)] = m.group(2)
        return hook_env_reason(ex, True)
    r = hook_env_reason(env, bool(seg) and os.path.basename(seg[0]) == "git")
    if r:
        return r
    if not seg:
        return None
    b = os.path.basename(seg[0])
    if b in SHELLS and depth < 2:
        sc = inner_script(seg[1:])
        return scan(sc, depth + 1) if sc else None
    if b != "git":
        return None
    cfg, sub, rest = git_split(seg[1:])
    for c in cfg:
        if c.lower().startswith("core.hookspath"):
            return "git -c %s (훅 경로 바꿔치기)" % c
    if sub == "config":
        low = [a.lower() for a in rest]
        if "core.hookspath" in low:
            k = low.index("core.hookspath")
            vals = [a for a in rest[k + 1:] if not a.startswith("-")]
            if vals:
                return "git config core.hooksPath %s (훅 경로 바꿔치기)" % vals[0]
        return None
    if sub not in NOVERIFY_SUBS:
        return None
    j = 0
    while j < len(rest):
        a = rest[j]
        if a == "--":
            break
        if a == "--no-verify":
            return "git %s --no-verify" % sub
        if a in ARG_NEXT:
            j += 2; continue
        if sub == "commit" and re.match(r"^-[A-Za-z]+$", a):
            for ch in a[1:]:
                if ch == "n":
                    return "git commit -n (--no-verify 의 짧은 형태)"
                if ch in COMMIT_ARG_SHORT:
                    break
        j += 1
    return None

# 지워도 도구가 다시 만드는 디렉토리 — 스택을 가정하지 않으려고 여러 생태계의 흔한 이름을 **기본값**으로만 둬요.
# 프로젝트는 .ax/config.yml sensors.regenerable_paths 글롭으로 넓혀요 (argv[4], 줄바꿈 구분).
REGEN = {
    # JS/TS
    "node_modules", "bower_components", ".pnpm-store", ".next", ".nuxt", ".output", ".svelte-kit", ".angular",
    ".expo", ".parcel-cache", ".turbo", ".vercel", ".netlify", ".docusaurus", "storybook-static", ".nyc_output",
    # JVM · 네이티브 · 모바일
    "build", "out", "target", ".gradle", ".kotlin", ".build", "DerivedData", "Pods", ".dart_tool", ".cxx",
    # Python
    "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox", ".nox", ".venv", "venv", ".eggs",
    # 공통
    "dist", "coverage", ".cache", ".terraform", ".serverless", ".aws-sam", ".session",
}
REGEN_SUFFIX = (".egg-info",)
REGEN_PREFIX = ("cmake-build-",)
def glob_rx(g):
    out, i, n = [], 0, len(g)
    while i < n:
        c = g[i]
        if c == "*":
            if i + 1 < n and g[i + 1] == "*":
                out.append(".*"); i += 2
                if i < n and g[i] == "/": i += 1
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        elif c in ".+(){}[]|^$\\":
            out.append("\\" + c)
        else:
            out.append(c)
        i += 1
    return re.compile("^" + "".join(out) + "(/.*)?$")
EXTRA = [glob_rx(g.strip().rstrip("/")) for g in (sys.argv[4] if len(sys.argv) > 4 else "").split("\n") if g.strip()]
def regenerable(parts):
    if any(x in REGEN or x.endswith(REGEN_SUFFIX) or x.startswith(REGEN_PREFIX) for x in parts):
        return True
    rel = "/".join(parts)
    return any(rx.match(rel) for rx in EXTRA)

CWD = [os.getcwd()]   # `cd x && rm -rf ../y` 처럼 앞 세그먼트의 cd 를 따라가요
def risky_path(t):
    if "$" in t or "`" in t:
        return False
    p = os.path.expanduser(t)
    ab = os.path.realpath(os.path.join(CWD[0], p))
    if root and not (ab == root or ab.startswith(root + os.sep)):
        return False
    rel = os.path.relpath(ab, root) if root else ab
    parts = [x for x in rel.split(os.sep) if x not in ("", ".")]
    if regenerable(parts):
        return False
    return True

def destructive_seg(seg, depth, piped_in):
    env, seg = unwrap(seg)
    if not seg:
        return None
    b = os.path.basename(seg[0])
    args = seg[1:]
    if b == "cd":
        dest = args[0] if args else os.path.expanduser("~")
        if "$" not in dest and "`" not in dest and dest != "-":
            CWD[0] = os.path.realpath(os.path.join(CWD[0], os.path.expanduser(dest)))
        return None
    if b in SHELLS and depth < 2:
        sc = inner_script(args)
        return scan(sc, depth + 1) if sc else None
    if b == "rm":
        rec, targets, opts, skip = False, [], True, False
        for a in args:
            if skip:
                skip = False; continue
            if re.match(r"^[0-9]*(>|>>|<|&>|>&)$", a):      # `> out.log` — 다음 토큰은 리다이렉션 대상
                skip = True; continue
            if ">" in a or "<" in a:                         # `2>/dev/null`, `2>` (`2>&1` 의 앞 조각)
                continue
            if opts and a == "--":
                opts = False; continue
            if opts and a.startswith("--"):
                rec = rec or a == "--recursive"; continue
            if opts and a.startswith("-") and len(a) > 1:
                rec = rec or "r" in a[1:] or "R" in a[1:]; continue
            targets.append(a)
        if not rec:
            return None
        if not targets:
            return "재귀 rm — 대상이 파이프로 들어와 알 수 없어요" if piped_in else None
        hit = [t for t in targets if risky_path(t)]
        return "재귀 rm: %s" % " ".join(hit) if hit else None
    if b == "find" and ("-delete" in args or any(a == "-exec" and k + 1 < len(args) and os.path.basename(args[k + 1]) == "rm"
                                                 for k, a in enumerate(args))):
        starts = []
        for a in args:
            if a.startswith("-") or a in ("(", "!"):
                break
            starts.append(a)
        hit = [t for t in (starts or ["."]) if risky_path(t)]
        return "find 로 대량 삭제: %s" % " ".join(hit) if hit else None
    if b != "git":
        return None
    _, sub, rest = git_split(args)
    gdir = CWD[0]
    if GIT_C[0]:
        if "$" in GIT_C[0] or "`" in GIT_C[0]:
            return None
        gdir = os.path.realpath(os.path.join(CWD[0], os.path.expanduser(GIT_C[0])))
        if root and not (gdir == root or gdir.startswith(root + os.sep)):
            return None                                  # 다른 리포 — 이 프로젝트의 일이 아니에요
    shorts = "".join(a[1:] for a in rest if re.match(r"^-[A-Za-z]+$", a))
    if sub == "clean":
        if "n" in shorts or "--dry-run" in rest:
            return None
        if "f" in shorts or "--force" in rest:
            return "git clean -f — 추적 안 되는 파일 삭제 (복구 불가)"
        return None
    if sub == "checkout":
        if "--" in rest and rest.index("--") + 1 < len(rest):
            return "git checkout -- <경로> — 작업 트리 변경 폐기"
        if "." in rest:
            return "git checkout . — 작업 트리 변경 폐기"
        if "f" in shorts or "--force" in rest:
            return "git checkout -f — 작업 트리 변경 폐기"
        # `git checkout <파일>` — `--` 없이도 실제 경로면 그 파일의 변경을 버려요 (브랜치 이름과는 경로 존재로 가려요)
        for a in rest:
            if not a.startswith("-") and os.path.exists(os.path.join(gdir, a)):
                return "git checkout <경로> — 작업 트리 변경 폐기"
        return None
    if sub == "switch" and ("f" in shorts or "--force" in rest or "--discard-changes" in rest):
        return "git switch -f — 작업 트리 변경 폐기"
    if sub == "worktree" and rest[:1] == ["remove"] and ("f" in shorts or "--force" in rest):
        return "git worktree remove --force — 워크트리의 커밋 안 된 변경 폐기"
    if sub == "restore":
        staged = "--staged" in rest or "S" in shorts
        worktree = "--worktree" in rest or "W" in shorts
        if worktree or not staged:
            return "git restore — 작업 트리 변경 폐기"
        return None
    if sub == "reset" and "--hard" in rest:
        return "git reset --hard — 커밋 안 된 변경 폐기"
    if sub == "stash" and rest and rest[0] in ("drop", "clear"):
        return "git stash %s — 스태시 삭제" % rest[0]
    if sub == "branch" and ("D" in shorts or ("--delete" in rest and ("--force" in rest or "f" in shorts))):
        return "git branch -D — 머지 안 된 브랜치 삭제"
    return None

def scan(s, depth=0):
    segs = segments(s)
    if segs is None:
        return None
    hits = []
    for k, seg in enumerate(segs):
        if mode == "bypass":
            r = bypass_seg(seg, depth)
        else:
            r = destructive_seg(seg, depth, k > 0)
        if r:
            if depth > 0:
                return r
            hits.append(r)
    return hits if depth == 0 else None

res = scan(raw)
for h in (res or []):
    print(h)
PYSCAN
    ) || return 3
    return 0
}

# ─── 임시 파일 — 인프라 실패가 초록불이 되지 않게 ──────────────────────
# goax_mktemp [-d] [root]
#   `mktemp` 가 실패하면 <root>/.ax/.session/tmp/ 아래로 폴백하고, 그것도 안 되면 1 을 돌려줘요.
#   호출자는 `X=$(goax_mktemp "$ROOT") || { goax_tmp_error; exit "$EXIT_ERROR"; }` 로 받아야 해요 — 빈 경로로
#   계속 가면 "룰 0건 검사 → all invariants pass" 가 돼요. 이 함수는 `$(...)` 안에서 불리니 사유는 stderr 에만
#   적고 (stdout 에 쓰면 변수로 삼켜져요) JSON 에러 한 줄은 호출자의 goax_error 가 내요. 실측(claude plugin eval 샌드박스, $TMPDIR 쓰기 금지):
#   check-rule-enforcement.sh 가 룰을 하나도 안 읽고 통과를 찍었어요. `-d` 는 디렉토리.
#   폴백 디렉토리는 `.ax/.session/` 아래라 .gitignore.template 이 이미 가리고, 하루 넘은 세션
#   디렉토리와 같이 goax_inject_fresh 가 실행될 때 함께 지워요.
goax_mktemp() {
    local dflag="" root fb out
    if [ "${1:-}" = "-d" ]; then dflag="-d"; shift; fi
    root="${1:-${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}}"
    # shellcheck disable=SC2086  # dflag 는 비었거나 -d
    if out=$(mktemp $dflag 2>/dev/null) && [ -n "$out" ]; then
        printf '%s\n' "$out"; return 0
    fi
    fb="$root/.ax/.session/tmp"
    if ! mkdir -p "$fb" 2>/dev/null; then
        printf '[goax] ERROR: 임시 파일을 못 만들어요 — mktemp 가 실패했고 (TMPDIR=%s) %s 도 만들 수 없어요\n' "${TMPDIR:-unset}" "$fb" >&2
        return 1
    fi
    # shellcheck disable=SC2086
    if out=$(mktemp $dflag "$fb/goax.XXXXXX" 2>/dev/null) && [ -n "$out" ]; then
        printf '%s\n' "$out"; return 0
    fi
    # mktemp 바이너리 자체가 없거나 템플릿을 거부하는 환경 — 순수 bash 로 마지막 시도.
    # mktemp 의 0600 을 흉내내려고 umask 077 로 만들어요 (프로젝트 트리 안이라 노출은 작지만 같은 계약을 지켜요)
    out="$fb/goax.$$.$RANDOM"
    if [ -n "$dflag" ]; then
        ( umask 077; mkdir "$out" ) 2>/dev/null && { printf '%s\n' "$out"; return 0; }
    else
        ( umask 077; set -o noclobber; : > "$out" ) 2>/dev/null && { printf '%s\n' "$out"; return 0; }
    fi
    printf '[goax] ERROR: 임시 파일을 못 만들어요 — mktemp 가 실패했고 (TMPDIR=%s) %s 에 쓸 수 없어요\n' "${TMPDIR:-unset}" "$fb" >&2
    return 1
}

# goax_tmp_error — goax_mktemp 실패 시 호출자가 내는 한 줄 (JSON 모드면 errors[], 아니면 stderr). exit 는 호출자가 해요:
#   X=$(goax_mktemp "$ROOT") || { goax_tmp_error; exit "$EXIT_ERROR"; }
# 헬퍼 안에서 exit 하면 안 돼요 — `$(...)` 서브셸만 끝나고 호출자는 빈 경로로 계속 가요 (그게 원래 버그예요).
goax_tmp_error() {
    goax_error "임시 파일을 못 만들어요 — mktemp 도 .ax/.session/tmp 도 실패했어요 (자세한 건 stderr 을 봐요)"
}

# ─── git hook 경로 — git 이 못 돌 때도 파일로 해석 ───────────────────────
# goax_git_hook_path <root> <hook>
#   `git rev-parse --git-path hooks/<hook>` (core.hooksPath · worktree · 별도 gitdir 반영) 을 먼저 쓰고,
#   git 이 실패하면 `.git` (디렉토리 또는 `gitdir:` 포인터 파일) 과 `.git/config` 의 `core.hooksPath` 를
#   직접 읽어요. 실측(claude plugin eval 샌드박스): `/usr/bin/git` xcrun 셔틀이 $TMPDIR 캐시를 못 써서
#   죽고, check-sensor-liveness C2 가 "pre-commit 미설치" 오탐 · check-rule-enforcement I6 가 프로젝트 훅을
#   못 봤어요. 절대경로를 출력하고, 저장소가 아니면 1. 존재 여부는 호출자가 봐요 (-f · -x).
goax_git_hook_path() {
    local root="$1" hook="$2" p gitdir hp common
    p=$(git -C "$root" rev-parse --git-path "hooks/$hook" 2>/dev/null) || p=""
    if [ -n "$p" ]; then
        case "$p" in /*) ;; *) p="$root/$p" ;; esac
        printf '%s\n' "$p"; return 0
    fi
    gitdir=""
    if [ -d "$root/.git" ]; then
        gitdir="$root/.git"
    elif [ -f "$root/.git" ]; then
        gitdir=$(sed -n 's/^gitdir:[[:space:]]*//p' "$root/.git" 2>/dev/null | head -1 | tr -d '\r')
        case "$gitdir" in ""|/*) ;; *) gitdir="$root/$gitdir" ;; esac
    fi
    [ -n "$gitdir" ] && [ -d "$gitdir" ] || return 1
    # linked worktree (`git worktree add`) 의 gitdir 은 .git/worktrees/<name> 이고 config 도 hooks 도 거기 없어요 —
    # `commondir` 파일이 공용 .git 을 가리켜요 (gitdir 기준 상대경로)
    if [ -f "$gitdir/commondir" ]; then
        common=$(head -1 "$gitdir/commondir" 2>/dev/null | tr -d '\r')
        case "$common" in ""|/*) ;; *) common="$gitdir/$common" ;; esac
        # `../..` 를 접어요 — 안 접으면 .git/worktrees/<name>/../../hooks 처럼 나가 비교가 깨져요
        [ -n "$common" ] && [ -d "$common" ] && gitdir=$(cd "$common" 2>/dev/null && pwd) || true
    fi
    # [core] 섹션의 hooksPath 만 — 로컬 config 뿐이에요 (global 은 git 이 살아 있을 때 위 경로가 봐요).
    # git 처럼 `#`/`;` 주석과 둘러싼 큰따옴표를 떼어요 — 안 떼면 C2·I6 가 훅을 못 찾아요.
    hp=$(awk '
        /^[[:space:]]*\[/ { core = (tolower($0) ~ /^[[:space:]]*\[core\]/); next }   # 섹션 이름은 대소문자 무시 (git 과 같게)
        core && /^[[:space:]]*hooksPath[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*[#;].*$/, ""); sub(/[[:space:]]+$/, "")
            if (substr($0, 1, 1) == "\"" && substr($0, length($0), 1) == "\"" && length($0) >= 2) $0 = substr($0, 2, length($0) - 2)
            print; exit
        }
    ' "$gitdir/config" 2>/dev/null)
    if [ -n "$hp" ]; then
        case "$hp" in
            /*) ;;
            "~/"*) hp="$HOME/${hp#\~/}" ;;
            *) hp="$root/$hp" ;;   # 상대경로는 워킹트리 루트 기준 (git 문서)
        esac
        printf '%s/%s\n' "$hp" "$hook"
    else
        printf '%s/hooks/%s\n' "$gitdir" "$hook"
    fi
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
                # 따옴표 한 쌍만 떼어요 — 끝 따옴표를 전부 지우면 `eslint --rule "x"` 가 `… "x` 로 깨져요.
                # 따옴표 값 뒤의 ` # 주석` 은 버리고, 맨 값은 ` #` 부터가 주석이에요 (YAML 과 같아요).
                q = substr(v, 1, 1)
                if (q == "\042" || q == "\047") {
                    e = length(v); while (e > 1 && substr(v, e, 1) != q) e--
                    if (e > 1) v = substr(v, 2, e - 2)
                } else sub(/[ \t]+#.*$/, "", v)
                if (v != "") print v
                next
            }
            if (i <= keyind) inlist = 0
        }
    ' "$file"
}

# _goax_yaml_list_multi <key> <file>...
#   goax_yaml_list 와 같은 규칙을 **awk 한 번**으로 여러 파일에 돌려요. 출력: `<file>\t<value>`.
#   룰 파일마다 goax_yaml_list 를 부르면 awk 가 파일 수만큼 떠요 — 모든 Edit/Read 에 걸리는 훅이라
#   룰 40개 + 모듈 10개에서 편집 한 번에 0.85초였어요 (리뷰 실측).
_goax_yaml_list_multi() {
    local key="${1:-}"; shift
    [ $# -gt 0 ] || return 0
    awk -v key="$key" '
        function ind(s,   i) { if (s ~ /^[ \t]*$/) return -1; i = match(s, /[^ \t]/); return i - 1 }
        FNR == 1 { inlist = 0; keyind = -1 }
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
                        if (v != "") print FILENAME "\t" v
                    }
                }
                next
            }
            if (i > keyind && t ~ /^[ \t]*-[ \t]+/) {
                v = t; sub(/^[ \t]*-[ \t]+/, "", v)
                sub(/[ \t]+$/, "", v)
                # 따옴표 한 쌍만 떼어요 — 끝 따옴표를 전부 지우면 `eslint --rule "x"` 가 `… "x` 로 깨져요.
                # 따옴표 값 뒤의 ` # 주석` 은 버리고, 맨 값은 ` #` 부터가 주석이에요 (YAML 과 같아요).
                q = substr(v, 1, 1)
                if (q == "\042" || q == "\047") {
                    e = length(v); while (e > 1 && substr(v, e, 1) != q) e--
                    if (e > 1) v = substr(v, 2, e - 2)
                } else sub(/[ \t]+#.*$/, "", v)
                if (v != "") print FILENAME "\t" v
                next
            }
            if (i <= keyind) inlist = 0
        }
    ' "$@"
}

# goax_glob_match <glob> <path>
#   `**` 를 이해하는 glob 매칭. 0 = 매치.
#   path-scoped 룰 주입(Layer 2 module / Spirit rules)이 공유해요 —
#   훅마다 따로 구현하면 같은 룰이 훅에 따라 다르게 매칭돼요.
#   python3 가 있으면 정확히, 없으면 보수적 substring 으로 degrade.
goax_glob_match() {
    local pattern="${1:-}" path="${2:-}"
    [ -z "$pattern" ] && return 1
    if goax_py_ok; then
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
    # python3 없음 — 셸 case 글롭으로 먼저 봐요 (case 의 `*` 는 `/` 도 넘어서 `**/*.kt` 가 `src/a.kt` 에 맞아요).
    # 예전엔 substring 만 봐서 `**/*.kt` 를 글자 그대로 `*.kt` 로 찾다가 lint_file · quality_configs 가 조용히 꺼졌어요 (리뷰 실측).
    # shellcheck disable=SC2254
    case "$path" in $pattern) return 0 ;; esac
    # 그다음 `**/` 접두를 걷어낸 나머지로 substring 판정 (보수적)
    local tail="${pattern##*\*\*/}"
    case "$path" in *"$tail"*) return 0 ;; esac
    return 1
}

# goax_rules_matching <rules-dir> <rel-path>
#   frontmatter 의 `paths:` 글롭이 rel-path 에 매칭되는 룰 파일들의 상대 경로를 출력.
#   본문이 아니라 **경로만** 돌려줘요 (B-pointer) — 룰 전문을 컨텍스트에 밀어 넣으면
#   편집 한 번에 수천 토큰이 들어가고, 정작 필요 없는 룰까지 같이 들어와요.
goax_rules_matching() {
    local dir="${1:-}" rel="${2:-}" prefix="${3:-}" f
    [ -d "$dir" ] || return 0
    local files=()
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in README.md) continue ;; esac
        files+=("$f")
    done
    [ ${#files[@]} -gt 0 ] || return 0
    _goax_yaml_list_multi paths "${files[@]}" \
        | awk -F '\t' -v p="$prefix" '{ n = $1; sub(/.*\//, "", n); print p n "\t" $2 }' \
        | goax_glob_owners "$rel"
}

# goax_module_rules_matching <project-root> <rel-path>
#   `.ax/modules/<name>/rules.md` 중 `paths:` 가 rel-path 에 매칭되는 모듈 이름을 출력해요.
#   `applies_to` 에 `code` 가 없으면 편집 대상이 아니라 빼요 (pr/commit/review 전용 룰). 필드가 아예 없으면
#   하위호환으로 포함. module-rules-inject.sh(주입)와 rule-read-gate.sh(게이트)가 같이 써요 —
#   둘이 따로 매칭하면 "주입은 했는데 게이트는 안 거는" 룰이 생겨요.
goax_module_rules_matching() {
    local root="${1:-}" rel="${2:-}" f excl
    [ -d "$root/.ax/modules" ] || return 0
    local files=()
    for f in "$root"/.ax/modules/*/rules.md; do
        [ -f "$f" ] && files+=("$f")
    done
    [ ${#files[@]} -gt 0 ] || return 0
    # applies_to 가 있는데 code 가 없는 파일은 빼요 (없으면 하위호환으로 포함)
    excl=$(_goax_yaml_list_multi applies_to "${files[@]}" \
        | awk -F '\t' '{ has[$1] = 1; if ($2 == "code") code[$1] = 1 } END { for (f in has) if (!(f in code)) print f }')
    _goax_yaml_list_multi paths "${files[@]}" \
        | GOAX_EXCL="$excl" awk -F '\t' '
            BEGIN { n = split(ENVIRON["GOAX_EXCL"], E, "\n"); for (i = 1; i <= n; i++) if (E[i] != "") X[E[i]] = 1 }
            !($1 in X) { m = $1; sub(/\/rules\.md$/, "", m); sub(/.*\//, "", m); print m "\t" $2 }' \
        | goax_glob_owners "$rel"
}

# goax_imported_paths <project-root>
#   CLAUDE.md · AGENTS.md 가 `@<경로>` 로 import 하는 파일의 프로젝트 기준 상대 경로를 출력해요.
#   이 파일들은 세션 시작부터 컨텍스트에 있어서 "Read 했나" 를 따질 필요가 없어요 (rule-read-gate).
goax_imported_paths() {
    local root="${1:-}" f
    for f in "$root/CLAUDE.md" "$root/AGENTS.md"; do
        [ -f "$f" ] || continue
        sed -nE 's#^@(\./)?([^[:space:]]+)[[:space:]]*$#\2#p' "$f"
    done | sort -u
}

# ─── 룰 패턴 — 룰 파일의 `<!-- 검출 패턴: <ERE> -->` 를 기계가 읽어요 ──────────
# goax_rule_patterns <rule-file>
#   출력: TSV `SP-<CAT>-<NNN>\t<ERE>` — 마커 한 줄에 한 행, 파일 순서대로.
#   `## SP-<CAT>-<NNN>:` 헤더가 현재 룰이고, 그 아래 `<!-- 검출 패턴: X -->` 의 X 가 패턴이에요
#   (`검출 패턴:` 뒤 공백부터 ` -->` 앞까지, 앞뒤 공백 trim, 따옴표 없음). `<regex>`·`<ERE>` 처럼
#   `<…>` 로만 된 값은 자리표시자라 버려요. frontmatter 와 코드펜스(```·~~~) 안은 안 봐요 — 출고 템플릿이 사용법을 펜스 안에 적어요.
#   헤더 앞에 나온 마커는 귀속할 룰이 없어서 버려요.
#
#   이 마커는 오래전부터 두 템플릿에 있었지만 읽는 쪽이 없어서 장식이었어요 —
#   `critical-rule-grep.sh` 가 이걸로 staged 파일을 검사하고, `zero-probe.sh` 가
#   ❌/✅ 예시로 패턴 자체를 검증해요. 같은 마커를 두 곳이 따로 파싱하면 갈라져요 — 여기 하나예요.
goax_rule_patterns() {
    local file="${1:-}"
    [ -f "$file" ] || return 0
    awk '
        BEGIN { fm=0; fmdone=0; fence=0; tok="" }
        NR==1 && /^---[[:space:]]*$/ { fm=1; next }
        fm==1 { if (/^---[[:space:]]*$/) { fm=0; fmdone=1 } next }
        /^[[:space:]]*(```|~~~)/ { fence=!fence; next }
        fence { next }
        /^## SP-[[:upper:][:digit:]]+-[[:digit:]]+:/ {
            tok=$0; sub(/^## /, "", tok); sub(/:.*$/, "", tok); next
        }
        /^[[:space:]]*<!--[[:space:]]*검출 패턴:/ {
            if (tok == "") next
            pat=$0
            sub(/^[[:space:]]*<!--[[:space:]]*검출 패턴:[[:space:]]*/, "", pat)
            sub(/[[:space:]]*-->[[:space:]]*$/, "", pat)
            if (pat == "" || pat ~ /^<[^>]*>$/) next    # `<regex>`·`<ERE>` 같은 자리표시자는 패턴이 아니에요
            printf "%s\t%s\n", tok, pat
        }
    ' "$file"
}

# goax_rule_examples <rule-file>
#   출력: TSV `SP-<CAT>-<NNN>\t<bad|good>\t<예시 텍스트>`.
#   룰 본문의 `❌ …`/`✅ …` 줄(템플릿 형식)과 `- 위반 예: …`/`- 대안: …` 줄(audit 승격 형식)을 읽어요.
#   백틱 span 이 있으면 span 마다 한 행(위반 예를 여러 개 나열하는 형식), 없으면 줄 전체가 한 행이에요.
#   `zero-probe.sh` 의 pattern-rules 프로브가 "❌ 는 걸리고 ✅ 는 안 걸린다" 를 재는 데 써요.
goax_rule_examples() {
    local file="${1:-}"
    [ -f "$file" ] || return 0
    awk '
        function emit(kind, text,   n, i, parts, s) {
            if (tok == "") return
            n = split(text, parts, "`")
            if (n >= 3) {
                for (i = 2; i <= n; i += 2) { s = parts[i]; if (s != "") printf "%s\t%s\t%s\n", tok, kind, s }
                return
            }
            sub(/^[[:space:]]+|[[:space:]]+$/, "", text)
            if (text != "" && text !~ /^<.*>$/) printf "%s\t%s\t%s\n", tok, kind, text
        }
        BEGIN { fm=0; fence=0; tok="" }
        NR==1 && /^---[[:space:]]*$/ { fm=1; next }
        fm==1 { if (/^---[[:space:]]*$/) fm=0; next }
        /^[[:space:]]*(```|~~~)/ { fence=!fence; next }
        fence { next }
        /^## SP-[[:upper:][:digit:]]+-[[:digit:]]+:/ { tok=$0; sub(/^## /, "", tok); sub(/:.*$/, "", tok); next }
        /^[[:space:]]*❌/            { t=$0; sub(/^[[:space:]]*❌[[:space:]]*/, "", t); emit("bad", t); next }
        /^[[:space:]]*✅/            { t=$0; sub(/^[[:space:]]*✅[[:space:]]*/, "", t); emit("good", t); next }
        /^[[:space:]]*-[[:space:]]*위반 예:/ { t=$0; sub(/^[[:space:]]*-[[:space:]]*위반 예:[[:space:]]*/, "", t); emit("bad", t); next }
        /^[[:space:]]*-[[:space:]]*대안:/    { t=$0; sub(/^[[:space:]]*-[[:space:]]*대안:[[:space:]]*/, "", t); emit("good", t); next }
    ' "$file"
}

# goax_frontmatter_scalar <file> <key>
#   frontmatter 의 스칼라 값 하나 (따옴표·인라인 주석 제거). 없으면 빈 문자열.
#   `severity:` 처럼 파일 단위 메타를 읽을 때 써요 — 배열은 goax_yaml_list.
goax_frontmatter_scalar() {
    local file="${1:-}" key="${2:-}"
    [ -f "$file" ] || return 0
    awk -v key="$key" '
        BEGIN { c=0 }
        /^---[[:space:]]*$/ { c++; if (c==2) exit; next }
        c==1 && $0 ~ ("^" key ":") {
            v=$0; sub("^" key ":[[:space:]]*", "", v)
            sub(/(^|[[:space:]])#.*$/, "", v)
            gsub(/^[[:space:]\042\047]+|[[:space:]\042\047]+$/, "", v)
            print v; exit
        }
    ' "$file"
}

# goax_glob_owners <path>
#   stdin `<label>\t<glob>` 줄 중 glob 이 path 에 맞는 label 을 처음 나온 순서대로 한 번씩 출력.
#   goax_glob_filter 의 반대 방향(경로 하나 × 글롭 여럿)이고 규칙은 goax_glob_match 와 같아요.
#   python 을 **한 번만** 띄워요 — 글롭마다 goax_glob_match 를 부르면 룰 41개짜리 프로젝트(commerce 실측)에서
#   편집 한 번에 2초가 걸렸어요. 모든 Edit/Read 에 걸리는 훅이라 그대로 두면 세션이 느려져요.
#   python3 가 없으면 goax_glob_match 의 substring degrade 를 줄마다 써요.
goax_glob_owners() {
    local path="${1:-}" label glob
    if goax_py_ok; then
        python3 -c '
import sys, re
path = sys.argv[1]
def glob_to_regex(g):
    out, i, n = [], 0, len(g)
    while i < n:
        c = g[i]
        if c == "*":
            if i + 1 < n and g[i+1] == "*":
                out.append(".*"); i += 2
                if i < n and g[i] == "/": i += 1
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        elif c in ".+(){}[]|^$\\":
            out.append("\\" + c)
        else:
            out.append(c)
        i += 1
    return "^" + "".join(out) + "$"
seen = set()
for line in sys.stdin:
    line = line.rstrip("\n")
    if "\t" not in line:
        continue
    label, glob = line.split("\t", 1)
    if not glob or label in seen:
        continue
    if re.match(glob_to_regex(glob), path):
        seen.add(label); print(label)
' "$path" 2>/dev/null
        return 0
    fi
    local seen=""
    while IFS="$(printf '\t')" read -r label glob; do
        [ -n "$glob" ] || continue
        case " $seen " in *" $label "*) continue ;; esac
        goax_glob_match "$glob" "$path" && { printf '%s\n' "$label"; seen="$seen $label"; }
    done
}

# goax_glob_filter <glob>
#   stdin 의 경로 목록에서 glob 에 맞는 것만 출력. `goax_glob_match` 와 같은 규칙인데
#   python 을 **한 번만** 띄워요 — staged 50개 × 룰 10개를 경로마다 호출하면 프로세스 500개예요.
#   python3 가 없으면 goax_glob_match 와 같은 substring degrade.
goax_glob_filter() {
    local pattern="${1:-}"
    [ -z "$pattern" ] && return 0
    if goax_py_ok; then
        # 스크립트는 -c 로 줘요 — heredoc 으로 주면 그게 stdin 을 차지해서 경로 목록이 안 들어와요.
        python3 -c '
import sys, re
pattern = sys.argv[1]
def glob_to_regex(g):
    out, i, n = [], 0, len(g)
    while i < n:
        c = g[i]
        if c == "*":
            if i + 1 < n and g[i+1] == "*":
                out.append(".*"); i += 2
                if i < n and g[i] == "/": i += 1
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        elif c in ".+(){}[]|^$\\":
            out.append("\\" + c)
        else:
            out.append(c)
        i += 1
    return "^" + "".join(out) + "$"
rx = re.compile(glob_to_regex(pattern))
for line in sys.stdin:
    p = line.rstrip("\n")
    if p and rx.match(p):
        print(p)
' "$pattern" 2>/dev/null
        return 0
    fi
    local tail="${pattern##*\*\*/}" p
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        case "$p" in *"$tail"*) printf '%s\n' "$p" ;; esac
    done
}

# ─── 파일 쓰기 락 ───────────────────────────────────────────────────
# goax_lock <lockdir> [timeout_s]  ·  goax_unlock <lockdir>  ·  goax_unlock_all
#   read → 변환 → tmp → mv 를 통째로 감싸요. `mv` 는 원자적이어도 lost-update 는 못 막아요
#   (실측: 레인 원장 동시 보고 30회 중 30회 유실). mkdir 은 POSIX 원자적이라 flock 없이 macOS 에서도 돼요.
#
#   같은 `tmp.$$` && `mv` 패턴을 쓰는 스크립트는 전부 이 헬퍼를 거쳐야 해요:
#     lanes-dispatch · tasks-gate · status-note · update-task · tier-from-state(--reset) · register-spirit-hook ·
#     build-memory · zero-init · zero-domain-risk · constitution-apply · update-state
#
# Usage:
#   goax_lock "$FILE.lock" || fail "다른 프로세스가 원장을 쓰는 중이에요"
#   ... 읽고 바꾸고 mv ...
#   goax_unlock "$FILE.lock"
#
# 이미 EXIT trap 을 건 스크립트는 그 trap 안에서 goax_unlock_all 을 같이 부르세요 —
# goax_lock 이 거는 trap 이 기존 trap 을 덮어써요.
GOAX_LOCKS_HELD=""                              # 개행 구분 (경로에 공백이 있어도 안전)
GOAX_LOCK_STALE="${GOAX_LOCK_STALE:-60}"        # pid 파일이 없는 락을 회수하기까지의 나이 (살아 있는 홀더는 대상 아님)

goax_lock() {
    local dir="${1:-}" timeout="${2:-10}" waited=0 iv="0.05" inc=5 now mt age pid
    [ -n "$dir" ] || return 1
    while :; do
        if mkdir "$dir" 2>/dev/null; then
            printf '%s\n' "$$" > "$dir/pid" 2>/dev/null || true
            GOAX_LOCKS_HELD="${GOAX_LOCKS_HELD}${dir}
"
            trap 'goax_unlock_all' EXIT INT TERM
            return 0
        fi
        # stale 회수 — 2초 넘게 기다린 뒤에만 검사해요 (빠른 경합에서 stat/date 를 안 띄우려고).
        # **살아 있는 홀더는 아무리 오래 잡고 있어도 안 뺏어요** — 타임아웃까지 기다리다 실패해요.
        # 예전엔 디렉토리 mtime 이 60초 넘으면 무조건 회수했는데, mtime 은 잡는 동안 갱신되지 않아서
        # 정당한 홀더(큰 파일·머신 슬립)를 뺏고 둘이 동시에 락을 가진 셈이 됐어요. 회수하는 건 둘뿐이에요:
        #   · pid 파일이 있는데 그 프로세스가 죽었음 (5초 뒤부터)
        #   · pid 파일이 없음 (손으로 만든 락 · mkdir 직후 죽음) 이고 GOAX_LOCK_STALE 을 넘김
        # kill -0 이 "not permitted" 로 실패하면 다른 사용자의 살아 있는 프로세스예요 — 죽은 게 아니에요.
        if [ "$waited" -ge 200 ]; then
            now=$(date +%s)
            mt=$(stat -c %Y "$dir" 2>/dev/null || stat -f %m "$dir" 2>/dev/null || echo "$now")   # GNU 먼저 (위 goax_inject_fresh 주석)
            case "$mt" in ''|*[!0-9]*) mt="$now" ;; esac
            age=$((now - mt))
            pid=$(cat "$dir/pid" 2>/dev/null || true)
            alive=""
            if [ -n "$pid" ]; then
                if kill -0 "$pid" 2>/dev/null; then alive=1
                elif kill -0 "$pid" 2>&1 | grep -qi 'permitted'; then alive=1
                fi
            fi
            if [ -n "$alive" ]; then
                :   # 홀더 생존 — 회수 안 함
            elif [ -n "$pid" ] && [ "$age" -gt 5 ]; then
                goax_warn "stale 락 회수: $dir (${age}s · pid $pid 없음)"
                rm -rf "$dir" 2>/dev/null || true
                continue
            elif [ -z "$pid" ] && [ "$age" -gt "$GOAX_LOCK_STALE" ]; then
                goax_warn "stale 락 회수: $dir (${age}s · pid 파일 없음)"
                rm -rf "$dir" 2>/dev/null || true
                continue
            fi
        fi
        if [ "$waited" -ge $((timeout * 100)) ]; then
            goax_warn "락 대기 시간 초과: $dir (${timeout}s)"
            return 1
        fi
        sleep "$iv" 2>/dev/null || sleep 1
        waited=$((waited + inc))
        if [ "$iv" = "0.05" ]; then iv="0.1"; inc=10
        elif [ "$iv" = "0.1" ]; then iv="0.2"; inc=20; fi
    done
}

goax_unlock() {
    local dir="${1:-}" keep="" d oldIFS
    [ -n "$dir" ] || return 0
    rm -rf "$dir" 2>/dev/null || true
    oldIFS="$IFS"; IFS='
'
    for d in $GOAX_LOCKS_HELD; do
        [ -z "$d" ] && continue
        [ "$d" = "$dir" ] && continue
        keep="${keep}${d}
"
    done
    IFS="$oldIFS"
    GOAX_LOCKS_HELD="$keep"
    return 0
}

goax_unlock_all() {
    local d oldIFS
    oldIFS="$IFS"; IFS='
'
    for d in $GOAX_LOCKS_HELD; do
        [ -n "$d" ] && rm -rf "$d" 2>/dev/null
    done
    IFS="$oldIFS"
    GOAX_LOCKS_HELD=""
    return 0
}

# ─── spec/ADR ID — 날짜 + 난수 (브랜치끼리 서로 안 봐도 안 겹쳐요) ─────────
# 새 ID: `YYYY-MM-DD-<4hex>` (예: 2026-09-25-a3f1). 옛 순번 `NNN`(spec)·`NNNN`(ADR) 도 계속 읽어요 (next-spec-num.sh).
# 주의: 옛 ADR `0008-x` 와 새 ID `2026-09-25-…` 는 둘 다 "숫자 4개 + 하이픈" 으로 시작해요 —
#       형식 판별은 반드시 GOAX_DOC_ID_ERE 로 하세요 (`[0-9]+-` 로 자르면 새 ID 가 전부 "2026" 이 돼요).
# 반복자 `{4}` 를 안 써요 — ubuntu 기본 mawk 는 구간 반복을 모르는 빌드가 있어요. `[a-f]` 범위도 안 써요 (로케일).
_GOAX_HX='[0123456789abcdef]'
GOAX_DOC_ID_ERE="^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-${_GOAX_HX}${_GOAX_HX}${_GOAX_HX}${_GOAX_HX}"
goax_doc_id() {
    local hex
    hex=$(od -An -N2 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    case "$hex" in [0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef]) ;; *) hex=$(printf '%04x' $(( (RANDOM << 1 ^ RANDOM) & 65535 ))) ;; esac
    printf '%s-%s' "$(date +%Y-%m-%d)" "$hex"
}
# goax_doc_key — stdin 의 항목 이름마다 비교 키: 새 ID 면 `YYYY-MM-DD-hhhh`, 옛 순번이면 앞 숫자.
goax_doc_key() {
    awk -v re="$GOAX_DOC_ID_ERE" '{ if ($0 ~ re) print substr($0, 1, 15); else { n = $0; sub(/[^0-9].*/, "", n); print n } }'
}
# goax_doc_sort — stdin 의 항목 이름을 오래된 순으로: 옛 순번(숫자순) 다음에 새 ID(이름순 = 날짜순).
goax_doc_sort() {
    awk -v re="$GOAX_DOC_ID_ERE" '{ if ($0 ~ re) print "1\t0\t" $0; else { n = $0; sub(/-.*/, "", n); print "0\t" (n + 0) "\t" $0 } }' \
        | sort -t "$(printf '\t')" -k1,1n -k2,2n -k3,3 | cut -f3-
}

# goax_resolve_spec <spec> [spec-base-dir]
#   `--spec 001` 같은 축약을 한 규칙으로 풀어요: 정확 일치 → prefix 일치가 정확히 1개 → 실패.
#   같은 인자에 스크립트마다 다른 답(검사 · 조용한 성공 · 에러)이 나오던 걸 없애요.
#   반환: 0 = 해석됨(디렉토리 이름을 stdout 으로) · 1 = 없음 · 2 = 후보 여럿
#         후보 여럿이면 GOAX_SPEC_CANDIDATES 에 공백 구분으로 담아요.
GOAX_SPEC_CANDIDATES=""
goax_resolve_spec() {
    local want="${1:-}" base="${2:-}" root hits n
    GOAX_SPEC_CANDIDATES=""
    [ -n "$want" ] || return 1
    if [ -z "$base" ]; then
        root="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
        base="$root/.ax/docs/spec"
    fi
    [ -d "$base" ] || return 1
    if [ -d "$base/$want" ]; then printf '%s' "$want"; return 0; fi
    hits=$(find "$base" -mindepth 1 -maxdepth 1 -type d -name "${want}*" 2>/dev/null \
           | sed 's|.*/||' | sort)
    # 새 ID(`2026-09-25-a3f1-slug`) 는 날짜로 시작해서 앞부분 축약으로는 못 찾아요 — 난수·slug 로도 찾아요
    [ -z "$hits" ] && hits=$(find "$base" -mindepth 1 -maxdepth 1 -type d -name "*-${want}*" 2>/dev/null \
           | sed 's|.*/||' | sort)
    n=$(printf '%s\n' "$hits" | grep -c . || true); n=${n:-0}
    if [ "$n" -eq 1 ]; then printf '%s' "$hits"; return 0; fi
    if [ "$n" -gt 1 ]; then
        GOAX_SPEC_CANDIDATES=$(printf '%s' "$hits" | tr '\n' ' ')
        GOAX_SPEC_CANDIDATES="${GOAX_SPEC_CANDIDATES% }"
        return 2
    fi
    return 1
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
