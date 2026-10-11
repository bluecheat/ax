#!/usr/bin/env bash
# .ax/scripts/bash/rules-compress.sh — 룰을 줄이기 전 사본을 잡고, 줄인 뒤 바뀌면 안 되는 것이 그대로인지 확인해요
#
# Usage:
#   bash rules-compress.sh --snapshot [<룰 파일>…] [--json] [--dry-run]   # 기본: 모든 룰 파일
#   bash rules-compress.sh --verify [--json]
#   bash rules-compress.sh --clear [--json]
#
# --snapshot  룰 파일 사본을 .ax/.rules-snapshot/ 에 둬요 (gitignore 대상). 있던 사본은 바꿔요.
# --verify    사본과 지금 파일을 비교해요. 아래 하나라도 다르면 status error · exit 1 이에요.
#               ids        SP ID 집합과 순서
#               frontmatter frontmatter 바이트 (paths · severity · enforced_by 가 여기 있어요)
#               patterns   `검출 패턴` 마커 (goax_rule_patterns 출력)
#               examples   검출 패턴이 있는 룰의 ✅/❌ 예시 — 프로브가 쓰는 예시라 옮기거나 지우면 안 돼요
#               probe      ❌ 는 걸리고 ✅ 는 안 걸리던 룰이 이제 그렇지 않음
#               adr        `<!-- adr: … -->` 링크
#             제목 글자가 바뀐 룰은 위반이 아니라 warnings 에 적어요. 사용자 확인이 필요해요.
# --clear     사본을 지워요. 사용자가 압축본을 받아들이거나 git 으로 되돌린 뒤에 불러요.
# 백업 파일은 만들지 않아요. 되돌리기는 git 이에요.
#
# Output (--json, --verify):
#   {"status":"ok|error","result":{"files":[{"file":"…","before":{"lines":312,"bytes":13028},"after":{"lines":140,"bytes":6100},
#     "violations":[{"kind":"ids|frontmatter|patterns|examples|probe|adr","id":"SP-…|null","detail":"…"}]}],
#     "violations":0,"saved_bytes":6928},"warnings":["SP-DATA-003 제목이 바뀌었어요: …"],…}
# Exit: 0 ok · 1 error (위반 · 사본 없음) · 2 skipped (jq 없음)

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; DRY_RUN=false; SHOW_HELP=false; MODE=""; ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --json)     JSON_MODE=true ;;
        --dry-run)  DRY_RUN=true ;;
        --snapshot) MODE=snapshot ;;
        --verify)   MODE=verify ;;
        --clear)    MODE=clear ;;
        --help|-h)  SHOW_HELP=true ;;
        --*) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
        *)          ARGS+=("$1") ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
command -v jq >/dev/null 2>&1 || { [ "$JSON_MODE" = true ] && printf '{"status":"skipped","result":{},"next_step":"jq 가 필요해요","warnings":["jq not found"],"errors":[]}\n'; exit "$EXIT_SKIPPED"; }
fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }
[ -n "$MODE" ] || fail "--snapshot · --verify · --clear 중 하나를 줘요"

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
cd "$PROJECT_ROOT" || exit "$EXIT_ERROR"
SNAP=".ax/.rules-snapshot"

rule_files() {
    local f
    for f in .ax/spirit/rules/*.md .ax/modules/*/rules.md; do
        [ -f "$f" ] && [ "$f" != .ax/spirit/rules/README.md ] && printf '%s\n' "$f"
    done
}

# ── --snapshot ─────────────────────────────────────────────────────
if [ "$MODE" = snapshot ]; then
    if [ ${#ARGS[@]} -gt 0 ]; then
        LIST=$(for a in "${ARGS[@]}"; do r=$(goax_normalize_path "$a" "$PROJECT_ROOT"); printf '%s\n' "${r#"$PROJECT_ROOT"/}"; done)
    else
        LIST=$(rule_files)
    fi
    [ -n "$LIST" ] || fail "룰 파일이 없어요 (.ax/spirit/rules/*.md · .ax/modules/*/rules.md)"
    while IFS= read -r f; do
        case "$f" in .ax/spirit/rules/*.md|.ax/modules/*/rules.md) ;; *) fail "룰 파일이 아니에요: $f" ;; esac
        [ -f "$f" ] || fail "파일이 없어요: $f"
    done <<< "$LIST"
    if [ "$DRY_RUN" = false ]; then
        rm -rf "$SNAP"
        while IFS= read -r f; do
            mkdir -p "$SNAP/$(dirname "$f")" && cp "$f" "$SNAP/$f" || fail "사본을 만들지 못했어요: $f"
        done <<< "$LIST"
    fi
    FILES=$(printf '%s\n' "$LIST" | jq -Rn '[inputs|select(length>0)]')
    NEXT="룰을 줄인 뒤 bash .ax/scripts/bash/rules-compress.sh --verify --json 으로 확인해요"
    if [ "$JSON_MODE" = true ]; then
        json_output ok "$(jq -nc --argjson f "$FILES" --arg d "$SNAP" --argjson dry "$DRY_RUN" '{snapshot:$d, files:$f, dry_run:$dry}')" "$NEXT"
    else
        goax_log "사본 $(printf '%s\n' "$LIST" | grep -c .)개 → $SNAP"; goax_log "$NEXT"
    fi
    exit "$EXIT_OK"
