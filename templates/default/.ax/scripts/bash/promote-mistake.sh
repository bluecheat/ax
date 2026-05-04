#!/usr/bin/env bash
# .ax/scripts/bash/promote-mistake.sh — mistake 승격 마킹 (룰 본문은 LLM 이 spirit/rules 에 직접 Edit)
#
# Usage:
#   # 후보 조회 (dry-run 기본)
#   bash promote-mistake.sh [--json] [--threshold N]
#
#   # 실제 적용 (사용자 동의 후) — mistake 에 promoted_to 마킹만
#   bash promote-mistake.sh --apply --token AX:CRITICAL:003 --category security [--json]
#
# 후보 모드: 카테고리당 N건 이상 mistake → 룰 승격 후보 출력
# 적용 모드: mistake 에 promoted_to 마킹만. 룰 본문은 LLM 이 .ax/spirit/rules/<category>.md 에
#           직접 작성 (path-scoped hook 이 매 작업 inject — CLAUDE.md 에 누적 X, heavy 회피).

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
SHOW_HELP=false
APPLY=false
THRESHOLD=2
TOKEN=""
CATEGORY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)      JSON_MODE=true ;;
        --help|-h)   SHOW_HELP=true ;;
        --apply)     APPLY=true ;;
        --threshold) shift; THRESHOLD="${1:-2}" ;;
        --token)     shift; TOKEN="${1:-}" ;;
        --category)  shift; CATEGORY="${1:-}" ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# //'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
MIST_DIR="$PROJECT_ROOT/.ax/mistakes"

if [ ! -d "$MIST_DIR" ]; then
    if [ "$JSON_MODE" = true ]; then json_skip "mistakes/ not found"
    else goax_warn "mistakes/ not found"; fi
    exit "$EXIT_SKIPPED"
fi

# ── 적용 모드 — mistake promoted_to 마킹만 ──
# 룰 본문 작성은 LLM 책임 (audit SKILL 안에서 spirit/rules 직접 Edit). CLAUDE.md 안 건드림.
if [ "$APPLY" = true ]; then
    [ -z "$TOKEN" ]    && { goax_error "--token required"; exit "$EXIT_ERROR"; }
    [ -z "$CATEGORY" ] && { goax_error "--category required"; exit "$EXIT_ERROR"; }

    # 해당 카테고리 mistake 에 promoted_to 마킹 (frontmatter)
    MARKED=()
    while IFS= read -r f; do
        if grep -q "^promoted_to:" "$f" 2>/dev/null; then
            continue
        fi
        if grep -q "^category: $CATEGORY" "$f" 2>/dev/null; then
            # frontmatter 안에 promoted_to 추가 (--- 사이)
            awk -v t="$TOKEN" '
                /^---$/ { c++; if (c==2) print "promoted_to: " t; print; next }
                { print }
            ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
            MARKED+=("$(basename "$f")")
        fi
    done < <(find "$MIST_DIR" -maxdepth 1 -name "*.md" ! -name "README.md")

    if [ "$JSON_MODE" = true ]; then
        marked_json="[$(printf '"%s",' "${MARKED[@]:-}" | sed 's/,$//')]"
        [ "${#MARKED[@]}" -eq 0 ] && marked_json="[]"
        RESULT=$(printf '{"token":"%s","category":"%s","marked_count":%s,"marked":%s}' \
                        "$TOKEN" "$CATEGORY" "${#MARKED[@]}" "$marked_json")
        json_output "ok" "$RESULT" "edit .ax/spirit/rules/<category>.md — add SP-<CAT>-NNN with paths frontmatter (path-scoped hook 이 매 작업 inject)"
    else
        goax_log "✓ marked ${#MARKED[@]} mistake(s) with promoted_to=$TOKEN — now edit spirit/rules/<category>.md"
    fi
    exit "$EXIT_OK"
fi

# ── 후보 모드 (default) ──
# bash 3.2 호환 — associative array 대신 sort+uniq
TMPLIST=$(mktemp)
trap 'rm -f "$TMPLIST"' EXIT

while IFS= read -r f; do
    [ -z "$f" ] && continue
    # 이미 승격된 건 제외
    if grep -q "^promoted_to:" "$f" 2>/dev/null; then continue; fi
    cat=$(grep -m1 "^category:" "$f" 2>/dev/null | awk '{print $2}' || true)
    [ -z "$cat" ] && continue
    echo "$cat" >> "$TMPLIST"
done < <(find "$MIST_DIR" -maxdepth 1 -name "*.md" ! -name "README.md" 2>/dev/null)

CANDIDATES=()
TOTAL_CATS=0
if [ -s "$TMPLIST" ]; then
    while IFS= read -r line; do
        cnt=$(echo "$line" | awk '{print $1}')
        cat=$(echo "$line" | awk '{print $2}')
        TOTAL_CATS=$((TOTAL_CATS + 1))
        if [ "$cnt" -ge "$THRESHOLD" ]; then
            CANDIDATES+=("$cat:$cnt")
        fi
    done < <(sort "$TMPLIST" | uniq -c | sort -rn)
fi

if [ "$JSON_MODE" = true ]; then
    cand_json="["
    first=true
    if [ "${#CANDIDATES[@]:-0}" -gt 0 ]; then
        for c in "${CANDIDATES[@]}"; do
            cat="${c%%:*}"; cnt="${c##*:}"
            [ "$first" = true ] || cand_json+=","
            cand_json+="{\"category\":\"$cat\",\"count\":$cnt}"
            first=false
        done
    fi
    cand_json+="]"
    RESULT=$(printf '{"candidates":%s,"threshold":%s,"total_categories":%s}' \
                    "$cand_json" "$THRESHOLD" "$TOTAL_CATS")
    json_output "ok" "$RESULT" "review candidates and run --apply with --token --category. then edit .ax/spirit/rules/<category>.md (LLM)"
else
    if [ "${#CANDIDATES[@]:-0}" -eq 0 ]; then
        goax_log "no candidates over threshold $THRESHOLD"
    else
        goax_log "promotion candidates (threshold $THRESHOLD):"
        for c in "${CANDIDATES[@]}"; do
            cat="${c%%:*}"; cnt="${c##*:}"
            goax_log "  $cat: $cnt 건"
        done
    fi
fi
