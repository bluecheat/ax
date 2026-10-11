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

# ─── 훅이 모델에게 주는 글의 길이 상한 — goax_cap_context ───────────────
# printf '%s' "$CTX" | goax_cap_context [최대 바이트] [전체를 볼 곳]
#   Claude Code 는 훅의 additionalContext·systemMessage·stdout 이 10,000자를 넘으면 파일로 빼고 앞 2,000자만
#   보여 줘요. 그 파일을 읽으라고 하지도 않아요. 그래서 훅이 먼저 그 아래로 줄여요.
#   상한은 바이트로 재요. 바이트 수는 글자 수보다 작을 수 없어서 로케일과 상관없이 글자 상한도 지켜져요.
#   기본은 GOAX_CONTEXT_MAX(8000). 넘으면 "… N바이트 생략 — <볼 곳>" 꼬리까지 합쳐 상한 안에 들어오게 자르고,
#   멀티바이트 글자 중간에서는 끊지 않아요. 자를 자리 가까이에 줄바꿈이 있으면 거기서 끊어요.
#   끝 줄바꿈은 지워져요 (`$(...)` 와 같아요).
goax_cap_context() {
    local max="${1:-}" where="${2:-}" s n lines tail k cut cn pre pn drop i b need om ol
    case "$max" in ''|*[!0-9]*) max="${GOAX_CONTEXT_MAX:-8000}" ;; esac
    case "$max" in ''|*[!0-9]*) max=8000 ;; esac
    s=$(cat)
    n=$(printf '%s' "$s" | LC_ALL=C wc -c | tr -d ' ')
    if [ "$n" -le "$max" ]; then printf '%s\n' "$s"; return 0; fi
    lines=$(printf '%s\n' "$s" | wc -l | tr -d ' ')
    # 꼬리 길이는 생략 수의 자릿수에 달려요 — 전체 크기로 위쪽 어림을 잡아요
    tail="… ${n}바이트·${lines}줄 생략${where:+ — $where}"
    k=$(( max - $(printf '%s' "$tail" | LC_ALL=C wc -c | tr -d ' ') - 1 ))
    [ "$k" -lt 0 ] && k=0
    # 파이프(`printf | head -c`)로 자르면 큰 입력에서 printf 가 SIGPIPE 로 "Broken pipe" 를 stderr 에 찍어요 —
    # C 로케일 서브셸의 바이트 단위 부분 문자열로 잘라요
    cut=$(LC_ALL=C; printf '%s' "${s:0:$k}")
    cn=$(printf '%s' "$cut" | LC_ALL=C wc -c | tr -d ' ')
    pre="${cut%$'\n'*}"
    if [ "$pre" != "$cut" ]; then
        pn=$(printf '%s' "$pre" | LC_ALL=C wc -c | tr -d ' ')
        [ $((pn * 4)) -ge $((cn * 3)) ] && { cut="$pre"; cn="$pn"; }
    fi
    # 끝에 반쯤 잘린 UTF-8 글자가 있으면 그 바이트들을 버려요
    # shellcheck disable=SC2046
    set -- $(printf '%s' "$cut" | LC_ALL=C tail -c 4 | od -An -tu1)
    drop=0; i=$#
    while [ "$i" -gt 0 ]; do
        b="${!i}"
        if [ "$b" -lt 128 ]; then break; fi
        if [ "$b" -ge 192 ]; then
            need=2; [ "$b" -ge 224 ] && need=3; [ "$b" -ge 240 ] && need=4
            [ $(( $# - i + 1 )) -lt "$need" ] && drop=$(( $# - i + 1 ))
            break
        fi
        i=$((i - 1))
    done
    if [ "$drop" -gt 0 ]; then
        cn=$((cn - drop))
        cut=$(LC_ALL=C; printf '%s' "${cut:0:$cn}")
    fi
    om=$((n - cn))
    ol=$(( lines - $(printf '%s\n' "$cut" | wc -l | tr -d ' ') ))
    [ "$ol" -lt 0 ] && ol=0
    if [ "$ol" -gt 0 ]; then tail="… ${om}바이트·${ol}줄 생략${where:+ — $where}"
    else tail="… ${om}바이트 생략${where:+ — $where}"; fi
    printf '%s\n%s\n' "$cut" "$tail"
}

# Exit codes
EXIT_OK=0
EXIT_ERROR=1
EXIT_SKIPPED=2

# 부른 스크립트의 인자에 --json 이 있었는지 — source 는 호출자의 "$@" 를 그대로 보여줘요.
# 파서가 --json 에 닿기 전에 오류가 나도(`--bogus --json`) envelope 으로 답하려고요 (smoke §68).
GOAX_ARGV_JSON=false
for _goax_a in "$@"; do [ "$_goax_a" = --json ] && GOAX_ARGV_JSON=true; done
unset _goax_a

# Logging — stderr only ([goax] prefix)
# JSON_MODE=true (또는 인자에 --json) 면 goax_error 는 stdout 에 json_output error 한 줄을 emit.
# caller 의 exit 흐름은 보존 (이 함수는 exit 안 함). exit 까지 묶고 싶으면 'json_error'.
goax_log()   { printf '[goax] %s\n' "$*" >&2; }
goax_warn()  { printf '[goax] WARN: %s\n' "$*" >&2; }
goax_error() {
    if [ "${JSON_MODE:-false}" = "true" ] || [ "${GOAX_ARGV_JSON:-false}" = "true" ]; then
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

# ─── 기능별 함수 — lib/*.sh ─────────────────────────────────────────
# common.sh 를 source 하면 lib/ 의 함수도 모두 쓸 수 있어요. 호출하는 쪽은 common.sh 하나만 source 해요.
# lib/ 가 없으면 설치가 깨진 상태라서, 이 세션은 /up 으로 다시 설치해요.
GOAX_LIB_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
for _goax_lib in secrets shellscan paths rules state lock ids; do
    if [ ! -f "$GOAX_LIB_DIR/$_goax_lib.sh" ]; then
        printf '[goax] ERROR: %s 가 없어요. 설치가 깨졌어요 — /up 으로 다시 설치해요\n' "$GOAX_LIB_DIR/$_goax_lib.sh" >&2
        return 1 2>/dev/null || exit 1
    fi
    # shellcheck source=/dev/null
    . "$GOAX_LIB_DIR/$_goax_lib.sh"
done
unset _goax_lib
