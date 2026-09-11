#!/usr/bin/env bash
# .ax/scripts/bash/update-task.sh — `.ax/current-task.json` 의 task 필드를 **락 안에서 in-place** 갱신
#
# Usage:
#   bash update-task.sh --phase <p> [--json] [--dry-run]
#   bash update-task.sh [--phase <p>] [--set <key>=<value> ...] [--blocked-by '<json 배열>'] \
#                       [--merge-intent '<json 객체>'] [--start] [--json] [--dry-run]
#   phase:  idle | triaged | spec | spec_checked | spec_blocked | tasks | implementing | review
#   --set 키:  task_id · description · size(S|M|L|XL) · risk(L0|L1|L2|L3) · domain ·
#              spec_id · spec_dir · spec_tier(standard|full)   — 빈 값은 안 받아요 (비우는 건 reset-task.sh)
#   --blocked-by    blocked_by 를 통째로 교체 (문자열 JSON 배열, '[]' 로 비움)
#   --merge-intent  intent_notes 에 얕은 병합 (JSON 객체) — 같은 키는 새 값이 이겨요
#   --start         started_at 을 지금(UTC)으로 — triage 가 새 task 를 열 때만
#   updated_at 은 매번 지금(UTC)으로 찍어요. 인자가 하나도 없으면 exit 1.
#
# 왜 있나 — triage · spec · spec-validate · spec-tasks · spec-implement 가 SKILL.md 안의 인라인 jq 로
#   이 파일을 `.x = …` 갱신했어요. 결정론 경계 위반이기도 하지만 더 큰 문제는 **락이 없었다**는 것 —
#   같은 파일을 쓰는 status-note.sh(handoff) 와 tier-from-state.sh --reset 은 락을 잡는데 상대편이
#   무락이면 두 세션이 같은 리포를 쓸 때 handoff 항목이 lost-update 로 사라져요. 이 스크립트가 그 5곳을
#   흡수해요. 락 문자열은 셋이 바이트 동일해야 해요 (락 단위는 파일).
#
# 갱신은 in-place 예요 — 모르는 키(handoff · 다른 skill 의 필드)는 그대로 둬요. 객체를 통째로 다시
#   만들지 않아요. 파일이 없으면 exit 1 — 여기서 최소 파일을 만들면 `/up` 의 seed(MANIFEST `->`)가
#   영영 막혀요.
#
# Output (--json):
#   {"status":"ok","result":{"path":".ax/current-task.json","phase":"<갱신 후>","changed":["phase","updated_at",…]},…}
# Exit: 0 ok · 1 error (파일 없음 · 값 검증 실패 · 락 대기 초과 · JSON 깨짐) · 2 skipped (jq 없음)

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; DRY_RUN=false
PHASE=""; SETS='{}'; SET_KV=(); BLOCKED=""; INTENT=""; START=false; NARGS=0
while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h) SHOW_HELP=true ;;
        --phase)   shift; PHASE="${1:-}"; NARGS=$((NARGS + 1)) ;;
        --set)     shift; SET_KV+=("${1:-}"); NARGS=$((NARGS + 1)) ;;
        --blocked-by)   shift; BLOCKED="${1:-}"; NARGS=$((NARGS + 1)) ;;
        --merge-intent) shift; INTENT="${1:-}"; NARGS=$((NARGS + 1)) ;;
        --start)   START=true; NARGS=$((NARGS + 1)) ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    [ $# -gt 0 ] && shift
done
if [ "$SHOW_HELP" = true ]; then
    sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "$EXIT_OK"
fi

fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }

if ! command -v jq >/dev/null 2>&1; then
    if [ "$JSON_MODE" = true ]; then json_skip "jq 가 필요해요 — current-task.json 은 JSON 이에요"; fi
    goax_warn "jq 가 없어 skip"; exit "$EXIT_SKIPPED"
fi
[ "$NARGS" -gt 0 ] || fail "바꿀 것이 없어요 — --phase · --set · --blocked-by · --merge-intent · --start 중 하나는 줘요"

# ── 값 검증 — 전부 파일을 열기 전에. 하나라도 틀리면 아무것도 안 써요 ──
# enum 은 case 로 잡되 [a-z] 범위는 안 써요 (en_US.UTF-8 에서 [a-z] 가 대문자도 물어요 — CLAUDE.md)
if [ -n "$PHASE" ]; then
    case "$PHASE" in idle|triaged|spec|spec_checked|spec_blocked|tasks|implementing|review) ;;
        *) fail "phase 는 idle|triaged|spec|spec_checked|spec_blocked|tasks|implementing|review 중 하나예요 (받은 값: '${PHASE}')" ;;
    esac
