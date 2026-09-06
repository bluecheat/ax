#!/usr/bin/env bash
# .ax/scripts/bash/zero-ablation.sh — 룰을 전부 끄고 무엇이 실제로 깨지는지 재는 절차
#
# Usage:
#   bash zero-ablation.sh --status [--json]
#   bash zero-ablation.sh --off [--rules zero-baseline,other] [--json] [--dry-run]
#   bash zero-ablation.sh --on  [--json] [--dry-run]
#
# 왜 필요한가:
#   첫날에 깐 룰은 **영구 자산이 아니에요.** 모델 세대가 바뀌면 "없으면 틀리던 것" 의 절반은
#   지시 없이도 맞습니다. 그런데 룰은 스스로 사라지지 않아서, 아무도 안 지우면 컨텍스트를
#   먹는 부채로 남아요 — 그리고 지시가 늘수록 준수율이 떨어져요(IFScale: 500개 밀도에서 68%).
#
#   그래서 주기적으로 **끄고 재봅니다.** 끈 상태로 실제 작업 N회를 돌려 무엇이 깨지는지 보고,
#   안 깨지는 룰은 지워요. 이게 첫날 팩이 부채가 되지 않게 하는 유일한 장치예요.
#
# 동작:
#   --off  `.ax/spirit/rules/<name>.md` → `<name>.md.ablated` 로 rename (내용 보존)
#   --on   `.ablated` 를 전부 되돌려요
#   --status 지금 꺼진 룰과 켜진 룰, 마지막 회차(.ax/.ablation-last)와 다음 기한(+180일)
#   --on 은 한 회차의 끝 — 마지막 회차를 기록하고 다음 기한을 .ax/docs/STATUS.md "다음" 에 체크박스로 넣어요
#   (status-note.sh). doctor 가 그 날짜를 I3 처럼 추적해요 (임박·초과)
#
#   `.ax/spirit/rules/*.md.ablated` 는 확장자가 `.md` 가 아니라서 주입 훅·doctor 가 안 봐요.
#   절차 문서: `.ax/_templates/zero/ablation.md`
#
# Output (--json):
#   {"status":"ok","result":{"mode":"off|on|status","active":[...],"ablated":[...],
#                            "changed":N,"dry_run":false},...}
#
# Exit: 0 ok · 1 error · 2 대상 없음

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
SHOW_HELP=false
MODE="status"
RULES=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --off)     MODE="off" ;;
        --on)      MODE="on" ;;
        --status)  MODE="status" ;;
        --rules)   shift; RULES="${1:-}" ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^#$//; s/^# //'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
RULES_DIR="$PROJECT_ROOT/.ax/spirit/rules"

lines_to_json() {
    if command -v jq >/dev/null 2>&1; then
        jq -Rn '[inputs | select(length > 0)]'
    else
        printf '[]'
    fi
}

selected() {   # $1 = basename without .md — --rules 로 좁혔으면 그 안에 드는지
    [ -z "$RULES" ] && return 0
    case ",$RULES," in *",$1,"*) return 0 ;; esac
    return 1
}

CHANGED=0
ACTIVE=""
ABLATED=""

