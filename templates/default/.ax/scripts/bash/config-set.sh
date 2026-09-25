#!/usr/bin/env bash
# .ax/scripts/bash/config-set.sh — .ax/config.yml 의 `<섹션>.<키>` 한 값을 락 안에서 바꿔요
#
# 왜: 모델의 Edit 로 적으면 들여쓰기 한 칸에 파서가 조용히 빈 값을 읽고, 동시 수정은 한쪽이 사라져요.
#
# Usage:
#   bash config-set.sh <섹션>.<키> <값>            [--json] [--dry-run]   # 스칼라 — `  키: "값"` 으로 바꿔요
#   bash config-set.sh --add <섹션>.<키> <값>      [--json] [--dry-run]   # 블록 리스트에 한 줄 추가 (이미 있으면 그대로)
#   bash config-set.sh --clear <섹션>.<키>         [--json] [--dry-run]   # 리스트를 `[]` 로
#
#   섹션은 최상위 키, 키는 그 바로 아래(들여쓰기 2칸) 키예요. **이미 있는 키만** 바꿔요 — 새 키를 만들지 않아요
#   (오타가 조용히 새 키가 되면 아무도 안 읽어요). 키의 뒤 주석은 스칼라를 바꿀 때 지워져요.
#   값에 `"` 와 `'` 가 둘 다 있으면 거부해요 — goax 의 YAML 파서는 이스케이프를 풀지 않아서 따옴표 한 종류만 써요.
#
# Output (--json):
#   {"status":"ok","result":{"path":".ax/config.yml","key":"commands.test","op":"set|add|clear","changed":true,
#                            "before":"…","after":"…"},…}
# Exit: 0 ok · 1 error (키 없음 · 형식 오류 · 락 실패)
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; DRY_RUN=false; SHOW_HELP=false
OP=set; POS=()
while [ $# -gt 0 ]; do
    if parse_common_opts "$1"; then shift; continue; fi
    case "$1" in
        --add)   OP=add ;;
        --clear) OP=clear ;;
        --*)     goax_error "알 수 없는 옵션: $1"; exit "$EXIT_ERROR" ;;
        *)       POS+=("$1") ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }

KEYPATH="${POS[0]:-}"; VALUE="${POS[1]:-}"
case "$KEYPATH" in *.*) ;; *) fail "<섹션>.<키> 가 필요해요 (예: commands.test)" ;; esac
SEC="${KEYPATH%%.*}"; KEY="${KEYPATH#*.}"
case "$SEC$KEY" in *[!0-9A-Za-z_]*) fail "섹션·키는 영문·숫자·_ 만 돼요: $KEYPATH" ;; esac
if [ "$OP" != clear ]; then
    [ "${#POS[@]}" -ge 2 ] || fail "값이 필요해요"
    case "$VALUE" in *$'\n'*) fail "값은 한 줄이에요" ;; esac
    case "$VALUE" in *\"*) case "$VALUE" in *\'*) fail "값에 \" 와 ' 를 같이 쓸 수 없어요" ;; esac; Q="'" ;; *) Q='"' ;; esac
    QV="${Q}${VALUE}${Q}"
fi

ROOT=$(find_project_root) || exit "$EXIT_ERROR"
CFG="$ROOT/.ax/config.yml"
[ -f "$CFG" ] || fail ".ax/config.yml 이 없어요 — /up 먼저"

LOCK=""
if [ "$DRY_RUN" != true ]; then
    LOCK="$CFG.lock"   # zero-domain-risk.sh 와 같은 문자열 — 락 단위는 파일
    goax_lock "$LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || fail "락을 못 잡았어요: $LOCK"
fi
unlock() { [ -n "$LOCK" ] && goax_unlock "$LOCK"; LOCK=""; }

