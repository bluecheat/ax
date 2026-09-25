#!/usr/bin/env bash
# pre-bash hook — 에이전트가 git 훅을 끄는 걸 막아요
#
# 막는 형태: `--no-verify`(commit·push·merge·cherry-pick·rebase·am·pull) · `git commit -n` · `git -c core.hooksPath=…` ·
#   `git config core.hooksPath <값>` · `HUSKY=0`·`HUSKY_SKIP_HOOKS` · `LEFTHOOK=0`·`LEFTHOOK_EXCLUDE` · `SKIP=<id>`(git 앞·export)
# 왜: goax 체인은 grep-on-commit 이 먼저 돌지만 프로젝트 훅(external:*)은 이 플래그 한 줄로 사라져요. 경고는 늦어요 —
#   읽는 순간 훅은 이미 꺼져 있어서 sensors.mode=warning 이어도 막아요. 사람은 `! git commit --no-verify …` 로 직접 해요.
# 판정: goax_shell_scan bypass (메시지 속 `-n`·`--no-verify` 는 안 걸려요). python3 가 못 돌면 간이 판정 — 통과시키지 않아요.
# 끄기: sensors.disabled_hooks 에 block-hook-bypass (minimal 프로필에서도 돌아요). 차단은 exit 2 + stderr.
set -uo pipefail

[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
CMD=""; CWD=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
    CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
fi
CMD="${CMD:-${CLAUDE_BASH_COMMAND:-${1:-}}}"
[ -z "$CMD" ] && exit 0

# 싼 사전 필터 — 관련 낱말이 아예 없으면 python 을 띄우지 않아요 (모든 Bash 호출에 걸리는 훅이에요)
printf '%s' "$CMD" | grep -qiE 'no-verify|hookspath|husky|lefthook|(^|[^[:alnum:]_])skip=|git[^;&|]* commit' || exit 0

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd || pwd)}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
[ -f "$COMMON" ] || exit 0
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"

goax_hook_enabled block-hook-bypass minimal || exit 0
[ "$(goax_mode)" = "off" ] && exit 0

REASON=""
SCAN=$(printf '%s' "$CMD" | goax_shell_scan bypass "$PROJECT_ROOT" "$CWD"); RC=$?
if [ "$RC" -eq 3 ]; then
    NORM=$(printf '%s' "$CMD" | tr -d '\047\042' | tr '\t\n' '  ')
    if printf '%s' "$NORM" | grep -qE '(^|[;&|( ])git .*--no-verify( |$)'; then REASON="--no-verify"
    elif printf '%s' "$NORM" | grep -qiE 'core\.hookspath'; then REASON="core.hooksPath 바꿔치기"
    elif printf '%s' "$NORM" | grep -qE '(^|[;&|( ])(HUSKY|LEFTHOOK)=(0|false)( |$)'; then REASON="HUSKY/LEFTHOOK=0"
    elif printf '%s' "$NORM" | grep -qE '(^|[;&|( ])(HUSKY_SKIP_HOOKS|LEFTHOOK_EXCLUDE|SKIP)=[^ ]+ +([^ ]+ +)*git '; then REASON="훅 건너뛰기 변수"
    fi
else
    REASON=$(printf '%s\n' "$SCAN" | head -1)
fi
[ -z "$REASON" ] && exit 0

printf '\033[31m[goax hook]\033[0m 🚫 git 훅 우회 차단: %s\n' "$REASON" >&2
printf '명령: %s\n' "$CMD" >&2
printf '프로젝트의 git 훅은 룰 집행 장치예요 (enforced_by: hook:* · external:*). 에이전트가 끄면 집행이 사라져요.\n' >&2
printf '훅이 실패했다면 그 원인을 고치세요. 정말 우회해야 하면 사용자에게 직접 실행해 달라고 요청하세요 (프롬프트에서 `! <명령>`).\n' >&2
exit 2
