#!/usr/bin/env bash
# post-edit hook — 변경 파일 lint
#
# Claude Code 공식 hook 입력: stdin JSON ({tool_name, tool_input.file_path, ...}).
# 정보 출력만 — 차단 안 함 (exit 0).
set -uo pipefail   # set -e 제거 — grep returning 1 (no match) 등이 hook 본체를 silent abort하지 않도록

# Bootstrap guard — install 중간이거나 .ax/ 부분 정리 시 silent skip (UX 노이즈 방지)
[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

# stdin JSON 파싱
INPUT="$(cat 2>/dev/null || true)"
TARGET_PATH=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    TARGET_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
fi
TARGET_PATH="${TARGET_PATH:-${CLAUDE_EDIT_PATH:-${1:-}}}"
[ -z "$TARGET_PATH" ] && exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONFIG="$PROJECT_ROOT/.ax/config.yml"

[ -f "$CONFIG" ] || exit 0

case "$TARGET_PATH" in
    *.kt|*.kts) command -v ktlint >/dev/null 2>&1 && ktlint --relative -- "$TARGET_PATH" 2>&1 || true ;;
    *.ts|*.tsx|*.js|*.jsx) command -v eslint >/dev/null 2>&1 && eslint --quiet "$TARGET_PATH" 2>&1 || true ;;
    *.py) command -v ruff >/dev/null 2>&1 && ruff check "$TARGET_PATH" 2>&1 || true ;;
    *.go) command -v gofmt >/dev/null 2>&1 && gofmt -l "$TARGET_PATH" 2>&1 || true ;;
    *) exit 0 ;;
esac
exit 0