fi

# ── --clear ────────────────────────────────────────────────────────
if [ "$MODE" = clear ]; then
    [ "$DRY_RUN" = true ] || rm -rf "$SNAP"
    if [ "$JSON_MODE" = true ]; then json_output ok '{"cleared":true}' ""; else goax_log "사본을 지웠어요"; fi
    exit "$EXIT_OK"
fi

# ── --verify ───────────────────────────────────────────────────────
[ -d "$SNAP" ] || fail "사본이 없어요. 먼저 bash .ax/scripts/bash/rules-compress.sh --snapshot 을 불러요"

frontmatter() { awk 'NR==1 && /^---[[:space:]]*$/ {fm=1; print; next} fm { print; if (/^---[[:space:]]*$/) exit }' "$1"; }
headers() {
    awk '/^[[:space:]]*(```|~~~)/ {f=!f; next} f {next}
         /^## SP-[[:upper:][:digit:]]+-[[:digit:]]+:/ { id=$2; sub(/:$/, "", id); t=$0; sub(/^## [^:]*:[[:space:]]*/, "", t); print id "\t" t }' "$1"
}
adrs() {
    awk '/^[[:space:]]*(```|~~~)/ {f=!f; next} f {next}
         /^## SP-[[:upper:][:digit:]]+-[[:digit:]]+:/ { id=$2; sub(/:$/, "", id); next }
         /<!--[[:space:]]*adr:/ { a=$0; sub(/^.*<!--[[:space:]]*adr:[[:space:]]*/, "", a); sub(/[[:space:]]*-->.*$/, "", a); print (id == "" ? "-" : id) "\t" a }' "$1" | sort
}
# 룰마다 프로브 결과: ok (❌ 는 패턴에 걸리고 ✅ 는 안 걸림) · fail
probe() {
    local file="$1" pats ex id kind text hit status
    pats=$(goax_rule_patterns "$file")
    [ -n "$pats" ] || return 0
    ex=$(goax_rule_examples "$file")
    printf '%s\n' "$pats" | cut -f1 | sort -u | while IFS= read -r id; do
        status=ok
        while IFS=$'\t' read -r _ kind text; do
            [ -n "$kind" ] || continue
            hit=false
            while IFS=$'\t' read -r _ p; do
                printf '%s\n' "$text" | grep -qE -- "$p" 2>/dev/null && { hit=true; break; }
            done < <(printf '%s\n' "$pats" | awk -F '\t' -v id="$id" '$1 == id')
            { [ "$kind" = bad ] && [ "$hit" = false ]; } && status=fail
            { [ "$kind" = good ] && [ "$hit" = true ]; } && status=fail
        done < <(printf '%s\n' "$ex" | awk -F '\t' -v id="$id" '$1 == id')
        printf '%s\t%s\n' "$id" "$status"
    done
}

