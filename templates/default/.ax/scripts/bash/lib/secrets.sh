#!/usr/bin/env bash
# .ax/scripts/bash/lib/secrets.sh — 시크릿 패턴 — mistake 시크릿 검사와 redact 가 함께 쓰는 SSOT
# common.sh 가 source 해요. 직접 source 하지 않아요.
# shellcheck disable=SC2034  # 여기서 정의한 변수는 common.sh 를 source 한 스크립트가 써요

# ─── 시크릿 패턴 SSOT ───────────────────────────────────────────────
# 시크릿의 형태를 아는 곳은 이 표 하나예요. 검출(grep)도 마스킹(sed)도 같은 행에서 나와요.
# 예전엔 훅이 자기 상수를, 여기가 자기 sed 를 따로 갖고 있어서 여덟 군데가 이미 서로 달라져 있었어요
# (AWS·GitHub·Stripe·PEM·JWT 정량자 · Slack 웹훅은 마스킹만 · key=value 는 키 이름까지).
#
#   goax_secret_rules()     표 자체. 한 행 = <use> TAB <label> TAB <ERE> TAB <sed 치환문>
#   goax_secret_patterns()  use=both|detect 행의 ERE 만 (검출용)
#   goax_secret_scan_file() 파일 하나를 검출해 `줄번호 TAB 라벨` 출력 (kv-detect 는 타입 자리를 지운 뒤)
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

# ─── kv-detect 의 타입 자리 제외 ─────────────────────────────────────
# kv-detect 는 키 이름 뒤 `:` 를 값의 시작으로 읽어요. 그래서 TS·Kotlin·Swift 의 **타입 자리**가 값으로 읽혀요
# — 실측(one-tenth): `token: string,` · `messageFor?(target: UserTarget, token: string, platform: Platform)`
# 이 CRITICAL 1건이 됐고, 그 프로젝트는 sensors.mode 를 warning 으로 내렸어요 (안전망 전체가 꺼진 셈이에요).
# ERE 에는 lookahead 가 없어서 행 하나로 "타입이면 빼라" 를 못 써요. 그래서 kv-detect 를 돌리기 **전에**
# 줄에서 타입 자리만 지워요. 지우는 건 `키: 타입` 조각뿐이라 같은 줄의 값 대입(`token: string = "…"`,
# `{ token: "…" }`)은 그대로 남아 걸려요. 줄 수는 바뀌지 않아요 (줄 번호가 원본과 같아요).
#   ① 원시 타입 — `token: string` · `password: String?` · `secret: number[]` (뒤가 식별자 글자가 아니면)
#   ② 선택 속성·인자 — `apiKey?: Foo` (`?:` 는 값 문법에 없어요)
#   ③ 타입 이름 + 타입 문법 — `token: UserToken,` · `)` · `;` · `|` · `&` · `<` · `>` · `[`
#      (`=` 는 일부러 빼요 — `token: Foo = "…"` 의 대입을 남기려고요)
#   ④ 줄 끝의 대문자 낱말 — `password: Password` (세미콜론 없는 interface). 숫자가 섞이면 빼지 않아요
#      (`secret: Abc123Secret` 같은 YAML 값을 놓치지 않으려고요)
# 대가: `{token: abc123def, …}` 처럼 따옴표 없는 값 뒤에 `,` 가 오는 YAML flow 표기는 ③ 에 걸려 빠져요.
#   발급처 형태(ghp_·sk-·AKIA 등)는 별도 행이라 영향 없어요.
_GOAX_SECRET_TS_TYPES='string|number|boolean|bigint|symbol|any|unknown|never|object|void|null|undefined|String|Number|Boolean|Int|Long|Double|Float|Bool|Char|Byte|Short|Any|Object|Unit'
goax_secret_type_strip_script() {
    local kv="(${_GOAX_SECRET_KV_KEYS})" id='[[:alpha:]_$][[:alnum:]_$.]*'
    printf 's#%s[?]?[[:space:]]*:[[:space:]]*(%s)([^[:alnum:]_$]|$)#\\1 \\3#g\n' "$kv" "$_GOAX_SECRET_TS_TYPES"
    printf 's#%s[?][[:space:]]*:[[:space:]]*%s#\\1#g\n' "$kv" "$id"
    printf 's#%s[[:space:]]*:[[:space:]]*%s([[:space:]]*[],;)|&<>[])#\\1\\2#g\n' "$kv" "$id"
    printf 's#%s[[:space:]]*:[[:space:]]*[[:upper:]][[:alpha:]]*[[:space:]]*$#\\1#\n' "$kv"
}

# goax_secret_scan_file <file>
#   걸린 줄마다 `<줄번호> TAB <라벨>` 을 출력해요 (한 줄에 여러 행이 걸리면 표 순서상 첫 라벨 하나).
#   줄 **내용**은 내보내지 않아요 — 시크릿을 stderr·로그로 다시 흘리면 검출한 의미가 없어요.
#   바이너리는 건너뛰어요 (grep -I). 검출 폭은 표(goax_secret_rules)와 같고, kv-detect 만 타입 자리를 지운 뒤 봐요.
goax_secret_scan_file() {
    local f="${1:-}" label pat strip
    [ -f "$f" ] || return 0
    grep -qI '' "$f" 2>/dev/null || return 0          # 바이너리·빈 파일
    strip=$(goax_secret_type_strip_script)
    goax_secret_rules | awk -F'\t' '$1=="both"||$1=="detect"{print $2 "\t" $3}' \
    | while IFS=$'\t' read -r label pat; do
        [ -n "$pat" ] || continue
        if [ "$label" = "kv-detect" ]; then
            sed -E "$strip" "$f" 2>/dev/null | grep -nE -e "$pat" 2>/dev/null
        else
            grep -nIE -e "$pat" -- "$f" 2>/dev/null
        fi | awk -F: -v l="$label" '{print $1 "\t" l}'
    done | sort -n -s -k1,1 | awk -F'\t' '!seen[$1]++'
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
