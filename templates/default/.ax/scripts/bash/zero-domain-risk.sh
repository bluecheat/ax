#!/usr/bin/env bash
# .ax/scripts/bash/zero-domain-risk.sh — config.yml 의 domain_risk 를 이 제품 도메인으로 교체
#
# Usage:
#   bash zero-domain-risk.sh --show [--json]
#   bash zero-domain-risk.sh --set "payment=L3,order=L2,search=L0" [--default L1] \
#                            [--json] [--dry-run] [--help]
#
# 왜 스크립트인가:
#   출고 config.yml 의 domain_risk 는 **예시**(payment/order/product/search)예요.
#   그대로 두면 이 제품의 도메인은 하나도 안 잡히고 전부 default_risk 로 떨어져요.
#   그러면 triage 매트릭스가 "S/M × L0 = 즉시 작업, spec 불필요" 로 흘리고,
#   역면접(M×L2 이상 발동)은 조건 미달로 스킵돼요. 0→1 은 결정 밀도가 가장 높은데
#   하네스가 마찰을 가장 적게 거는 상태가 돼요. 그래서 **첫날에 교체**해요.
#
#   손으로 고치면 조용히 틀려요 (예시 키 잔존·들여쓰기 붕괴·중복 키). 그래서 결정론으로
#   옮겼어요 — 키 검증 + 블록 통째 재작성 + before/after 카운트.
#
# 규칙:
#   - 키는 영문 kebab-case (^[a-z][a-z0-9-]*$), 값은 L0|L1|L2|L3
#   - 기존 domain_risk 블록은 **통째로 교체**돼요 (예시 키가 남지 않게)
#   - domain_risk: 가 없으면 파일 끝에 새 블록을 붙이고 warning 을 내요
#
# Output (--json):
#   {"status":"ok","result":{"before":{"keys":N,"list":[...]},
#                            "after":{"keys":N,"list":[...]},
#                            "default_risk":"L1","dry_run":false},...}
#
# Exit:
#   0  ok
#   1  error (키·레벨 형식 위반, config.yml 부재, 인자 누락)

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
SHOW_HELP=false
SHOW_ONLY=false
SET_SPEC=""
DEFAULT_RISK=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)     JSON_MODE=true ;;
        --dry-run)  DRY_RUN=true ;;
        --show)     SHOW_ONLY=true ;;
        --set)      shift; SET_SPEC="${1:-}" ;;
        --default)  shift; DEFAULT_RISK="${1:-}" ;;
        --help|-h)  SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^#$//; s/^# //'
    exit "$EXIT_OK"
fi

fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
CONFIG="$PROJECT_ROOT/.ax/config.yml"
CONFIG_LOCK="$CONFIG.lock"

if [ ! -f "$CONFIG" ]; then
    MSG=".ax/config.yml 이 없어요 — 먼저 /up 으로 하네스를 설치하세요"
    if [ "$JSON_MODE" = true ]; then json_error "$MSG"; fi
    goax_error "$MSG"; exit "$EXIT_ERROR"
fi

lines_to_json() {   # stdin(줄 목록) → JSON array
    if command -v jq >/dev/null 2>&1; then
        jq -Rn '[inputs | select(length > 0)]'
    else
        printf '[]'
    fi
}

# 키 정규식 — 읽기·검증·재작성 세 곳이 **이 하나**를 봐요.
# `[a-z]` 브래킷은 en_US.UTF-8 collation 에서 대문자를 삼켜요 (`Payment` 이 통과).
# 그래서 POSIX 클래스로 쓰고 LC_ALL=C 로 ASCII 에 고정해요.
KEY_RE='[[:lower:]][[:lower:][:digit:]-]*'
PAIR_RE="^${KEY_RE}=L[0-3]$"

# domain_risk 블록 읽기 — `domain_risk:` 다음부터 첫 비들여쓰기 줄 전까지.
# awk range(/start/,/end/) 는 start 가 end 패턴에도 매칭되면 1줄로 붕괴해요.
# `domain_risk:` 자체가 ^[^[:space:]] 라서 정확히 그 함정이라, flag 로 우회해요.
read_pairs() {
    awk '/^domain_risk:/{f=1;next} f && /^[^[:space:]]/{exit} f' "$1" \
        | LC_ALL=C grep -E '^[[:space:]]+'"$KEY_RE"':[[:space:]]*L[0-3]' \
        | LC_ALL=C sed -E 's/^[[:space:]]+('"$KEY_RE"'):[[:space:]]*(L[0-3]).*/\1=\2/' || true
}

BEFORE=$(read_pairs "$CONFIG")
BEFORE_N=$(printf '%s' "$BEFORE" | grep -c . || true); BEFORE_N=${BEFORE_N:-0}

CUR_DEFAULT=$(grep -E '^default_risk:' "$CONFIG" 2>/dev/null | head -1 | awk '{print $2}' || true)
CUR_DEFAULT=${CUR_DEFAULT:-L1}

