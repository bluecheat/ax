#!/usr/bin/env bash
# .ax/scripts/bash/tasks-gate.sh — spec 완료 게이트 + [P] 검증
#
# Usage:
#   bash tasks-gate.sh [--spec <NNN-slug>] [--json] [--strict] [--help]
#   bash tasks-gate.sh --all [--json] [--strict]      # 모든 spec 훑기
#
# 왜 필요한가 — 완료 판정이 "빈 체크박스 0개" 뿐이었어요. 그래서 (a) 수용 기준은
# 안 채워졌는데 task 만 끝난 경우, (b) 미완료 task 를 지워서 통과시킨 경우를
# 구분하지 못했어요. 실사용 리포에서 spec 21개 중 14개가 미완료 task 를 남긴 채
# 끝나 있었는데, 아무도 그걸 알려주지 않았어요.
#
# 검사 4종:
#   G1 미완료  `- [ ]` 가 남아 있나 (`- [~]` 보류는 제외 — 의도적 보류는 정상)
#   G2 커버리지 spec.md §3 의 AC 중 대응 task 가 없는 것 (spec-kit /analyze 의 coverage gap)
#   G3 orphan  어떤 AC 도 참조하지 않는 task
#   G4 유실    task 총 수가 봉인값보다 줄었나 — "미완료를 지워서 통과" 방어
#
# G2/G3 는 spec.md 에 `AC<n>` ID 가 있을 때만 검사해요 (없는 기존 spec 은 생략).
# G4 는 `.ax/state.json` 의 spec별 봉인값과 비교해요. 봉인값이 없으면 현재 수를 기록만.
#
# Output (--json):
#   {"status":"ok|warning","result":{"spec":"012-x","total":12,"done":9,"open":2,
#     "paused":1,"ac_total":3,"ac_uncovered":["AC3"],"orphan_tasks":["T007"],
#     "task_count_drop":0,"complete":false},...}
#
# Exit: 0 통과 / 2 위반 (--strict 일 때만) / 1 error

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; STRICT=false; ALL=false; SPEC=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --strict)  STRICT=true ;;
        --all)     ALL=true ;;
        --dry-run) : ;;                # 읽기 전용 (봉인값 기록만 side-effect)
        --spec)    shift; SPEC="${1:-}" ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
SPEC_BASE="$PROJECT_ROOT/.ax/docs/spec"

# 대상 spec 결정 — 미지정이면 current-task.json 의 활성 spec
if [ -z "$SPEC" ] && [ "$ALL" != true ]; then
    TASK_FILE="$PROJECT_ROOT/.ax/current-task.json"
    if [ -f "$TASK_FILE" ] && command -v jq >/dev/null 2>&1; then
        SD=$(jq -r '.spec_dir // empty' "$TASK_FILE" 2>/dev/null || true)
        [ -n "$SD" ] && SPEC=$(basename "$SD")
    fi
fi

# ── 한 spec 검사 → "spec|total|done|open|paused|ac_total|uncovered|orphans|drop" ──
check_spec() {
    local dir="$1" name; name=$(basename "$dir")
    local tasks="$dir/tasks.md" spec="$dir/spec.md"
    [ -f "$tasks" ] || { printf '%s|0|0|0|0|0|||0\n' "$name"; return 0; }

    local total done_n open_n paused
    total=$(grep -cE '^- \[[ x~X]\] ' "$tasks" 2>/dev/null || true);  total=${total:-0}
    done_n=$(grep -cE '^- \[[xX]\] ' "$tasks" 2>/dev/null || true);   done_n=${done_n:-0}
    open_n=$(grep -cE '^- \[ \] ' "$tasks" 2>/dev/null || true);      open_n=${open_n:-0}
    paused=$(grep -cE '^- \[~\] ' "$tasks" 2>/dev/null || true);      paused=${paused:-0}

    # AC 커버리지 — spec.md 에 AC ID 가 있을 때만
    local ac_total=0 uncovered="" orphans=""
    if [ -f "$spec" ]; then
        local acs; acs=$(grep -ohE '\*\*AC[0-9]+\*\*|(^|[^A-Za-z])AC[0-9]+\b' "$spec" 2>/dev/null \
                          | grep -ohE 'AC[0-9]+' | sort -u || true)
        ac_total=$(printf '%s' "$acs" | grep -c . || true); ac_total=${ac_total:-0}
        if [ "$ac_total" -gt 0 ]; then
            local refs; refs=$(grep -ohE '\[AC[0-9]+\]' "$tasks" 2>/dev/null \
                                | grep -ohE 'AC[0-9]+' | sort -u || true)
            local a
            while IFS= read -r a; do
                [ -z "$a" ] && continue
                printf '%s\n' "$refs" | grep -qx "$a" || uncovered="${uncovered}${a} "
            done <<EOF
$acs
EOF
            # orphan — AC 참조가 없는 task (보류는 제외)
            local line tid
            while IFS= read -r line; do
                case "$line" in *'[AC'*) continue ;; esac
                tid=$(printf '%s' "$line" | grep -ohE 'T[0-9]{3,}' | head -1 || true)
                [ -n "$tid" ] && orphans="${orphans}${tid} "
            done < <(grep -E '^- \[[ xX]\] ' "$tasks" 2>/dev/null || true)
        fi
    fi

    # G4 유실 — state.json 의 봉인값 대비
    local drop=0 sealed=""
    local ST="$PROJECT_ROOT/.ax/state.json"
    if command -v jq >/dev/null 2>&1 && [ -f "$ST" ]; then
        sealed=$(jq -r --arg s "$name" '.task_seal[$s] // empty' "$ST" 2>/dev/null || true)
        if [ -n "$sealed" ] && [ "$total" -lt "$sealed" ]; then
            drop=$((sealed - total))
        fi
        # 봉인값 갱신 — 최대치를 기억해요 (task 는 늘 수 있지만 줄면 안 돼요)
        if [ -z "$sealed" ] || [ "$total" -gt "$sealed" ]; then
            local TMP="$ST.tmp.$$"
            jq --arg s "$name" --argjson n "$total" \
               '.task_seal = ((.task_seal // {}) | .[$s] = $n)' "$ST" > "$TMP" 2>/dev/null \
               && mv "$TMP" "$ST" || rm -f "$TMP"
        fi
    fi

    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$name" "$total" "$done_n" "$open_n" "$paused" "$ac_total" \
        "${uncovered% }" "${orphans% }" "$drop"
}

