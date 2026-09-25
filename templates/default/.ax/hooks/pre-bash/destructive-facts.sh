#!/usr/bin/env bash
# pre-bash hook — 되돌리기 어려운 명령은 사실을 먼저 적게 해요 (fact-forcing)
#
# 대상: 프로젝트 안 재귀 rm · find -delete · git clean -f · git checkout -- <경로>/./-f · git restore(작업 트리) ·
#   git reset --hard · git stash drop|clear · git branch -D. 재생성 디렉토리(기본값 + sensors.regenerable_paths)와
#   프로젝트 밖 경로는 제외. 값이 변수(`$X`)인 경로는 판단하지 않아요 — 안전망이지 보안 경계가 아니에요.
# 동작: 세션에서 처음 보는 명령이면 exit 2 로 막고 "지워질 파일 · 되돌리는 절차 · 사용자 지시 원문" 을 요구해요.
#   같은 명령을 다시 실행하면 통과, 명령이 바뀌면 다시 물어요. 3번째 뒤로는 한 줄. 세션 id 가 없으면 경고만.
#   "정말요?" 는 늘 "네" 라서 사실을 요구해요 — 적는 과정에서 모르던 파일이 보여요 (CONCEPTS §5.6.1).
# 판정: goax_shell_scan destructive. python3 가 못 돌면 간이 판정.
# 모드: warning·fail 둘 다 막아요 (off 면 안 돌아요). 끄기: sensors.disabled_hooks 에 destructive-facts.
set -uo pipefail

[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
CMD=""; CWD=""; SID=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
    CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
    SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
fi
CMD="${CMD:-${CLAUDE_BASH_COMMAND:-${1:-}}}"
[ -z "$CMD" ] && exit 0

# 싼 사전 필터 — 모든 Bash 호출에 걸리는 훅이라 관련 낱말이 없으면 python 을 안 띄워요
printf '%s' "$CMD" | grep -qE '(^|[^[:alnum:]_-])(rm|find|git)([^[:alnum:]_-]|$)' || exit 0

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd || pwd)}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
[ -f "$COMMON" ] || exit 0
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"

goax_hook_enabled destructive-facts standard || exit 0
[ "$(goax_mode)" = "off" ] && exit 0

HITS=$(printf '%s' "$CMD" | goax_shell_scan destructive "$PROJECT_ROOT" "$CWD"); RC=$?
if [ "$RC" -eq 3 ]; then
    # python3 가 없거나 실패 — 셸 문법을 못 읽으니 간이 판정으로 내려가요 (재생성 디렉토리·프로젝트 밖 구분도 못 해요).
    # 조용히 통과하면 안전망이 꺼진 걸 아무도 몰라요. 오탐은 "같은 명령 재실행" 으로 한 번에 풀려요.
    goax_inject_fresh "$SID" "destructive-facts-nopython" \
        && printf '[goax] python3 를 못 써서 파괴 명령 판정을 간이 모드로 해요 (재생성 디렉토리 구분 없음)\n' >&2
    NORM=$(printf '%s' "$CMD" | tr -d '\047\042' | tr '\t\n' '  ')
    HITS=""
    for p in '(^|[;&|( ])rm +(-[[:alnum:]]*[rR]|--recursive)' 'git +(-C +[^ ]+ +)?reset +--hard' \
             'git +(-C +[^ ]+ +)?clean +-[[:alnum:]]*f' 'git +(-C +[^ ]+ +)?(checkout|restore) ' \
             'git +(-C +[^ ]+ +)?stash +(drop|clear)' 'git +(-C +[^ ]+ +)?branch +-D' ' -delete( |$)'; do
        printf '%s' "$NORM" | grep -qE "$p" && { HITS="(간이 판정) $p"; break; }
    done
fi
[ -z "$HITS" ] && exit 0

if [ -z "$SID" ]; then
    printf '\033[33m[goax hook]\033[0m ⚠ 되돌리기 어려운 명령 (세션 추적 불가 — 경고만): %s\n' "$(printf '%s' "$HITS" | head -1)" >&2
    exit 0
fi

KEY=$(printf '%s' "$CMD" | cksum | awk '{print $1 "-" $2}')
# 이미 한 번 막혀서 사실을 적고 다시 온 명령이면 통과
goax_session_marked "$SID" facts "$KEY" && exit 0
goax_session_mark "$SID" facts "$KEY"
N=$(goax_session_count "$SID" facts-denials)

if [ "$N" -gt 3 ]; then
    printf '\033[33m[goax hook]\033[0m ✋ (#%s) 되돌리기 어려운 명령: %s — 대상 파일 · 되돌리는 절차 · 사용자 지시 원문을 적고 같은 명령을 다시 실행하세요.\n' \
        "$N" "$(printf '%s' "$HITS" | head -1)" >&2
    exit 2
fi

{
    printf '\033[33m[goax hook]\033[0m ✋ 되돌리기 어려운 명령이에요 — 실행 전에 사실을 먼저 적어 주세요 (이번 세션 %s번째).\n' "$N"
    printf '%s\n' "$HITS" | sed 's/^/  감지: /'
    printf '  명령: %s\n' "$CMD"
    printf '  1. 이 명령이 지우거나 되돌릴 파일 목록 — 추적 안 되는(untracked) 파일, 내가 만들지 않은 파일은 특히 (`git status --porcelain <경로>` 로 확인)\n'
    printf '  2. 되돌리는 절차 한 줄 (없으면 "복구 불가" 라고 적기)\n'
    printf '  3. 이 작업을 지시한 사용자 메시지 원문 인용\n'
    printf '  적은 뒤 같은 명령을 그대로 다시 실행하면 통과해요. 범위를 좁힐 수 있으면 좁힌 명령으로 바꾸세요 (새 명령이라 다시 확인해요).\n'
    printf '  (끄기: .ax/config.yml sensors.disabled_hooks 에 destructive-facts)\n'
} >&2
exit 2
