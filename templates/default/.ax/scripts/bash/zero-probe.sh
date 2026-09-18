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
# 내장 프로브 `pattern-rules` — 파일이 없어도 항상 돌아요 (룰 파일에 `<!-- 검출 패턴: -->` 이 하나라도 있으면):
#   룰마다 ❌ 예시가 패턴에 **걸리고** ✅ 예시는 **안 걸리는지** 를 재요. 워킹트리·인덱스를 건드리지 않아요
#   (hermetic) — 훅이 실제로 도는지는 secret-scan.sh 류 프로브와 doctor I5/C2 가 봐요.
#   ❌/✅ 가 없는 패턴 룰은 skip 으로 세요 — 안 잰 것은 통과가 아니에요.
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

# 내장 프로브 대상 — 패턴 마커가 있는 룰 파일
PATTERN_RULE_FILES=""
for rf in "$PROJECT_ROOT"/.ax/spirit/rules/*.md "$PROJECT_ROOT"/.ax/modules/*/rules.md; do
    [ -f "$rf" ] || continue
    case "$(basename "$rf")" in README.md) continue ;; esac
    [ -n "$(goax_rule_patterns "$rf")" ] && PATTERN_RULE_FILES="${PATTERN_RULE_FILES}${rf}"$'\n'
done
HAS_PATTERN_RULES=false; [ -n "$PATTERN_RULE_FILES" ] && HAS_PATTERN_RULES=true

if [ "$COUNT" -eq 0 ] && [ "$HAS_PATTERN_RULES" = false ]; then
    MSG="프로브가 없어요 — .ax/_templates/zero/probes/ 에서 복사해 ${PROBE_DIR#$PROJECT_ROOT/} 에 두세요"
    if [ "$JSON_MODE" = true ]; then json_skip "$MSG"; fi
    goax_warn "$MSG"; exit "$EXIT_SKIPPED"
fi

probe_desc() {   # 첫 `# probe:` 주석 한 줄
    sed -n 's/^# *probe: *//p' "$1" 2>/dev/null | head -1
}

if [ "$LIST_ONLY" = true ]; then
    [ "$HAS_PATTERN_RULES" = true ] && printf '%s\t%s\n' "pattern-rules" "(내장) 룰의 검출 패턴이 ❌ 예시를 잡고 ✅ 예시를 안 잡는지"
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
LOG_DIR=$(goax_mktemp -d "$PROJECT_ROOT") || { goax_tmp_error; exit "$EXIT_ERROR"; }
trap '[ -n "${LOG_DIR:-}" ] && rm -rf "$LOG_DIR"' EXIT   # 조기 종료에도 지워요 — 폴백이면 프로젝트 트리(.ax/.session/tmp) 안이라 새면 보여요

# 결과 한 건을 집계·JSON 에 적어요. 파일 프로브와 내장 프로브가 같은 경로를 타야 스키마가 안 갈라져요.
#   record_probe <name> <desc> <exit-code> <log-file> [always_tail]
record_probe() {
    local name="$1" desc="$2" code="$3" LOG="$4" always_tail="${5:-false}" ok entry TAIL_JSON
    ok="false"
    case "$code" in
        0) PASSED=$((PASSED + 1)); ok="true" ;;
        2) SKIPPED=$((SKIPPED + 1)); ok="null" ;;
        *) FAILED=$((FAILED + 1)) ;;
    esac
    TAIL_JSON="[]"
    if { [ "$code" -ne 0 ] || [ "$always_tail" = true ]; } && command -v jq >/dev/null 2>&1; then
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
}

