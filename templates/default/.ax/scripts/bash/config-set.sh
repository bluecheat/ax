#!/usr/bin/env bash
# .ax/scripts/bash/config-set.sh — .ax/config.yml 의 `<섹션>.<키>` 한 값을 락 안에서 바꿔요
#
# 왜: onboarding·zero 가 `commands.test` 같은 값을 모델의 Edit 로 적어 왔어요. 들여쓰기 한 칸이 틀리면
#     goax_yaml_list·grep 파서가 조용히 빈 값을 읽고, 두 세션이 동시에 고치면 한쪽이 사라져요.
#     값 하나를 바꾸는 결정론 도구가 있어야 SKILL.md 가 "무엇을" 만 정하고 "어떻게" 는 안 해요.
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

# awk 한 번 — 섹션 안 `  KEY:` 줄(과 블록 리스트면 그 아래 `    - …` 줄들)을 찾아 바꿔요.
#   출력 첫 줄: "FOUND\t<before>" 또는 "MISSING". 나머지는 새 파일 본문.
OUT=$(awk -v sec="$SEC" -v key="$KEY" -v op="$OP" -v qv="${QV:-}" -v raw="${VALUE:-}" '
    function endlist() {
        if (op == "add" && !dup) body = body "    - " qv "\n"
        body = body pend; pend = ""; inlist = 0
    }
    BEGIN { insec = 0; found = 0; inlist = 0; before = ""; pend = "" }
    {
        line = $0
        if (line ~ /^[^ \t#][^:]*:/) {                       # 최상위 키
            if (inlist) { endlist() }
            s = line; sub(/:.*/, "", s); insec = (s == sec)
            body = body line "\n"; next
        }
        if (inlist) {
            # 주석·빈 줄은 잠깐 들고 있어요 — 다음 줄이 항목이면 그 앞에, 리스트가 끝나면 새 항목 **뒤에** 내보내요
            if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) { pend = pend line "\n"; next }
            if (line ~ /^    +- /) {
                body = body pend; pend = ""
                v = line; sub(/^ *- */, "", v); sub(/[ \t]+$/, "", v); gsub(/^["\047]|["\047]$/, "", v)
                before = before (before == "" ? "" : " | ") v
                if (v == raw) dup = 1
                if (op != "clear") body = body line "\n"
                next
            }
            endlist()
        }
        if (insec && !found && line ~ ("^  " key ":")) {
            found = 1
            rest = line; sub("^  " key ":[ \t]*", "", rest)
            if (op == "set") {
                before = rest; sub(/[ \t]+#.*$/, "", before)
                body = body "  " key ": " qv "\n"; next
            }
            # 리스트 — flow `[]`/`[a, b]` 또는 블록
            if (rest ~ /^\[/) {
                v = rest; sub(/^\[/, "", v); sub(/\].*$/, "", v); before = v
                if (op == "clear") { body = body "  " key ": []\n"; next }
                if (v ~ /[^ \t]/) { print "FLOWLIST"; exit }
                body = body "  " key ":\n    - " qv "\n"; next
            }
            body = body "  " key (op == "clear" ? ": []" : ":") "\n"
            inlist = 1; dup = 0; next
        }
        body = body line "\n"
    }
    END {
        if (inlist) endlist()
        if (!found) { print "MISSING"; exit }
        printf "FOUND\t%s\n%s", before, body
    }' "$CFG")
HEAD1="${OUT%%$'\n'*}"
case "$HEAD1" in
    MISSING)  unlock; fail "$SEC.$KEY 키가 config.yml 에 없어요 — 새 키는 만들지 않아요 (/up 으로 템플릿을 받아요)" ;;
    FLOWLIST) unlock; fail "$SEC.$KEY 가 한 줄 리스트([a, b])예요 — 블록 리스트로 바꾼 뒤 --add 해요" ;;
esac
BEFORE="${HEAD1#FOUND$'\t'}"
NEW="${OUT#*$'\n'}"          # $(...) 가 끝 줄바꿈을 먹어요 — 쓸 때 하나 붙여요
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
