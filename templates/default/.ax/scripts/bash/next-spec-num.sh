#!/usr/bin/env bash
# .ax/scripts/bash/next-spec-num.sh — 새 spec/ADR ID 발급 (이름은 옛 "번호" 시절 그대로)
#
# Usage:
#   bash next-spec-num.sh [--kind spec|adr] [--reserve --slug <slug>] [--json] [--dry-run] [--help]
#   bash next-spec-num.sh [--kind spec|adr] --check-duplicates [--json]
#
# ID 형식: `YYYY-MM-DD-<4hex>` (예: 2026-09-25-a3f1) — mistakes 파일과 같은 날짜+난수 계열이에요.
#   spec → .ax/docs/spec/<id>-<slug>/      ADR → .ax/docs/adr/<id>-<slug>.md
#
# 왜: 순번은 "디렉토리 최댓값 + 1" 이라 브랜치마다 같은 번호를 받아요 (실측: spec 중복 8 · ADR 중복 12).
#   날짜+난수는 서로를 볼 필요가 없고, 드물게 겹치면 O_EXCL 생성이 실패해 다시 뽑아요.
# 옛 순번(`NNN-slug/`, `NNNN-slug.md`)은 그대로 읽어요 — 이름을 바꾸면 링크가 깨져요. `--check-duplicates` 는 그 중복을 보고해요.
#
# --reserve --slug <slug>  ID 를 뽑아 실물까지 원자적으로 만들어요 (spec: mkdir, adr: noclobber).
#                          --dry-run 이면 아무것도 안 만들고 경로만 보여줘요.
# (--reserve 없이) 계산만  새 ID 미리보기 — 예약이 아니라서 호출할 때마다 달라요.
#
# Output (--json):
#   {"status":"ok","result":{"next":"2026-09-25-a3f1","previous":"<가장 최근 항목 이름>|null","existing_count":4,
#                            "reserved":true,"path":".ax/docs/spec/2026-09-25-a3f1-foo"},...}
#   --check-duplicates: {"duplicates":["0008",…],"duplicate_count":N}
#
# Output (text): 2026-09-25-a3f1
# Exit: 0 ok · 1 error
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
SHOW_HELP=false
DRY_RUN=false
RESERVE=false
CHECK_DUP=false
SLUG=""
KIND="spec"
while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --reserve) RESERVE=true ;;
        --check-duplicates) CHECK_DUP=true ;;
        --slug)    shift; SLUG="${1:-}" ;;
        --kind)    shift; KIND="${1:-spec}" ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then
    goax_help "${BASH_SOURCE[0]}"
    exit "$EXIT_OK"
fi
if [ "$RESERVE" = true ] && [ -z "$SLUG" ]; then
    if [ "$JSON_MODE" = true ]; then json_error "--reserve requires --slug <slug>"; fi
    goax_error "--reserve requires --slug <slug>"; exit "$EXIT_ERROR"
fi
case "$KIND" in
    spec|adr) ;;
    *) goax_error "invalid --kind: $KIND (spec|adr)"; exit "$EXIT_ERROR" ;;
esac

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
if [ "$KIND" = "adr" ]; then
    DIR="$PROJECT_ROOT/.ax/docs/adr"; REL_DIR=".ax/docs/adr"
else
    DIR="$PROJECT_ROOT/.ax/docs/spec"; REL_DIR=".ax/docs/spec"
fi

# 항목 이름 (ADR 은 .md 뗀 것) — 새 ID 든 옛 순번이든 숫자로 시작하는 것만
list_artifacts() {
    [ -d "$DIR" ] || return 0
    if [ "$KIND" = "adr" ]; then
        find "$DIR" -maxdepth 1 -type f -name '[0-9]*.md' 2>/dev/null | sed 's|.*/||; s|\.md$||'
    else
        find "$DIR" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' 2>/dev/null | sed 's|.*/||'
    fi
}

