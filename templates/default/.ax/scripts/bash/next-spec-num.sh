#!/usr/bin/env bash
# .ax/scripts/bash/next-spec-num.sh — 다음 spec/ADR 번호 계산
#
# Usage:
#   bash next-spec-num.sh [--kind spec|adr] [--reserve --slug <slug>] [--json] [--dry-run] [--help]
#   bash next-spec-num.sh [--kind spec|adr] --check-duplicates [--json]
#
# --kind spec (기본) — .ax/docs/spec/NNN-*/ 스캔, NNN 3자리 zero-pad (overflow: 999)
# --kind adr        — .ax/docs/adr/NNNN-*.md 스캔, NNNN 4자리 zero-pad (overflow: 9999)
#
# --reserve --slug <slug>  번호를 *원자적으로* 선점하고 실물까지 만들어요.
#   계산만 하면 두 세션이 같은 max+1 을 받아 번호가 겹쳐요 (실사용에서 발생).
#   그래서 번호만으로 먼저 만들고(NNN / NNNN.md) 곧바로 slug 를 붙여 rename 해요.
#   - spec: mkdir NNN        → 실패하면 그 번호는 남이 가져간 것 → NNN+1 재시도
#   - adr : noclobber > NNNN.md → 같은 원리 (O_EXCL)
#   슬러그 없는 예약 상태도 스캔 glob 에 잡히도록 glob 이 `NNN*` 이에요 —
#   `NNN-*` 였다면 rename 직전 창에서 다른 세션이 같은 번호를 또 골라요.
#
# Output (--json):
#   {"status":"ok","result":{"next":"005","previous":"004","existing_count":4,
#                            "reserved":true,"path":".ax/docs/spec/005-foo"},...}
#
# Output (text):
#   005

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

if [ "$RESERVE" = true ] && [ -z "$SLUG" ]; then
    if [ "$JSON_MODE" = true ]; then json_error "--reserve requires --slug <slug>"; fi
    goax_error "--reserve requires --slug <slug>"; exit "$EXIT_ERROR"
fi

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# //; s/^#//'
    exit "$EXIT_OK"
fi

case "$KIND" in
    spec|adr) ;;
    *) goax_error "invalid --kind: $KIND (spec|adr)"; exit "$EXIT_ERROR" ;;
esac

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"

# ── kind 별 파라미터 ──────────────────────────────────────────────
# GLOB 이 `NNN-*` 가 아니라 `NNN*` 인 게 핵심이에요. 예약 단계의 이름은 아직
# slug 가 없는 `NNN` 이라, `NNN-*` 로 스캔하면 다른 세션이 그 예약을 못 보고
# 같은 번호를 또 골라요 (실사용에서 ADR 7 쌍이 이렇게 겹쳤어요).
if [ "$KIND" = "adr" ]; then
    NUM_DIR="$PROJECT_ROOT/.ax/docs/adr"
    REL_DIR=".ax/docs/adr"
    GLOB='[0-9][0-9][0-9][0-9]*.md'
    FMT="%04d"; MAX=9999; ZERO="0000"; FIRST="0001"
    FIRST_MSG="first ADR — create .ax/docs/adr/0001-<slug>.md"
    OVERFLOW_MSG="ADR number overflow: 9999 초과 — NNNN-* 4자리 규약 위반. ADR 정리 후 재시도."
else
    NUM_DIR="$PROJECT_ROOT/.ax/docs/spec"
    REL_DIR=".ax/docs/spec"
    GLOB='[0-9][0-9][0-9]*'
    FMT="%03d"; MAX=999; ZERO="000"; FIRST="001"
    FIRST_MSG="first spec — create .ax/docs/spec/001-<slug>/"
    OVERFLOW_MSG="spec number overflow: 999 초과 — NNN-* 3자리 규약 위반. spec 정리/아카이브 후 재시도."
fi

# 번호 원장 — 한 번 쓰인 번호는 영구히 점유돼요.
# ADR 템플릿의 "폐기된 ADR 도 ID 재사용 안 함" 규약과 같은 의미예요.
# 실물만 스캔하면 예약을 rename 하는 순간 번호가 다시 풀려서 경합이 재현돼요.
MARK_DIR="$NUM_DIR/.numbers"

list_artifacts() {
    # shellcheck disable=SC2086
    ls -d "$NUM_DIR"/$GLOB 2>/dev/null | sed 's|.*/||' || true
}

