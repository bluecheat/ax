#!/usr/bin/env bash
# .ax/scripts/bash/ade-settings.sh — .claude/settings.json 의 goax 훅을 템플릿에서 생성·점검 (단일 저장소 · 모노레포)
#
# 왜: 모노레포 세션은 저장소 루트에서 열려서 하위 프로젝트 settings 의 훅이 안 돌고, 손으로 쓴 루트 settings 는
#   템플릿에 훅이 늘어도 안 따라와요(실측: 4개 누락). 단일 저장소의 .ax/settings.json.suggested 머지를 `jq '*'` 로 하면
#   배열이 통째로 바뀌어 사용자 훅이 사라져요. 그래서 goax 훅 명령만 템플릿에서 다시 넣어요.
#
# Usage:
#   bash ade-settings.sh --check [--ade-root <dir>] [--plugin-dir <dir>] [--json]
#   bash ade-settings.sh --apply [--ade-root <dir>] [--plugin-dir <dir>] [--json] [--dry-run]
#
#   ADE 루트 기본값 = 프로젝트의 git 최상위 (git 이 아니면 프로젝트 루트). 프로젝트 루트와 같으면 단일 저장소 모드 —
#   템플릿 명령을 그대로(`bash "${CLAUDE_PROJECT_DIR}/.ax/hooks/…"`) 프로젝트의 .claude/settings.json 에 맞춰요.
#   템플릿: --plugin-dir > ${CLAUDE_SKILL_DIR}/../.. > ${CLAUDE_PLUGIN_ROOT} 의 templates/default/.claude/settings.json.template
#
# 생성: 모노레포면 템플릿 명령을 `env CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR}/<rel>" bash "…/<rel>/.ax/hooks/<x>.sh"` 로,
#   단일 저장소면 그대로. 병합(--apply): 이 프로젝트의 goax 훅 명령만 빼고 템플릿 그룹을 다시 붙여요 — 다른 키·사용자 훅·
#   다른 goax 프로젝트의 훅은 그대로. 멱등. 백업 파일은 안 만들어요 (되돌리기는 git). 판정 규칙은 아래 MINE_JQ.
#
# Output (--json):
#   {"status":"ok|warning|skipped","result":{"ade_root":"…","project_rel":"projects/commerce","settings":".claude/settings.json",
#     "expected":N,"present":N,"missing":["PreToolUse .ax/hooks/pre-bash/destructive-facts.sh",…],"stale":[…],
#     "applied":false,"changed":false},…}
#   --check: missing·stale 이 있으면 status warning (exit 0). --apply 후엔 둘 다 비어요.
#   "project_rel" 은 단일 저장소면 "" 예요.
# Exit: 0 ok · 1 error · 2 skipped (jq 없음 · 템플릿 못 찾음)
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
RAW_ROOT="$PROJECT_ROOT"      # 락 문자열용 — register-spirit-hook.sh · zero-init.sh 가 find_project_root 그대로 써요
PROJECT_ROOT=$(CDPATH="" cd -P "$PROJECT_ROOT" && pwd -P)
if [ -z "$ADE_ROOT" ]; then
    ADE_ROOT=$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null || true)
    [ -n "$ADE_ROOT" ] || ADE_ROOT="$PROJECT_ROOT"
