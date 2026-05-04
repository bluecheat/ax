#!/usr/bin/env bash
# pre-bash hook — Claude가 `git commit`을 호출하기 직전 pre-commit hook chain 트리거
#
# 왜 분리: settings.json의 PreToolUse:Bash는 모든 Bash에 발화함. 매번
#   pre-commit 검사를 돌리면 비용↑. 이 래퍼는 commit 의도가 보일 때만 위임.
#
# 매칭: `git commit`, `git ci`, `gh pr create` 등 staging→remote 흐름.
#
# 동작: $PROJECT_ROOT/.ax/hooks/pre-commit/*.sh 를 사전순으로 자동 chain.
#   - 어떤 hook이 exit 2 (fail) 리턴하면 즉시 차단 (chain 중단)
#   - exit 1 등 비정상은 stderr 로 보고하되 차단 X (set -e trap 회피)
#   - 새 프로젝트별 hook은 별도 파일로 추가하면 자동 picked up — plugin shipped
#     critical-rule-grep.sh를 직접 수정하지 말 것 (drift / clobber 방지).

set -uo pipefail   # set -e 제거 — chain의 hook exit code를 직접 처리

# Bootstrap guard — install 중간이거나 .ax/ 부분 정리 시 silent skip (UX 노이즈 방지)
[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
CMD=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
fi
CMD="${CMD:-${CLAUDE_BASH_COMMAND:-${1:-}}}"
[ -z "$CMD" ] && exit 0

# commit 의도 패턴
if ! printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(git[[:space:]]+(commit|ci)|gh[[:space:]]+pr[[:space:]]+create)([[:space:]]|$)'; then
    exit 0
fi

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd || pwd)}"
PRE_COMMIT_DIR="$PROJECT_ROOT/.ax/hooks/pre-commit"

[ -d "$PRE_COMMIT_DIR" ] || exit 0

# 자동 chain — 사전순 실행, 첫 fail(exit 2)에서 즉시 차단
EXIT_CODE=0
shopt -s nullglob 2>/dev/null || true
for hook in "$PRE_COMMIT_DIR"/*.sh; do
    [ -f "$hook" ] || continue
    RC=0
    bash "$hook" || RC=$?
    if [ "$RC" -eq 2 ]; then
        EXIT_CODE=2
        break
    elif [ "$RC" -ne 0 ]; then
        echo "[goax grep-on-commit] hook exit=$RC: $(basename "$hook") — chain 계속" >&2
    fi
done

exit "$EXIT_CODE"
