#!/usr/bin/env bash
# tests/smoke.sh — goax Plugin 구조 검증 (진입점)
# 검증: 파일 구조·JSON 유효성·skill/agent frontmatter·shell 문법·jq syntax·hook 경로 양방향
#       cross-check·MANIFEST 완전성·버전 마커 lint·scripts/bash 런타임 e2e
#
# 검사는 tests/smoke/NN-*.sh 조각에 있어요. 여기서는 조각을 병렬로 돌리고, 출력을 파일 순서대로 붙이고,
# 실패를 합쳐요. 조각이 `smoke_done` 표식 없이 끝나면(중간 exit · set -u 사망) 그것도 실패로 셉니다.
#
# Usage:
#   bash tests/smoke.sh                 # 전부
#   bash tests/smoke.sh locks worktree  # 파일 이름에 그 글자가 든 조각만 (12-locks · 18-friction-worktree)
#                                       # 절이 어느 조각에 있는지는 `grep -n '^section ' tests/smoke/*.sh`
#   GOAX_SMOKE_JOBS=1 bash tests/smoke.sh   # 순차로 (기본은 CPU 수)
#
# 섹션 번호는 **논리 그룹**이에요 — 파일 순서와 다릅니다 (§26 이 §18 위에 있어요).

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
JOBS="${GOAX_SMOKE_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
case "$JOBS" in ''|*[!0-9]*|0) JOBS=4 ;; esac

PARTS=()
for p in "$REPO"/tests/smoke/[0-9][0-9]-*.sh; do
    [ -f "$p" ] || continue
    if [ $# -gt 0 ]; then
        hit=false
        for want in "$@"; do case "$(basename "$p")" in *"$want"*) hit=true ;; esac; done
        [ "$hit" = true ] || continue
    fi
    PARTS+=("$p")
done
if [ "${#PARTS[@]}" -eq 0 ]; then
    printf '\033[31m✗ 돌릴 조각이 없어요: %s\033[0m\n' "$*"; exit 1
fi

OUT=$(mktemp -d) || { printf '✗ mktemp 실패\n'; exit 1; }
trap 'rm -rf "$OUT"' EXIT
START=$(date +%s)
# 조각 하나가 멈춰도 CI 가 같이 멈추지 않게 조각마다 시간 상한 (GOAX_SMOKE_PART_TIMEOUT, 기본 600초 — 지나면 exit 142)
PART_TIMEOUT="${GOAX_SMOKE_PART_TIMEOUT:-600}"
printf '%s\0' "${PARTS[@]}" | xargs -0 -P "$JOBS" -n 1 bash -c \
    'n=$(basename "$2" .sh); perl -e "alarm shift; exec @ARGV" "$1" bash "$2" > "$0/$n.log" 2>&1; echo $? > "$0/$n.rc"' "$OUT" "$PART_TIMEOUT"

fail_count=0
for p in "${PARTS[@]}"; do
    n=$(basename "$p" .sh)
    grep -v '^@@smoke-part-done ' "$OUT/$n.log" 2>/dev/null
    done_line=$(grep '^@@smoke-part-done ' "$OUT/$n.log" 2>/dev/null | tail -1)
    if [ -n "$done_line" ]; then
        fail_count=$((fail_count + ${done_line##*fail=}))
    else
        printf '\033[31m✗\033[0m 조각 %s 이 끝까지 안 돌았어요 (exit %s) — bash tests/smoke/%s.sh 로 혼자 돌려 봐요\n' \
            "$n" "$(cat "$OUT/$n.rc" 2>/dev/null || echo '?')" "$n"
        fail_count=$((fail_count + 1))
    fi
done

printf '\n\033[1m== ✨ 결과 ==\033[0m  조각 %s개 · 병렬 %s · %s초\n' "${#PARTS[@]}" "$JOBS" "$(( $(date +%s) - START ))"
if [ "$fail_count" -eq 0 ]; then
    printf '\033[32m✓ 모든 smoke 검증 통과\033[0m\n'
    exit 0
else
    printf '\033[31m✗ %s개 실패\033[0m\n' "$fail_count"
    exit 1
fi