# 실물 번호를 원장에 반영 (기존 프로젝트 자동 백필 — 멱등)
sync_ledger() {
    [ -d "$NUM_DIR" ] || return 0
    mkdir -p "$MARK_DIR" 2>/dev/null || return 0
    local n
    list_artifacts | sed -E 's/^([0-9]+).*/\1/' | sort -u | while IFS= read -r n; do
        [ -n "$n" ] && [ ! -e "$MARK_DIR/$n" ] && : > "$MARK_DIR/$n" 2>/dev/null || true
    done
}

# 점유된 번호 전체 = 실물 ∪ 원장
list_taken() {
    { list_artifacts | sed -E 's/^([0-9]+).*/\1/'
      ls "$MARK_DIR" 2>/dev/null | grep -E '^[0-9]+$' || true
    } | sort -u
}

# 읽기 전용 모드(--check-duplicates / --dry-run)에서는 원장을 건드리지 않아요.
# 백필은 "이미 실물로 존재하는 번호"만 기록하므로 건너뛰어도 계산 결과는 동일해요
# (list_taken 이 실물 ∪ 원장이라 실물 쪽에서 이미 커버돼요).
if [ "$CHECK_DUP" != true ] && [ "$DRY_RUN" != true ]; then
    sync_ledger
fi
ENTRIES=$(list_taken)
# ── 중복 번호 진단 (--check-duplicates) ──────────────────────────
# 예약 도입 이전에 만들어진 충돌은 자동으로 못 고쳐요 (링크가 깨지니까).
# 대신 doctor 가 보이게 해서 사람이 판단하게 해요.
if [ "$CHECK_DUP" = true ]; then
    DUPS=$(list_artifacts | sed -E 's/^([0-9]+).*/\1/' | sort | uniq -d || true)
    DUP_COUNT=$(printf '%s' "$DUPS" | grep -c . || true); DUP_COUNT=${DUP_COUNT:-0}
    if [ "$JSON_MODE" = true ]; then
        DUP_JSON="[]"
        if [ "$DUP_COUNT" -gt 0 ] && command -v jq >/dev/null 2>&1; then
            DUP_JSON=$(printf '%s\n' "$DUPS" | jq -Rn '[inputs | select(length>0)]')
        fi
        RESULT=$(printf '{"duplicates":%s,"duplicate_count":%s}' "$DUP_JSON" "$DUP_COUNT")
        if [ "$DUP_COUNT" -gt 0 ]; then
            json_output "ok" "$RESULT" "중복 번호 ${DUP_COUNT}건 — 링크가 깨질 수 있어 자동 수정하지 않아요. 재번호 여부는 사람이 결정하세요."
        else
            json_output "ok" "$RESULT" "중복 번호 없음"
        fi
    else
        [ "$DUP_COUNT" -gt 0 ] && printf '%s\n' "$DUPS"
    fi
    exit "$EXIT_OK"
fi

EXISTING_COUNT=$(list_artifacts | grep -c . || true)
EXISTING_COUNT=${EXISTING_COUNT:-0}
TAKEN_COUNT=$(printf '%s' "$ENTRIES" | grep -c . || true)
TAKEN_COUNT=${TAKEN_COUNT:-0}

if [ ! -d "$NUM_DIR" ] || [ "$TAKEN_COUNT" -eq 0 ]; then
    PREV="$ZERO"; NEXT="$FIRST"