fi
# 배열이라 값 안의 줄바꿈도 살아요. ${arr[@]+…} 는 bash 3.2(macOS) 의 set -u 가 빈 배열에서 죽는 것 우회.
for kv in ${SET_KV[@]+"${SET_KV[@]}"}; do
    case "$kv" in *=*) ;; *) fail "--set 은 <key>=<value> 꼴이에요 (받은 값: '${kv}')" ;; esac
    k="${kv%%=*}"; v="${kv#*=}"
    [ -n "$v" ] || fail "--set ${k} 의 값이 비었어요 — 비우는 건 reset-task.sh 로"
    case "$k" in
        size)      case "$v" in S|M|L|XL) ;; *) fail "size 는 S|M|L|XL 중 하나예요 (받은 값: '${v}')" ;; esac ;;
        risk)      case "$v" in L0|L1|L2|L3) ;; *) fail "risk 는 L0|L1|L2|L3 중 하나예요 (받은 값: '${v}')" ;; esac ;;
        spec_tier) case "$v" in standard|full) ;; *) fail "spec_tier 는 standard|full 중 하나예요 (받은 값: '${v}')" ;; esac ;;
        task_id|description|domain|spec_id|spec_dir) ;;
        *) fail "--set 이 받는 키는 task_id·description·size·risk·domain·spec_id·spec_dir·spec_tier 예요 (받은 키: '${k}')" ;;
    esac
    SETS=$(jq -nc --argjson o "$SETS" --arg k "$k" --arg v "$v" '$o + {($k): $v}')
done
if [ -n "$BLOCKED" ]; then
    printf '%s' "$BLOCKED" | jq -e 'type == "array" and all(type == "string")' >/dev/null 2>&1 \
        || fail "--blocked-by 는 문자열 JSON 배열이에요 (예: '[\"spec.md:42 NEEDS\"]' · 비우려면 '[]')"
fi
if [ -n "$INTENT" ]; then
    printf '%s' "$INTENT" | jq -e 'type == "object"' >/dev/null 2>&1 \
        || fail "--merge-intent 는 JSON 객체예요 (예: '{\"scope\":\"…\"}')"
fi
[ -n "$BLOCKED" ] || BLOCKED='null'
[ -n "$INTENT" ] || INTENT='null'

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
FILE="$PROJECT_ROOT/.ax/current-task.json"; REL=".ax/current-task.json"
[ -f "$FILE" ] || fail "$REL 이 없어요 — /up 으로 설치를 마쳐요"

# 바뀌는 키 목록 — 출력용. updated_at 은 항상.
CHANGED=$(jq -nc --arg p "$PHASE" --argjson s "$SETS" --argjson bb "$BLOCKED" --argjson it "$INTENT" --argjson st "$START" \
    '[ (if $p != "" then "phase" else empty end), ($s | keys[]),
       (if $bb != null then "blocked_by" else empty end), (if $it != null then "intent_notes" else empty end),
       (if $st then "started_at" else empty end), "updated_at" ] | unique')

# 한 번의 jq 로 전부 — 필터는 in-place `.k = v` 뿐이에요. `. + $sets` 도 최상위 키만 덮어요.
FILTER='. + $sets
    | if $p != "" then .phase = $p else . end
    | if $bb != null then .blocked_by = $bb else . end
    | if $it != null then .intent_notes = ((.intent_notes // {}) + $it) else . end
    | if $st then .started_at = $ts else . end
    | .updated_at = $ts'
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ "$DRY_RUN" = true ]; then
    # 락도 파일도 안 건드려요 — 검증만 하고 "무엇이 바뀔지" 를 답해요 (JSON 이 깨졌으면 여기서도 알려요)
    jq -e . "$FILE" >/dev/null 2>&1 || fail "$REL 을 읽지 못했어요 — JSON 이 깨졌는지 봐요"
    RES=$(jq -nc --arg p "$REL" --arg ph "$PHASE" --argjson ch "$CHANGED" '{path: $p, dry_run: true, phase: (if $ph != "" then $ph else null end), changed: $ch}')
    [ "$JSON_MODE" = true ] && json_output "ok" "$RES" "dry-run — 안 썼어요" || goax_log "dry-run — $REL 안 썼어요 (바뀔 키: $(printf '%s' "$CHANGED" | jq -r 'join(", ")'))"
    exit "$EXIT_OK"
fi

# 락 — status-note.sh · tier-from-state.sh --reset 과 같은 문자열 (락 단위는 파일). 읽기부터 락 안이에요.
LOCK="$(goax_normalize_path "$PROJECT_ROOT/.ax/current-task.json" "$PROJECT_ROOT").lock"
goax_lock "$LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || fail "다른 프로세스가 $REL 을 쓰는 중이에요 — 잠시 뒤 다시 해요"
TMP="$FILE.tmp.$$"
if ! jq --arg p "$PHASE" --argjson sets "$SETS" --argjson bb "$BLOCKED" --argjson it "$INTENT" --argjson st "$START" --arg ts "$TS" \
        "$FILTER" "$FILE" > "$TMP" 2>/dev/null; then
    rm -f "$TMP"; fail "$REL 을 읽지 못했어요 — JSON 이 깨졌는지 봐요 (원본은 그대로예요)"
fi
mv "$TMP" "$FILE"
NEW_PHASE=$(jq -r '.phase // "idle"' "$FILE")
goax_unlock "$LOCK"

RES=$(jq -nc --arg p "$REL" --arg ph "$NEW_PHASE" --argjson ch "$CHANGED" '{path: $p, phase: $ph, changed: $ch}')
NEXT="phase=${NEW_PHASE}"; [ -n "$PHASE" ] && NEXT="phase → ${PHASE}"
[ "$JSON_MODE" = true ] && json_output "ok" "$RES" "$NEXT" || goax_log "$REL 갱신 — $(printf '%s' "$CHANGED" | jq -r 'join(", ")') ($NEXT)"
exit "$EXIT_OK"
