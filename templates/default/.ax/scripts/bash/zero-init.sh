#!/usr/bin/env bash
# .ax/scripts/bash/zero-init.sh — 첫날 팩(templates/zero) 을 프로젝트에 설치
#
# Usage:
#   bash zero-init.sh [--plugin-dir <path>] [--json] [--dry-run] [--no-hook] [--help]
#
# 무엇이 깔리나:
#   .ax/spirit/rules/zero-baseline.md     산문 룰 5개 (기계로 못 옮긴 것만)
#   .ax/hooks/pre-bash/zero-guard-bash.sh 계약 hook + .claude/settings.json 등록
#   .ax/_templates/zero/                  워크시트·템플릿 (사용자가 채우는 것)
#     product/{value-hypothesis,unit-economics,success-and-stop,first-users}.md
#     prd-v0.1.md · irreversible-axes.md · sian-gate.md
#     checks.md · ablation.md · probe-recipes.md · ci-github-actions.yml
#     probes/*.sh   (복사해서 .ax/probes/ 에 두면 zero-probe.sh 가 돌려요)
#
# 왜 룰이 5개뿐인가: 원래 규율 16개 중 8개는 hook·스크립트·테스트로 옮겼고(프롬프트 토큰 0),
#   1개는 지금 하네스가 이미 하는 일이라 지웠어요. 판정표는 checks.md.
#   근거 — "비대한 CLAUDE.md 는 Claude 가 실제 지시를 무시하게 만든다"(Claude Code
#   best-practices), 지시 500개 밀도에서 최고 모델도 68% 준수(IFScale).
#
#   **덮어쓰지 않아요.** 같은 이름이 이미 있으면 skipped 로 보고만 해요 — 룰은 사용자
#   큐레이션 영역이라 재실행이 남의 편집을 먹으면 안 돼요 (up 과 같은 계약).
#   SP-* 토큰이 기존 룰과 겹치면 warnings 로 알려요.
#
# Output (--json):
#   {"status":"ok","result":{"installed":[...],"skipped":[...],"rules_installed":N,
#                            "hook_registered":true|false,"dry_run":false},...}
#
# Exit:
#   0  ok
#   1  error
#   2  skipped (plugin-dir 미해결 — graceful degradation)

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
SHOW_HELP=false
NO_HOOK=false
PLUGIN_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)       JSON_MODE=true ;;
        --dry-run)    DRY_RUN=true ;;
        --no-hook)    NO_HOOK=true ;;
        --plugin-dir) shift; PLUGIN_DIR="${1:-}" ;;
        --help|-h)    SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^#$//; s/^# //'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"

