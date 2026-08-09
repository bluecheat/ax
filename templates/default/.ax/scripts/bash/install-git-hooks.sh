#!/usr/bin/env bash
# .ax/scripts/bash/install-git-hooks.sh — OpenCode mode (또는 Claude Code 미사용 환경)
# 사용자가 .ax/hooks/pre-commit/*.sh 자동 chain 을 git pre-commit 으로 보전하도록 wrapper 설치.
#
# Usage:
#   bash install-git-hooks.sh [--force] [--json] [--dry-run] [--help]
#
# 동작:
#   1. git 리포 root 확인 (없으면 error)
#   2. .git/hooks/pre-commit 존재 여부 + goax marker (#goax-pre-commit-chain) 검사
#   3. 없으면: wrapper 작성 + chmod +x  →  action=installed
#   4. 있고 goax marker 포함: skipped (idempotent)
#   5. 있고 marker 없으면: --force 필요. 기존 hook 을 .bak.<ts> 로 백업 후 새로 작성  →  action=replaced
#
# JSON output (--json):
#   {"status":"ok|skipped|error",
#    "result":{"hook_path":"...","action":"installed|skipped|replaced","backup":"..."|null},
#    "next_step":"...","warnings":[],"errors":[]}
#
# Exit:
#   0 OK / 1 ERROR / 2 SKIPPED (이미 등록)

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
SHOW_HELP=false
FORCE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --force)   FORCE=true ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# //; s/^#//'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
cd "$PROJECT_ROOT"

if [ ! -d ".git" ] && [ ! -f ".git" ]; then
    if [ "$JSON_MODE" = true ]; then json_error "not a git repository: $PROJECT_ROOT"
    else goax_error "not a git repository: $PROJECT_ROOT"; exit "$EXIT_ERROR"; fi
fi

GIT_DIR=$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null) || GIT_DIR=".git"
[ "${GIT_DIR:0:1}" = "/" ] || GIT_DIR="$PROJECT_ROOT/$GIT_DIR"
HOOK_DIR="$GIT_DIR/hooks"
HOOK_PATH="$HOOK_DIR/pre-commit"
REL_HOOK="${HOOK_PATH#$PROJECT_ROOT/}"

mkdir -p "$HOOK_DIR"

GOAX_MARKER="#goax-pre-commit-chain"
WRAPPER=$(cat <<'WRAPPER_EOF'
#!/usr/bin/env bash
#goax-pre-commit-chain
# goax — OpenCode/non-Claude-Code 환경에서 hook 시스템 보전.
# .ax/hooks/pre-commit/*.sh 자동 chain (사전순).
# 첫 exit 2 (fail) 에서 차단. 기타 비정상 exit 는 stderr 로 보고 후 chain 계속.
set -uo pipefail
PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HOOK_DIR="$PROJECT/.ax/hooks/pre-commit"
[ -d "$HOOK_DIR" ] || exit 0
shopt -s nullglob 2>/dev/null || true
for hook in "$HOOK_DIR"/*.sh; do
    [ -f "$hook" ] || continue
    RC=0
    GOAX_PROJECT_DIR="$PROJECT" bash "$hook" || RC=$?
    if [ "$RC" -eq 2 ]; then
        echo "[goax git-pre-commit] $(basename "$hook") → exit 2 — 차단" >&2
        exit 2
    elif [ "$RC" -ne 0 ]; then
        echo "[goax git-pre-commit] $(basename "$hook") exit=$RC — chain 계속" >&2
    fi
done
exit 0
WRAPPER_EOF
)

ACTION=""
BACKUP=""

if [ -f "$HOOK_PATH" ]; then
    if grep -q "$GOAX_MARKER" "$HOOK_PATH" 2>/dev/null; then
        ACTION="skipped"
        if [ "$JSON_MODE" = true ]; then
            json_output "skipped" \
                "{\"hook_path\":\"$REL_HOOK\",\"action\":\"skipped\",\"backup\":null}" \
                "이미 goax wrapper 등록됨 — 재설치 원하면 --force"
        else
            goax_log "✓ 이미 goax wrapper 등록됨: $REL_HOOK (재설치는 --force)"
        fi
        exit "$EXIT_SKIPPED"
    fi
    # 다른 hook 있음
    if [ "$FORCE" != true ]; then
        if [ "$JSON_MODE" = true ]; then
            json_error "$REL_HOOK 이미 존재 (goax marker 없음) — --force 필요"
        else
            goax_error "$REL_HOOK 이미 존재. 덮어쓰려면 --force (기존은 .bak 으로 백업)"
            exit "$EXIT_ERROR"
        fi
    fi
    BACKUP="${HOOK_PATH}.bak.$(date +%Y%m%d-%H%M%S)"
    if [ "$DRY_RUN" != true ]; then
        cp "$HOOK_PATH" "$BACKUP"
    fi
    ACTION="replaced"
else
    ACTION="installed"
fi

if [ "$DRY_RUN" = true ]; then
    if [ "$JSON_MODE" = true ]; then
        BACKUP_FIELD="null"
        [ -n "$BACKUP" ] && BACKUP_FIELD="\"${BACKUP#$PROJECT_ROOT/}\""
        json_output "ok" \
            "{\"hook_path\":\"$REL_HOOK\",\"action\":\"$ACTION\",\"backup\":$BACKUP_FIELD,\"dry_run\":true}" \
            "would $ACTION → $REL_HOOK"
    else
        goax_log "dry-run: would $ACTION → $REL_HOOK${BACKUP:+ (backup: $BACKUP)}"
    fi
    exit "$EXIT_OK"
fi

printf '%s\n' "$WRAPPER" > "$HOOK_PATH"
chmod +x "$HOOK_PATH"

if [ "$JSON_MODE" = true ]; then
    BACKUP_FIELD="null"
    [ -n "$BACKUP" ] && BACKUP_FIELD="\"${BACKUP#$PROJECT_ROOT/}\""
    json_output "ok" \
        "{\"hook_path\":\"$REL_HOOK\",\"action\":\"$ACTION\",\"backup\":$BACKUP_FIELD}" \
        ".ax/hooks/pre-commit/*.sh 가 git commit 시 자동 chain — CATASTROPHIC·secrets 검출 보전"
else
    goax_log "✓ $ACTION → $REL_HOOK${BACKUP:+ (백업: ${BACKUP#$PROJECT_ROOT/})}"
    goax_log "  .ax/hooks/pre-commit/*.sh 가 git commit 시 자동 chain 됩니다."
fi
exit "$EXIT_OK"
