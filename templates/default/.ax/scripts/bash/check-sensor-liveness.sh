#!/usr/bin/env bash
# .ax/scripts/bash/check-sensor-liveness.sh — Sensors 가 "실제로 막을 수 있는 상태"인지 검증
#
# Usage:
#   bash check-sensor-liveness.sh [--json] [--strict] [--help]
#
# rule-enforcement 가 룰 라벨의 schema 를 보는 것과 직교로, 이 스크립트는 Sensors
# 장치 자체의 생사를 봐요 — 라벨이 완벽해도 아래가 죽어 있으면 아무것도 차단되지 않아요.
#
# Checks:
#   C1. grep 스캐폴드 미작성 — critical-rule-grep.sh 에 #goax-grep-scaffold 마커 잔존
#       (또는 구버전 출고본의 데모 내용 잔존: hydration/kotlin-mutable-domain 패턴)
#   C2. git pre-commit 미설치 — 사람이 터미널에서 하는 커밋은 Claude Code
#       PreToolUse 훅이 못 잡아요. install-git-hooks.sh 로 설치해야 커버.
#   C3. 차단 능력 0 — sensors.mode 가 warning/off 이고 C2 도 미설치면, 어떤 위반도
#       "경고 후 통과"(off 는 검사 자체 생략)만 해요. 이 상태를 명시적 finding 으로 보고.
#   C4. 세션 루트 이탈 — CLAUDE_PROJECT_DIR 가 .ax 루트와 다르면 훅·spirit 주입이
#       조용히 빠질 수 있어요 (서브디렉토리에서 세션 시작한 경우).
#
# JSON output schema (--json):
#   { status: ok|warning|error,
#     result: {
#       grep_scaffold_unfilled: bool, grep_demo_content: bool,
#       git_precommit_installed: bool, sensors_mode: "warning|fail|off",
#       blocking_zero: bool, session_root_mismatch: bool,
#       project_root: "...", claude_project_dir: "..."|null
#     },
#     next_step, warnings, errors }
#
# Exit codes:
#   0 = ok / 1 = error (jq 미설치, 프로젝트 루트 탐지 실패 등)
#   단, --strict 설정 시 finding > 0 이면 exit 1.

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
STRICT=false
SHOW_HELP=false
while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --strict)  STRICT=true ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    goax_help "${BASH_SOURCE[0]}"
    exit "$EXIT_OK"
fi

if ! command -v jq >/dev/null 2>&1; then
    if [ "$JSON_MODE" = true ]; then json_error "jq 미설치"
    else goax_error "jq 미설치 — liveness 검증 불가"; exit "$EXIT_ERROR"; fi
fi

ROOT=$(find_project_root) || exit "$EXIT_ERROR"

FINDINGS=0

# ─── C1: grep 스캐폴드/데모 상태 ─────────────────────────────────
GREP_HOOK="$ROOT/.ax/hooks/pre-commit/critical-rule-grep.sh"
SCAFFOLD=false
DEMO=false
if [ -f "$GREP_HOOK" ]; then
    grep -q '#goax-grep-scaffold' "$GREP_HOOK" 2>/dev/null && SCAFFOLD=true
    # 구버전 출고본의 데모 검사 잔재 — 남의 룰(Next.js/Kotlin)을 검사 중.
    # 한시적 검사예요: 프로젝트가 진짜로 같은 카테고리명(kotlin-mutable-domain)을
    # 쓰면 오탐이니, 구버전 설치가 소멸하는 시점에 이 분기 제거.
    grep -qE 'kotlin-mutable-domain|Hydration 위험' "$GREP_HOOK" 2>/dev/null && DEMO=true
fi
{ [ "$SCAFFOLD" = true ] || [ "$DEMO" = true ]; } && FINDINGS=$((FINDINGS + 1))