fi
[ -d "$ADE_ROOT" ] || { goax_error "ADE 루트가 디렉토리가 아니에요: $ADE_ROOT"; exit "$EXIT_ERROR"; }
ADE_ROOT=$(CDPATH="" cd -P "$ADE_ROOT" && pwd -P)
REL=""
if [ "$ADE_ROOT" != "$PROJECT_ROOT" ]; then
    case "$PROJECT_ROOT" in "$ADE_ROOT"/*) ;; *) goax_error "프로젝트($PROJECT_ROOT)가 ADE 루트($ADE_ROOT) 아래에 없어요"; exit "$EXIT_ERROR" ;; esac
    REL="${PROJECT_ROOT#"$ADE_ROOT"/}"
fi

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
    (.hooks // {}) | if $rel == "" then . else with_entries(.value |= map(.hooks |= map(
        if (.command // "") | test("\\$\\{CLAUDE_PROJECT_DIR\\}/\\.ax/hooks/")
        then .command = ("env CLAUDE_PROJECT_DIR=\"${CLAUDE_PROJECT_DIR}/" + $rel + "\" "
                         + (.command | sub("\\$\\{CLAUDE_PROJECT_DIR\\}/\\.ax/hooks/"; "${CLAUDE_PROJECT_DIR}/" + $rel + "/.ax/hooks/")))
        else . end))) end' "$TPL")

# 이 프로젝트의 goax 훅 명령인가 — jq 함수 정의 (pairs · 병합이 같이 써요)
#   모노레포: 명령에 `/<rel>/.ax/hooks/` 가 있으면.
#   단일 저장소: 프로젝트 안 `.ax/hooks/<x>.sh` 를 가리키고(`${CLAUDE_PROJECT_DIR}/` · `$CLAUDE_PROJECT_DIR/` · `"$CLAUDE_PROJECT_DIR"/` ·
#     `./` · 맨 `.ax/` · 절대 경로 `<루트>/`) **그 <x> 가 템플릿에 있는** 것만. 템플릿에 없는 `.ax/hooks/` 훅(zero-guard-bash ·
#     팀이 직접 만든 훅)은 goax 가 관리하는 배선이 아니라서 건드리지 않아요 — 리뷰 실측: 안 가리면 --apply 가 zero-guard 를 지웠어요.
TPL_PATHS=$(jq -c '[.hooks[][]?.hooks[]?.command // "" | capture("(?<p>\\.ax/hooks/[^\" ]+\\.sh)").p] | unique' "$TPL")
MINE_JQ='def hookpath: ((capture("(?<p>\\.ax/hooks/[^\"'"'"' ]+\\.sh)") | .p) // "");
def mine($rel): (.command // "") as $c
    | if $rel == "" then
        (($c | test("(\\$\\{CLAUDE_PROJECT_DIR\\}\"?/|\\$CLAUDE_PROJECT_DIR\"?/|^|[\\s\"'"'"'])(\\./)?\\.ax/hooks/"))
          or ($c | contains($root + "/.ax/hooks/")))
        and (($c | hookpath) as $p | any($tpl[]; . == $p))
      else $c | contains("/" + $rel + "/.ax/hooks/") end;'

# (이벤트, 훅 경로) 쌍 — 이 프로젝트의 것만
pairs() {   # pairs <hooks-json>
    printf '%s' "$1" | jq -r --arg rel "$REL" --arg root "$PROJECT_ROOT" --argjson tpl "$TPL_PATHS" "$MINE_JQ"'
        to_entries[] | .key as $ev | .value[]? | .hooks[]? | select(mine($rel)) | (.command // "")
        | "\($ev) " + hookpath' | sort -u
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
        # 단일 저장소는 register-spirit-hook.sh · zero-init.sh 와 같은 파일을 써요 — 락 문자열을 바이트 단위로 맞춰요
        if [ -z "$REL" ]; then LOCK="$RAW_ROOT/.claude/settings.json.lock"
        else LOCK="$(goax_normalize_path "$SETTINGS" "$ADE_ROOT").lock"; fi
        goax_lock "$LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || { goax_error "락을 못 잡았어요: $LOCK"; exit "$EXIT_ERROR"; }
        BASE='{}'
        [ -f "$SETTINGS" ] && BASE=$(cat "$SETTINGS")
        printf '%s' "$BASE" | jq -e . >/dev/null 2>&1 || { goax_unlock "$LOCK"; goax_error "$SETTINGS_REL 이 JSON 이 아니에요 — 손으로 고친 뒤 다시"; exit "$EXIT_ERROR"; }
        TMP=$(goax_mktemp "$PROJECT_ROOT") || { goax_unlock "$LOCK"; goax_tmp_error; exit "$EXIT_ERROR"; }
        # 이 프로젝트의 goax 명령을 빼고(빈 그룹·빈 이벤트는 정리), 템플릿 그룹을 뒤에 붙여요
        if ! printf '%s' "$BASE" | jq --arg rel "$REL" --arg root "$PROJECT_ROOT" --argjson tpl "$TPL_PATHS" --argjson exp "$EXPECTED_HOOKS" "$MINE_JQ"'
            ((.hooks // {})
                | with_entries(.value |= (map(.hooks |= map(select(mine($rel) | not)))
                                          | map(select((.hooks | length) > 0))))
                | with_entries(select((.value | length) > 0))) as $kept
            | .hooks = (reduce ($exp | to_entries[]) as $e ($kept; .[$e.key] = ((.[$e.key] // []) + $e.value)))' > "$TMP"; then
            rm -f "$TMP"; goax_unlock "$LOCK"; goax_error "settings 병합 실패 — 아무것도 안 바꿨어요"; exit "$EXIT_ERROR"
        fi
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
    printf 'ADE 루트 %s · 프로젝트 %s\n' "$ADE_ROOT" "${REL:-(단일 저장소)}"
    printf '  기대 %s · 등록 %s\n' "$(count "$EXP_PAIRS")" "$(count "$CUR_PAIRS")"
    [ -n "$MISSING" ] && printf '%s\n' "$MISSING" | sed 's/^/  누락  /'
    [ -n "$STALE" ] && printf '%s\n' "$STALE" | sed 's/^/  잔재  /'
    [ "$APPLIED" = true ] && printf '  ✅ %s 갱신\n' "$SETTINGS_REL"
    [ "$MODE" = apply ] && [ "$CHANGED" = true ] && [ "$DRY_RUN" = true ] && printf '  (dry-run — 쓰지 않았어요)\n'
    [ "$STATUS" = ok ] && [ "$APPLIED" != true ] && printf '  ✅ 템플릿과 일치\n'
fi
exit "$EXIT_OK"
