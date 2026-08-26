#!/usr/bin/env bash
# pre-edit hook — spirit/rules/<name>.md 의 frontmatter `paths:` 와 편집 대상 파일 매칭 →
# 매칭된 룰 파일 경로를 additionalContext로 Claude에게 안내 (B-pointer: lazy Read 패턴).
#
# 입력: stdin JSON {tool_input.file_path|tool_input.notebook_path}
# 출력: stdout JSON {hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:"..."}}
#
# 매칭 없으면 silent exit 0. .claude/rules/ shim 의존 X — Claude Code 공식 hook
# additionalContext 메커니즘으로 path-scoped rule loading을 .ax/-only로 구현.
set -uo pipefail

# Bootstrap guard — install 중간이거나 .ax/ 부분 정리 시 silent skip
[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0
[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/spirit/rules" ] || exit 0

# stdin JSON 파싱
INPUT="$(cat 2>/dev/null || true)"
TARGET_PATH=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    TARGET_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
fi
TARGET_PATH="${TARGET_PATH:-${CLAUDE_EDIT_PATH:-${1:-}}}"
[ -z "$TARGET_PATH" ] && exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SPIRIT_DIR="$PROJECT_ROOT/.ax/spirit/rules"
[ -d "$SPIRIT_DIR" ] || exit 0

# 경로 정규화 헬퍼 — `./x`·`a/../x` 같은 표기 변형을 흡수해야 경로 판정이 일관돼요.
# common.sh 가 없으면 degrade (원래 문자열 그대로) 하되 죽지 않아요.
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
if [ -f "$COMMON" ]; then
    # shellcheck source=../../scripts/bash/common.sh
    source "$COMMON"
fi
type goax_normalize_path >/dev/null 2>&1 || goax_normalize_path() { printf '%s' "${1:-}"; }

TARGET_ABS=$(goax_normalize_path "$TARGET_PATH" "$PROJECT_ROOT")
ROOT_ABS=$(goax_normalize_path "$PROJECT_ROOT" "$PROJECT_ROOT")
TARGET_REL="${TARGET_ABS#$ROOT_ABS/}"
[ "$TARGET_REL" = "$TARGET_ABS" ] && TARGET_REL="${TARGET_ABS#/}"

# spirit/rules/<name>.md frontmatter에서 paths: 배열 추출 (각 줄: 단일 glob 패턴)
extract_paths_from_file() {
    awk '
        BEGIN { c=0; in_paths=0 }
        /^---$/ { c++; if (c==2) exit; next }
        c==1 {
            if (/^paths:[[:space:]]*$/)                     { in_paths=1; next }
            if (/^paths:[[:space:]]*\[[[:space:]]*\]/)      { in_paths=0; next }
            if (/^[a-zA-Z_]/)                                { in_paths=0 }
            if (in_paths && /^[[:space:]]+-[[:space:]]+/) {
                sub(/^[[:space:]]+-[[:space:]]+/, "")
                gsub(/^"|"$/, "")
                gsub(/^'\''|'\''$/, "")
                print
            }
        }
    ' "$1"
}

# python으로 glob 매칭 (** 처리 정확). 없으면 conservative pass-through.
match_glob() {
    local pattern="$1"
    local path="$2"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$pattern" "$path" <<'PY' 2>/dev/null
import sys, re
pattern, path = sys.argv[1], sys.argv[2]
def glob_to_regex(g):
    out = []
    i, n = 0, len(g)
    while i < n:
        c = g[i]
        if c == '*':
            if i + 1 < n and g[i+1] == '*':
                out.append('.*')
                i += 2
                if i < n and g[i] == '/':
                    i += 1
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
print('1' if re.match(glob_to_regex(pattern), path) else '0')
PY
    else
        # python 없으면 단순 substring match로 대체
        case "$path" in
            *${pattern##\*\*\/}*) echo "1" ;;
            *) echo "0" ;;
        esac
    fi
}

MATCHED=()
for f in "$SPIRIT_DIR"/*.md; do
    [ -f "$f" ] || continue
    matched_this=false
    while IFS= read -r glob; do
        [ -z "$glob" ] && continue
        if [ "$(match_glob "$glob" "$TARGET_REL")" = "1" ]; then
            matched_this=true
            break
        fi
    done < <(extract_paths_from_file "$f")
    [ "$matched_this" = true ] && MATCHED+=(".ax/spirit/rules/$(basename "$f")")
done

# 매칭 없으면 silent
[ ${#MATCHED[@]} -eq 0 ] && exit 0

# additionalContext 생성 (룰 파일 경로 알림 — Claude가 필요 시 Read)
LIST=""
for m in "${MATCHED[@]}"; do
    LIST+="- $m"$'\n'
done
CTX="📋 Path-scoped spirit rules apply to ${TARGET_REL} — Read these before editing if not yet:"$'\n'"$LIST"

# JSON 출력
if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ctx "$CTX" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
else
    # jq 부재 시 minimal escape
    esc=$(printf '%s' "$CTX" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$esc"
fi
exit 0
