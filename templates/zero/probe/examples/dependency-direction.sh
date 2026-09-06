#!/usr/bin/env bash
# probe: 하위 패키지가 상위를 import 하면 경계 lint 가 막는가
#
# 계약: 게이트가 막았으면 exit 0 · 못 막았으면 exit 1 · 돌릴 수 없으면 exit 2
# 이 파일을 프로젝트에 맞게 고쳐서 `.ax/probes/` 에 두세요.

set -uo pipefail

VIOLATION="packages/core/src/__probe_dependency__.ts"
GATE=(npx eslint "$VIOLATION" --no-inline-config)   # ← 프로젝트 경계 lint 로 교체

[ -d "packages/core/src" ] || { echo "packages/core/src 없음 — skip"; exit 2; }
command -v npx >/dev/null 2>&1 || { echo "npx 없음 — skip"; exit 2; }

cleanup() { [ -f "$VIOLATION" ] && unlink "$VIOLATION"; }
trap cleanup EXIT

# 1. 일부러 위반 만들기 — 하위 계층이 상위 계층을 끌어옵니다
printf "import React from 'react';\nexport const x = React;\n" > "$VIOLATION"

# 2. 게이트 실행 — **파이프 없이**. `| tail` 을 붙이면 exit code 가 tail 것이 돼요
"${GATE[@]}" > /dev/null 2>&1
code=$?

# 3. 판정 — 막았으면(비0) 통과
if [ "$code" -ne 0 ]; then
    echo "게이트가 위반을 차단했어요 (exit $code)"
    exit 0
fi

echo "PROBE FAILED — 역방향 import 가 통과했어요. 경계 lint 가 뚫려 있습니다"
echo "  확인: no-restricted-imports 설정 · --no-inline-config (disable 주석 우회 차단)"
exit 1
