#!/usr/bin/env bash
# .ax/scripts/bash/update-task.sh — `.ax/current-task.json` 의 task 필드를 **락 안에서 in-place** 갱신
#
# Usage:
#   bash update-task.sh --phase <p> [--json] [--dry-run]
#   bash update-task.sh [--task <id>] [--phase <p>] [--set <key>=<value> ...] [--blocked-by '<json 배열>'] \
#                       [--merge-intent '<json 객체>'] [--start] [--activate] [--json] [--dry-run]
#   phase:  triaged | spec | spec_checked | spec_blocked | tasks | implementing | review   (idle 은 reset-task.sh 만)
#   --set 키:  task_id · description · size(S|M|L|XL) · risk(L0|L1|L2|L3) · domain ·
#              spec_id · spec_dir · spec_tier(standard|full) · plan_doc(외부 계획 문서 경로) ·
#              friction(autopilot|phase_gate|per_task)   — 빈 값은 안 받아요 (비우는 건 reset-task.sh)
#   friction 은 사용자가 이 task 에 한해 미리 준 확인 강도예요 ("묻지 말고 쭉 해" → autopilot).
#     spec-implement 가 config.yml 의 confirmation.mode 대신 이 값을 써요. L3 override(C5)는 여전히 우선해요.
#   --blocked-by    blocked_by 를 통째로 교체 (문자열 JSON 배열, '[]' 로 비움)
#   --merge-intent  intent_notes 에 얕은 병합 (JSON 객체) — 같은 키면 새 값이 우선해요
#   --start         started_at 을 지금(UTC)으로 — triage 가 새 task 를 열 때만. 새 task 가 지금 작업이 돼요
#   --task <id>     이 작업만 갱신해요 (.ax/tasks/<id>.json). 지금 작업(current-task.json 의 task_id)이 아니면
#                   current-task.json 은 그대로예요 — 병렬 작업이 서로 덮지 않아요. 없으면 지금 작업이 대상
#   --activate      --task 의 작업을 지금 작업으로 (current-task.json 의 task 필드를 그 작업 것으로 바꿔요)
#
# 작업별 상태: task_id 가 있는 작업은 .ax/tasks/<task_id>.json 이 원본이고 current-task.json 은 지금 작업의
#   사본 + handoff 예요. --start 로 다른 작업을 열면 앞 작업은 자기 파일에 남아요 (--task <id> --activate 로 돌아가요).
#   task_id 가 없는 옛 형식은 예전처럼 current-task.json 만 고쳐요.
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
#   {"status":"ok","result":{"path":".ax/current-task.json","phase":"<갱신 후>","changed":["phase","updated_at",…],
#     "task_id":"<대상>"|null,"task_file":".ax/tasks/<id>.json"|null,"active":<current-task.json 도 고쳤나>},…}
# Exit: 0 ok · 1 error (파일 없음 · 값 검증 실패 · 락 대기 초과 · JSON 깨짐) · 2 skipped (jq 없음)

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; DRY_RUN=false
PHASE=""; SETS='{}'; SET_KV=(); BLOCKED=""; INTENT=""; START=false; ACTIVATE=false; TASK_OPT=""; NARGS=0; EMPTY_OPT=""; opt=""
while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h) SHOW_HELP=true ;;
        --phase|--set|--blocked-by|--merge-intent|--task)
            opt="$1"
            # 값이 비었거나 다음 토큰이 옵션(--…)이면 값을 삼키지 않고 오류로 — 예전엔 빈 값을 "안 준 것" 으로 접어
            # updated_at 만 조용히 쓰고 ok 였고 (spec-validate 가 BLOCKED 를 비워 보내면 phase 만 spec_blocked 로
            # 넘어갔어요), `--set --json` 은 --json 을 값으로 먹어 오류가 봉투 없이 나갔어요.
            if [ $# -lt 2 ]; then EMPTY_OPT="$opt"                       # 마지막 토큰 — 값 없음
            elif [ "${2#--}" != "$2" ]; then EMPTY_OPT="$opt"           # 다음이 옵션 — 삼키지 않아요 (--json 이 살아요)
            else
                shift; [ -n "$1" ] || EMPTY_OPT="$opt"                  # 빈 문자열 — 삼키되 오류
                case "$opt" in
                    --phase)        PHASE="$1" ;;
                    --set)          SET_KV+=("$1") ;;
                    --blocked-by)   BLOCKED="$1" ;;
                    --merge-intent) INTENT="$1" ;;
                    --task)         TASK_OPT="$1"; NARGS=$((NARGS - 1)) ;;   # 대상만 고르고 바꿀 건 아니에요
                esac
            fi
            NARGS=$((NARGS + 1)) ;;
        --start)   START=true; NARGS=$((NARGS + 1)) ;;
        --activate) ACTIVATE=true; NARGS=$((NARGS + 1)) ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    [ $# -gt 0 ] && shift
done
if [ "$SHOW_HELP" = true ]; then
    goax_help "${BASH_SOURCE[0]}"
    exit "$EXIT_OK"
fi

fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }
[ -z "$EMPTY_OPT" ] || { command -v jq >/dev/null 2>&1 || JSON_MODE=false; fail "${EMPTY_OPT} 의 값이 비었어요 (다음 토큰이 옵션이면 값이 빠진 거예요) — 값을 주거나 옵션을 빼요"; }

