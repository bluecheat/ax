#!/usr/bin/env bash
# pre-bash hook — 첫날 계약 둘 (산문 룰에서 옮겨 온 것)
#
#   1. `git add -A` / `git add .` — 차단. 워킹 트리는 공유 자원이에요.
#   2. 게이트 명령을 파이프에 물림 — 경고. `cmd | tail` 의 exit code 는 tail 것이에요.
#
# 왜 hook 인가: 둘 다 기계가 판정할 수 있어요. 산문으로 적으면 advisory 지만
# hook 은 실행을 보장해요. 그리고 hook 정의는 settings.json 에 살아서
# **모델 컨텍스트를 한 글자도 안 씁니다.**
#
# ⚠️ 조용해야 해요 — 통과하면 아무 말도 안 해요. hook 출력은 컨텍스트에 들어가서,
#    시끄러운 hook 은 (가)로 옮겨서 아낀 토큰을 도로 씁니다.
#
# 입력: Claude Code 공식 hook stdin JSON ({tool_name, tool_input.command, ...})
# 종료: 차단 exit 2 · 경고 stderr + exit 0 · 통과 무출력 exit 0
#
# 의도적으로 `git add -A` 를 써야 하면 GOAX_ALLOW_ADD_ALL=1 를 붙이세요.
# (mode-aware 로 두지 않은 이유: warning 이면 산문 룰과 같아져서 옮긴 의미가 없어요.
#  준수 비용이 "경로를 적는다" 뿐이라 차단이 정당해요.)

set -uo pipefail   # -e 없음 — grep 미매칭(exit 1)이 hook 을 조용히 죽이면 안 돼요

[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0
[ "${GOAX_ALLOW_ADD_ALL:-0}" = "1" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"
CMD=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
fi
CMD="${CMD:-${CLAUDE_BASH_COMMAND:-${1:-}}}"
[ -z "$CMD" ] && exit 0

# 정규화 — 따옴표·탭·연속 공백 흡수 (표기 변형으로 우회되면 안 돼요). \047=' \042="
NORM=$(printf '%s' "$CMD" | tr -d '\047\042' | tr '\t\n' '  ' | sed -E 's/  +/ /g')

matches() { printf '%s' "$NORM" | grep -qE "$1"; }

# ── 1. git add -A / . / --all ────────────────────────────────────
# 명령어 위치의 git add 만 (`# git add -A` 같은 주석·문서 인용은 앞 문자로 걸러져요)
if matches '(^| |[;&|(])git add ([^;&|]* )?(-A|--all|\.)( |$)'; then
    printf '[goax] git add -A 차단 — 다른 세션이 같은 트리에 있을 수 있어요. 경로를 적어서 스테이지하세요 (git add <path>).\n' >&2
    exit 2
fi

# ── 2. 게이트 명령을 파이프에 물림 ───────────────────────────────
# `cmd | tail` 의 종료 코드는 tail 것이라, 실패가 초록으로 보여요.
# 오탐이 있을 수 있어 경고만 해요 (차단하면 정상적인 로그 훑기까지 막혀요).
GATE='(test|typecheck|tsc|lint|build|pytest|go test|cargo (test|build)|gradlew|xcodebuild|eslint|ruff|mypy)'
SWALLOW='\| *(head|tail|grep|less|more|wc|cat)'
if matches "$GATE" && matches "$SWALLOW"; then
    printf '[goax] 게이트 명령에 파이프가 붙었어요 — exit code 가 뒤 명령 것으로 바뀝니다. bash .ax/scripts/bash/zero-verify.sh 를 쓰거나 set -o pipefail 을 켜세요.\n' >&2
    exit 0
fi

exit 0