# ── 중복 진단 (--check-duplicates) ────────────────────────────────
# 옛 순번은 번호 부분끼리, 새 ID 는 ID 부분끼리 비교해요. 자동으로 고치지 않아요 (링크가 깨져요).
if [ "$CHECK_DUP" = true ]; then
    DUPS=$(list_artifacts | goax_doc_key | sort | uniq -d || true)
    DUP_COUNT=$(printf '%s' "$DUPS" | grep -c . || true); DUP_COUNT=${DUP_COUNT:-0}
    if [ "$JSON_MODE" = true ]; then
        DUP_JSON="[]"
        if [ "$DUP_COUNT" -gt 0 ] && command -v jq >/dev/null 2>&1; then
            DUP_JSON=$(printf '%s\n' "$DUPS" | jq -Rn '[inputs | select(length>0)]')
        fi
        RESULT=$(printf '{"duplicates":%s,"duplicate_count":%s}' "$DUP_JSON" "$DUP_COUNT")
        if [ "$DUP_COUNT" -gt 0 ]; then
            json_output "ok" "$RESULT" "중복 번호 ${DUP_COUNT}건 — 링크가 깨질 수 있어 자동 수정하지 않아요. 새 항목은 날짜+난수 ID 라 더 겹치지 않아요."
        else
            json_output "ok" "$RESULT" "중복 번호 없음"
        fi
    else
        [ "$DUP_COUNT" -gt 0 ] && printf '%s\n' "$DUPS"
    fi
    exit "$EXIT_OK"
fi

EXISTING_COUNT=$(list_artifacts | grep -c . || true); EXISTING_COUNT=${EXISTING_COUNT:-0}
# 가장 최근 항목 — 새 ID 가 옛 순번보다 뒤, 같은 형식끼리는 이름순 (날짜·순번이 앞에 있어요)
PREV=$(list_artifacts | goax_doc_sort | tail -1 || true)

make_path() {   # make_path <id> → 절대 경로
    if [ "$KIND" = "adr" ]; then printf '%s/%s-%s.md' "$DIR" "$1" "$SLUG"; else printf '%s/%s-%s' "$DIR" "$1" "$SLUG"; fi
}
emit() {   # emit <id> <reserved> [path_rel] [next_step]
    if [ "$JSON_MODE" = true ]; then
        RESULT=$(jq -nc --arg next "$1" --arg prev "$PREV" --argjson n "$EXISTING_COUNT" \
                        --argjson reserved "$2" --arg path "${3:-}" \
            '{next: $next, previous: (if $prev == "" then null else $prev end), existing_count: $n, reserved: $reserved}
             + (if $path == "" then {} else {path: $path} end)')
        json_output "ok" "$RESULT" "${4:-}"
    else
        echo "$1"
    fi
}

# ── 계산만 (미리보기) ──────────────────────────────────────────────
if [ "$RESERVE" != true ]; then
    ID=$(goax_doc_id)
    if [ "$KIND" = "adr" ]; then emit "$ID" false "" "create $REL_DIR/${ID}-<slug>.md (--reserve --slug 로 선점)"
    else emit "$ID" false "" "create $REL_DIR/${ID}-<slug>/ (--reserve --slug 로 선점)"; fi
    exit "$EXIT_OK"
fi

# ── 예약 (--reserve) ──────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
    ID=$(goax_doc_id); P=$(make_path "$ID")
    emit "$ID" false "${P#"$PROJECT_ROOT"/}" "dry-run — would reserve ${P#"$PROJECT_ROOT"/}"
    exit "$EXIT_OK"
fi

mkdir -p "$DIR"
CLAIMED=""; ATTEMPT=0
while [ "$ATTEMPT" -lt 20 ]; do
    ATTEMPT=$((ATTEMPT + 1))
    ID=$(goax_doc_id); P=$(make_path "$ID")
    if [ "$KIND" = "adr" ]; then
        ( set -o noclobber; : > "$P" ) 2>/dev/null && { CLAIMED="$ID"; break; }
    else
        mkdir "$P" 2>/dev/null && { CLAIMED="$ID"; break; }
    fi
done
if [ -z "$CLAIMED" ]; then
    if [ "$JSON_MODE" = true ]; then json_error "ID 예약 실패 — 20회 연속 실패. 디렉토리 권한을 확인하세요: $REL_DIR"; fi
    goax_error "ID 예약 실패 (20회 시도): $REL_DIR"; exit "$EXIT_ERROR"
fi
emit "$CLAIMED" true "${P#"$PROJECT_ROOT"/}" "reserved ${P#"$PROJECT_ROOT"/} — 내용을 채우세요"
exit "$EXIT_OK"
