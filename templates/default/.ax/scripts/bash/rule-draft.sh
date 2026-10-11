#!/usr/bin/env bash
# .ax/scripts/bash/rule-draft.sh — 룰을 쓰기 전에 필요한 사실을 모아요 (rule skill 이 불러요)
#
# Usage:
#   bash rule-draft.sh --category <이름> [--from-mistake <파일>…] [--title "<제목 초안>"] [--json]
#   bash rule-draft.sh --from-mistake <파일>… [--json]            # 카테고리는 mistake frontmatter 에서
#
# 모으는 것:
#   target       룰을 넣을 파일 (.ax/spirit/rules/<category>.md). 없으면 exists:false 이고 rule skill 이 _templates/spirit/rule.md 로 만들어요
#   prefix       그 파일의 SP 접두사와 다음 번호 (SP-<PREFIX>-<NNN>)
#   similar      제목 낱말이 둘 이상 겹치는 기존 룰 — 새로 쓰지 말고 기존 룰을 고칠 후보예요
#   mistakes     mistake 마다 요약 한 줄, 언급한 파일 경로, 패턴 초안(③), 이미 승격됐는지
#   paths        언급한 파일 경로에서 뽑은 확장자와 디렉토리 — frontmatter `paths:` 후보예요
#   enforcement  패턴 초안이 ERE 로 컴파일되면 "grep", 아니면 "human" 이에요
# 이 스크립트는 파일을 쓰지 않아요. 룰 본문은 rule skill 이 고정 틀로 써요.
#
# Output (--json):
#   {"status":"ok","result":{"category":"data","target":{"file":"…","exists":true},"prefix":"DATA","next_id":"SP-DATA-024",
#     "similar":[{"id":"SP-DATA-006","title":"…","shared":["cursor","pagination"]}],
#     "mistakes":[{"file":"…","summary":"…","paths":["…"],"pattern":"…|null","pattern_compiles":true,"promoted":false}],
#     "paths":{"extensions":["kt"],"dirs":["commerce-data/src/main/kotlin/…/adapter"]},"enforcement":"grep|human"},…}
# Exit: 0 ok · 1 error (카테고리를 못 정함) · 2 skipped (jq 없음)

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; CATEGORY=""; TITLE=""; MISTAKES=()
while [ $# -gt 0 ]; do
    case "$1" in
        --json)     JSON_MODE=true ;;
        --dry-run)  ;;                          # 읽기 전용 — 표준 옵션 호환
        --category) shift; CATEGORY="${1:-}" ;;
        --title)    shift; TITLE="${1:-}" ;;
        --from-mistake) shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do MISTAKES+=("$1"); shift; done; continue ;;
        --help|-h)  SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
command -v jq >/dev/null 2>&1 || { [ "$JSON_MODE" = true ] && printf '{"status":"skipped","result":{},"next_step":"jq 가 필요해요","warnings":["jq not found"],"errors":[]}\n'; exit "$EXIT_SKIPPED"; }

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }

