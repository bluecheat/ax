#!/usr/bin/env bash
# .ax/scripts/bash/register-spirit-hook.sh — .claude/settings.json에
# spirit-rules-inject.sh hook을 idempotent하게 등록.
#
# Usage:
#   bash register-spirit-hook.sh [--json] [--dry-run] [--help]
#
# 동작:
# 1. .claude/settings.json 미존재 시 SKIP (install 먼저)
# 2. 이미 등록됐으면 SKIP (재실행 안전)
# 3. 백업 (.claude/settings.json.bak.YYYYMMDD-HHMMSS)
# 4. jq로 PreToolUse "Edit|Write|MultiEdit" matcher hooks 배열에 명령 append
# 5. matcher entry 자체가 없으면 신규 entry 생성

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
SHOW_HELP=false

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# //; s/^#//'
    exit "$EXIT_OK"
fi

if ! command -v jq >/dev/null 2>&1; then
    if [ "$JSON_MODE" = true ]; then json_error "jq 미설치"
    else goax_error "jq 미설치 — settings.json 안전 머지 불가"; exit "$EXIT_ERROR"; fi
fi

fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
SETTINGS="$PROJECT_ROOT/.claude/settings.json"
# 락 경로는 zero-init.sh 와 **글자 그대로** 같아야 해요 — 둘 다 이 settings.json 에 jq 머지를
# 해요. 이름이 갈리면 락이 두 개가 돼서 서로를 못 막아요.
SETTINGS_LOCK="$SETTINGS.lock"

if [ ! -f "$SETTINGS" ]; then
    if [ "$JSON_MODE" = true ]; then json_skip ".claude/settings.json 미존재 — install 먼저"
    else goax_warn ".claude/settings.json 미존재 — install 먼저 실행"; fi
    exit "$EXIT_SKIPPED"
fi

# 락 창은 멱등 grep 부터예요 — "아직 없다" 를 읽고 나서 쓰는 자리라, 락 밖이면 두 프로세스가
# 둘 다 없다고 읽고 둘 다 append 해서 훅이 두 번 등록돼요.
if [ "$DRY_RUN" != true ]; then
    goax_lock "$SETTINGS_LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || fail "다른 프로세스가 .claude/settings.json 을 쓰는 중이에요 — 잠시 뒤 다시 해요"
fi

# 이미 등록 검증 (텍스트 grep — jq 없는 경우는 위에서 이미 차단됨)
if grep -q 'spirit-rules-inject\.sh' "$SETTINGS"; then
    if [ "$JSON_MODE" = true ]; then
        json_output "ok" '{"registered_now":false,"already_present":true}' "no action needed"
    else
        goax_log "✓ spirit-rules-inject.sh 이미 등록됨 — skip"
    fi
    if [ "$DRY_RUN" != true ]; then goax_unlock "$SETTINGS_LOCK"; fi
    exit "$EXIT_OK"
fi

# 등록할 명령 — settings.json 컨벤션 (다른 hook 명령과 일관)
HOOK_CMD='bash "${CLAUDE_PROJECT_DIR}/.ax/hooks/pre-edit/spirit-rules-inject.sh"'

if [ "$DRY_RUN" = true ]; then
    if [ "$JSON_MODE" = true ]; then
        json_output "ok" '{"registered_now":false,"already_present":false,"dry_run":true}' "would register"
    else
        goax_log "dry-run: would add spirit-rules-inject.sh to PreToolUse Edit|Write|MultiEdit"
    fi
    exit "$EXIT_OK"
fi

# 백업
TS=$(date +%Y%m%d-%H%M%S)
BACKUP="$SETTINGS.bak.$TS"
cp "$SETTINGS" "$BACKUP"

# jq 머지 — PreToolUse 배열에서 matcher="Edit|Write|MultiEdit" entry의 hooks 배열에 명령 append.
# 그런 entry 없으면 신규 entry 추가. 다른 hook들은 보존.
TMP="$SETTINGS.tmp.$$"
jq --arg cmd "$HOOK_CMD" '
    .hooks.PreToolUse = (
        (.hooks.PreToolUse // []) as $arr
        | if ($arr | any(.matcher == "Edit|Write|MultiEdit")) then
            $arr | map(
                if .matcher == "Edit|Write|MultiEdit"
                then .hooks += [{type: "command", command: $cmd}]
                else . end
            )
          else
            $arr + [{matcher: "Edit|Write|MultiEdit", hooks: [{type: "command", command: $cmd}]}]
          end
    )
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"

if [ "$JSON_MODE" = true ]; then
    BACKUP_REL="${BACKUP#$PROJECT_ROOT/}"
    json_output "ok" "{\"registered_now\":true,\"already_present\":false,\"backup_path\":\"$BACKUP_REL\"}" "review .claude/settings.json"
else
    goax_log "✓ spirit-rules-inject.sh 등록됨 — backup: $BACKUP"
fi
goax_unlock "$SETTINGS_LOCK"
exit "$EXIT_OK"