# ── --show (또는 --set 없이 호출) ────────────────────────────────
if [ "$SHOW_ONLY" = true ]; then
    if [ "$JSON_MODE" = true ]; then
        BJ=$(printf '%s' "$BEFORE" | lines_to_json)
        RESULT=$(printf '{"before":{"keys":%s,"list":%s},"default_risk":"%s"}' \
                        "$BEFORE_N" "$BJ" "$CUR_DEFAULT")
        json_output "ok" "$RESULT" "현재 도메인 ${BEFORE_N}개 (default_risk=${CUR_DEFAULT})"
    else
        printf '%s\n' "$BEFORE"
        printf 'default_risk: %s\n' "$CUR_DEFAULT"
    fi
    exit "$EXIT_OK"
fi

if [ -z "$SET_SPEC" ]; then
    MSG="--set \"key=L0,...\" 또는 --show 가 필요해요"
    if [ "$JSON_MODE" = true ]; then json_error "$MSG"; fi
    goax_error "$MSG"; exit "$EXIT_ERROR"
fi

# ── --set 파싱 + 검증 ────────────────────────────────────────────
NEW_PAIRS=$(printf '%s' "$SET_SPEC" | tr ',' '\n' \
            | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep -v '^$' || true)
NEW_N=$(printf '%s' "$NEW_PAIRS" | grep -c . || true); NEW_N=${NEW_N:-0}
if [ "$NEW_N" -eq 0 ]; then
    MSG="--set 값이 비었어요 (예: --set \"payment=L3,order=L2\")"
    if [ "$JSON_MODE" = true ]; then json_error "$MSG"; fi
    goax_error "$MSG"; exit "$EXIT_ERROR"
fi

# 검증은 **재작성과 같은 전체 매치 하나**로 해요. 예전엔 검증이 부분 매치 글롭 3개,
# 재작성이 sed 전체 매치라 둘이 어긋났고, 어긋난 입력이 status ok 로 데이터를 깼어요:
#   `Payment=L2`  → collation 때문에 검증만 통과 → sed 거부 → domain_risk 4개가 통째로 소실
#   `new=oops=L3` → 검증이 중간 토큰을 버려 통과 → 들여쓰기 없는 깨진 YAML 삽입
BAD=""
SEEN=""
while IFS= read -r pair; do
    [ -z "$pair" ] && continue
    if printf '%s\n' "$pair" | LC_ALL=C grep -qE "$PAIR_RE"; then
        k="${pair%%=*}"
        case " $SEEN " in
            *" $k "*) BAD="$BAD [$pair: 키 중복]"; continue ;;
        esac
        SEEN="$SEEN $k"
        continue
    fi
    # 여기부터는 **왜** 떨어졌는지 메시지만 갈라요 — 판정은 위 전체 매치가 이미 했어요
    case "$pair" in
        *=*) ;;
        *) BAD="$BAD [$pair: key=LEVEL 형식이 아니에요]"; continue ;;
    esac
    case "${pair##*=}" in
        L0|L1|L2|L3) BAD="$BAD [$pair: 키는 영문 kebab-case 만 (영소문자로 시작, a-z0-9- 만)]" ;;
        *)           BAD="$BAD [$pair: 레벨은 L0~L3]" ;;
    esac
done <<PAIRS
$NEW_PAIRS
PAIRS

if [ -n "$BAD" ]; then
    MSG="유효하지 않은 항목:$BAD"
    if [ "$JSON_MODE" = true ]; then json_error "$MSG"; fi
    goax_error "$MSG"; exit "$EXIT_ERROR"
fi

if [ -n "$DEFAULT_RISK" ]; then
    case "$DEFAULT_RISK" in
        L0|L1|L2|L3) ;;
        *) MSG="--default 는 L0~L3 만 (받은 값: $DEFAULT_RISK)"
           if [ "$JSON_MODE" = true ]; then json_error "$MSG"; fi
           goax_error "$MSG"; exit "$EXIT_ERROR" ;;
    esac
else
    DEFAULT_RISK="$CUR_DEFAULT"
fi

# ── 블록 재작성 ──────────────────────────────────────────────────
BLOCK=$(printf '%s\n' "$NEW_PAIRS" | LC_ALL=C sed -E 's/^('"$KEY_RE"')=(L[0-3])$/  \1: \2/')

