#!/usr/bin/env bash
# pre-bash hook — 에이전트가 git 훅을 끄는 걸 막아요
#
# 막는 형태: `--no-verify`(commit·push·merge·cherry-pick·rebase·am·pull) · `git commit -n` ·
#            `git -c core.hooksPath=…` · `git config core.hooksPath <값>` ·
#            훅 매니저 끄기 변수 — `HUSKY=0`·`HUSKY_SKIP_HOOKS`(husky) · `LEFTHOOK=0`·`LEFTHOOK_EXCLUDE`(lefthook) ·
#            `SKIP=<훅id>`(pre-commit 프레임워크, git 명령 앞이나 export 일 때만) — 앞에 붙이든 export 하든
#
# 왜: CRITICAL 룰은 `enforced_by: hook:*` 또는 `external:*`(husky·lefthook·pre-commit 프레임워크)로만
#     집행돼요 (I1). goax 자체의 pre-commit 체인은 grep-on-commit.sh 가 PreToolUse 에서 먼저 돌려서
#     `--no-verify` 로도 안 빠지지만, 프로젝트의 git 훅(commit-msg·pre-push·lint-staged)은 이 플래그
#     한 줄로 사라져요. 훅이 실패했을 때 에이전트가 고치는 대신 끄면 집행이 없는 것과 같아요.
#
# ⚠️ 성격: 사고 방지용 안전망이지 보안 경계가 아니에요. 사람이 직접 우회하는 건 막지 않아요 —
#    사용자는 프롬프트에서 `! git commit --no-verify …` 로 직접 실행할 수 있어요.
#
# 판정: common.sh goax_shell_scan bypass — 따옴표·heredoc 을 셸처럼 읽어서
#       `git commit -m "fix -n handling"` 의 `-n` 이나 커밋 메시지 속 `--no-verify` 는 안 걸려요.
#       python3 가 없거나 **있는데 실패하면**(xcrun shim 등) 따옴표를 벗긴 문자열에서 `--no-verify`·`core.hooksPath`·
#       훅 끄기 변수를 봐요 — 판정 못 했다고 통과시키지 않아요.
# 모드: sensors.mode 가 warning 이어도 차단해요 (off 면 안 돌아요). 경고로는 이 사고를 못 막아요 —
#       경고를 읽는 바로 그 순간에 훅은 이미 꺼져 있어요.
# 끄기: .ax/config.yml sensors.disabled_hooks 에 block-hook-bypass (프로필 minimal 에서도 돌아요)
# 차단은 exit 2 + stderr.
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
