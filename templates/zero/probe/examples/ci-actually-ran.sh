#!/usr/bin/env bash
# probe: CI 가 "성공" 이 아니라 실제로 게이트를 돌렸는가
#
# 계약: 확인됐으면 exit 0 · 안 돌았으면 exit 1 · 확인할 수 없으면 exit 2
#
# 왜 이 프로브가 있나: 워크플로가 의존성 설치에서 실패해 테스트를 **한 번도 실행하지 않은 채**
# 체크는 초록으로 보였어요. "워크플로 성공" 은 증거가 아니에요.
# 증거는 **로그에 게이트 출력 줄이 있다** 예요.

set -uo pipefail

# 로그에서 찾을 표식 — 프로젝트의 테스트 러너 출력에 맞게 고치세요
MARKER='Tests?[[:space:]]+[0-9]+|[0-9]+ (passed|failed)|zero-verify'

command -v gh >/dev/null 2>&1 || { echo "gh CLI 없음 — skip"; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "gh 미인증 — skip"; exit 2; }

LOG=$(mktemp)
cleanup() { unlink "$LOG" 2>/dev/null || true; }
trap cleanup EXIT

# 마지막 실행 로그를 파일로 받아요 (파이프로 grep 하면 gh 의 exit code 를 잃어요)
gh run view --log > "$LOG" 2>/dev/null
code=$?
[ "$code" -eq 0 ] || { echo "gh run view 실패 (exit $code) — skip"; exit 2; }

hits=$(grep -cE "$MARKER" "$LOG" || true)
if [ "${hits:-0}" -gt 0 ]; then
    echo "CI 로그에 게이트 출력 ${hits}줄 — 실제로 돌았어요"
    exit 0
fi

echo "PROBE FAILED — 마지막 CI 로그에 게이트 출력이 없어요. 워크플로는 초록인데 게이트는 안 돌았습니다"
echo "  확인: 설치 스텝 실패 · 조건부 skip · 잘못된 경로"
exit 1
