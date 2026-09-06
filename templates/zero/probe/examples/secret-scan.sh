#!/usr/bin/env bash
# probe: 시크릿이 담긴 파일을 커밋하려 하면 pre-commit 이 막는가
#
# 계약: 게이트가 막았으면 exit 0 · 못 막았으면 exit 1 · 돌릴 수 없으면 exit 2
#
# 워킹 트리를 건드리므로 스테이지·인덱스를 반드시 되돌려요 (다른 세션이 같은 트리에
# 있을 수 있어요). 커밋은 만들지 않아요 — pre-commit 훅만 부릅니다.

set -uo pipefail

FIXTURE=".probe-secret.txt"

command -v git >/dev/null 2>&1 || { echo "git 없음 — skip"; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "git 저장소 아님 — skip"; exit 2; }
HOOK="$(git rev-parse --git-dir)/hooks/pre-commit"
[ -x "$HOOK" ] || { echo "pre-commit 훅 미설치 — skip (install-git-hooks.sh)"; exit 2; }

cleanup() {
    git reset -q -- "$FIXTURE" 2>/dev/null || true
    [ -f "$FIXTURE" ] && unlink "$FIXTURE"
}
trap cleanup EXIT

# 1. 일부러 위반 만들기 — 문서에서 흔히 쓰는 가짜 AWS 키 형태
printf 'AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE\n' > "$FIXTURE"
git add -f "$FIXTURE" 2>/dev/null || { echo "스테이지 실패 — skip"; exit 2; }

# 2. 훅만 직접 실행 — 커밋을 만들지 않아요. 파이프 없이
"$HOOK" > /dev/null 2>&1
code=$?

# 3. 판정
if [ "$code" -ne 0 ]; then
    echo "pre-commit 이 시크릿을 차단했어요 (exit $code)"
    exit 0
fi

echo "PROBE FAILED — 시크릿이 스테이지를 통과했어요. secrets 게이트가 뚫려 있습니다"
exit 1