if ! command -v jq >/dev/null 2>&1; then
    if [ "$JSON_MODE" = true ]; then json_skip "jq 가 필요해요 — current-task.json 은 JSON 이에요"; fi
    goax_warn "jq 가 없어 skip"; exit "$EXIT_SKIPPED"
fi
[ "$NARGS" -gt 0 ] || fail "바꿀 것이 없어요 — --phase · --set · --blocked-by · --merge-intent · --start · --activate 중 하나는 줘요"
[ "$ACTIVATE" = false ] || [ -n "$TASK_OPT" ] || fail "--activate 는 --task <id> 와 같이 줘요 — 어느 작업을 지금 작업으로 할지요"

# ── 값 검증 — 전부 파일을 열기 전에. 하나라도 틀리면 아무것도 안 써요 ──
# enum 은 case 로 잡되 [a-z] 범위는 안 써요 (en_US.UTF-8 에서 [a-z] 가 대문자도 물어요 — CLAUDE.md)
if [ -n "$PHASE" ]; then
    case "$PHASE" in triaged|spec|spec_checked|spec_blocked|tasks|implementing|review) ;;
        idle) fail "phase idle 은 reset-task.sh 가 써요 — task 필드도 같이 비워야 해요" ;;
        *) fail "phase 는 triaged|spec|spec_checked|spec_blocked|tasks|implementing|review 중 하나예요 (받은 값: '${PHASE}')" ;;
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
        friction)  case "$v" in autopilot|phase_gate|per_task) ;; *) fail "friction 은 autopilot|phase_gate|per_task 중 하나예요 (받은 값: '${v}')" ;; esac ;;
        task_id|description|domain|spec_id|spec_dir) ;;
        plan_doc)  case "$v" in *$'\n'*) fail "plan_doc 는 경로 한 줄이에요" ;; esac ;;
        *) fail "--set 이 받는 키는 task_id·description·size·risk·domain·spec_id·spec_dir·spec_tier·friction·plan_doc 이에요 (받은 키: '${k}')" ;;
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
       (if $bb != null then "blocked_by" else empty end), (if ($it != null and ($it | length) > 0) then "intent_notes" else empty end),
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
# 작업 파일(.ax/tasks/<id>.json)도 쓰면 그 락을 **안쪽에서** 잡아요 — 순서를 늘 current-task → 작업 파일로 고정해
# tier-from-state.sh --reset 과 서로 기다리다 멈추지 않게 해요.
LOCK="$(goax_normalize_path "$PROJECT_ROOT/.ax/current-task.json" "$PROJECT_ROOT").lock"
goax_lock "$LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || fail "다른 프로세스가 $REL 을 쓰는 중이에요 — 잠시 뒤 다시 해요"
jq -e . "$FILE" >/dev/null 2>&1 || { goax_unlock "$LOCK"; fail "$REL 을 읽지 못했어요 — JSON 이 깨졌는지 봐요 (원본은 그대로예요)"; }
ACTIVE=$(jq -r '.task_id // empty' "$FILE")
NEW_ID=$(printf '%s' "$SETS" | jq -r '.task_id // empty')
# 대상 작업 — --task > (--start 의) 새 task_id > 지금 작업. 비면 옛 형식(current-task.json 만)
TARGET="$TASK_OPT"
if [ -n "$TARGET" ] && [ -n "$NEW_ID" ] && [ "$NEW_ID" != "$TARGET" ]; then
    goax_unlock "$LOCK"; fail "--task ${TARGET} 와 --set task_id=${NEW_ID} 가 달라요 — 작업 id 는 바꾸지 않아요"
fi
[ -n "$TARGET" ] || TARGET="$NEW_ID"
[ -n "$TARGET" ] || TARGET="$ACTIVE"
ARGS_JQ=(--arg p "$PHASE" --argjson sets "$SETS" --argjson bb "$BLOCKED" --argjson it "$INTENT" --argjson st "$START" --arg ts "$TS")
TMP="$FILE.tmp.$$"
MIRROR=true; TASK_REL=""
if [ -z "$TARGET" ]; then
    if ! jq "${ARGS_JQ[@]}" "$FILTER" "$FILE" > "$TMP" 2>/dev/null; then
        rm -f "$TMP"; goax_unlock "$LOCK"; fail "$REL 을 읽지 못했어요 — JSON 이 깨졌는지 봐요 (원본은 그대로예요)"
    fi
    mv "$TMP" "$FILE"
