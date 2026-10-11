#!/usr/bin/env bash
# post-edit hook — 룰 파일을 고치면 바뀐 룰 블록을 rule-lint.sh 로 검사하고, 지적이 있으면 모델에게 알려요
#
# 대상: .ax/spirit/rules/*.md, .ax/modules/*/rules.md 를 Edit·Write·MultiEdit 했을 때예요.
# 이유: rule skill 을 거치지 않고 세션에서 룰을 바로 고쳐도 기준(docs/reference/writing-for-agents.md)을 적용해요.
# 결과: 지적이 없으면 출력이 없어요. 있으면 PostToolUse additionalContext 로 알려요. 막지는 않아요.
# 끄기: sensors.disabled_hooks 에 rule-lint.
set -uo pipefail

[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
LINT="$PROJECT_ROOT/.ax/scripts/bash/rule-lint.sh"
[ -f "$COMMON" ] && [ -f "$LINT" ] || exit 0
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"
goax_hook_enabled rule-lint standard || exit 0
[ "$(goax_mode)" = "off" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"
TARGET_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -n "$TARGET_PATH" ] || exit 0
REL=$(goax_normalize_path "$TARGET_PATH" "$PROJECT_ROOT"); REL="${REL#"$(goax_normalize_path "$PROJECT_ROOT" "$PROJECT_ROOT")"/}"
case "$REL" in
    .ax/spirit/rules/*.md|.ax/modules/*/rules.md) ;;
    *) exit 0 ;;
esac
[ -f "$PROJECT_ROOT/$REL" ] || exit 0

OUT=$(cd "$PROJECT_ROOT" && GOAX_PROJECT_DIR="$PROJECT_ROOT" bash "$LINT" --changed --json "$REL" 2>/dev/null) || exit 0
N=$(printf '%s' "$OUT" | jq -r '.result.total // 0' 2>/dev/null || echo 0)
[ "${N:-0}" -gt 0 ] || exit 0

LIST=$(printf '%s' "$OUT" | jq -r '.result.findings[] | "- \(.file):\(.line) [\(.kind)] \(.id // "") \(.text)"' 2>/dev/null)
CTX="[goax] 룰 작성 기준 지적 ${N}건 — $REL
$(printf '%s\n' "$LIST" | goax_cap_context 3000 "전체는 bash .ax/scripts/bash/rule-lint.sh $REL")
이 세션은 지적된 줄을 기준(.ax/docs/reference/writing-for-agents.md)대로 고쳐요. 사건 경위와 날짜는 mistake 나 ADR 로 옮기고, 룰에는 '이유:' 한 줄만 남겨요.
harness 지적은 goax 가 해야 할 일이라, 이 세션은 룰로 쓰지 말고 사용자에게 알려요."
CTX=$(printf '%s' "$CTX" | goax_cap_context)
jq -nc --arg c "$CTX" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
exit 0
