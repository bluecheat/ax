#!/usr/bin/env bash
# .ax/scripts/bash/ade-settings.sh — 모노레포 ADE 루트의 .claude/settings.json 에 goax 훅을 템플릿에서 생성·점검
#
# 왜: 세션은 보통 저장소 루트(ADE 루트)에서 시작해요. 그런데 goax 는 하위 프로젝트(projects/<app>/.ax)에 있어요.
#     훅은 `${CLAUDE_PROJECT_DIR}/.ax/hooks/…` 를 보니, 루트 세션에선 경로가 안 맞아 **전부 조용히 꺼져요**.
#     실측(commerce-monorepo, 2026-09-25): 루트 settings 를 손으로 만들어
#     `env CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR}/projects/commerce" bash …` 로 감싸 우회하고 있었는데,
#     손으로 만든 파일이라 템플릿에 훅이 늘어도 따라오지 않아 새 훅 4개가 빠져 있었어요.
#     이 스크립트가 그 파일을 **템플릿에서** 만들어요 — 손으로 고치지 않아요.
#
# Usage:
#   bash ade-settings.sh --check [--ade-root <dir>] [--plugin-dir <dir>] [--json]
#   bash ade-settings.sh --apply [--ade-root <dir>] [--plugin-dir <dir>] [--json] [--dry-run]
#
#   ADE 루트 기본값 = 프로젝트의 git 최상위. 프로젝트 루트와 같으면(단일 저장소) 할 일이 없어요 → exit 2.
#   템플릿: --plugin-dir > ${CLAUDE_SKILL_DIR}/../.. > ${CLAUDE_PLUGIN_ROOT} 의 templates/default/.claude/settings.json.template
#
# 생성 규칙: 템플릿의 `bash "${CLAUDE_PROJECT_DIR}/.ax/hooks/<x>.sh"` 를
#   `env CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR}/<rel>" bash "${CLAUDE_PROJECT_DIR}/<rel>/.ax/hooks/<x>.sh"` 로 바꿔요.
#   (<rel> = ADE 루트 기준 프로젝트 경로)
# 병합 규칙 (--apply): 기존 파일의 다른 키·다른 훅은 그대로 두고, **이 프로젝트(<rel>)의 goax 훅 명령만** 지웠다가
#   템플릿대로 다시 넣어요. 한 저장소에 goax 프로젝트가 여럿이면 각자 자기 몫만 바꿔요 — 훅은 자기 프로젝트 밖
#   파일·명령을 판정하지 않으니 여러 프로젝트가 같이 등록돼도 서로 막지 않아요. 멱등. 바뀌면 `.bak.<시각>` 을 남겨요.
#
# Output (--json):
#   {"status":"ok|warning|skipped","result":{"ade_root":"…","project_rel":"projects/commerce","settings":".claude/settings.json",
#     "expected":N,"present":N,"missing":["PreToolUse .ax/hooks/pre-bash/destructive-facts.sh",…],"stale":[…],
#     "applied":false,"changed":false},…}
#   --check: missing·stale 이 있으면 status warning (exit 0). --apply 후엔 둘 다 비어요.
# Exit: 0 ok · 1 error · 2 skipped (단일 저장소 · jq 없음 · 템플릿 못 찾음)
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; DRY_RUN=false; SHOW_HELP=false
MODE=""; ADE_ROOT=""; PLUGIN_DIR=""
while [ $# -gt 0 ]; do
    if parse_common_opts "$1"; then shift; continue; fi
    case "$1" in
        --check)      MODE=check ;;
        --apply)      MODE=apply ;;
        --ade-root)   shift; ADE_ROOT="${1:-}" ;;
        --plugin-dir) shift; PLUGIN_DIR="${1:-}" ;;
        *) goax_error "알 수 없는 옵션: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
[ -n "$MODE" ] || { goax_error "--check 또는 --apply 가 필요해요"; exit "$EXIT_ERROR"; }
skip() { if [ "$JSON_MODE" = true ]; then json_skip "$1"; fi; goax_log "$1"; exit "$EXIT_SKIPPED"; }
command -v jq >/dev/null 2>&1 || skip "jq 가 없어요"

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
PROJECT_ROOT=$(CDPATH="" cd -P "$PROJECT_ROOT" && pwd -P)
if [ -z "$ADE_ROOT" ]; then
    ADE_ROOT=$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null || true)
