#!/usr/bin/env bash
# .ax/scripts/bash/zero-verify.sh — 게이트 명령을 정직하게 돌리고 증거 블록을 만들어요
#
# Usage:
#   bash zero-verify.sh [--json] [--only build,test,lint,typecheck] [--dry-run] [--help]
#   bash zero-verify.sh --cmd "pnpm test" [--cmd "pnpm lint"] [--json]
#
# 무엇을 푸는가:
#   "주장에는 명령과 출력이 붙는다"·"파이프가 exit code 를 덮는다" 는 산문 룰이었어요.
#   룰은 advisory 라 지켜질 때만 지켜져요. 그래서 도구로 옮겼어요 —
#   이 스크립트는 **파이프를 쓰지 않고** 각 명령을 돌리고, exit code 를 따로 잡아
#   기계가 읽을 수 있는 증거로 돌려줘요. 사람이 파이프를 안 쓰기로 결심할 필요가 없어요.
#
#   실측 사례: `typecheck 2>&1 | tail -20` 이 타입 오류를 한 세션 내내 "0 오류" 로 보고했고,
#   같은 세션에서 `xcodebuild | tail -5` 가 exit 65(서명 실패)를 성공으로 읽었어요.
#
# 명령 출처: 인자 --cmd 가 있으면 그것만. 없으면 .ax/config.yml 의 commands.{build,test,lint,typecheck}
#            (빈 값은 건너뛰고 skipped 로 보고해요 — "안 돌렸다" 를 숨기지 않아요)
#
# 출력 꼬리(tail_lines): 실패한 명령만 마지막 20줄을 실어요. 통과한 명령은 안 실어요
#            (통과 로그는 컨텍스트만 먹어요).
#
# Output (--json):
#   {"status":"ok|error","result":{"checks":[{"name","cmd","exit","ok","tail_lines"}],
#                                  "passed":N,"failed":N,"skipped":N,"evidence":"..."},...}
#
# Exit:
#   0  전부 통과 (또는 --dry-run)
#   1  하나라도 실패 — CI 에서 그대로 게이트로 쓸 수 있어요
#   2  **하나도 안 돌았음** — config.yml commands 가 비었거나 --only 가 전부 걸러냈어요.
#      초록을 주지 않는 게 핵심이에요: "게이트가 없다" 를 통과로 보고하면 이 도구가
#      막으려던 사고(게이트를 한 번도 실행하지 않은 CI 가 초록)를 그대로 재현해요

set -uo pipefail   # -e 없음 — 실패한 게이트에서 스크립트가 죽으면 나머지를 못 재요

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
SHOW_HELP=false
ONLY=""
CMDS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --only)    shift; ONLY="${1:-}" ;;
        --cmd)     shift; [ -n "${1:-}" ] && CMDS+=("$1") ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^#$//; s/^# //'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
cd "$PROJECT_ROOT" || exit "$EXIT_ERROR"
CONFIG="$PROJECT_ROOT/.ax/config.yml"

# ── 돌릴 명령 모으기 ─────────────────────────────────────────────
NAMES=()
RUNS=()

if [ "${#CMDS[@]}" -gt 0 ]; then
    i=0
    for c in "${CMDS[@]}"; do
        i=$((i + 1))
        NAMES+=("cmd$i"); RUNS+=("$c")
    done
else
    for key in typecheck test lint build; do
        case ",$ONLY," in
            ,,) ;;                                  # --only 없음 = 전부
            *",$key,"*) ;;                          # 지정됨
            *) continue ;;
        esac
        val=""
        if [ -f "$CONFIG" ]; then
            val=$(grep -E "^[[:space:]]+${key}:" "$CONFIG" 2>/dev/null | head -1 \
                  | sed -E "s/^[[:space:]]+${key}:[[:space:]]*//; s/[[:space:]]*#.*$//" \
                  | tr -d '"' | tr -d "'" | sed -E 's/[[:space:]]+$//')
        fi
        NAMES+=("$key"); RUNS+=("$val")
    done
fi

if [ "${#NAMES[@]}" -eq 0 ]; then
    MSG="돌릴 명령이 없어요 — .ax/config.yml 의 commands 를 채우거나 --cmd 로 주세요"
    if [ "$JSON_MODE" = true ]; then json_skip "$MSG"; fi
    goax_warn "$MSG"; exit "$EXIT_SKIPPED"
fi

# ── 실행 ─────────────────────────────────────────────────────────
PASSED=0; FAILED=0; SKIPPED=0
CHECKS_JSON=""
EVIDENCE=""
LOG_DIR=$(mktemp -d)

idx=0
for name in "${NAMES[@]}"; do
    cmd="${RUNS[$idx]}"
    idx=$((idx + 1))

    if [ -z "$cmd" ]; then
        SKIPPED=$((SKIPPED + 1))
        EVIDENCE="${EVIDENCE}- ${name}: (명령 없음 — 안 돌렸어요)