# ─── C2: git pre-commit ──────────────────────────────────────────
# core.hooksPath 설정(husky v9 등)까지 반영해 실제 경로로 확인.
# 실행권한 없는 훅은 git 이 무시하므로 -x 까지 요구.
GIT_HOOK_OK=false
GIT_PC=$(git -C "$ROOT" rev-parse --git-path hooks/pre-commit 2>/dev/null || echo "")
if [ -n "$GIT_PC" ]; then
    case "$GIT_PC" in /*) ;; *) GIT_PC="$ROOT/$GIT_PC" ;; esac
    [ -f "$GIT_PC" ] && [ -x "$GIT_PC" ] && GIT_HOOK_OK=true
fi
[ "$GIT_HOOK_OK" = false ] && FINDINGS=$((FINDINGS + 1))

# ─── C3: 차단 능력 0 ─────────────────────────────────────────────
# config 경로를 명시해서 읽어요 — 인자 없이 부르면 goax_mode 가 CLAUDE_PROJECT_DIR
# 기준으로 경로를 만들어서, C4(루트 이탈) 상황에서 없는 config 를 읽고 기본값으로
# 떨어져요 (mode=fail 프로젝트를 차단 능력 0 으로 오진).
SENSOR_MODE=$(goax_mode "$ROOT/.ax/config.yml" 2>/dev/null || echo warning)
BLOCKING_ZERO=false
if [ "$SENSOR_MODE" = "off" ] \
    || { [ "$SENSOR_MODE" != "fail" ] && [ "$GIT_HOOK_OK" = false ]; }; then
    BLOCKING_ZERO=true
    # C2(훅 부재)가 이미 센 경우는 원인이 같아 중복 가산하지 않아요 —
    # mode 만으로 차단 0 이 되는 경우(off)만 별도 finding 으로 가산.
    [ "$GIT_HOOK_OK" = true ] && FINDINGS=$((FINDINGS + 1))
fi

# ─── C4: 세션 루트 이탈 ──────────────────────────────────────────
ROOT_MISMATCH=false
CPD="${CLAUDE_PROJECT_DIR:-}"
if [ -n "$CPD" ]; then
    # 심볼릭 링크 차이 흡수
    CPD_REAL=$(cd "$CPD" 2>/dev/null && pwd -P || echo "$CPD")
    ROOT_REAL=$(cd "$ROOT" 2>/dev/null && pwd -P || echo "$ROOT")
    if [ "$CPD_REAL" != "$ROOT_REAL" ]; then
        ROOT_MISMATCH=true
        FINDINGS=$((FINDINGS + 1))
    fi
fi

# ─── 보고 ────────────────────────────────────────────────────────
if [ "$JSON_MODE" = true ]; then
    result=$(jq -n \
        --argjson scaffold "$SCAFFOLD" \
        --argjson demo "$DEMO" \
        --argjson githook "$GIT_HOOK_OK" \
        --arg mode "$SENSOR_MODE" \
        --argjson bz "$BLOCKING_ZERO" \
        --argjson rm "$ROOT_MISMATCH" \
        --arg root "$ROOT" \
        --arg cpd "$CPD" \
        '{grep_scaffold_unfilled: $scaffold, grep_demo_content: $demo,
          git_precommit_installed: $githook, sensors_mode: $mode,
          blocking_zero: $bz, session_root_mismatch: $rm,
          project_root: $root,
          claude_project_dir: (if $cpd == "" then null else $cpd end)}')
    if [ "$FINDINGS" -eq 0 ]; then
        json_output "ok" "$result" "sensor liveness pass"
    else
        json_output "warning" "$result" "$FINDINGS finding — blocking_zero 면 install-git-hooks.sh 부터"
    fi
else
    if [ "$FINDINGS" -eq 0 ]; then
        goax_log "✓ sensor liveness pass (mode=$SENSOR_MODE, git pre-commit ✓)"
    else
        goax_log "⚠ sensor liveness: $FINDINGS finding"
        [ "$SCAFFOLD" = true ] && echo "  C1 grep 스캐폴드 미작성 — AGENTS.md 🔴 룰의 패턴을 채우세요" >&2
        [ "$DEMO" = true ] && echo "  C1 grep 훅에 구버전 데모 내용 잔존 — /up 재실행으로 스캐폴드 갱신" >&2
        [ "$GIT_HOOK_OK" = false ] && echo "  C2 git pre-commit 미설치 — bash .ax/scripts/bash/install-git-hooks.sh" >&2
        [ "$BLOCKING_ZERO" = true ] && echo "  C3 차단 능력 0 — mode=$SENSOR_MODE$([ "$GIT_HOOK_OK" = false ] && echo " + git hook 부재"). 지금 어떤 위반도 자동 차단되지 않아요" >&2
        [ "$ROOT_MISMATCH" = true ] && echo "  C4 세션 루트 이탈 — 세션을 $ROOT 에서 시작하세요 (훅·spirit 주입 누락 위험)" >&2
    fi
fi

if [ "$STRICT" = true ] && [ "$FINDINGS" -gt 0 ]; then
    exit "$EXIT_ERROR"
fi
exit "$EXIT_OK"
