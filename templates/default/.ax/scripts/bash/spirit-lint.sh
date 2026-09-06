#!/usr/bin/env bash
# .ax/scripts/bash/spirit-lint.sh — Spirit 무결성 lint (values · tone · rules/ + modules/*/rules.md)
#
# Usage:
#   bash spirit-lint.sh [--json] [--strict]
#
# 검사 (spirit skill 이 산문으로 시키던 것을 스크립트로 옮겼어요 — doctor 가 불러요):
#   F1 필수 파일    values.md · tone.md 존재 + 비어있지 않음, rules/ 디렉토리, _templates/spirit/rule.md
#   F2 frontmatter  rules/<cat>.md 마다 `category:` 키
#   F3 헤더 형식    `## ` 헤더는 전부 `## SP-<CAT>-<NNN>: 제목` (spirit/rules + modules/*/rules.md)
#   F4 토큰 중복    같은 SP-<CAT>-<NNN> 이 어디서든 두 번 (spirit ↔ modules 교차 포함)
#   F5 placeholder  values/tone/rules 에 템플릿 잔재 (`__X__` · `<여기에` · `<자기 팀` · `TODO(goax)`)
#
# 자동 수정은 안 해요 — 위치만 알려줘요. 헤더 형식은 `.ax/docs/reference/rules-tokens.md` 가 SSOT.
#
# Output (--json):
#   {"status":"ok|warning","result":{"files":{"values":true,"tone":true,"rules_dir":true,"rule_template":true},
#     "rules_files":N,"rules_count":N,"missing_files":[],"missing_frontmatter":[],
#     "bad_headers":[{"file":"…","line":N,"text":"…"}],"duplicates":[{"token":"SP-X-001","files":["…"]}],
#     "placeholders":[{"file":"…","line":N}],"findings":N,"ok":bool},…}
# Exit: 0 ok/warning · 1 error · --strict 면 findings > 0 일 때 1

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; STRICT=false; DRY_RUN=false
while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --strict)  STRICT=true ;;
        --dry-run) DRY_RUN=true ;;   # 읽기 전용 스크립트 — 표준 옵션 호환용
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then
    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
SP="$PROJECT_ROOT/.ax/spirit"

# ── F1 필수 파일 ─────────────────────────────────────────────────
F_VALUES=false; F_TONE=false; F_RULES=false; F_TPL=false
MISSING=()
[ -s "$SP/values.md" ] && F_VALUES=true || MISSING+=(".ax/spirit/values.md")
[ -s "$SP/tone.md" ]   && F_TONE=true   || MISSING+=(".ax/spirit/tone.md")
[ -d "$SP/rules" ]     && F_RULES=true  || MISSING+=(".ax/spirit/rules/")
[ -f "$PROJECT_ROOT/.ax/_templates/spirit/rule.md" ] && F_TPL=true || MISSING+=(".ax/_templates/spirit/rule.md")

# ── 검사 대상 룰 파일 (spirit/rules/*.md + modules/*/rules.md, README 제외) ──
RULE_FILES=()
while IFS= read -r f; do [ -n "$f" ] && RULE_FILES+=("$f"); done < <(
    { find "$SP/rules" -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null
      find "$PROJECT_ROOT/.ax/modules" -mindepth 2 -maxdepth 2 -name 'rules.md' 2>/dev/null; } | sort)
