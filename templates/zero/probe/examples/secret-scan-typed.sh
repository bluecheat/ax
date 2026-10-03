#!/usr/bin/env bash
# probe: 타입 선언 옆의 시크릿 값은 막고, 타입 선언만 있는 파일은 통과시키는가
#
# 계약: 게이트가 막았으면 exit 0 · 못 막았으면 exit 1 · 돌릴 수 없으면 exit 2
#
# secret-scan.sh 의 짝이에요. 그쪽은 "막는가" 만 재요. 이쪽은 **막아야 할 것과 막으면 안 되는 것을 같이** 재요 —
# `token: string,` 같은 TS 타입 선언을 시크릿으로 잡는 게이트는 매 커밋 오탐을 내고, 결국 프로젝트가
# sensors.mode 를 warning 으로 내려 안전망 전체를 끄게 돼요 (실측). 그래서 둘 다 확인해요:
#   1) 타입 선언과 같은 파일·같은 줄에 있는 실제 값 대입은 여전히 막는가 (네거티브)
#   2) 타입 선언만 있는 파일은 통과하는가 (오탐 회귀)
#
# 워킹 트리를 건드리므로 스테이지·인덱스를 반드시 되돌려요. 커밋은 만들지 않아요.

set -uo pipefail

FIXTURE=".probe-secret-typed.ts"

command -v git >/dev/null 2>&1 || { echo "git 없음 — skip"; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "git 저장소 아님 — skip"; exit 2; }
HOOK="$(git rev-parse --git-dir)/hooks/pre-commit"
[ -x "$HOOK" ] || { echo "pre-commit 훅 미설치 — skip (install-git-hooks.sh)"; exit 2; }

cleanup() {
    git reset -q -- "$FIXTURE" 2>/dev/null || true
    [ -f "$FIXTURE" ] && unlink "$FIXTURE"
}
trap cleanup EXIT

types_only() {
    printf 'export interface PushTarget {\n  token: string,\n  apiKey?: string;\n'
    printf '  messageFor?(target: UserTarget, token: string, platform: Platform): string;\n}\n'
}

# 1. 타입 선언 + 실제 값 — 막혀야 해요. 값은 공개 예시용 가짜예요.
{
    types_only
    printf 'export const token: string = "PROBEFIXTURE0not0a0real0secret";\n'
} > "$FIXTURE"
git add -f "$FIXTURE" 2>/dev/null || { echo "스테이지 실패 — skip"; exit 2; }
"$HOOK" > /dev/null 2>&1
code=$?
if [ "$code" -eq 0 ]; then
    echo "PROBE FAILED — 타입 선언 옆의 시크릿 값이 스테이지를 통과했어요. secrets 게이트가 뚫려 있습니다"
    exit 1
fi

# 2. 타입 선언만 — 통과해야 해요. 다른 훅이 이 파일을 막을 이유는 없어야 해요.
types_only > "$FIXTURE"
git add -f "$FIXTURE" 2>/dev/null || { echo "스테이지 실패 — skip"; exit 2; }
"$HOOK" > /dev/null 2>&1
code=$?
if [ "$code" -ne 0 ]; then
    echo "PROBE FAILED — 타입 선언만 있는 파일을 막았어요 (exit $code). 오탐이 이어지면 게이트를 끄게 돼요"
    exit 1
fi

echo "타입 옆 시크릿 값은 막고 (exit ≠ 0) 타입 선언만은 통과시켰어요"
exit 0
