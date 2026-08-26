#!/usr/bin/env bash
# .ax/scripts/bash/promote-mistake.sh — mistake 승격 마킹 + archive (룰 본문은 LLM 이 spirit/rules 에 직접 Edit)
#
# Usage:
#   # 후보 조회 (dry-run 기본)
#   bash promote-mistake.sh [--json] [--threshold N]
#
#   # 1단계 — mistake 에 promoted_to 마킹
#   bash promote-mistake.sh --apply --token AX:CRITICAL:003 --category security [--json]
#
#   # 2단계 (LLM 이 spirit/rules 룰 본문 작성한 후) — archive 로 이동
#   bash promote-mistake.sh --archive --token AX:CRITICAL:003 [--json]
#
# 후보 모드: 카테고리당 N건 이상 mistake → 룰 승격 후보 출력
# 적용 모드: mistake 에 promoted_to 마킹만. 룰 본문은 LLM 이 .ax/spirit/rules/<category>.md 에
#           직접 작성 (path-scoped hook 이 매 작업 inject — CLAUDE.md 에 누적 X, heavy 회피).
# archive 모드: SP 토큰이 spirit/rules/*.md 에 존재하는지 검증 후, promoted_to=<token> 마킹된
#               mistake 파일을 .ax/mistakes/_archive/<YYYY>/<MM>/ 로 이동. 검색 candidate 에서 제외.

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
SHOW_HELP=false
APPLY=false
ARCHIVE=false
THRESHOLD=""
THRESHOLD_SET=false
TOKEN=""
CATEGORY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)      JSON_MODE=true ;;
        --help|-h)   SHOW_HELP=true ;;
        --apply)     APPLY=true ;;
        --archive)   ARCHIVE=true ;;
        --threshold)
            shift; THRESHOLD="${1:-}"
            case "$THRESHOLD" in
                ''|*[!0-9]*) goax_error "--threshold 는 양의 정수가 필요해요 (받은 값: '$THRESHOLD')"; exit "$EXIT_ERROR" ;;
            esac
            THRESHOLD_SET=true ;;
        --token)     shift; TOKEN="${1:-}" ;;
        --category)  shift; CATEGORY="${1:-}" ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# //'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
MIST_DIR="$PROJECT_ROOT/.ax/mistakes"

# threshold SSOT — .ax/config.yml 의 mistake_loop.promotion_threshold 를 기본값으로.
# --threshold 로 명시하면 그 값이 우선. config.yml 없거나 숫자 파싱 실패 시 3 (config.yml
# 기본 shipped 값과 동일 — 두 곳이 어긋나지 않도록).
if [ "$THRESHOLD_SET" != true ]; then
    CONFIG="$PROJECT_ROOT/.ax/config.yml"
    CFG_THRESHOLD=""
    if [ -f "$CONFIG" ]; then
        CFG_THRESHOLD=$(grep -E '^[[:space:]]*promotion_threshold:[[:space:]]*' "$CONFIG" 2>/dev/null \
            | head -1 | sed -E 's/^[^:]*:[[:space:]]*//' | awk '{print $1}')
    fi
    case "$CFG_THRESHOLD" in
        ''|*[!0-9]*) THRESHOLD=3 ;;
        *)           THRESHOLD="$CFG_THRESHOLD" ;;
    esac
fi

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
        json_output "ok" "$RESULT" "MANDATORY 2 steps remain: (1) Edit .ax/spirit/rules/<project>-${CATEGORY}.md — add ${TOKEN} with frontmatter paths/severity/enforced_by (new file or append). (2) bash .ax/scripts/bash/promote-mistake.sh --archive --token ${TOKEN} — moves marked mistakes to _archive/YYYY/MM/. Skill must NOT report success until both done — mistake 가 .ax/mistakes/ root 에 promoted_to 마킹된 채 남아 있으면 미완료."
    else
        goax_log "✓ marked ${#MARKED[@]} mistake(s) with promoted_to=$TOKEN — MANDATORY: (1) edit spirit/rules/<project>-${CATEGORY}.md add ${TOKEN}, (2) run --archive --token ${TOKEN}"
    fi
    exit "$EXIT_OK"
fi

# ── archive 모드 — promoted_to 마킹된 파일을 _archive/<YYYY>/<MM>/ 로 이동 ──
# SP 토큰이 spirit/rules/*.md 에 존재하는지 사전 검증 (룰 본문 누락 방지)
if [ "$ARCHIVE" = true ]; then
    [ -z "$TOKEN" ] && { goax_error "--token required"; exit "$EXIT_ERROR"; }

    # SP 토큰 존재 검증 — spirit/rules/*.md 어딘가에 있어야 archive 가능
    SPIRIT_DIR="$PROJECT_ROOT/.ax/spirit/rules"
    if [ ! -d "$SPIRIT_DIR" ] || ! grep -rqE "^## ${TOKEN}([[:space:]:]|$)" "$SPIRIT_DIR" 2>/dev/null; then
        MSG="SP token '${TOKEN}' not found in .ax/spirit/rules/*.md (heading '## ${TOKEN}' or '## ${TOKEN}:'). 룰 본문 먼저 작성 후 다시 시도."
        if [ "$JSON_MODE" = true ]; then json_error "$MSG"
        else goax_error "$MSG"; fi
        exit "$EXIT_ERROR"
    fi

    YEAR=$(date +%Y)
    MONTH=$(date +%m)
    ARCHIVE_DIR="$MIST_DIR/_archive/$YEAR/$MONTH"
    mkdir -p "$ARCHIVE_DIR"

    MOVED=()
    while IFS= read -r f; do
        if grep -qE "^promoted_to: ${TOKEN}([[:space:]]|$)" "$f" 2>/dev/null; then
            mv "$f" "$ARCHIVE_DIR/"
            MOVED+=("$(basename "$f")")
        fi
    done < <(find "$MIST_DIR" -maxdepth 1 -name "*.md" ! -name "README.md")

    if [ "$JSON_MODE" = true ]; then
        moved_json="[$(printf '"%s",' "${MOVED[@]:-}" | sed 's/,$//')]"
        [ "${#MOVED[@]}" -eq 0 ] && moved_json="[]"
        REL_ARCHIVE="${ARCHIVE_DIR#$PROJECT_ROOT/}"
        RESULT=$(printf '{"token":"%s","archived_count":%s,"archived":%s,"archive_dir":"%s"}' \
                        "$TOKEN" "${#MOVED[@]}" "$moved_json" "$REL_ARCHIVE")
        json_output "ok" "$RESULT" "archived ${#MOVED[@]} mistake(s) to ${REL_ARCHIVE} — audit candidate 검색에서 자동 제외"
    else
        goax_log "✓ archived ${#MOVED[@]} mistake(s) → ${ARCHIVE_DIR#$PROJECT_ROOT/}"
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
    if [ "${#CANDIDATES[@]}" -gt 0 ]; then
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
    if [ "${#CANDIDATES[@]}" -eq 0 ]; then
        goax_log "no candidates over threshold $THRESHOLD"
    else
        goax_log "promotion candidates (threshold $THRESHOLD):"
        for c in "${CANDIDATES[@]}"; do
            cat="${c%%:*}"; cnt="${c##*:}"
            goax_log "  $cat: $cnt 건"
        done
    fi
fi