# ── mistake 마다 사실 뽑기 ────────────────────────────────────────
M_JSON='[]'; ALL_PATHS=""; ANY_PATTERN=false; ALL_COMPILE=true; WORDS="$TITLE"
for m in ${MISTAKES[@]+"${MISTAKES[@]}"}; do
    f="$m"; case "$f" in /*) ;; *) f="$PROJECT_ROOT/$f" ;; esac
    [ -f "$f" ] || fail "mistake 파일이 없어요: $m"
    cat_m=$(goax_frontmatter_scalar "$f" category 2>/dev/null || true)
    [ -z "$CATEGORY" ] && CATEGORY="$cat_m"
    summary=$(awk '/^# 무엇이 일어났나/{getline; while ($0 ~ /^[[:space:]]*$/) getline; print; exit}' "$f")
    paths=$(awk '/^# 어디서/{on=1; next} /^# /{on=0} on' "$f" \
        | grep -oE '`[^`]*/[^`]*\.[[:alnum:]]+`' | tr -d '`' | sed -E 's#^\./##' | awk 'NF && !s[$0]++' || true)
    pattern=$(grep -oE '패턴 초안:[[:space:]]*`[^`]+`' "$f" | head -1 | sed -E 's/^패턴 초안:[[:space:]]*`//; s/`$//' || true)
    compiles=false
    if [ -n "$pattern" ] && [ "${pattern#<}" = "$pattern" ]; then
        ANY_PATTERN=true
        printf '' | grep -E -- "$pattern" >/dev/null 2>&1; rc=$?
        [ "$rc" -le 1 ] && compiles=true || ALL_COMPILE=false
    else
        pattern=""
    fi
    promoted=false; grep -qE '^promoted_to:[[:space:]]*[^[:space:]]' "$f" && promoted=true
    ALL_PATHS="${ALL_PATHS}${paths}"$'\n'
    WORDS="$WORDS $summary"
    M_JSON=$(jq -c --arg file "${f#"$PROJECT_ROOT"/}" --arg s "$summary" --arg p "$pattern" --argjson c "$compiles" \
        --argjson pr "$promoted" --argjson paths "$(printf '%s\n' "$paths" | jq -Rn '[inputs|select(length>0)]')" \
        '. + [{file:$file, summary:$s, paths:$paths, pattern:(if $p=="" then null else $p end), pattern_compiles:$c, promoted:$pr}]' <<<"$M_JSON")
done
[ -n "$CATEGORY" ] || fail "카테고리를 정할 수 없어요. --category <이름> 을 주거나 mistake frontmatter 에 category 를 적어요"
case "$CATEGORY" in *[![:lower:][:digit:]-]*) fail "카테고리는 소문자·숫자·하이픈이에요 (받은 값: '$CATEGORY')" ;; esac

# ── 대상 파일 · 접두사 · 다음 번호 ─────────────────────────────────
RULES_DIR="$PROJECT_ROOT/.ax/spirit/rules"
TARGET="$RULES_DIR/$CATEGORY.md"
if [ ! -f "$TARGET" ]; then
    # 카테고리 이름이 다른 파일에 frontmatter 로 있을 수 있어요 (예: commerce-data.md 의 category: data)
    for rf in "$RULES_DIR"/*.md; do
        [ -f "$rf" ] || continue
        [ "$(goax_frontmatter_scalar "$rf" category 2>/dev/null || true)" = "$CATEGORY" ] && { TARGET="$rf"; break; }
    done
fi
EXISTS=false; PREFIX=""; NEXT=""; SIMILAR='[]'
if [ -f "$TARGET" ]; then
    EXISTS=true
    PREFIX=$(grep -oE '^## SP-[[:upper:][:digit:]]+-[0-9]+' "$TARGET" | sed -E 's/^## SP-//; s/-[0-9]+$//' | sort | uniq -c | sort -rn | awk 'NR==1{print $2}')
    if [ -n "$PREFIX" ]; then
        MAXN=$(grep -oE "^## SP-${PREFIX}-[0-9]+" "$TARGET" | sed -E 's/.*-0*([0-9]+)$/\1/' | sort -n | tail -1)
        NEXT=$(printf 'SP-%s-%03d' "$PREFIX" $(( ${MAXN:-0} + 1 )))
    fi
    # 제목 낱말 겹침 — 두 글자 이상 낱말이 둘 이상 겹치면 후보
    SIMILAR=$(grep -E '^## SP-' "$TARGET" | LC_ALL=C awk -v words="$WORDS" '
        BEGIN { n = split(tolower(words), w, /[^[:alnum:]\200-\377]+/); for (i = 1; i <= n; i++) if (length(w[i]) >= 2) want[w[i]] = 1 }
        {
            id = $2; sub(/:$/, "", id); title = $0; sub(/^## SP-[^:]*:[[:space:]]*/, "", title)
            m = split(tolower(title), t, /[^[:alnum:]\200-\377]+/); shared = ""; c = 0
            for (j = 1; j <= m; j++) if ((t[j] in want) && !(t[j] in seen)) { seen[t[j]] = 1; c++; shared = shared (shared == "" ? "" : "\t") t[j] }
            delete seen
            if (c >= 2) printf "%s\t%s\t%s\n", id, title, shared
        }' | jq -Rn '[inputs|select(length>0)|split("\t")|{id:.[0], title:.[1], shared:.[2:]}]')
else
    TARGET="$RULES_DIR/$CATEGORY.md"
fi

EXTS=$(printf '%s\n' "$ALL_PATHS" | awk -F. 'NF>1{print $NF}' | awk 'NF && !s[$0]++' | jq -Rn '[inputs|select(length>0)]')
DIRS=$(printf '%s\n' "$ALL_PATHS" | awk 'NF{ sub(/\/[^\/]*$/, ""); print }' | awk 'NF && !s[$0]++' | jq -Rn '[inputs|select(length>0)]')
ENF="human"; [ "$ANY_PATTERN" = true ] && [ "$ALL_COMPILE" = true ] && ENF="grep"

RESULT=$(jq -nc --arg cat "$CATEGORY" --arg tf "${TARGET#"$PROJECT_ROOT"/}" --argjson ex "$EXISTS" --arg pre "$PREFIX" \
    --arg next "$NEXT" --argjson sim "$SIMILAR" --argjson ms "$M_JSON" --argjson exts "$EXTS" --argjson dirs "$DIRS" --arg enf "$ENF" \
    '{category:$cat, target:{file:$tf, exists:$ex}, prefix:(if $pre=="" then null else $pre end),
      next_id:(if $next=="" then null else $next end), similar:$sim, mistakes:$ms,
      paths:{extensions:$exts, dirs:$dirs}, enforcement:$enf}')
NEXT_STEP="룰 하나를 고정 틀로 써요 (.ax/docs/reference/writing-for-agents.md). similar 가 있으면 새 룰 대신 그 룰을 고칠지 먼저 사용자에게 물어요"
[ "$EXISTS" = false ] && NEXT_STEP="${TARGET#"$PROJECT_ROOT"/} 가 없어요. .ax/_templates/spirit/rule.md 를 복사해 만들고, 접두사는 사용자와 정해요. ${NEXT_STEP}"
if [ "$JSON_MODE" = true ]; then
    json_output "ok" "$RESULT" "$NEXT_STEP"
else
    printf '%s\n' "$RESULT" | jq .
    goax_log "$NEXT_STEP"
fi
exit "$EXIT_OK"