TARGETS=""
if [ "$ALL" = true ]; then
    TARGETS=$(find "$SPEC_BASE" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' 2>/dev/null | sort || true)
elif [ -n "$SPEC" ] && [ -d "$SPEC_BASE/$SPEC" ]; then
    TARGETS="$SPEC_BASE/$SPEC"
fi

if [ -z "$TARGETS" ]; then
    if [ "$JSON_MODE" = true ]; then
        json_output "skipped" '{"reason":"no target spec"}' "검사할 spec 이 없어요 — --spec <NNN-slug> 또는 --all"
    else
        goax_log "검사할 spec 없음"
    fi
    exit "$EXIT_OK"
fi

VIOLATIONS=0; ROWS=""
while IFS= read -r d; do
    [ -z "$d" ] && continue
    ROWS="${ROWS}$(check_spec "$d")"$'\n'
done <<EOF
$TARGETS
EOF

# 집계 + 보고
FIRST=""; TOTAL_OPEN=0
while IFS='|' read -r name total done_n open_n paused ac_total uncovered orphans drop; do
    [ -z "$name" ] && continue
    [ -z "$FIRST" ] && FIRST="$name|$total|$done_n|$open_n|$paused|$ac_total|$uncovered|$orphans|$drop"
    TOTAL_OPEN=$((TOTAL_OPEN + open_n))
    [ "$open_n" -gt 0 ] && VIOLATIONS=$((VIOLATIONS + 1))
    [ -n "$uncovered" ] && VIOLATIONS=$((VIOLATIONS + 1))
    [ "$drop" -gt 0 ] && VIOLATIONS=$((VIOLATIONS + 1))
    if [ "$JSON_MODE" != true ]; then
        printf '%s: %s/%s 완료' "$name" "$done_n" "$total"
        [ "$paused" -gt 0 ] && printf ' (보류 %s)' "$paused"
        [ "$open_n" -gt 0 ] && printf '  ⚠ 미완료 %s' "$open_n"
        [ -n "$uncovered" ] && printf '  ⚠ 대응 task 없는 AC: %s' "$uncovered"
        [ -n "$orphans" ] && printf '  · AC 미참조 task: %s' "$orphans"
        [ "$drop" -gt 0 ] && printf '  ❌ task %s개 사라짐' "$drop"
        printf '\n'
    fi
done <<EOF
$ROWS
EOF

if [ "$JSON_MODE" = true ]; then
    IFS='|' read -r name total done_n open_n paused ac_total uncovered orphans drop <<EOF
$FIRST
EOF
    UNC_J="[]"; ORP_J="[]"
    if command -v jq >/dev/null 2>&1; then
        [ -n "$uncovered" ] && UNC_J=$(printf '%s' "$uncovered" | tr ' ' '\n' | jq -Rn '[inputs|select(length>0)]')
        [ -n "$orphans" ]   && ORP_J=$(printf '%s' "$orphans"   | tr ' ' '\n' | jq -Rn '[inputs|select(length>0)]')
    fi
    COMPLETE=false
    [ "${open_n:-1}" -eq 0 ] && [ -z "$uncovered" ] && [ "${drop:-0}" -eq 0 ] && COMPLETE=true
    RESULT=$(printf '{"spec":"%s","total":%s,"done":%s,"open":%s,"paused":%s,"ac_total":%s,"ac_uncovered":%s,"orphan_tasks":%s,"task_count_drop":%s,"complete":%s,"violations":%s}' \
        "${name:-}" "${total:-0}" "${done_n:-0}" "${open_n:-0}" "${paused:-0}" "${ac_total:-0}" \
        "$UNC_J" "$ORP_J" "${drop:-0}" "$COMPLETE" "$VIOLATIONS")
    if [ "$VIOLATIONS" -gt 0 ]; then
        json_output "warning" "$RESULT" "완료 조건 미충족 ${VIOLATIONS}건 — 미완료 task 는 끝내거나 [~] 로 사유와 함께 보류 처리하세요"
    else
        json_output "ok" "$RESULT" "완료 조건 충족"
    fi
fi

[ "$VIOLATIONS" -gt 0 ] && [ "$STRICT" = true ] && exit 2
exit "$EXIT_OK"