FILES_JSON='[]'; WARN=(); TOTAL_V=0; SAVED=0
while IFS= read -r snapf; do
    f="${snapf#"$SNAP"/}"
    V='[]'
    addv() { V=$(jq -c --arg k "$1" --arg i "$2" --arg d "$3" '. + [{kind:$k, id:(if $i=="" then null else $i end), detail:$d}]' <<<"$V"); }
    if [ ! -f "$f" ]; then
        addv ids "" "파일이 사라졌어요"
    else
        [ "$(frontmatter "$snapf")" = "$(frontmatter "$f")" ] || addv frontmatter "" "frontmatter 가 바뀌었어요 (paths · severity · enforced_by 는 압축 대상이 아니에요)"
        HB=$(headers "$snapf"); HA=$(headers "$f")
        IB=$(printf '%s\n' "$HB" | cut -f1); IA=$(printf '%s\n' "$HA" | cut -f1)
        if [ "$IB" != "$IA" ]; then
            gone=$(comm -23 <(printf '%s\n' "$IB" | sort) <(printf '%s\n' "$IA" | sort) | grep . | tr '\n' ' ')
            new=$(comm -13 <(printf '%s\n' "$IB" | sort) <(printf '%s\n' "$IA" | sort) | grep . | tr '\n' ' ')
            if [ -n "$gone$new" ]; then
                [ -n "$gone" ] && addv ids "" "없어진 룰: ${gone% }"
                [ -n "$new" ] && addv ids "" "새로 생긴 룰: ${new% }"
            else
                addv ids "" "룰 순서가 바뀌었어요"
            fi
        fi
        while IFS=$'\t' read -r id tb; do
            [ -n "$id" ] || continue
            ta=$(printf '%s\n' "$HA" | awk -F '\t' -v id="$id" '$1 == id { sub(/^[^\t]*\t/, ""); print; exit }')
            [ -n "$ta" ] && [ "$ta" != "$tb" ] && WARN+=("$f $id 제목이 바뀌었어요: '$tb' → '$ta'")
        done <<< "$HB"
        PB=$(goax_rule_patterns "$snapf"); PA=$(goax_rule_patterns "$f")
        if [ "$PB" != "$PA" ]; then
            while IFS= read -r id; do
                [ -n "$id" ] || continue
                [ "$(printf '%s\n' "$PB" | awk -F '\t' -v i="$id" '$1==i')" = "$(printf '%s\n' "$PA" | awk -F '\t' -v i="$id" '$1==i')" ] \
                    || addv patterns "$id" "검출 패턴이 바뀌었어요"
            done < <(printf '%s\n%s\n' "$PB" "$PA" | cut -f1 | awk 'NF && !s[$0]++')
        fi
        PIDS=$(printf '%s\n' "$PB" | cut -f1 | awk 'NF && !s[$0]++')
        if [ -n "$PIDS" ]; then
            EB=$(goax_rule_examples "$snapf"); EA=$(goax_rule_examples "$f")
            while IFS= read -r id; do
                [ "$(printf '%s\n' "$EB" | awk -F '\t' -v i="$id" '$1==i')" = "$(printf '%s\n' "$EA" | awk -F '\t' -v i="$id" '$1==i')" ] \
                    || addv examples "$id" "검출 패턴이 있는 룰의 ✅/❌ 예시가 바뀌었어요 (프로브가 쓰는 예시라 그대로 둬요)"
            done <<< "$PIDS"
            RB=$(probe "$snapf"); RA=$(probe "$f")
            while IFS=$'\t' read -r id st; do
                [ "$st" = ok ] || continue
                [ "$(printf '%s\n' "$RA" | awk -F '\t' -v i="$id" '$1==i {print $2}')" = ok ] \
                    || addv probe "$id" "❌ 는 걸리고 ✅ 는 안 걸리던 룰이 이제 그렇지 않아요"
            done <<< "$RB"
        fi
        [ "$(adrs "$snapf")" = "$(adrs "$f")" ] || addv adr "" "<!-- adr: --> 링크가 바뀌었어요"
    fi
    LB=$(wc -l < "$snapf"); BB=$(wc -c < "$snapf"); LA=0; BA=0
    [ -f "$f" ] && { LA=$(wc -l < "$f"); BA=$(wc -c < "$f"); }
    SAVED=$(( SAVED + BB - BA ))
    TOTAL_V=$(( TOTAL_V + $(jq 'length' <<<"$V") ))
    FILES_JSON=$(jq -c --arg f "$f" --argjson lb "$LB" --argjson bb "$BB" --argjson la "$LA" --argjson ba "$BA" --argjson v "$V" \
        '. + [{file:$f, before:{lines:$lb, bytes:$bb}, after:{lines:$la, bytes:$ba}, violations:$v}]' <<<"$FILES_JSON")
done < <(find "$SNAP" -type f -name '*.md' | sort)

RESULT=$(jq -nc --argjson fs "$FILES_JSON" --argjson v "$TOTAL_V" --argjson s "$SAVED" '{files:$fs, violations:$v, saved_bytes:$s}')
WJ=$(printf '%s\n' ${WARN[@]+"${WARN[@]}"} | jq -Rn '[inputs|select(length>0)]')
if [ "$TOTAL_V" -gt 0 ]; then
    STATUS=error; NEXT="위반 ${TOTAL_V}건을 되돌린 뒤 --verify 를 다시 불러요"
    EJ=$(jq -c '[.files[] | .file as $f | .violations[] | "\($f)\(if .id then " " + .id else "" end) [\(.kind)] \(.detail)"]' <<<"$RESULT")
else
    STATUS=ok; NEXT="사용자에게 줄어든 바이트(${SAVED})와 diff 를 보여주고 받아들일지 물어요. 받아들이면 --clear 를 불러요"
    EJ='[]'
fi
if [ "$JSON_MODE" = true ]; then
    json_output "$STATUS" "$RESULT" "$NEXT" "$WJ" "$EJ"
else
    printf '%s\n' "$RESULT" | jq .
    goax_log "$NEXT"
fi
[ "$TOTAL_V" -gt 0 ] && exit "$EXIT_ERROR"
exit "$EXIT_OK"
