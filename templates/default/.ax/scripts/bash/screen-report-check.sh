#!/usr/bin/env bash
# .ax/scripts/bash/screen-report-check.sh — screen-designer 리포트가 판정할 수 있는 모양인지 봐요 (screen skill 이 판정 전에)
#
# 왜: 리포트 첫 줄의 verdict 만 믿으면, 스크린샷 없이 "통과" 라고 쓴 리포트도 통과해요.
#   그래서 첫 줄 형식 · `통과` 의 근거(실제로 있는 스크린샷 파일 · 게이트 표의 측정값) · ❌ 개수를 결정론으로 세요.
#   skill 은 이 JSON 만 읽고 판정해요 — 리포트 본문을 메인 컨텍스트로 다시 읽지 않아요.
#
# 규칙:
#   첫 줄            `verdict: 통과` · `verdict: 보강 필요` · `verdict: 실측 아님` 중 정확히 하나
#   게이트 표         `### 게이트` 아래 첫 표. 2열(측정값)이 비었거나 —·-·TBD 면 빈 칸, 4열(결과)에 ❌ 가 있으면 실패 행
#   통과일 때         스크린샷(.png·.jpg·.jpeg·.webp) 경로가 하나 이상 있고 파일이 실제로 있어야 하고, 빈 칸 0 · ❌ 0 ·
#                    코드값 칸 0 (측정값에 `코드값` 이나 `실측 아님` 이 적힌 칸 — 코드 상수는 실측이 아니에요)
#   보강 필요일 때     ❌ 가 하나 이상이어야 해요 (❌ 0 인데 보강 필요면 모순)
#   실측 아님일 때     빈 칸·❌ 는 허용 — 대신 미해결이 리포트에 있어야 사용자에게 보여줄 수 있어요
#
# Usage:
#   bash screen-report-check.sh [--report <path>] [--json]     # 없으면 docs/design/reports/ 의 가장 최근 .md
#
# Output (--json):
#   {"status":"ok|warning","result":{"report":"…","verdict":"통과|보강 필요|실측 아님"|null,"valid":bool,
#     "screenshots":{"cited":N,"existing":N},"gates":{"rows":N,"empty":N,"failed":N,"code":N},"problems":["…"]},…}
#   status=warning 이면 valid=false — skill 은 problems 를 브리프에 붙여 한 번만 다시 맡겨요.
# Exit: 0 ok/warning · 1 error (리포트 없음) · 2 skipped (jq 없음)
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; DRY_RUN=false; SHOW_HELP=false; REPORT=""
while [ $# -gt 0 ]; do
    if parse_common_opts "$1"; then shift; continue; fi
    case "$1" in
        --report) REPORT="${2:-}"; shift 2 ;;
        *) goax_error "알 수 없는 옵션: $1 — --help 로 사용법을 봐요"; exit "$EXIT_ERROR" ;;
    esac
done
if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
if ! command -v jq >/dev/null 2>&1; then
    [ "$JSON_MODE" = true ] && json_skip "jq 가 필요해요 — brew install jq 또는 apt-get install jq"
    goax_warn "jq 가 없어 skip"; exit "$EXIT_SKIPPED"
fi
fail() { [ "$JSON_MODE" = true ] && json_error "$1"; goax_error "$1"; exit "$EXIT_ERROR"; }
PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
cd "$PROJECT_ROOT"

