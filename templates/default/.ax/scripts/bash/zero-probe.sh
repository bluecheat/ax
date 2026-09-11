#!/usr/bin/env bash
# .ax/scripts/bash/zero-probe.sh — 네거티브 프로브 러너 (게이트가 아직 막는지 상시 확인)
#
# Usage:
#   bash zero-probe.sh [--json] [--dir .ax/probes] [--only <name>] [--list] [--help]
#
# 무엇을 푸는가:
#   "게이트를 깔았다" 와 "게이트가 막는다" 는 다른 사실이에요. 실측 — CI 가 의존성 설치
#   실패로 **한 번도 안 돌면서 초록**이었어요. policy-as-code 실무의 같은 경고:
#   "통제를 집행하는 것처럼 보이는 룰이 조용히 false 가 아니라 undefined 로 평가될 수 있고,
#    undefined 는 denied 와 다르다."
#
#   그래서 프로브를 첫날 1회로 끝내지 않고 **CI 에서 매 푸시마다** 돌려요.
#
# 프로브 계약 (`.ax/probes/*.sh` 파일 하나 = 프로브 하나):
#   - 실행 가능해야 해요 (chmod +x 아니어도 bash <file> 로 돌려요)
#   - 스스로 위반을 만들고 → 게이트를 돌리고 → 되돌리고 → **판정**해요
#   - **게이트가 막았으면 exit 0**, 못 막았으면 exit 1, 돌릴 수 없으면 exit 2 (skip)
#   - 첫 줄 주석 `# probe: <설명>` 이 보고에 실려요
#   예시: `.ax/_templates/zero/probes/` 를 복사해서 프로젝트에 맞게 고치세요
#
# Output (--json):
#   {"status":"ok|error","result":{"probes":[{"name","desc","exit","ok","tail_lines"}],
#                                  "passed":N,"failed":N,"skipped":N},...}
#
# Exit:
#   0  전부 통과 (막아야 할 걸 다 막았음)
#   1  하나라도 실패 — **게이트가 뚫려 있어요.** CI 를 여기서 세우세요
#   2  프로브가 하나도 없음

set -uo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
SHOW_HELP=false
LIST_ONLY=false
PROBE_DIR=""
ONLY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dir)     shift; PROBE_DIR="${1:-}" ;;
        --only)    shift; ONLY="${1:-}" ;;
        --list)    LIST_ONLY=true ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    goax_help "${BASH_SOURCE[0]}"
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
cd "$PROJECT_ROOT" || exit "$EXIT_ERROR"
[ -n "$PROBE_DIR" ] || PROBE_DIR="$PROJECT_ROOT/.ax/probes"

FILES=""
if [ -d "$PROBE_DIR" ]; then
    FILES=$(find "$PROBE_DIR" -maxdepth 1 -name '*.sh' 2>/dev/null | sort || true)
fi
COUNT=$(printf '%s' "$FILES" | grep -c . || true); COUNT=${COUNT:-0}

if [ "$COUNT" -eq 0 ]; then
    MSG="프로브가 없어요 — .ax/_templates/zero/probes/ 에서 복사해 ${PROBE_DIR#$PROJECT_ROOT/} 에 두세요"
    if [ "$JSON_MODE" = true ]; then json_skip "$MSG"; fi
    goax_warn "$MSG"; exit "$EXIT_SKIPPED"
fi

probe_desc() {   # 첫 `# probe:` 주석 한 줄
    sed -n 's/^# *probe: *//p' "$1" 2>/dev/null | head -1
}

if [ "$LIST_ONLY" = true ]; then
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        printf '%s\t%s\n' "$(basename "$f" .sh)" "$(probe_desc "$f")"
    done <<PROBES
$FILES
PROBES
    exit "$EXIT_OK"
fi

PASSED=0; FAILED=0; SKIPPED=0
PROBES_JSON=""
LOG_DIR=$(mktemp -d)

while IFS= read -r f; do
    [ -z "$f" ] && continue
    name=$(basename "$f" .sh)
    [ -n "$ONLY" ] && [ "$name" != "$ONLY" ] && continue
    desc=$(probe_desc "$f")

    LOG="$LOG_DIR/$name.log"
    bash "$f" > "$LOG" 2>&1
    code=$?

    ok="false"
    case "$code" in
        0) PASSED=$((PASSED + 1)); ok="true" ;;
        2) SKIPPED=$((SKIPPED + 1)); ok="null" ;;
        *) FAILED=$((FAILED + 1)) ;;
    esac

    TAIL_JSON="[]"
    if [ "$code" -ne 0 ] && command -v jq >/dev/null 2>&1; then
        TAIL_JSON=$(tail -10 "$LOG" | jq -Rn '[inputs]' 2>/dev/null || printf '[]')
    fi
    if command -v jq >/dev/null 2>&1; then
        entry=$(jq -nc --arg n "$name" --arg d "$desc" --argjson e "$code" \
                       --argjson t "$TAIL_JSON" --argjson o "$ok" \
                       '{name:$n,desc:$d,exit:$e,ok:$o,tail_lines:$t}')
    else
        entry=$(printf '{"name":"%s","desc":"%s","exit":%s,"ok":%s,"tail_lines":[]}' \
                       "$name" "$desc" "$code" "$ok")
    fi
    PROBES_JSON="${PROBES_JSON}${PROBES_JSON:+,}${entry}"
done <<PROBES
$FILES
PROBES

if [ "$FAILED" -gt 0 ]; then
    STATUS="error"; EXIT_CODE=1
    NEXT="프로브 ${FAILED}건 실패 — **막아야 할 위반이 통과했어요.** 게이트가 뚫려 있습니다"
else
    STATUS="ok"; EXIT_CODE=0
    NEXT="프로브 ${PASSED}건 통과 (skip ${SKIPPED}) — 차단이 아직 살아 있어요"
fi

if [ "$JSON_MODE" = true ]; then
    RESULT=$(printf '{"probes":[%s],"passed":%s,"failed":%s,"skipped":%s}' \
                    "$PROBES_JSON" "$PASSED" "$FAILED" "$SKIPPED")
    json_output "$STATUS" "$RESULT" "$NEXT"
else
    printf '%s\n' "$NEXT"
fi

unlink "$LOG_DIR"/*.log 2>/dev/null || true
rmdir "$LOG_DIR" 2>/dev/null || true
exit "$EXIT_CODE"