"
        CHECKS_JSON="${CHECKS_JSON}${CHECKS_JSON:+,}$(printf '{"name":"%s","cmd":"","exit":null,"ok":null,"tail_lines":[]}' "$name")"
        continue
    fi

    if [ "$DRY_RUN" = true ]; then
        EVIDENCE="${EVIDENCE}- ${name}: dry-run — ${cmd}
"
        CHECKS_JSON="${CHECKS_JSON}${CHECKS_JSON:+,}$(jq -nc --arg n "$name" --arg c "$cmd" \
            '{name:$n,cmd:$c,exit:null,ok:null,tail_lines:[]}' 2>/dev/null \
            || printf '{"name":"%s","cmd":"%s","exit":null,"ok":null,"tail_lines":[]}' "$name" "$cmd")"
        continue
    fi

    LOG="$LOG_DIR/$name.log"
    # 핵심 — 파이프 없이 실행하고 exit code 를 그대로 받아요.
    # 출력은 파일로 빼요 (`| tee` 조차 쓰지 않아요. pipefail 이 꺼져 있으면 그것도 코드를 덮어요)
    bash -c "$cmd" > "$LOG" 2>&1
    code=$?

    if [ "$code" -eq 0 ]; then
        PASSED=$((PASSED + 1))
        EVIDENCE="${EVIDENCE}- ${name}: \`${cmd}\` → exit 0
"
        CHECKS_JSON="${CHECKS_JSON}${CHECKS_JSON:+,}$(jq -nc --arg n "$name" --arg c "$cmd" \
            '{name:$n,cmd:$c,exit:0,ok:true,tail_lines:[]}' 2>/dev/null \
            || printf '{"name":"%s","cmd":"%s","exit":0,"ok":true,"tail_lines":[]}' "$name" "$cmd")"
    else
        FAILED=$((FAILED + 1))
        EVIDENCE="${EVIDENCE}- ${name}: \`${cmd}\` → **exit ${code}**
"
        TAIL_JSON="[]"
        if command -v jq >/dev/null 2>&1; then
            TAIL_JSON=$(tail -20 "$LOG" | jq -Rn '[inputs]' 2>/dev/null || printf '[]')
        fi
        CHECKS_JSON="${CHECKS_JSON}${CHECKS_JSON:+,}$(jq -nc --arg n "$name" --arg c "$cmd" \
            --argjson e "$code" --argjson t "$TAIL_JSON" \
            '{name:$n,cmd:$c,exit:$e,ok:false,tail_lines:$t}' 2>/dev/null \
            || printf '{"name":"%s","cmd":"%s","exit":%s,"ok":false,"tail_lines":[]}' "$name" "$cmd" "$code")"
    fi
done

WARN_JSON="[]"
if [ "$FAILED" -gt 0 ]; then
    STATUS="error"; EXIT_CODE=1
    NEXT="게이트 ${FAILED}건 실패 — tail_lines 를 보고 고친 뒤 다시 돌리세요"
elif [ "$PASSED" -eq 0 ] && [ "$DRY_RUN" != true ]; then
    # 하나도 안 돌았는데 초록을 주면 이 도구가 막으려던 바로 그 사고예요
    # (CI 가 게이트를 한 번도 실행하지 않고 통과한 사례). 그래서 exit 2 로 세워요.
    STATUS="skipped"; EXIT_CODE=2
    NEXT="**게이트가 하나도 안 돌았어요** (안 돌린 것 ${SKIPPED}건) — .ax/config.yml 의 commands 를 채우세요. 안 돌린 건 통과가 아니에요"
    WARN_JSON=$(_goax_json_array "$NEXT")
else
    STATUS="ok"; EXIT_CODE=0
    if [ "$SKIPPED" -gt 0 ]; then
        NEXT="통과 ${PASSED}건 · **안 돌린 것 ${SKIPPED}건** — 안 돌린 건 통과가 아니에요"
        WARN_JSON=$(_goax_json_array "안 돌린 게이트 ${SKIPPED}건 — commands 가 비었어요")
    else
        NEXT="통과 ${PASSED}건. 이 증거 블록을 보고에 그대로 붙이세요"
    fi
fi

if [ "$JSON_MODE" = true ]; then
    if command -v jq >/dev/null 2>&1; then
        RESULT=$(jq -nc --argjson checks "[${CHECKS_JSON}]" \
                       --argjson p "$PASSED" --argjson f "$FAILED" --argjson s "$SKIPPED" \
                       --arg ev "$EVIDENCE" \
                       '{checks:$checks,passed:$p,failed:$f,skipped:$s,evidence:$ev}')
    else
        RESULT=$(printf '{"checks":[%s],"passed":%s,"failed":%s,"skipped":%s,"evidence":""}' \
                        "$CHECKS_JSON" "$PASSED" "$FAILED" "$SKIPPED")
    fi
    json_output "$STATUS" "$RESULT" "$NEXT" "$WARN_JSON"
else
    printf '%s' "$EVIDENCE"
    printf '%s\n' "$NEXT"
fi

unlink "$LOG_DIR"/*.log 2>/dev/null || true
rmdir "$LOG_DIR" 2>/dev/null || true
exit "$EXIT_CODE"
