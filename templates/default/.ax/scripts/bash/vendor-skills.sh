#!/usr/bin/env bash
# .ax/scripts/bash/vendor-skills.sh — goax skill/command/agent 를 저장소에 동봉
#
# Usage:
#   bash vendor-skills.sh --plugin-dir <path> [--json] [--dry-run] [--help]
#   bash vendor-skills.sh --check [--json]        # 동봉본 ↔ plugin 버전 비교만
#
# 왜 필요한가 — 두 개의 루트가 있어요:
#
#   ADE 루트     에이전트가 스킬을 찾는 곳. `.claude/skills/` 가 여기 있어야 해요.
#                (Claude Code 는 세션 시작 지점 기준으로 discovery 해요)
#   프로젝트 루트 코드와 하네스가 있는 곳. `.ax/` 가 여기 있어요.
#
# 단일 저장소면 둘이 같아요. **모노레포면 갈라져요** — `.claude/` 는 저장소
# 루트에, `.ax/` 는 `projects/<app>/` 에 있는 식이에요. 이때 조상 탐색만으로는
# 하네스를 영영 못 찾아서(하위에 있으니까), 저장소 루트에 `.goax-root` 포인터를
# 남겨요. common.sh 의 find_project_root 가 그걸 읽어요.
#
# 동봉 대상: skills/ commands/ agents/  → <ADE 루트>/.claude/ 아래
# 사용자가 만든 자기 스킬은 건드리지 않아요 (goax 가 출고한 이름만 덮어써요).
#
# Output (--json):
#   {"status":"ok","result":{"ade_root":"...","project_root":"...","split":true,
#     "vendored":["skills/up",...],"pointer_written":true,"version":"0.4.0"},...}
#
# Exit: 0 ok / 1 error / 2 skipped

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; DRY_RUN=false; SHOW_HELP=false; CHECK_ONLY=false; PLUGIN_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)       JSON_MODE=true ;;
        --dry-run)    DRY_RUN=true ;;
        --check)      CHECK_ONLY=true ;;
        --plugin-dir) shift; PLUGIN_DIR="${1:-}" ;;
        --help|-h)    SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "$EXIT_OK"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
ADE_ROOT=$(goax_ade_root "$PROJECT_ROOT")