fi
[ -n "$ADE_ROOT" ] && [ -d "$ADE_ROOT" ] || skip "ADE 루트를 못 정했어요 (git 저장소가 아니면 --ade-root 로 주세요)"
ADE_ROOT=$(CDPATH="" cd -P "$ADE_ROOT" && pwd -P)
[ "$ADE_ROOT" != "$PROJECT_ROOT" ] || skip "단일 저장소 — ADE 루트 = 프로젝트 루트라 .claude/settings.json 은 up 이 관리해요"
case "$PROJECT_ROOT" in "$ADE_ROOT"/*) ;; *) goax_error "프로젝트($PROJECT_ROOT)가 ADE 루트($ADE_ROOT) 아래에 없어요"; exit "$EXIT_ERROR" ;; esac
REL="${PROJECT_ROOT#"$ADE_ROOT"/}"

if [ -z "$PLUGIN_DIR" ]; then
    if [ -n "${CLAUDE_SKILL_DIR:-}" ] && [ -d "${CLAUDE_SKILL_DIR}/../../templates" ]; then
        PLUGIN_DIR="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
    elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/templates" ]; then
        PLUGIN_DIR="$CLAUDE_PLUGIN_ROOT"
    fi
fi
TPL="$PLUGIN_DIR/templates/default/.claude/settings.json.template"
[ -n "$PLUGIN_DIR" ] && [ -f "$TPL" ] || skip "settings.json.template 을 못 찾았어요 (--plugin-dir 로 goax 플러그인 경로를 주세요)"

SETTINGS="$ADE_ROOT/.claude/settings.json"
SETTINGS_REL=".claude/settings.json"

# 템플릿을 이 프로젝트용으로 바꾼 hooks 객체
EXPECTED_HOOKS=$(jq -c --arg rel "$REL" '
    (.hooks // {}) | with_entries(.value |= map(.hooks |= map(
        if (.command // "") | test("\\$\\{CLAUDE_PROJECT_DIR\\}/\\.ax/hooks/")
        then .command = ("env CLAUDE_PROJECT_DIR=\"${CLAUDE_PROJECT_DIR}/" + $rel + "\" "
                         + (.command | sub("\\$\\{CLAUDE_PROJECT_DIR\\}/\\.ax/hooks/"; "${CLAUDE_PROJECT_DIR}/" + $rel + "/.ax/hooks/")))
        else . end)))' "$TPL")

# (이벤트, 훅 경로) 쌍 — 이 프로젝트 몫만
pairs() {   # pairs <hooks-json>
    printf '%s' "$1" | jq -r --arg rel "$REL" '
        to_entries[] | .key as $ev | .value[]? | .hooks[]? | (.command // "")
        | select(contains("/" + $rel + "/.ax/hooks/"))
        | "\($ev) " + (capture("(?<p>\\.ax/hooks/[^\" ]+\\.sh)").p // "")' | sort -u
}
CURRENT_HOOKS='{}'
[ -f "$SETTINGS" ] && CURRENT_HOOKS=$(jq -c '.hooks // {}' "$SETTINGS" 2>/dev/null || echo '{}')
EXP_PAIRS=$(pairs "$EXPECTED_HOOKS")
CUR_PAIRS=$(pairs "$CURRENT_HOOKS")
MISSING=$(comm -23 <(printf '%s\n' "$EXP_PAIRS" | grep -v '^$' || true) <(printf '%s\n' "$CUR_PAIRS" | grep -v '^$' || true) || true)
STALE=$(comm -13 <(printf '%s\n' "$EXP_PAIRS" | grep -v '^$' || true) <(printf '%s\n' "$CUR_PAIRS" | grep -v '^$' || true) || true)
arr() { printf '%s\n' "$1" | grep -v '^$' | jq -R . | jq -sc .; }
count() { printf '%s\n' "$1" | grep -c . || true; }

APPLIED=false; CHANGED=false
if [ "$MODE" = apply ] && { [ -n "$MISSING" ] || [ -n "$STALE" ]; }; then
    CHANGED=true
    if [ "$DRY_RUN" != true ]; then
        mkdir -p "$ADE_ROOT/.claude"
        LOCK="$(goax_normalize_path "$SETTINGS" "$ADE_ROOT").lock"
        goax_lock "$LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || { goax_error "락을 못 잡았어요: $LOCK"; exit "$EXIT_ERROR"; }
        BASE='{}'
        [ -f "$SETTINGS" ] && BASE=$(cat "$SETTINGS")
        printf '%s' "$BASE" | jq -e . >/dev/null 2>&1 || { goax_unlock "$LOCK"; goax_error "$SETTINGS_REL 이 JSON 이 아니에요 — 손으로 고친 뒤 다시"; exit "$EXIT_ERROR"; }
        TMP=$(goax_mktemp "$PROJECT_ROOT") || { goax_unlock "$LOCK"; goax_tmp_error; exit "$EXIT_ERROR"; }
        # 이 프로젝트 몫의 goax 명령을 빼고(빈 그룹·빈 이벤트는 정리), 템플릿 그룹을 뒤에 붙여요
        if ! printf '%s' "$BASE" | jq --arg rel "$REL" --argjson exp "$EXPECTED_HOOKS" '
            ((.hooks // {})
                | with_entries(.value |= (map(.hooks |= map(select(((.command // "") | contains("/" + $rel + "/.ax/hooks/")) | not)))
                                          | map(select((.hooks | length) > 0))))
                | with_entries(select((.value | length) > 0))) as $kept
            | .hooks = (reduce ($exp | to_entries[]) as $e ($kept; .[$e.key] = ((.[$e.key] // []) + $e.value)))' > "$TMP"; then
            rm -f "$TMP"; goax_unlock "$LOCK"; goax_error "settings 병합 실패 — 아무것도 안 바꿨어요"; exit "$EXIT_ERROR"
        fi
        [ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
        mv "$TMP" "$SETTINGS"
        goax_unlock "$LOCK"
        APPLIED=true
        CUR_PAIRS=$(pairs "$(jq -c '.hooks // {}' "$SETTINGS")")
        MISSING=$(comm -23 <(printf '%s\n' "$EXP_PAIRS" | grep -v '^$' || true) <(printf '%s\n' "$CUR_PAIRS" | grep -v '^$' || true) || true)
        STALE=$(comm -13 <(printf '%s\n' "$EXP_PAIRS" | grep -v '^$' || true) <(printf '%s\n' "$CUR_PAIRS" | grep -v '^$' || true) || true)
    fi
fi

STATUS=ok; { [ -n "$MISSING" ] || [ -n "$STALE" ]; } && STATUS=warning
if [ "$JSON_MODE" = true ]; then
    RESULT=$(jq -nc --arg ade "$ADE_ROOT" --arg rel "$REL" --arg s "$SETTINGS_REL" \
        --argjson e "$(count "$EXP_PAIRS")" --argjson p "$(count "$CUR_PAIRS")" \
        --argjson m "$(arr "$MISSING")" --argjson st "$(arr "$STALE")" \
        --argjson ap "$APPLIED" --argjson ch "$CHANGED" \
        '{ade_root:$ade, project_rel:$rel, settings:$s, expected:$e, present:$p, missing:$m, stale:$st, applied:$ap, changed:$ch}')
    NEXT=""
    [ "$STATUS" = warning ] && NEXT="bash .ax/scripts/bash/ade-settings.sh --apply — 루트 settings 를 템플릿대로 맞춰요 (다른 훅은 보존)"
    json_output "$STATUS" "$RESULT" "$NEXT"
else
    printf 'ADE 루트 %s · 프로젝트 %s\n' "$ADE_ROOT" "$REL"
    printf '  기대 %s · 등록 %s\n' "$(count "$EXP_PAIRS")" "$(count "$CUR_PAIRS")"
    [ -n "$MISSING" ] && printf '%s\n' "$MISSING" | sed 's/^/  누락  /'
    [ -n "$STALE" ] && printf '%s\n' "$STALE" | sed 's/^/  잔재  /'
    [ "$APPLIED" = true ] && printf '  ✅ %s 갱신 (백업 .bak.*)\n' "$SETTINGS_REL"
    [ "$MODE" = apply ] && [ "$CHANGED" = true ] && [ "$DRY_RUN" = true ] && printf '  (dry-run — 쓰지 않았어요)\n'
    [ "$STATUS" = ok ] && [ "$APPLIED" != true ] && printf '  ✅ 템플릿과 일치\n'
fi
exit "$EXIT_OK"