# plugin root: --plugin-dir > CLAUDE_SKILL_DIR > CLAUDE_PLUGIN_ROOT
if [ -z "$PLUGIN_DIR" ]; then
    if [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
        PLUGIN_DIR="$(cd "${CLAUDE_SKILL_DIR}/../.." 2>/dev/null && pwd)" || PLUGIN_DIR=""
    elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
        PLUGIN_DIR="$CLAUDE_PLUGIN_ROOT"
    fi
fi

if [ -z "$PLUGIN_DIR" ] || [ ! -d "$PLUGIN_DIR/templates/zero" ]; then
    MSG="templates/zero 를 못 찾았어요 — --plugin-dir <plugin root> 로 알려주세요"
    if [ "$JSON_MODE" = true ]; then json_skip "$MSG"; fi
    goax_warn "$MSG"; exit "$EXIT_SKIPPED"
fi

ZERO="$PLUGIN_DIR/templates/zero"
RULES_DST="$PROJECT_ROOT/.ax/spirit/rules"
TPL_DST="$PROJECT_ROOT/.ax/_templates/zero"

INSTALLED=""
SKIPPED=""
WARN_LINES=""
RULES_N=0
HOOK_REGISTERED=false

add_warn() { WARN_LINES="${WARN_LINES}$1
"; }

# 기존 룰의 SP-* 토큰 (중복 경고용)
EXISTING_TOKENS=$(grep -hoE '^## SP-[A-Z]+-[0-9]{3}:' "$RULES_DST"/*.md 2>/dev/null \
                  | sed -E 's/^## (SP-[A-Z]+-[0-9]{3}):/\1/' | sort -u || true)

# copy_one <src> <dst-abs> <dst-rel>
copy_one() {
    local src="$1" dst="$2" rel="$3"
    if [ ! -f "$src" ]; then
        add_warn "출고 파일 부재: ${src#"$PLUGIN_DIR"/}"
        return 0
    fi
    if [ -e "$dst" ]; then
        SKIPPED="${SKIPPED}${rel}
"
        return 0
    fi
    if [ "$DRY_RUN" != true ]; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
    fi
    INSTALLED="${INSTALLED}${rel}
"
}

# (1) 산문 룰 — 라이브 영역
for f in "$ZERO"/spirit/rules/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    before_installed="$INSTALLED"
    copy_one "$f" "$RULES_DST/$name" ".ax/spirit/rules/$name"
    if [ "$INSTALLED" != "$before_installed" ]; then
        RULES_N=$((RULES_N + 1))
        while IFS= read -r tok; do
            [ -z "$tok" ] && continue
            case "
$EXISTING_TOKENS
" in
                *"
$tok
"*) add_warn "SP 토큰 중복: $tok (기존 룰과 겹쳐요 — doctor 가 잡아요)" ;;
            esac
        done <<TOKENS
$(grep -oE '^## SP-[A-Z]+-[0-9]{3}:' "$f" | sed -E 's/^## (SP-[A-Z]+-[0-9]{3}):/\1/')
TOKENS
    fi
done

# (2) 워크시트·템플릿 — 사용자가 채우는 영역
for f in "$ZERO"/product/*.md; do
    [ -f "$f" ] || continue
    n=$(basename "$f")
    copy_one "$f" "$TPL_DST/product/$n" ".ax/_templates/zero/product/$n"
done
for f in "$ZERO"/probe/examples/*.sh; do
    [ -f "$f" ] || continue
    n=$(basename "$f")
    copy_one "$f" "$TPL_DST/probes/$n" ".ax/_templates/zero/probes/$n"
done
copy_one "$ZERO/prd/prd-v0.1.md"               "$TPL_DST/prd-v0.1.md"            ".ax/_templates/zero/prd-v0.1.md"
copy_one "$ZERO/adr/irreversible-axes.md"      "$TPL_DST/irreversible-axes.md"   ".ax/_templates/zero/irreversible-axes.md"
copy_one "$ZERO/design/sian-gate.md"           "$TPL_DST/sian-gate.md"           ".ax/_templates/zero/sian-gate.md"
copy_one "$ZERO/probe/README.md"               "$TPL_DST/probe-recipes.md"       ".ax/_templates/zero/probe-recipes.md"
copy_one "$ZERO/checks/README.md"              "$TPL_DST/checks.md"              ".ax/_templates/zero/checks.md"
copy_one "$ZERO/ablation.md"                   "$TPL_DST/ablation.md"            ".ax/_templates/zero/ablation.md"
copy_one "$ZERO/ci/github-actions.yml.example" "$TPL_DST/ci-github-actions.yml"  ".ax/_templates/zero/ci-github-actions.yml"

# (3) 계약 hook — 라이브 영역 + settings.json 등록
HOOK_SRC="$ZERO/hooks/zero-guard-bash.sh"
HOOK_DST="$PROJECT_ROOT/.ax/hooks/pre-bash/zero-guard-bash.sh"
HOOK_CMD='bash "${CLAUDE_PROJECT_DIR}/.ax/hooks/pre-bash/zero-guard-bash.sh"'
SETTINGS="$PROJECT_ROOT/.claude/settings.json"
# 락 경로는 register-spirit-hook.sh 와 **글자 그대로** 같아야 해요 — 둘 다 이 settings.json 에
# jq 머지를 해요. 이름이 갈리면 락이 두 개가 돼서 서로를 못 막아요.
SETTINGS_LOCK="$SETTINGS.lock"

fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }

if [ "$NO_HOOK" != true ]; then
    copy_one "$HOOK_SRC" "$HOOK_DST" ".ax/hooks/pre-bash/zero-guard-bash.sh"
    if [ "$DRY_RUN" != true ] && [ -f "$HOOK_DST" ]; then chmod +x "$HOOK_DST"; fi

    # 락 창은 멱등 grep 부터예요 — "아직 없다" 를 읽고 나서 쓰는 자리라, 락 밖이면 두 프로세스가
    # 둘 다 없다고 읽고 둘 다 append 해서 훅이 여러 번 등록돼요 (실측: 5회 동시 → 3회 등록).
    if [ "$DRY_RUN" != true ]; then
        goax_lock "$SETTINGS_LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || fail "다른 프로세스가 .claude/settings.json 을 쓰는 중이에요 — 잠시 뒤 다시 해요"
    fi

    if [ ! -f "$SETTINGS" ]; then
        add_warn ".claude/settings.json 이 없어서 hook 을 등록 못 했어요 — /up 후 zero-init 을 다시 부르세요"
    elif grep -q 'zero-guard-bash\.sh' "$SETTINGS" 2>/dev/null; then
        HOOK_REGISTERED=true
    elif ! command -v jq >/dev/null 2>&1; then
        add_warn "jq 가 없어 settings.json 을 안전하게 못 고쳤어요 — PreToolUse Bash 에 zero-guard-bash.sh 를 손으로 추가하세요"
    elif [ "$DRY_RUN" = true ]; then
        : # dry-run 은 아무것도 안 써요
    else
        cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
        # 백업은 최신 3개만 — 재실행마다 쌓이면 .claude/ 가 백업 무덤이 되고, 정작
        # 되돌릴 때 어느 게 직전인지 사람이 못 골라요.
        BAK_OLD=$(ls -1t "$SETTINGS".bak.* 2>/dev/null | tail -n +4 || true)
        if [ -n "$BAK_OLD" ]; then
            printf '%s\n' "$BAK_OLD" | while IFS= read -r old; do
                if [ -n "$old" ]; then rm -f "$old"; fi
            done
        fi
        STMP="$SETTINGS.tmp.$$"
        if jq --arg cmd "$HOOK_CMD" '
            .hooks.PreToolUse = (
                (.hooks.PreToolUse // []) as $arr
                | if ($arr | any(.matcher == "Bash")) then
                    $arr | map(if .matcher == "Bash"
                               then .hooks += [{type: "command", command: $cmd}]
                               else . end)
                  else
                    $arr + [{matcher: "Bash", hooks: [{type: "command", command: $cmd}]}]
                  end
            )' "$SETTINGS" > "$STMP"; then
            mv "$STMP" "$SETTINGS"
            HOOK_REGISTERED=true
        else
            rm -f "$STMP"      # jq 가 죽으면 반쪽짜리 .tmp.$$ 가 .claude/ 에 남아요
            add_warn "settings.json 머지 실패 — 원본은 그대로예요"
        fi
    fi

    if [ "$DRY_RUN" != true ]; then goax_unlock "$SETTINGS_LOCK"; fi
fi

INSTALLED_N=$(printf '%s' "$INSTALLED" | grep -c . || true); INSTALLED_N=${INSTALLED_N:-0}
SKIPPED_N=$(printf '%s' "$SKIPPED" | grep -c . || true);     SKIPPED_N=${SKIPPED_N:-0}

lines_to_json() {   # stdin(줄 목록) → JSON array
    if command -v jq >/dev/null 2>&1; then
        jq -Rn '[inputs | select(length > 0)]'
    else
        printf '[]'
    fi
}

if [ "$DRY_RUN" = true ]; then
    NEXT="dry-run — 설치 ${INSTALLED_N}건 / 기존 보존 ${SKIPPED_N}건. --dry-run 빼고 다시 부르세요"
else
    NEXT="첫날 팩 설치 (산문 룰 ${RULES_N} 파일 · hook 등록 ${HOOK_REGISTERED}). 다음: .ax/_templates/zero/product/ 워크시트로 제품·비즈니스를 먼저 정해요"
fi

if [ "$JSON_MODE" = true ]; then
    INSTALLED_JSON=$(printf '%s' "$INSTALLED" | lines_to_json)
    SKIPPED_JSON=$(printf '%s' "$SKIPPED" | lines_to_json)
    WARN_JSON=$(printf '%s' "$WARN_LINES" | lines_to_json)
    RESULT=$(printf '{"installed":%s,"skipped":%s,"rules_installed":%s,"hook_registered":%s,"dry_run":%s}' \
                    "$INSTALLED_JSON" "$SKIPPED_JSON" "$RULES_N" "$HOOK_REGISTERED" "$DRY_RUN")
    json_output "ok" "$RESULT" "$NEXT" "$WARN_JSON"
else
    printf '%s' "$INSTALLED" | while IFS= read -r l; do [ -n "$l" ] && printf '  + %s\n' "$l"; done
    printf '%s' "$SKIPPED"   | while IFS= read -r l; do [ -n "$l" ] && printf '  = %s (기존 보존)\n' "$l"; done
    printf '%s' "$WARN_LINES" | while IFS= read -r l; do [ -n "$l" ] && goax_warn "$l"; done
    printf '%s\n' "$NEXT"
fi
