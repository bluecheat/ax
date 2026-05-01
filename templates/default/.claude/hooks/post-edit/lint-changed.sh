#!/usr/bin/env bash
# post-edit hook — 변경 파일 lint
set -euo pipefail

TARGET_PATH="${CLAUDE_EDIT_PATH:-${1:-}}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG="$PROJECT_ROOT/.ax-first/config.yml"

[ -f "$CONFIG" ] || exit 0
[ -z "${TARGET_PATH:-}" ] && exit 0

case "$TARGET_PATH" in
    *.kt|*.kts) command -v ktlint >/dev/null 2>&1 && ktlint --relative -- "$TARGET_PATH" 2>&1 || true ;;
    *.ts|*.tsx|*.js|*.jsx) command -v eslint >/dev/null 2>&1 && eslint --quiet "$TARGET_PATH" 2>&1 || true ;;
    *.py) command -v ruff >/dev/null 2>&1 && ruff check "$TARGET_PATH" 2>&1 || true ;;
    *.go) command -v gofmt >/dev/null 2>&1 && gofmt -l "$TARGET_PATH" 2>&1 || true ;;
    *) exit 0 ;;
esac
exit 0