# ADE 루트가 프로젝트보다 위가 아니면(형제·무관) 프로젝트를 ADE 로 봐요
case "$PROJECT_ROOT" in
    "$ADE_ROOT"|"$ADE_ROOT"/*) ;;
    *) ADE_ROOT="$PROJECT_ROOT" ;;
esac

SPLIT=false
[ "$ADE_ROOT" != "$PROJECT_ROOT" ] && SPLIT=true
REL_PROJECT="${PROJECT_ROOT#$ADE_ROOT/}"
[ "$REL_PROJECT" = "$PROJECT_ROOT" ] && REL_PROJECT="."

VENDOR_VER_FILE="$ADE_ROOT/.claude/.goax-vendored"
CUR_VENDORED=""
[ -f "$VENDOR_VER_FILE" ] && CUR_VENDORED=$(head -1 "$VENDOR_VER_FILE" 2>/dev/null | tr -d '\r')

# ── --check: 버전 비교만 ─────────────────────────────────────────
if [ "$CHECK_ONLY" = true ]; then
    PLUGIN_VER=""
    [ -n "$PLUGIN_DIR" ] && [ -f "$PLUGIN_DIR/VERSION" ] && PLUGIN_VER=$(cat "$PLUGIN_DIR/VERSION" 2>/dev/null | tr -d '\r')
    STALE=false
    [ -n "$CUR_VENDORED" ] && [ -n "$PLUGIN_VER" ] && [ "$CUR_VENDORED" != "$PLUGIN_VER" ] && STALE=true
    if [ "$JSON_MODE" = true ]; then
        RESULT=$(printf '{"vendored":%s,"vendored_version":"%s","plugin_version":"%s","stale":%s,"ade_root":"%s","split":%s}' \
            "$([ -n "$CUR_VENDORED" ] && echo true || echo false)" \
            "$CUR_VENDORED" "$PLUGIN_VER" "$STALE" "$ADE_ROOT" "$SPLIT")
        if [ "$STALE" = true ]; then
            json_output "ok" "$RESULT" "동봉본이 ${CUR_VENDORED} 인데 plugin 은 ${PLUGIN_VER} 예요 — /vendor 재실행으로 갱신하세요"
        else
            json_output "ok" "$RESULT" "동봉 상태 확인 완료"
        fi
    else
        printf 'vendored=%s plugin=%s stale=%s\n' "${CUR_VENDORED:-none}" "${PLUGIN_VER:-unknown}" "$STALE"
    fi
    exit "$EXIT_OK"
fi

# ── 동봉 ─────────────────────────────────────────────────────────
if [ -z "$PLUGIN_DIR" ]; then
    if [ "$JSON_MODE" = true ]; then json_error "--plugin-dir 필요 — SKILL.md 에서 \${CLAUDE_SKILL_DIR}/../.. 로 전달하세요"; fi
    goax_error "--plugin-dir required"; exit "$EXIT_ERROR"
fi
if [ ! -d "$PLUGIN_DIR/skills" ]; then
    if [ "$JSON_MODE" = true ]; then json_error "plugin skills/ 를 찾을 수 없어요: $PLUGIN_DIR/skills"; fi
    goax_error "not a plugin dir: $PLUGIN_DIR"; exit "$EXIT_ERROR"
fi

PLUGIN_VER=$(cat "$PLUGIN_DIR/VERSION" 2>/dev/null | tr -d '\r' || echo unknown)
VENDORED=""

vendor_one() {   # $1 = 하위 디렉토리명 (skills|commands|agents)
    local kind="$1" src="$PLUGIN_DIR/$1" dst="$ADE_ROOT/.claude/$1" name
    [ -d "$src" ] || return 0
    for item in "$src"/*; do
        [ -e "$item" ] || continue
        name=$(basename "$item")
        VENDORED="${VENDORED}${kind}/${name}"$'\n'
        [ "$DRY_RUN" = true ] && continue
        mkdir -p "$dst"
        rm -rf "${dst:?}/$name"
        cp -R "$item" "$dst/$name"
    done
}

vendor_one skills
vendor_one commands
vendor_one agents

POINTER_WRITTEN=false
if [ "$SPLIT" = true ] && [ "$DRY_RUN" != true ]; then
    {
        printf '# goax — 이 저장소에서 .ax/ 하네스가 있는 경로\n'
        printf '# ADE 루트(.claude/ 가 있는 여기) 와 프로젝트 루트가 달라서 필요해요.\n'
        printf '# common.sh 의 find_project_root 가 이 파일을 읽어요.\n'
        printf '%s\n' "$REL_PROJECT"
    } > "$ADE_ROOT/.goax-root"
    POINTER_WRITTEN=true
fi

if [ "$DRY_RUN" != true ]; then
    mkdir -p "$ADE_ROOT/.claude"
    printf '%s\n' "$PLUGIN_VER" > "$VENDOR_VER_FILE"
fi

VCOUNT=$(printf '%s' "$VENDORED" | grep -c . || true); VCOUNT=${VCOUNT:-0}

if [ "$JSON_MODE" = true ]; then
    VJSON="[]"
    if [ "$VCOUNT" -gt 0 ] && command -v jq >/dev/null 2>&1; then
        VJSON=$(printf '%s\n' "$VENDORED" | jq -Rn '[inputs | select(length>0)]')
    fi
    RESULT=$(printf '{"ade_root":"%s","project_root":"%s","split":%s,"pointer_written":%s,"count":%s,"version":"%s","vendored":%s}' \
        "$ADE_ROOT" "$PROJECT_ROOT" "$SPLIT" "$POINTER_WRITTEN" "$VCOUNT" "$PLUGIN_VER" "$VJSON")
    if [ "$DRY_RUN" = true ]; then
        json_output "ok" "$RESULT" "dry-run — ${VCOUNT}개 항목을 $ADE_ROOT/.claude/ 로 동봉할 예정"
    else
        json_output "ok" "$RESULT" "동봉 완료 (v$PLUGIN_VER) — 커밋하면 팀원은 plugin 설치 없이 쓸 수 있어요"
    fi
else
    printf '%s\n' "$VENDORED"
fi
exit "$EXIT_OK"