else
    PREV=$(printf '%s\n' "$ENTRIES" | sed -E 's/^([0-9]+).*/\1/' | sort -n | tail -1)
    PREV="${PREV:-$ZERO}"
    NEXT_NUM=$((10#${PREV} + 1))
    if [ "$NEXT_NUM" -gt "$MAX" ]; then
        if [ "$JSON_MODE" = true ]; then json_error "$OVERFLOW_MSG"; fi
        goax_error "$OVERFLOW_MSG"; exit "$EXIT_ERROR"
    fi
    NEXT=$(printf "$FMT" "$NEXT_NUM")
fi

# ── 계산만 (기존 동작 — 하위호환) ────────────────────────────────
if [ "$RESERVE" != true ]; then
    if [ "$JSON_MODE" = true ]; then
        RESULT=$(printf '{"next":"%s","previous":"%s","existing_count":%s,"reserved":false}' \
                        "$NEXT" "$PREV" "$EXISTING_COUNT")
        if [ "$TAKEN_COUNT" -eq 0 ]; then
            json_output "ok" "$RESULT" "$FIRST_MSG"
        elif [ "$KIND" = "adr" ]; then
            json_output "ok" "$RESULT" "create $REL_DIR/${NEXT}-<slug>.md"
        else
            json_output "ok" "$RESULT" "create $REL_DIR/${NEXT}-<slug>/"
        fi
    else
        echo "$NEXT"
    fi
    exit "$EXIT_OK"
fi

# ── 예약 (--reserve) ──────────────────────────────────────────────
if [ "$KIND" = "adr" ]; then FINAL_REL="$REL_DIR/${NEXT}-${SLUG}.md"; else FINAL_REL="$REL_DIR/${NEXT}-${SLUG}"; fi
if [ "$DRY_RUN" = true ]; then
    if [ "$JSON_MODE" = true ]; then
        RESULT=$(printf '{"next":"%s","previous":"%s","existing_count":%s,"reserved":false,"path":"%s"}' \
                        "$NEXT" "$PREV" "$EXISTING_COUNT" "$FINAL_REL")
        json_output "ok" "$RESULT" "dry-run — would reserve $FINAL_REL"
    else
        echo "$NEXT"
    fi
    exit "$EXIT_OK"
fi

mkdir -p "$NUM_DIR" "$MARK_DIR"

# 원장에 번호를 원자적으로 선점해요 (noclobber = O_EXCL).
# 마커는 지우지 않아요 — 지우면 rename 직후 번호가 풀려 경합이 그대로 재현돼요.
ATTEMPT=0; MAX_ATTEMPT=200; NUM=$((10#${NEXT})); CLAIMED=""
while [ "$ATTEMPT" -lt "$MAX_ATTEMPT" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    if [ "$NUM" -gt "$MAX" ]; then
        if [ "$JSON_MODE" = true ]; then json_error "$OVERFLOW_MSG"; fi
        goax_error "$OVERFLOW_MSG"; exit "$EXIT_ERROR"
    fi
    CAND=$(printf "$FMT" "$NUM")
    if ( set -o noclobber; : > "$MARK_DIR/${CAND}" ) 2>/dev/null; then
        CLAIMED="$CAND"; break
    fi
    NUM=$((NUM + 1))
done

if [ -z "$CLAIMED" ]; then
    if [ "$JSON_MODE" = true ]; then json_error "번호 예약 실패 — ${MAX_ATTEMPT}회 연속 경합. 동시 세션이 비정상적으로 많거나 디렉토리 권한 문제."; fi
    goax_error "번호 예약 실패 (${MAX_ATTEMPT}회 시도)"; exit "$EXIT_ERROR"
fi

if [ "$KIND" = "adr" ]; then
    FINAL="$NUM_DIR/${CLAIMED}-${SLUG}.md"; FINAL_REL="$REL_DIR/${CLAIMED}-${SLUG}.md"
    CREATE_OK=false; : > "$FINAL" 2>/dev/null && CREATE_OK=true
else
    FINAL="$NUM_DIR/${CLAIMED}-${SLUG}";    FINAL_REL="$REL_DIR/${CLAIMED}-${SLUG}"
    CREATE_OK=false; mkdir -p "$FINAL" 2>/dev/null && CREATE_OK=true
fi

if [ "$CREATE_OK" != true ]; then
    # 마커는 남겨요 — 번호를 회수하면 다른 세션이 같은 번호를 집을 수 있어요
    if [ "$JSON_MODE" = true ]; then json_error "번호 ${CLAIMED} 는 예약됐는데 실물 생성 실패: $FINAL_REL (권한 확인)"; fi
    goax_error "실물 생성 실패: $FINAL_REL"; exit "$EXIT_ERROR"
fi

WARN="[]"
[ "$CLAIMED" != "$NEXT" ] && WARN=$(_goax_json_array "번호 경합 — ${NEXT} 는 이미 사용 중이라 ${CLAIMED} 로 예약했어요")

if [ "$JSON_MODE" = true ]; then
    RESULT=$(printf '{"next":"%s","previous":"%s","existing_count":%s,"reserved":true,"path":"%s"}' \
                    "$CLAIMED" "$PREV" "$EXISTING_COUNT" "$FINAL_REL")
    json_output "ok" "$RESULT" "reserved $FINAL_REL — 내용을 채우세요" "$WARN"
else
    echo "$CLAIMED"
fi
