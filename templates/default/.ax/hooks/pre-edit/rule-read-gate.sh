#!/usr/bin/env bash
# pre-edit hook — 이 파일에 걸린 룰을 이번 세션에 안 읽었으면 편집을 막아요 (rule-read gate)
#
# 왜: spirit-rules-inject.sh · module-rules-inject.sh 는 룰 파일 **경로**만 알려줘요 (B-pointer).
#     읽을지는 모델이 정해요. 실측(commerce mistakes 22건, 2026-07~09): 20건을 사용자가 잡았고
#     그중 "고치기 전에 조사 안 함" 이 절반이에요 — 원문 그대로 "hook 이 읽으라 지시한
#     commerce-application.md 를 건너뛰고 이웃 파일 grep 만으로 추론해" 금지된 suffix 를 썼어요.
#     안내는 건너뛸 수 있어요. 그래서 **읽었다는 사실**을 확인해요.
#
# 판정 (결정론 — 모델의 "확인했어요" 를 믿지 않아요):
#   Read    대상이 `.ax/spirit/rules/*.md` 또는 `.ax/modules/*/rules.md` 면 세션 마커를 찍고 통과.
#   Edit/Write/MultiEdit
#           대상 경로에 매칭되는 룰 파일(spirit `paths:` · module `paths:`+`applies_to: code`) 중
#           이번 세션에 Read 안 한 게 있으면 exit 2 로 막고 목록을 줘요. 다 읽었으면 통과.
#           CLAUDE.md · AGENTS.md 가 `@` 로 import 한 룰은 이미 컨텍스트에 있어서 빼요.
#           `.ax/` 자체 편집 · sensors.rule_gate_exempt 글롭은 건너뛰어요.
#   매칭은 주입 훅과 같은 common.sh 함수예요 (goax_rules_matching · goax_module_rules_matching).
#   Read 기록은 `.ax/.session/<sid>/rules-read.log`(`<epoch>\t<상대경로>`) 한 파일이에요 — 판정은 awk 한 번이고,
#   경로를 파일 이름으로 바꾸지 않아서 한글 룰 파일 이름끼리 겹칠 일이 없어요.
#   기록 TTL 은 GOAX_INJECT_TTL(기본 4시간). compaction 이 일어나면 SessionStart(source=compact) 훅이 이 기록을 지워서
#   룰 본문이 컨텍스트에서 빠진 뒤엔 다시 읽게 해요.
#   세션당 3번까지 전체 안내, 그 뒤는 한 줄 (같은 긴 문구 반복이 루프를 부른다는 ECC 실측 #2142).
#   세션 id 가 없으면(수동 실행·옛 런타임) 추적할 수 없어서 통과해요.
# 모드: sensors.mode warning·fail 둘 다 막아요 (off 면 안 돌아요) — 통과 조건이 Read 한 번이라 싸요.
# 끄기: .ax/config.yml sensors.disabled_hooks 에 rule-read-gate, 또는 sensors.hook_profile: minimal
# ⚠️ 성격: Bash 의 `sed -i`·`cat >` 로 고치면 이 훅은 안 걸려요. 사고 방지용이지 보안 경계가 아니에요.
set -uo pipefail