if [ -z "$REPORT" ]; then
    REPORT=$( { ls -t docs/design/reports/*.md 2>/dev/null | head -1; } || true)
    [ -n "$REPORT" ] || fail "리포트가 없어요 — docs/design/reports/ 가 비었어요. screen-designer 가 쓴 경로를 --report 로 줘요"
fi
[ -f "$REPORT" ] || fail "리포트가 없어요: $REPORT"

FIRST=$(head -1 "$REPORT" | sed -E 's/[[:space:]]+$//')
VERDICT=""
case "$FIRST" in
    "verdict: 통과") VERDICT="통과" ;;
    "verdict: 보강 필요") VERDICT="보강 필요" ;;
    "verdict: 실측 아님") VERDICT="실측 아님" ;;
esac

# 게이트 표 — `### 게이트` 아래 첫 표의 데이터 행 (헤더·구분선 제외)
GATES=$(awk '
    /^###[[:space:]]+게이트/ { in_sec = 1; next }
    in_sec && /^#/ { exit }
    in_sec && /^\|/ { n++; if (n <= 2) next; print; seen = 1; next }
    in_sec && seen && !/^\|/ { exit }' "$REPORT")
G_ROWS=0; G_EMPTY=0; G_FAIL=0; G_CODE=0
while IFS= read -r row; do
    [ -n "$row" ] || continue
    G_ROWS=$((G_ROWS + 1))
    measured=$(printf '%s' "$row" | awk -F'|' '{ v = $3; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); print v }')
    result=$(printf '%s' "$row" | awk -F'|' '{ print $5 }')
    case "$measured" in ""|"—"|"-"|"TBD"|"tbd") G_EMPTY=$((G_EMPTY + 1)) ;; esac
    case "$result" in *❌*) G_FAIL=$((G_FAIL + 1)) ;; esac
    case "$measured" in *코드값*|*"실측 아님"*) G_CODE=$((G_CODE + 1)) ;; esac
done <<< "$GATES"

# 스크린샷 — 리포트에 적힌 이미지 경로 중 실제로 있는 것 (상대 경로는 프로젝트 루트 기준)
CITED=0; EXIST=0
while IFS= read -r p; do
    [ -n "$p" ] || continue
    CITED=$((CITED + 1))
    case "$p" in /*) f="$p" ;; *) f="$PROJECT_ROOT/$p" ;; esac
    [ -f "$f" ] && EXIST=$((EXIST + 1))
done < <(grep -oE '[^`[:space:]()]+\.(png|jpg|jpeg|webp)' "$REPORT" | awk '!seen[$0]++' || true)

PROBLEMS=()
[ -n "$VERDICT" ] || PROBLEMS+=("첫 줄이 verdict 형식이 아니에요: '${FIRST:0:60}' — 'verdict: 통과|보강 필요|실측 아님' 중 하나로")
[ "$G_ROWS" -gt 0 ] || PROBLEMS+=("'### 게이트' 표가 없어요 — 게이트마다 측정값·기준·결과 행이 있어야 해요")
case "$VERDICT" in
    통과)
        [ "$EXIST" -gt 0 ] || PROBLEMS+=("통과인데 실제로 있는 스크린샷이 없어요 (적힌 경로 ${CITED}개 · 있는 파일 ${EXIST}개) — 재지 못했으면 '실측 아님'")
        [ "$G_EMPTY" -eq 0 ] || PROBLEMS+=("통과인데 게이트 측정값 빈 칸이 ${G_EMPTY}개예요 — 숫자 없이 ✅ 는 통과가 아니에요")
        [ "$G_FAIL" -eq 0 ] || PROBLEMS+=("통과인데 ❌ 가 ${G_FAIL}개예요 — '보강 필요' 로")
        [ "$G_CODE" -eq 0 ] || PROBLEMS+=("통과인데 코드값으로 적은 칸이 ${G_CODE}개예요 — 화면에서 재거나 '실측 아님' 으로") ;;
    "보강 필요")
        [ "$G_FAIL" -gt 0 ] || [ "$G_EMPTY" -gt 0 ] || PROBLEMS+=("보강 필요인데 ❌·빈 칸이 없어요 — 무엇이 남았는지 게이트 표에 적어요") ;;
    "실측 아님")
        if [ "$G_FAIL" -gt 0 ] && ! grep -qE '^###[[:space:]]+미해결' "$REPORT"; then
            PROBLEMS+=("실측 아님인데 ❌ ${G_FAIL}개를 적을 '### 미해결' 절이 없어요")
        fi ;;
esac

VALID=true; [ "${#PROBLEMS[@]}" -eq 0 ] || VALID=false
PJ=$(printf '%s\n' ${PROBLEMS[@]+"${PROBLEMS[@]}"} | jq -R . | jq -sc 'map(select(length > 0))')
RESULT=$(jq -nc --arg r "${REPORT#"$PROJECT_ROOT"/}" --arg v "$VERDICT" --argjson ok "$VALID" \
    --argjson c "$CITED" --argjson e "$EXIST" --argjson gr "$G_ROWS" --argjson ge "$G_EMPTY" --argjson gf "$G_FAIL" --argjson gc "$G_CODE" --argjson p "$PJ" \
    '{report: $r, verdict: (if $v == "" then null else $v end), valid: $ok,
      screenshots: {cited: $c, existing: $e}, gates: {rows: $gr, empty: $ge, failed: $gf, code: $gc}, problems: $p}')
if [ "$JSON_MODE" = true ]; then
    if [ "$VALID" = true ]; then json_output ok "$RESULT" "verdict ${VERDICT} — 판정할 수 있어요"
    else json_output warning "$RESULT" "리포트를 판정할 수 없어요 — problems 를 붙여 screen-designer 에게 한 번 다시 맡겨요"; fi
else
    printf '[goax] %s — verdict %s · 게이트 %s행 (빈 칸 %s · ❌ %s) · 스크린샷 %s/%s\n' \
        "${REPORT#"$PROJECT_ROOT"/}" "${VERDICT:-없음}" "$G_ROWS" "$G_EMPTY" "$G_FAIL" "$EXIST" "$CITED"
    for p in ${PROBLEMS[@]+"${PROBLEMS[@]}"}; do printf '  ❗ %s\n' "$p"; done
fi
exit "$EXIT_OK"
