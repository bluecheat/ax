#!/usr/bin/env bash
# .ax/hud/statusline.sh — goax HUD (단일 디자인, preset 없음)
# .claude/settings.json의 statusLine.command 에서 호출
# Claude Code statusline 공식: stdin JSON, multi-line, ANSI colors
# https://code.claude.com/docs/en/statusline
#
# 표시:
#   triage: <Size>×<Risk>    — 색상 매트릭스로 작업 위험도 즉시 인지
#   harness: <evolution>     — 4계층 종합 활성도 (우주 진화 한 글자)
#   ☄<n>                     — mistakes count (혜성, 우주 메타포 일관)
#
# 우주 진화 단계 (4계층 활성 수 합산):
#   0/4: ·  (특이점)
#   1/4: ✦  (별 첫 빛)
#   2/4: ⭐  (항성)
#   3/4: 🌟  (빛나는 별)
#   4/4: 🪐  (우아한 행성)
#
# IMPORTANT: state.json read-only. 갱신은 .ax/scripts/bash/update-state.sh.
# state.json schema·ownership: docs/state-ownership.md (plugin repo).

set -u

# stdin JSON (Claude Code statusline 사양)
INPUT=$(cat 2>/dev/null || echo '{}')
if command -v jq >/dev/null 2>&1; then
    WS_DIR=$(echo "$INPUT" | jq -r '.workspace.current_dir // "."' 2>/dev/null || echo ".")
else
    WS_DIR="."
fi

S="$WS_DIR/.ax/state.json"

# goax 미설치 / jq 없음 — fallback
if [ ! -f "$S" ] || ! command -v jq >/dev/null 2>&1; then
    printf "\033[2mgoax\033[0m"
    exit 0
fi

# ─── harness 진화 단계 (4계층 종합) ───
ACTIVE=0
for layer in L0_triage L1_constitution L2_module L3_spec_adr; do
    A=$(jq -r ".layers.${layer}.active // false" "$S" 2>/dev/null)
    [ "$A" = "true" ] && ACTIVE=$((ACTIVE+1))
done

case "$ACTIVE" in
    4) HARNESS="🪐"; HC="\033[36m" ;;  # 우아한 행성 + cyan
    3) HARNESS="🌟"; HC="\033[32m" ;;  # 빛나는 별 + green
    2) HARNESS="⭐"; HC="\033[33m" ;;  # 항성 + yellow
    1) HARNESS="✦";  HC="\033[33m" ;;  # 별 첫 빛 + yellow
    *) HARNESS="·";  HC="\033[2m"  ;;  # 특이점 + dim
esac
HARNESS_FRAG=$(printf "\033[2mharness:\033[0m %b%s\033[0m" "$HC" "$HARNESS")

# ─── triage (current_task) ───
SIZE=$(jq -r '.current_task.size // ""' "$S" 2>/dev/null)
RISK=$(jq -r '.current_task.risk // ""' "$S" 2>/dev/null)

# Risk 색상 — L3 red / L2 yellow / L1 green / L0 dim
case "$RISK" in
    L3) RC="\033[31m" ;;
    L2) RC="\033[33m" ;;
    L1) RC="\033[32m" ;;
    L0) RC="\033[2m"  ;;
    *)  RC=""         ;;
esac

# Size 색상 — XL red / L yellow / M cyan / S dim
case "$SIZE" in
    XL) SC="\033[31m" ;;
    L)  SC="\033[33m" ;;
    M)  SC="\033[36m" ;;
    S)  SC="\033[2m"  ;;
    *)  SC=""         ;;
esac

TRIAGE_FRAG=""
if [ -n "$SIZE" ] && [ -n "$RISK" ]; then
    TRIAGE_FRAG=$(printf "\033[2mtriage:\033[0m %b%s\033[0m\033[2m×\033[0m%b%s\033[0m" \
        "$SC" "$SIZE" "$RC" "$RISK")
elif [ -n "$RISK" ]; then
    TRIAGE_FRAG=$(printf "\033[2mtriage:\033[0m %b%s\033[0m" "$RC" "$RISK")
elif [ -n "$SIZE" ]; then
    TRIAGE_FRAG=$(printf "\033[2mtriage:\033[0m %b%s\033[0m" "$SC" "$SIZE")
fi

# ─── mistakes ☄ ───
MIS=$(jq -r '.cross_cut.mistakes.count // 0' "$S" 2>/dev/null)
if [ "$MIS" -ge 10 ]; then
    MIS_FRAG=$(printf "\033[31m☄%s\033[0m" "$MIS")
elif [ "$MIS" -ge 5 ]; then
    MIS_FRAG=$(printf "\033[33m☄%s\033[0m" "$MIS")
elif [ "$MIS" -gt 0 ]; then
    MIS_FRAG="☄${MIS}"
else
    MIS_FRAG="\033[2m☄0\033[0m"
fi

# ─── 조합 (단일 줄) ───
LINE=""
[ -n "$TRIAGE_FRAG" ] && LINE="$TRIAGE_FRAG | "
LINE="${LINE}${HARNESS_FRAG} | $MIS_FRAG"

printf "%b" "$LINE"
