#!/usr/bin/env bash
# post-edit hook — 편집한 파일 하나를 프로젝트가 정한 명령으로 검사하고, 실패하면 모델에게 알려요
#
# 명령은 .ax/config.yml `commands.lint_file` 목록이에요 — "<글롭> => <명령>" 한 줄씩, `{file}` 은 편집한 파일의
# 프로젝트 상대 경로(셸 인용됨)로 바뀌어요. 첫 번째로 맞는 글롭 하나만 돌려요.
#   commands:
#     lint_file:
#       - "**/*.kt => ktlint {file}"
#       - "**/*.py => ruff check {file}"
#       - "apps/web/**/*.ts => pnpm --dir apps/web exec eslint --quiet {file}"
# 비어 있으면 아무것도 안 해요 — 확장자로 스택을 추측하지 않아요 (추측은 다른 버전·다른 설정의 도구를 돌려요).
# 후보는 `detect-stack.sh` 가 프로젝트가 선언한 도구에서 뽑아 보여줘요.
#
# 결과: 통과면 조용히. 실패면 PostToolUse additionalContext 로 출력 앞부분(40줄·3000자)을 넘겨요 — 막지는 않아요.
#   (예전 판은 stdout 에 찍기만 해서 모델에게 전혀 안 보였어요.)
# 시간: GOAX_LINT_TIMEOUT(기본 30초). timeout/gtimeout 이 있으면 그걸로 끊어요.
# 입력: stdin JSON ({tool_name, tool_input.file_path, ...}).
# 끄기: .ax/config.yml sensors.disabled_hooks 에 lint-changed, 또는 sensors.hook_profile: minimal
set -uo pipefail   # set -e 제거 — grep returning 1 (no match) 등이 hook 본체를 silent abort하지 않도록

# Bootstrap guard — install 중간이거나 .ax/ 부분 정리 시 silent skip (UX 노이즈 방지)
[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONFIG="$PROJECT_ROOT/.ax/config.yml"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
[ -f "$CONFIG" ] && [ -f "$COMMON" ] || exit 0
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"
goax_hook_enabled lint-changed standard || exit 0

RULES=$(goax_yaml_list "$CONFIG" lint_file 2>/dev/null || true)
[ -n "$RULES" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
TARGET_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -n "$TARGET_PATH" ] || exit 0
case "$TARGET_PATH" in /*) ;; *) TARGET_PATH="$PROJECT_ROOT/$TARGET_PATH" ;; esac
[ -f "$TARGET_PATH" ] || exit 0
ROOT_ABS=$( (CDPATH="" cd -P "$PROJECT_ROOT" 2>/dev/null && pwd -P) || printf '%s' "$PROJECT_ROOT")
TD=$( (CDPATH="" cd -P "$(dirname "$TARGET_PATH")" 2>/dev/null && pwd -P) || dirname "$TARGET_PATH")
REL="${TD%/}/$(basename "$TARGET_PATH")"; REL="${REL#"$ROOT_ABS"/}"
case "$REL" in /*|.ax/*) exit 0 ;; esac

CMD=""; GLOB=""
while IFS= read -r rule; do
    case "$rule" in *" => "*) ;; *) continue ;; esac
    g="${rule%% => *}"; c="${rule#* => }"
    [ -n "$g" ] && [ -n "$c" ] || continue
    if goax_glob_match "$g" "$REL"; then GLOB="$g"; CMD="$c"; break; fi
done <<< "$RULES"
[ -n "$CMD" ] || exit 0

QUOTED=$(printf '%q' "$REL")
RUN="${CMD//\{file\}/$QUOTED}"
TO="${GOAX_LINT_TIMEOUT:-30}"; case "$TO" in ''|*[!0-9]*) TO=30 ;; esac
TOOL_TO=""
command -v timeout >/dev/null 2>&1 && TOOL_TO=timeout
[ -z "$TOOL_TO" ] && command -v gtimeout >/dev/null 2>&1 && TOOL_TO=gtimeout
if [ -n "$TOOL_TO" ]; then
    OUT=$(cd "$PROJECT_ROOT" && "$TOOL_TO" "$TO" bash -c "$RUN" 2>&1); RC=$?
else
    OUT=$(cd "$PROJECT_ROOT" && bash -c "$RUN" 2>&1); RC=$?
fi
[ "$RC" -eq 0 ] && exit 0

NOTE="시간 초과(${TO}초)"; [ "$RC" -ne 124 ] && NOTE="exit $RC"
CTX="[goax] lint 실패 — $REL ($NOTE)
명령: $RUN   (commands.lint_file: \"$GLOB\")
$(printf '%s\n' "$OUT" | head -40 | cut -c1-300 | head -c 3000)
고친 파일의 문제면 지금 고치세요. 원래 있던 문제거나 명령이 잘못됐으면 사용자에게 알려요 — 설정을 느슨하게 하지 않아요."
jq -nc --arg c "$CTX" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
exit 0