[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
# jq 한 번 — 모든 Edit·Read 에 걸리는 훅이라 프로세스 수가 곧 지연이에요
IFS="$(printf '\t')" read -r TOOL TARGET_PATH SID < <(printf '%s' "$INPUT" \
    | jq -r '[(.tool_name // ""), (.tool_input.file_path // .tool_input.notebook_path // ""), (.session_id // "")] | @tsv' 2>/dev/null) || true
[ -n "$TARGET_PATH" ] && [ -n "$SID" ] || exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
[ -f "$COMMON" ] || exit 0
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"

goax_hook_enabled rule-read-gate standard || exit 0
[ "$(goax_mode)" = "off" ] && exit 0

SDIR=$(goax_session_dir "$SID")

# 경로는 심볼릭 링크를 풀어서 비교해요 — macOS 의 /tmp ↔ /private/tmp 처럼 루트와 대상이 서로 다른 이름으로
# 오면 "프로젝트 밖" 으로 읽혀 게이트가 통째로 빠져요 (리뷰 실측). 없는 파일(Write 로 새로 만들 때)은 부모 디렉토리를 풀어요.
real_dir() { ( CDPATH="" cd -P "$1" 2>/dev/null && pwd -P ); }
TARGET_ABS=$(goax_normalize_path "$TARGET_PATH" "$PROJECT_ROOT")
ROOT_ABS=$(real_dir "$PROJECT_ROOT"); [ -n "$ROOT_ABS" ] || ROOT_ABS=$(goax_normalize_path "$PROJECT_ROOT" "$PROJECT_ROOT")
_td=$(dirname "$TARGET_ABS")
while [ ! -d "$_td" ] && [ "$_td" != "/" ]; do _td=$(dirname "$_td"); done
_tr=$(real_dir "$_td")
[ -n "$_tr" ] && TARGET_ABS="${_tr%/}${TARGET_ABS#"$_td"}"
TARGET_REL="${TARGET_ABS#"$ROOT_ABS"/}"
[ "$TARGET_REL" = "$TARGET_ABS" ] && exit 0      # 프로젝트 밖 파일 — 이 프로젝트 룰의 대상이 아니에요

# ── Read — 룰 파일을 읽었으면 기록 ────────────────────────────────
if [ "$TOOL" = "Read" ]; then
    case "$TARGET_REL" in
        .ax/spirit/rules/*.md|.ax/modules/*/rules.md)
            mkdir -p "$SDIR" 2>/dev/null && printf '%s\t%s\n' "$(date +%s)" "$TARGET_REL" >> "$SDIR/rules-read.log" ;;
    esac
    exit 0
fi

case "$TOOL" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac
case "$TARGET_REL" in .ax/*) exit 0 ;; esac

CONFIG="$PROJECT_ROOT/.ax/config.yml"
if [ -f "$CONFIG" ]; then
    while IFS= read -r g; do
        [ -z "$g" ] && continue
        goax_glob_match "$g" "$TARGET_REL" && exit 0
    done < <(goax_yaml_list "$CONFIG" rule_gate_exempt)
fi

# ── 이 파일에 걸린 룰 중 안 읽은 것 ────────────────────────────────
IMPORTED=$(goax_imported_paths "$PROJECT_ROOT")
READ_SET=""
[ -f "$SDIR/rules-read.log" ] && READ_SET=$(awk -F '\t' -v now="$(date +%s)" -v ttl="${GOAX_INJECT_TTL:-14400}" \
    'now - $1 < ttl { print $2 }' "$SDIR/rules-read.log")
UNREAD=()
while IFS= read -r r; do
    [ -z "$r" ] && continue
    printf '%s\n' "$IMPORTED" | grep -qxF "$r" && continue
    printf '%s\n' "$READ_SET" | grep -qxF "$r" && continue
    UNREAD+=("$r")
done < <(
    goax_rules_matching "$PROJECT_ROOT/.ax/spirit/rules" "$TARGET_REL" ".ax/spirit/rules/"
    goax_module_rules_matching "$PROJECT_ROOT" "$TARGET_REL" | sed 's#^\(.*\)$#.ax/modules/\1/rules.md#'
)
[ ${#UNREAD[@]} -eq 0 ] && exit 0

N=$(goax_session_count "$SID" rule-gate-denials)
if [ "$N" -gt 3 ]; then
    printf '\033[33m[goax hook]\033[0m 📖 (#%s) 룰 미독 — %s 편집 전에 Read: %s\n' \
        "$N" "$TARGET_REL" "$(printf '%s ' "${UNREAD[@]}")" >&2
    exit 2
fi
{
    printf '\033[33m[goax hook]\033[0m 📖 %s 에 걸린 룰을 이번 세션에 아직 안 읽었어요. 편집 전에 Read 하세요:\n' "$TARGET_REL"
    printf '  - %s\n' "${UNREAD[@]}"
    printf '  읽은 뒤 이 파일에 해당하는 SP-ID 를 한 줄로 짚고 같은 편집을 다시 하면 통과해요.\n'
    printf '  (Read 도구로 읽어야 기록돼요. 끄기: .ax/config.yml sensors.disabled_hooks 에 rule-read-gate · 경로 예외: sensors.rule_gate_exempt)\n'
} >&2
exit 2
