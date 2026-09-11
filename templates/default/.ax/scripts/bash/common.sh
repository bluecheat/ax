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
# macOS 기본 awk(BWK)는 length/substr 가 바이트 단위라 상한 위치가 한글 한 글자를 반으로
# 가르고, 그 뒤 정규식이 `awk: towc: multibyte conversion failure` 로 **awk 를 통째로
# 중단**시켜요. 실측 피해 둘 —
#   · build-memory.sh: "🔴 CRITICAL 룰 (3)" 머리말은 grep -c 로 따로 세니 건수를 계속
#     보고하는데 그 아래 목록만 사라져요. triage 에 룰이 0건 닿는데 아무도 모릅니다.
#   · triage-search.sh: 스니펫이 반 글자에서 잘려 `앱<?>` 처럼 깨진 채 컨텍스트에 들어가요.
# 공백은 1바이트이고 UTF-8 연속 바이트(0x80-0xBF)가 될 수 없어서, 공백에서만 끊으면 어느
# awk 에서도 안 깨져요. 리눅스는 gawk 가 문자 단위, mawk(ubuntu 기본)는 바이트 단위지만 towc
# 검사가 없어 어느 쪽도 죽지는 않아요 — 그래서 macOS 에서만 터져요. CI 는 macOS 도 돌지만
# 180바이트를 넘는 한글 룰 픽스처가 없어서 못 잡았어요 (smoke §44 가 그 자리를 채워요).
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
# 예전엔 훅이 자기 상수를, 여기가 자기 sed 를 따로 들고 있어서 여덟 축이 이미 갈라져 있었어요
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
#   - 행 순서 = 적용 순서. 좁은 패턴이 위 (`sk-(ant|proj)-` 가 `sk-` 보다 위여야 라벨이 안 뭉개져요)
#   - 검출과 마스킹의 폭은 같게. 다르면 `check-mistake-secrets.sh` 와 `critical-rule-grep.sh` 가
#     같은 파일에 다른 답을 내요
#
# key=value 두 행이 공유하는 키 이름이에요. 두 행은 정량자와 캡처만 달라야 해서 조각을 하나로 둬요 —
# 이게 이 축의 드리프트(검출에만 `passwd`·`access_key`, 마스킹에만 `pg_key`)를 막는 유일한 장치예요.
# 대소문자는 브래킷으로 써요 (sed 에는 grep 의 `-i` 가 없어요).
_GOAX_SECRET_KV_KEYS='[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Aa][Cc][Cc][Ee][Ss][Ss][_-]?[Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Bb][Ee][Aa][Rr][Ee][Rr]|[Pp][Gg][_-]?[Kk][Ee][Yy]'

goax_secret_rules() {
    # 표는 인용 heredoc 이에요 — 행에 `\.`·`\1`·`$`·`%`·`{`·양쪽 따옴표가 다 들어가서 printf 나
    # 비인용 heredoc 은 그중 일부를 먹어요. `@KV@` 만 위 조각으로 치환해요.
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
        now=$(date +%s); mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
        case "$mt" in ''|*[!0-9]*) mt=0 ;; esac   # GNU `stat -f` 는 실패해도 stdout 에 파일시스템 요약을 찍어요 — GNU 형식을 먼저
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
# --help — 헤더 주석 블록(2행부터 첫 비-`#` 행 전까지)을 `# ` 벗겨서 그대로 찍어요.
#   예전엔 스크립트마다 `sed -n '2,NNp'` 로 줄 번호를 손으로 들고 있었는데, 헤더가 자라면 `Exit:` 계약 줄이
#   잘리고 줄면 `set -euo pipefail` 까지 찍혔어요 (실측 19/37 스크립트가 어긋나 있었어요). 줄 번호를 없애요.
# Usage: if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
goax_help() {
    awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$1"
}

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

# ─── 파일 쓰기 락 ───────────────────────────────────────────────────
# goax_lock <lockdir> [timeout_s]  ·  goax_unlock <lockdir>  ·  goax_unlock_all
#   read → 변환 → tmp → mv 를 통째로 감싸요. `mv` 자체는 원자적이지만 lost-update 는 못 막아요 —
#   두 프로세스가 같은 원본을 읽으면 나중에 mv 하는 쪽이 앞의 변경을 통째로 덮어써요.
#   실측(레인 원장): `--report A` ‖ `--report B` 30회 중 30회 유실(보고 16줄 중 8줄만 남음),
#   tasks-gate 의 task_seal 은 10회 중 5회 유실 — G4 "미완료를 지워서 통과" 방어가 같이 사라져요.
#   mkdir 은 POSIX 에서 원자적이라 flock(리눅스 전용) 없이 macOS/BSD 에서도 상호배제가 돼요.
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

# ─── spec 인자 해석 ─────────────────────────────────────────────────
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