# awk 한 번 — 파일을 다 읽고(END) `섹션.키` 줄의 형태부터 판정한 뒤 바꿔요.
#   형태: scalar(값이 있는 줄) · flow(`[…]`) · block(키 뒤가 비고 아래에 `- ` 항목들 — 들여쓰기 2칸 이상 아무거나).
#   set 은 scalar 에만, --add/--clear 는 리스트(flow·block·빈 값)에만 — 모양이 다르면 쓰지 않고 거부해요
#   (리뷰 실측: 리스트 키에 set 하면 항목이 고아로 남아 disabled_hooks 가 조용히 비었어요).
#   값은 awk -v 가 아니라 ENVIRON 으로 넘겨요 — -v 는 `\n` · `\d` 같은 백슬래시 이스케이프를 해석해서 config.yml 을 깨뜨렸어요.
#   출력 첫 줄: "FOUND\t<before>" · "MISSING" · "FLOWLIST" · "NOTLIST" · "NOTSCALAR". 나머지는 새 파일 본문.
OUT=$(CS_SEC="$SEC" CS_KEY="$KEY" CS_OP="$OP" CS_QV="${QV:-}" CS_RAW="${VALUE:-}" awk '
    function strip(v,   q, e) {                          # goax_yaml_list 와 같은 규칙 — 따옴표 한 쌍 · 주석
        sub(/^[ \t]*-[ \t]*/, "", v); sub(/[ \t]+$/, "", v); q = substr(v, 1, 1)
        if (q == "\042" || q == "\047") { e = length(v); while (e > 1 && substr(v, e, 1) != q) e--; if (e > 1) v = substr(v, 2, e - 2) }
        else sub(/[ \t]+#.*$/, "", v)
        return v
    }
    { L[++n] = $0 }
    END {
        sec = ENVIRON["CS_SEC"]; key = ENVIRON["CS_KEY"]; op = ENVIRON["CS_OP"]; qv = ENVIRON["CS_QV"]; raw = ENVIRON["CS_RAW"]
        insec = 0; k = 0
        for (i = 1; i <= n; i++) {
            if (L[i] ~ /^[^ \t#][^:]*:/) { s = L[i]; sub(/:.*/, "", s); insec = (s == sec); continue }
            if (insec && L[i] ~ ("^  " key ":([ \t]|$)")) { k = i; break }
        }
        if (!k) { print "MISSING"; exit }
        rest = L[k]; sub("^  " key ":[ \t]*", "", rest)
        restv = rest; sub(/[ \t]+#.*$/, "", restv); if (restv ~ /^#/) restv = ""
        # block 항목 범위: k+1 부터, 주석·빈 줄은 건너뛰며 `- ` 항목이 이어지는 동안
        last = k; items = 0; ind = ""
        for (i = k + 1; i <= n; i++) {
            if (L[i] ~ /^[ \t]*#/ || L[i] ~ /^[ \t]*$/) continue
            if (L[i] ~ /^  +- / || L[i] ~ /^  +-$/) {
                items++; last = i
                if (ind == "") { ind = L[i]; sub(/-.*/, "", ind) }
                continue
            }
            break
        }
        before = ""
        if (restv ~ /^\[/) {
            kind = "flow"; v = restv; sub(/^\[/, "", v); sub(/\].*$/, "", v); before = v
        } else if (restv != "") { kind = "scalar"; before = restv
        } else if (items > 0) { kind = "block"
        } else kind = "empty"
        if (op == "set" && (kind == "block" || kind == "flow")) { print "NOTSCALAR"; exit }
        if (op != "set" && kind == "scalar") { print "NOTLIST"; exit }
        if (op == "add" && kind == "flow" && before ~ /[^ \t]/) { print "FLOWLIST"; exit }
        if (ind == "") ind = "    "
        out = ""
        for (i = 1; i < k; i++) out = out L[i] "\n"
        if (op == "set") {
            out = out "  " key ": " qv "\n"; from = k + 1
        } else if (op == "clear") {
            if (kind == "block") {
                for (i = k + 1; i <= last; i++) if (L[i] ~ /^  +-/) before = before (before == "" ? "" : " | ") strip(L[i])
            }
            out = out "  " key ": []\n"
            for (i = k + 1; i <= last; i++) if (L[i] !~ /^  +-/) out = out L[i] "\n"
            from = last + 1
        } else {                                              # add
            dup = 0
            if (kind == "block") {
                for (i = k + 1; i <= last; i++) if (L[i] ~ /^  +-/) {
                    v = strip(L[i]); before = before (before == "" ? "" : " | ") v; if (v == raw) dup = 1
                }
                for (i = k; i <= last; i++) out = out L[i] "\n"
                if (!dup) out = out ind "- " qv "\n"
            } else {
                out = out "  " key ":\n" ind "- " qv "\n"
            }
            from = last + 1
        }
        for (i = from; i <= n; i++) out = out L[i] "\n"
        printf "FOUND\t%s\n%s", before, out
    }' "$CFG")
HEAD1="${OUT%%$'\n'*}"
case "$HEAD1" in
    MISSING)  unlock; fail "$SEC.$KEY 키가 config.yml 에 없어요 — 새 키는 만들지 않아요 (/up 으로 템플릿을 받아요)" ;;
    FLOWLIST) unlock; fail "$SEC.$KEY 가 한 줄 리스트([a, b])예요 — 블록 리스트로 바꾼 뒤 --add 해요" ;;
    NOTSCALAR) unlock; fail "$SEC.$KEY 는 리스트예요 — --add / --clear 로 다뤄요" ;;
    NOTLIST)  unlock; fail "$SEC.$KEY 는 한 값(스칼라)이에요 — --add 가 아니라 값을 바로 줘요" ;;
esac
BEFORE="${HEAD1#FOUND$'\t'}"
NEW="${OUT#*$'\n'}"          # $(...) 가 끝 줄바꿈을 없애요 — 쓸 때 하나 붙여요
CHANGED=true
cmp -s <(printf '%s\n' "$NEW") "$CFG" && CHANGED=false

if [ "$DRY_RUN" != true ] && [ "$CHANGED" = true ]; then
    TMP=$(goax_mktemp "$ROOT") || { unlock; goax_tmp_error; exit "$EXIT_ERROR"; }
    printf '%s\n' "$NEW" > "$TMP" && mv "$TMP" "$CFG"
fi
unlock

if [ "$OP" = set ]; then AFTER="$VALUE"
elif [ "$OP" = clear ]; then AFTER="[]"
elif [ "$DRY_RUN" = true ]; then AFTER="${BEFORE:+$BEFORE | }$VALUE"
else AFTER=$(goax_yaml_list "$CFG" "$KEY" 2>/dev/null | paste -sd '|' - | sed 's/|/ | /g'); fi
if [ "$JSON_MODE" = true ]; then
    json_output ok "$(jq -nc --arg k "$SEC.$KEY" --arg op "$OP" --argjson ch "$CHANGED" --arg b "$BEFORE" --arg a "$AFTER" \
        '{path:".ax/config.yml", key:$k, op:$op, changed:$ch, before:$b, after:$a}')" ""
else
    printf '%s.%s: %s → %s%s\n' "$SEC" "$KEY" "${BEFORE:-(빈 값)}" "$AFTER" "$([ "$CHANGED" = true ] || printf ' (변화 없음)')"
fi
exit "$EXIT_OK"