SPIRIT_N=$(find "$SP/rules" -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')

rel() { printf '%s' "${1#"$PROJECT_ROOT"/}"; }

# ── F2 frontmatter (spirit/rules 만 — modules 는 module: 키가 따로 있어요) ──
NO_FM=()
for f in "${RULE_FILES[@]:-}"; do
    [ -n "$f" ] || continue
    case "$f" in "$SP"/rules/*) ;; *) continue ;; esac
    head -1 "$f" | grep -q '^---[[:space:]]*$' || { NO_FM+=("$(rel "$f")"); continue; }
    awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f" | grep -qE '^category:[[:space:]]*[^[:space:]]' \
        || NO_FM+=("$(rel "$f")")
done

# ── F3 헤더 형식 · F4 중복 · F5 placeholder ─────────────────────
BAD_JSON="[]"; DUP_JSON="[]"; PH_JSON="[]"
BAD_N=0; DUP_N=0; PH_N=0; RULES_COUNT=0
TOK_LIST=""   # "TOKEN<TAB>file" 누적
if [ "${#RULE_FILES[@]}" -gt 0 ]; then
    for f in "${RULE_FILES[@]}"; do
        r=$(rel "$f")
        # 비표준 `## ` 헤더
        while IFS= read -r ln; do
            [ -z "$ln" ] && continue
            BAD_N=$((BAD_N + 1))
            n=${ln%%:*}; t=${ln#*:}
            [ "$JSON_MODE" = true ] && BAD_JSON=$(printf '%s' "$BAD_JSON" | jq -c --arg f "$r" --arg n "$n" --arg t "$t" '. + [{file:$f,line:($n|tonumber),text:$t}]')
            [ "$JSON_MODE" = true ] || printf '  ✗ %s:%s — 비표준 헤더: %s\n' "$r" "$n" "$t"
        done < <(grep -nE '^## ' "$f" | grep -vE '^[0-9]+:## SP-[A-Z]+-[0-9]{3}: ' || true)
        # 토큰 수집
        while IFS= read -r tok; do
            [ -z "$tok" ] && continue
            RULES_COUNT=$((RULES_COUNT + 1))
            TOK_LIST="${TOK_LIST}${tok}	${r}
"
        done < <(grep -oE '^## SP-[A-Z]+-[0-9]{3}:' "$f" | sed -E 's/^## //; s/:$//' || true)
        # placeholder
        while IFS= read -r ln; do
            [ -z "$ln" ] && continue
            PH_N=$((PH_N + 1))
            n=${ln%%:*}
            [ "$JSON_MODE" = true ] && PH_JSON=$(printf '%s' "$PH_JSON" | jq -c --arg f "$r" --arg n "$n" '. + [{file:$f,line:($n|tonumber)}]')
            [ "$JSON_MODE" = true ] || printf '  ⚠ %s:%s — 템플릿 placeholder 잔재\n' "$r" "$n"
        done < <(grep -nE '__[A-Za-z_]+__|<여기에|<자기 팀|TODO\(goax\)' "$f" || true)
    done
fi
for f in "$SP/values.md" "$SP/tone.md"; do
    [ -f "$f" ] || continue
    r=$(rel "$f")
    while IFS= read -r ln; do
        [ -z "$ln" ] && continue
        PH_N=$((PH_N + 1)); n=${ln%%:*}
        [ "$JSON_MODE" = true ] && PH_JSON=$(printf '%s' "$PH_JSON" | jq -c --arg f "$r" --arg n "$n" '. + [{file:$f,line:($n|tonumber)}]')
        [ "$JSON_MODE" = true ] || printf '  ⚠ %s:%s — 템플릿 placeholder 잔재\n' "$r" "$n"
    done < <(grep -nE '__[A-Za-z_]+__|<여기에|<자기 팀|TODO\(goax\)' "$f" || true)
done
# 중복 토큰 — 파일 경계 없이
if [ -n "$TOK_LIST" ]; then
    while IFS= read -r tok; do
        [ -z "$tok" ] && continue
        DUP_N=$((DUP_N + 1))
        files=$(printf '%s' "$TOK_LIST" | awk -F'\t' -v t="$tok" '$1==t{print $2}' | sort -u)
        if [ "$JSON_MODE" = true ]; then
            fj=$(printf '%s\n' "$files" | jq -R . | jq -sc .)
            DUP_JSON=$(printf '%s' "$DUP_JSON" | jq -c --arg t "$tok" --argjson f "$fj" '. + [{token:$t,files:$f}]')
        else
            printf '  ✗ %s 중복 — %s\n' "$tok" "$(printf '%s' "$files" | tr '\n' ' ')"
        fi
    done < <(printf '%s' "$TOK_LIST" | cut -f1 | sort | uniq -d)
fi

FINDINGS=$(( ${#MISSING[@]} + ${#NO_FM[@]} + BAD_N + DUP_N + PH_N ))
OK=true; [ "$FINDINGS" -gt 0 ] && OK=false

if [ "$JSON_MODE" = true ]; then
    mj=$(printf '%s\n' "${MISSING[@]:-}" | grep -v '^$' | jq -R . | jq -sc .)
    fmj=$(printf '%s\n' "${NO_FM[@]:-}" | grep -v '^$' | jq -R . | jq -sc .)
    RESULT=$(jq -nc \
        --argjson v "$F_VALUES" --argjson t "$F_TONE" --argjson rd "$F_RULES" --argjson tp "$F_TPL" \
        --arg rf "$SPIRIT_N" --arg rc "$RULES_COUNT" --argjson m "$mj" --argjson fm "$fmj" \
        --argjson bad "$BAD_JSON" --argjson dup "$DUP_JSON" --argjson ph "$PH_JSON" \
        --arg fn "$FINDINGS" --argjson ok "$OK" \
        '{files:{values:$v,tone:$t,rules_dir:$rd,rule_template:$tp},rules_files:($rf|tonumber),rules_count:($rc|tonumber),
          missing_files:$m,missing_frontmatter:$fm,bad_headers:$bad,duplicates:$dup,placeholders:$ph,findings:($fn|tonumber),ok:$ok}')
    if [ "$OK" = true ]; then
        json_output "ok" "$RESULT" "Spirit 무결성 이상 없음 — ${SPIRIT_N} 카테고리 · SP 토큰 ${RULES_COUNT}개"
    else
        json_output "warning" "$RESULT" "finding ${FINDINGS}건 — 위치를 보고 직접 고쳐요 (자동 수정 안 함). 형식: .ax/docs/reference/rules-tokens.md"
    fi
else
    printf '🧪 Spirit lint — %s 카테고리 · SP 토큰 %s개\n' "$SPIRIT_N" "$RULES_COUNT"
    for m in "${MISSING[@]:-}"; do [ -n "$m" ] && printf '  ✗ 필수 파일 없음: %s\n' "$m"; done
    for m in "${NO_FM[@]:-}"; do [ -n "$m" ] && printf '  ✗ frontmatter category: 누락: %s\n' "$m"; done
    if [ "$OK" = true ]; then printf '  ✓ 이상 없음\n'; else printf '  → finding %s건 (자동 수정 안 함)\n' "$FINDINGS"; fi
fi

if [ "$STRICT" = true ] && [ "$OK" = false ]; then exit "$EXIT_ERROR"; fi
exit "$EXIT_OK"