if [ -d "$RULES_DIR" ]; then
    for f in "$RULES_DIR"/*.md; do
        [ -f "$f" ] || continue
        base=$(basename "$f" .md)
        if [ "$MODE" = "off" ] && selected "$base"; then
            [ "$DRY_RUN" = true ] || mv "$f" "$f.ablated"
            CHANGED=$((CHANGED + 1))
            ABLATED="${ABLATED}${base}
"
        else
            ACTIVE="${ACTIVE}${base}
"
        fi
    done
    for f in "$RULES_DIR"/*.md.ablated; do
        [ -f "$f" ] || continue
        base=$(basename "$f" .md.ablated)
        if [ "$MODE" = "on" ]; then
            [ "$DRY_RUN" = true ] || mv "$f" "$RULES_DIR/$base.md"
            CHANGED=$((CHANGED + 1))
            ACTIVE="${ACTIVE}${base}
"
        elif [ "$MODE" != "off" ]; then
            # --off 는 위 루프에서 방금 rename 한 것을 여기서 다시 세면 중복돼요
            ABLATED="${ABLATED}${base}
"
        fi
    done
fi

ACTIVE_N=$(printf '%s' "$ACTIVE" | grep -c . || true); ACTIVE_N=${ACTIVE_N:-0}
ABLATED_N=$(printf '%s' "$ABLATED" | grep -c . || true); ABLATED_N=${ABLATED_N:-0}

case "$MODE" in
    off) NEXT="룰 ${CHANGED} 파일을 껐어요. 이제 실제 작업 5회 이상을 돌리고 **무엇이 깨졌는지** 적으세요. 안 깨진 룰은 지웁니다 (절차: .ax/_templates/zero/ablation.md). 되돌리기: --on" ;;
    on)  NEXT="룰 ${CHANGED} 파일을 되돌렸어요. 깨진 목록을 ablation 기록에 남기고, 안 깨진 룰은 이번에 지우세요" ;;
    *)   NEXT="켜진 룰 ${ACTIVE_N} · 꺼진 룰 ${ABLATED_N}" ;;
esac

if [ "$DRY_RUN" = true ]; then
    NEXT="dry-run — ${NEXT}"
fi

if [ "$ACTIVE_N" -eq 0 ] && [ "$ABLATED_N" -eq 0 ]; then
    MSG=".ax/spirit/rules/ 에 룰이 없어요"
    if [ "$JSON_MODE" = true ]; then json_skip "$MSG"; fi
    goax_warn "$MSG"; exit "$EXIT_SKIPPED"
fi

# ── 회차 기록 — --on 이 한 회차의 끝이에요. 다음 기한(6개월)을 인계 노트에 체크박스로 박아요.
# 날짜가 문서 안에만 있으면 이 절차는 영영 안 돌아요 — doctor 가 STATUS.md 의 기한을 I3 처럼 추적해요.
LAST_FILE="$PROJECT_ROOT/.ax/.ablation-last"
if [ "$MODE" = "on" ] && [ "$DRY_RUN" = false ] && [ "$CHANGED" -gt 0 ]; then
    date +%F > "$LAST_FILE" 2>/dev/null || true
    DUE=$(date -v+180d +%F 2>/dev/null || date -d '+180 days' +%F 2>/dev/null || true)
    if [ -n "$DUE" ] && [ -f "$SCRIPT_DIR/status-note.sh" ]; then
        bash "$SCRIPT_DIR/status-note.sh" --done next "룰 ablation 재검토" --json >/dev/null 2>&1 || true
        bash "$SCRIPT_DIR/status-note.sh" --add next "- [ ] $DUE 룰 ablation 재검토 (.ax/_templates/zero/ablation.md)" --json >/dev/null 2>&1 || true
        NEXT="$NEXT · 다음 회차 $DUE 를 .ax/docs/STATUS.md 에 적었어요"
    fi
fi
LAST_ROUND=""; [ -f "$LAST_FILE" ] && LAST_ROUND=$(tr -d '[:space:]' < "$LAST_FILE" 2>/dev/null || true)
NEXT_DUE=""
if [ -n "$LAST_ROUND" ]; then
    NEXT_DUE=$(date -j -v+180d -f '%Y-%m-%d' "$LAST_ROUND" +%F 2>/dev/null || date -d "$LAST_ROUND +180 days" +%F 2>/dev/null || true)
fi
if [ "$MODE" = "status" ] && [ -z "$LAST_ROUND" ]; then
    NEXT="$NEXT · 아직 한 회차도 안 돌았어요 — 첫 기한은 zero §13 이 STATUS.md 에 적어요"
fi

if [ "$JSON_MODE" = true ]; then
    AJ=$(printf '%s' "$ACTIVE" | lines_to_json)
    BJ=$(printf '%s' "$ABLATED" | lines_to_json)
    RESULT=$(printf '{"mode":"%s","active":%s,"ablated":%s,"changed":%s,"dry_run":%s,"last_round":"%s","next_due":"%s"}' \
                    "$MODE" "$AJ" "$BJ" "$CHANGED" "$DRY_RUN" "$LAST_ROUND" "$NEXT_DUE")
    json_output "ok" "$RESULT" "$NEXT"
else
    printf '%s\n' "$NEXT"
    [ -n "$LAST_ROUND" ] && printf '마지막 회차 %s · 다음 기한 %s\n' "$LAST_ROUND" "$NEXT_DUE"
fi