else
    TF=$(goax_task_path "$PROJECT_ROOT" "$TARGET"); TASK_REL=${TF#"$PROJECT_ROOT"/}
    mkdir -p "$(dirname "$TF")" || { goax_unlock "$LOCK"; fail ".ax/tasks/ 를 만들지 못했어요 — 권한을 봐요"; }
    # --start 로 다른 작업을 열 때 지금 작업이 아직 파일이 없으면(옛 형식에서 넘어온 첫 갱신) 먼저 자기 파일로 남겨요
    if { [ "$START" = true ] || [ "$ACTIVATE" = true ]; } && [ -n "$ACTIVE" ] && [ "$ACTIVE" != "$TARGET" ]; then
        AF=$(goax_task_path "$PROJECT_ROOT" "$ACTIVE")
        if [ ! -f "$AF" ] && [ "$(jq -r '.phase // "idle"' "$FILE")" != idle ]; then
            jq --argjson k "$GOAX_TASK_FIELDS" 'with_entries(select(.key as $x | $k | index($x)))' "$FILE" > "$AF" 2>/dev/null || rm -f "$AF"
        fi
    fi
    TLOCK="$(goax_normalize_path "$TF" "$PROJECT_ROOT").lock"
    goax_lock "$TLOCK" "${GOAX_LOCK_TIMEOUT:-10}" || { goax_unlock "$LOCK"; fail "다른 프로세스가 $TASK_REL 을 쓰는 중이에요 — 잠시 뒤 다시 해요"; }
    if [ -f "$TF" ]; then
        BASE=$(jq -c . "$TF" 2>/dev/null) || { goax_unlock "$TLOCK"; goax_unlock "$LOCK"; fail "$TASK_REL 을 읽지 못했어요 — JSON 이 깨졌는지 봐요"; }
    elif [ "$TARGET" = "$ACTIVE" ]; then
        BASE=$(jq -c --argjson k "$GOAX_TASK_FIELDS" 'with_entries(select(.key as $x | $k | index($x)))' "$FILE")   # 옛 형식 → 첫 갱신에 옮겨요
    elif [ "$START" = true ]; then
        BASE='{"intent_notes":{},"blocked_by":[]}'
    else
        goax_unlock "$TLOCK"; goax_unlock "$LOCK"
        fail "작업 ${TARGET} 이 없어요 ($TASK_REL) — 새 작업은 triage 가 --start 로 열어요"
    fi
    REC=$(printf '%s' "$BASE" | jq -c "${ARGS_JQ[@]}" --arg id "$TARGET" "$FILTER | .task_id = \$id") \
        || { goax_unlock "$TLOCK"; goax_unlock "$LOCK"; fail "$TASK_REL 갱신 값을 만들지 못했어요"; }
    printf '%s\n' "$REC" | jq . > "$TF.tmp.$$" && mv "$TF.tmp.$$" "$TF" \
        || { rm -f "$TF.tmp.$$"; goax_unlock "$TLOCK"; goax_unlock "$LOCK"; fail "$TASK_REL 을 쓰지 못했어요"; }
    goax_unlock "$TLOCK"
    # 지금 작업이거나 지금 작업이 되는 경우만 current-task.json 을 고쳐요 — 아니면 다른 세션의 지금 작업을 덮어요
    if [ "$TARGET" = "$ACTIVE" ] || [ "$START" = true ] || [ "$ACTIVATE" = true ]; then
        if ! jq --argjson k "$GOAX_TASK_FIELDS" --argjson r "$REC" 'with_entries(select(.key as $x | ($k | index($x)) == null)) + $r' "$FILE" > "$TMP" 2>/dev/null; then
            rm -f "$TMP"; goax_unlock "$LOCK"; fail "$REL 을 읽지 못했어요 — JSON 이 깨졌는지 봐요 (원본은 그대로예요)"
        fi
        mv "$TMP" "$FILE"
    else
        MIRROR=false
    fi
fi
if [ "$MIRROR" = true ]; then NEW_PHASE=$(jq -r '.phase // "idle"' "$FILE"); else NEW_PHASE=$(jq -r '.phase // "idle"' "$TF"); fi
goax_unlock "$LOCK"

RES=$(jq -nc --arg p "$REL" --arg ph "$NEW_PHASE" --argjson ch "$CHANGED" --arg t "$TARGET" --arg tf "$TASK_REL" --argjson a "$MIRROR" \
    '{path: $p, phase: $ph, changed: $ch, task_id: (if $t != "" then $t else null end), task_file: (if $tf != "" then $tf else null end), active: $a}')
NEXT="phase=${NEW_PHASE}"; [ -n "$PHASE" ] && NEXT="phase → ${PHASE}"
[ "$MIRROR" = true ] || NEXT="${NEXT} (작업 ${TARGET} 만 — 지금 작업은 ${ACTIVE:-없음} 그대로)"
[ "$JSON_MODE" = true ] && json_output "ok" "$RES" "$NEXT" || goax_log "${TASK_REL:-$REL} 갱신 — $(printf '%s' "$CHANGED" | jq -r 'join(", ")') ($NEXT)"
exit "$EXIT_OK"