# 변환 안 된 줄이 하나라도 있으면 **파일을 쓰지 않아요.**
# 예전엔 원문(`Payment=L2`)이 그대로 블록에 실려 깨진 YAML 이 나갔는데, 그걸
# warning 한 줄 + status ok 로 보고했어요. 재작성 실패는 경고가 아니라 에러예요.
UNCONVERTED=$(printf '%s\n' "$BLOCK" | LC_ALL=C grep -vE '^  '"$KEY_RE"': L[0-3]$' | grep -v '^$' || true)
if [ -n "$UNCONVERTED" ]; then
    MSG="domain_risk 블록을 못 만들었어요 (변환 안 된 줄: $(printf '%s' "$UNCONVERTED" | tr '\n' ' ')) — config.yml 은 그대로 뒀어요"
    if [ "$JSON_MODE" = true ]; then json_error "$MSG"; fi
    goax_error "$MSG"; exit "$EXIT_ERROR"
fi

TMP="$CONFIG.tmp.$$"
# 락 창은 HAS_BLOCK grep 부터예요 — "블록이 있나" 를 읽고 그 판정으로 파일을 통째 재작성하니까,
# 락 밖이면 두 세션이 서로의 domain_risk 를 조용히 지워요 (common.sh 머리말의 실측 사고).
# dry-run 은 TMP 를 만들었다 지우기만 하고 CONFIG 를 안 건드려서 락을 안 잡아요 —
# TMP 는 `$CONFIG.tmp.$$` 라 프로세스별로 갈려서 경합하지 않아요.
if [ "$DRY_RUN" != true ]; then
    goax_lock "$CONFIG_LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || fail "다른 프로세스가 .ax/config.yml 을 쓰는 중이에요 — 잠시 뒤 다시 해요"
fi
HAS_BLOCK=false
grep -qE '^domain_risk:' "$CONFIG" && HAS_BLOCK=true

if [ "$HAS_BLOCK" = true ]; then
    # awk -v 로는 여러 줄 값을 못 넘겨요 ("newline in string" 로 죽어요).
    # 블록 치환은 순수 bash 루프로 — 들여쓴 줄과 빈 줄이 블록 안, 비들여쓰기 줄이 블록 끝.
    in_block=false
    {
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                default_risk:*) printf 'default_risk: %s\n' "$DEFAULT_RISK"; continue ;;
                domain_risk:*)  printf 'domain_risk:\n%s\n' "$BLOCK"; in_block=true; continue ;;
            esac
            if [ "$in_block" = true ]; then
                case "$line" in
                    [![:space:]]*) in_block=false; printf '\n%s\n' "$line" ;;
                    *) : ;;   # 블록 안(들여쓴 줄·빈 줄·주석) — 통째 교체되므로 버려요
                esac
                continue
            fi
            printf '%s\n' "$line"
        done < "$CONFIG"
    } > "$TMP"
else
    cp "$CONFIG" "$TMP"
    {
        printf '\n# 도메인 위험도 — zero-domain-risk.sh 작성 (첫날 설정)\n'
        printf 'default_risk: %s\n' "$DEFAULT_RISK"
        printf 'domain_risk:\n%s\n' "$BLOCK"
    } >> "$TMP"
fi

AFTER=$(read_pairs "$TMP")
AFTER_N=$(printf '%s' "$AFTER" | grep -c . || true); AFTER_N=${AFTER_N:-0}

WARNS=""
add_warn() { WARNS="${WARNS}${WARNS:+
}$1"; }
[ "$HAS_BLOCK" = true ] || add_warn "config.yml 에 domain_risk: 가 없어서 파일 끝에 새로 붙였어요 — 위치를 확인하세요"
[ "$AFTER_N" = "$NEW_N" ] || add_warn "쓰려던 ${NEW_N}개 중 ${AFTER_N}개만 반영됐어요 — config.yml 구조를 확인하세요"

if [ "$DRY_RUN" = true ]; then
    unlink "$TMP" 2>/dev/null || true
    NEXT="dry-run — ${BEFORE_N}개 → ${NEW_N}개로 교체될 예정 (default_risk=${DEFAULT_RISK})"
else
    mv "$TMP" "$CONFIG"
    goax_unlock "$CONFIG_LOCK"
    NEXT="domain_risk ${BEFORE_N}개 → ${AFTER_N}개 (default_risk=${DEFAULT_RISK}). triage 가 이제 이 도메인으로 위험도를 잡아요"
fi

if [ "$JSON_MODE" = true ]; then
    BJ=$(printf '%s' "$BEFORE" | lines_to_json)
    AJ=$(printf '%s' "$AFTER" | lines_to_json)
    WJ=$(printf '%s' "$WARNS" | lines_to_json)
    RESULT=$(printf '{"before":{"keys":%s,"list":%s},"after":{"keys":%s,"list":%s},"default_risk":"%s","dry_run":%s}' \
                    "$BEFORE_N" "$BJ" "$AFTER_N" "$AJ" "$DEFAULT_RISK" "$DRY_RUN")
    json_output "ok" "$RESULT" "$NEXT" "$WJ"
else
    printf '%s' "$WARNS" | while IFS= read -r l; do [ -n "$l" ] && goax_warn "$l"; done
    printf '%s\n' "$NEXT"
fi