# ─── 내장 프로브: pattern-rules ─────────────────────────────────────
# 룰 파일의 `<!-- 검출 패턴: -->` 하나하나에 대해 ❌ 예시(goax_rule_examples 의 bad) 가 걸리고
# ✅ 예시(good) 가 안 걸리는지. 파일을 만들거나 stage 하지 않아요 — 문자열을 grep 에 흘릴 뿐이에요.
# 판정: 하나라도 어긋나면 exit 1 · 잴 수 있는 룰이 0 이면 exit 2 · 나머지 exit 0.
run_pattern_probe() {   # stdout 에 로그, 종료 코드가 판정
    local n_rule=0 n_fail=0 n_skip=0 rf rel token pat pats toks bads goods b g prc rule_ok bad_ok
    while IFS= read -r rf; do
        [ -z "$rf" ] && continue
        rel="${rf#$PROJECT_ROOT/}"
        EX=$(goax_rule_examples "$rf")
        PATS=$(goax_rule_patterns "$rf")
        toks=$(printf '%s\n' "$PATS" | cut -f1 | awk 'NF && !seen[$0]++')
        # 룰(토큰) 단위로 판정해요 — 한 룰의 마커 여러 줄은 OR 이라, ❌ 는 그중 하나에만 걸리면 되고
        # ✅ 는 어느 것에도 걸리면 안 돼요.
        while IFS= read -r token; do
            [ -z "$token" ] && continue
            n_rule=$((n_rule + 1))
            pats=$(printf '%s\n' "$PATS" | awk -F'\t' -v t="$token" '$1==t {print $2}')
            rule_ok=true
            while IFS= read -r pat; do
                [ -z "$pat" ] && continue
                grep -qE -e "$pat" /dev/null 2>/dev/null; prc=$?
                if [ "$prc" -eq 2 ]; then
                    printf 'FAIL %s — 검출 패턴 문법 오류: %s (%s)\n' "$token" "$pat" "$rel"; rule_ok=false
                fi
            done <<< "$pats"
            if [ "$rule_ok" = false ]; then n_fail=$((n_fail + 1)); continue; fi
            bads=$(printf '%s\n' "$EX" | awk -F'\t' -v t="$token" '$1==t && $2=="bad" {print $3}')
            goods=$(printf '%s\n' "$EX" | awk -F'\t' -v t="$token" '$1==t && $2=="good" {print $3}')
            if [ -z "$bads" ]; then
                printf 'skip %s — ❌ 예시가 없어 패턴을 못 재요 (%s)\n' "$token" "$rel"; n_skip=$((n_skip + 1)); continue
            fi
            while IFS= read -r b; do
                [ -z "$b" ] && continue
                bad_ok=false
                while IFS= read -r pat; do
                    [ -z "$pat" ] && continue
                    printf '%s\n' "$b" | grep -qE -e "$pat" && { bad_ok=true; break; }
                done <<< "$pats"
                if [ "$bad_ok" = false ]; then
                    printf 'FAIL %s — ❌ 예시가 패턴에 안 걸려요: %s (%s)\n' "$token" "$b" "$rel"; rule_ok=false
                fi
            done <<< "$bads"
            while IFS= read -r g; do
                [ -z "$g" ] && continue
                while IFS= read -r pat; do
                    [ -z "$pat" ] && continue
                    if printf '%s\n' "$g" | grep -qE -e "$pat"; then
                        printf 'FAIL %s — ✅ 예시가 패턴에 걸려요 (오탐): %s (%s)\n' "$token" "$g" "$rel"; rule_ok=false
                    fi
                done <<< "$pats"
            done <<< "$goods"
            if [ "$rule_ok" = true ]; then printf 'ok   %s (%s)\n' "$token" "$rel"; else n_fail=$((n_fail + 1)); fi
        done <<< "$toks"
    done <<< "$PATTERN_RULE_FILES"
    printf 'pattern-rules: 룰 %d개 — ok %d · fail %d · skip %d\n' "$n_rule" $((n_rule - n_fail - n_skip)) "$n_fail" "$n_skip"
    [ "$n_fail" -gt 0 ] && return 1
    [ "$n_rule" -eq 0 ] || [ "$n_skip" -eq "$n_rule" ] && return 2
    return 0
}

if [ "$HAS_PATTERN_RULES" = true ] && { [ -z "$ONLY" ] || [ "$ONLY" = "pattern-rules" ]; }; then
    LOG="$LOG_DIR/pattern-rules.log"
    run_pattern_probe > "$LOG" 2>&1; code=$?
    record_probe "pattern-rules" "(내장) 룰의 검출 패턴이 ❌ 예시를 잡고 ✅ 예시를 안 잡는지" "$code" "$LOG" true
fi

while IFS= read -r f; do
    [ -z "$f" ] && continue
    name=$(basename "$f" .sh)
    [ -n "$ONLY" ] && [ "$name" != "$ONLY" ] && continue
    desc=$(probe_desc "$f")

    LOG="$LOG_DIR/$name.log"
    bash "$f" > "$LOG" 2>&1
    code=$?
    record_probe "$name" "$desc" "$code" "$LOG"
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

exit "$EXIT_CODE"
